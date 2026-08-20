#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
候选品发现 —— 速卖通侧数据采集 + 一次过滤，产出待做 1688 反查的候选队列。

重要限界：
    速卖通只有「需求信号 + 素材」，没有重量和外箱尺寸。
    而决定能不能做的硬指标（落地成本、运费占比）全依赖 1688 侧的重量体积。
    => 本工具产出的是**候选队列**，不是 PASS/FAIL。
       补齐 1688 的 cost_cny / weight_kg / l,w,h 之后，再交给 screen.py 定生死。

数据源可插拔（--source）：
    csv        手工整理的 CSV。今天就能用，零依赖，零风险。
    affiliate  速卖通联盟开放平台 API。稳定合规，但只覆盖联盟目录，且需申请审批。
    html       直接抓公开商品页。覆盖全量，但脆弱且违反 ToS，见下方说明。

用法：
    python3 tools/discover.py --source csv raw.csv -o queue.csv
    python3 tools/discover.py --source affiliate --keywords "hair wig,ipl laser" -o queue.csv
    python3 tools/discover.py --source html --urls urls.txt -o queue.csv --rate 0.2
"""

import argparse, csv, hashlib, hmac, json, os, re, sys, time, urllib.parse, urllib.request

# 速卖通侧硬门槛（1688 侧的门槛在 screen.py）
RULES = {
    "min_main_imgs": 6,
    "min_detail_imgs": 10,
    "require_video": True,
    "min_price_kes": 8000,      # 原计划 2,000；集货+CPA 实算后的真实下限
    "min_orders": 50,           # 有销售 —— 原计划只说"有销售"，这里给个数
    "min_reviews": 30,
    "min_reviews_90d_pct": 15,  # 低于此判为衰退期
    "max_sellers_same_item": 20,
}

OUT_COLS = ["name", "source_url", "ali_price_kes", "orders", "reviews",
            "reviews_90d_pct", "sellers", "main_imgs", "detail_imgs", "has_video",
            "category", "variants", "image_url", "notes",
            # 以下留空，待 1688 反查补齐后交给 screen.py
            "cost_cny", "weight_kg", "l_cm", "w_cm", "h_cm",
            "local_price_kes", "suppliers_1688"]


# ---------------------------------------------------------------------------
# 数据源适配器
# ---------------------------------------------------------------------------

class CsvSource:
    """手工整理的 CSV。列名与 OUT_COLS 同名即可，缺的留空。"""
    def __init__(self, path):
        self.path = path

    def fetch(self):
        with open(self.path, encoding="utf-8-sig") as fh:
            yield from csv.DictReader(fh)


class AffiliateSource:
    """速卖通联盟开放平台 (TOP 网关)。

    需要环境变量 ALIEXPRESS_APP_KEY / ALIEXPRESS_APP_SECRET，先在开放平台申请并通过审批。

    ⚠️ 签名算法与字段名按阿里 TOP 网关通用规范实现，但速卖通接口版本会变 ——
       首次接入请对照当前官方文档核对 method 名与返回字段，本实现是骨架不是保证。
    """
    GATEWAY = "https://api-sg.aliexpress.com/sync"
    METHOD = "aliexpress.affiliate.product.query"

    def __init__(self, keywords, ship_to="KE", currency="KES", pages=3, page_size=50):
        self.app_key = os.getenv("ALIEXPRESS_APP_KEY")
        self.app_secret = os.getenv("ALIEXPRESS_APP_SECRET")
        if not (self.app_key and self.app_secret):
            sys.exit("需要设置 ALIEXPRESS_APP_KEY / ALIEXPRESS_APP_SECRET")
        self.keywords, self.ship_to = keywords, ship_to
        self.currency, self.pages, self.page_size = currency, pages, page_size

    def _sign(self, params):
        base = "".join(f"{k}{params[k]}" for k in sorted(params))
        return hmac.new(self.app_secret.encode(), base.encode(),
                        hashlib.sha256).hexdigest().upper()

    def _call(self, extra):
        params = {
            "app_key": self.app_key, "method": self.METHOD,
            "sign_method": "hmac-sha256", "format": "json", "v": "2.0",
            "timestamp": str(int(time.time() * 1000)),
            **extra,
        }
        params["sign"] = self._sign(params)
        req = urllib.request.Request(
            self.GATEWAY, data=urllib.parse.urlencode(params).encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())

    def fetch(self):
        for kw in self.keywords:
            for page in range(1, self.pages + 1):
                data = self._call({
                    "keywords": kw, "page_no": str(page),
                    "page_size": str(self.page_size),
                    "ship_to_country": self.ship_to,
                    "target_currency": self.currency,
                    "target_language": "EN",
                })
                for item in _dig_products(data):
                    yield _from_affiliate(item)


class HtmlSource:
    """直接抓公开商品页。

    ⚠️ 三点务必知情：
      1. 违反速卖通 ToS。是否使用由你决定，风险自负。
      2. 极其脆弱 —— 页面内嵌 JSON 结构不定期变化，几周就要修一次。
      3. 本实现**不包含任何反爬绕过**（不处理滑块验证、不做设备指纹伪造、不轮换代理）。
         遇到验证码就是遇到了，请改用官方 API。

    只接受你自己提供的 URL 列表，不做全站遍历；默认限速很低，请勿调高。
    """
    UA = "Mozilla/5.0 (compatible; product-research/1.0)"

    def __init__(self, url_file, rate=0.2):
        self.urls = [l.strip() for l in open(url_file, encoding="utf-8")
                     if l.strip() and not l.startswith("#")]
        self.delay = 1.0 / rate if rate > 0 else 5.0

    def fetch(self):
        for i, url in enumerate(self.urls):
            if i:
                time.sleep(self.delay)
            try:
                req = urllib.request.Request(url, headers={"User-Agent": self.UA})
                with urllib.request.urlopen(req, timeout=30) as r:
                    html = r.read().decode("utf-8", "ignore")
            except Exception as e:
                print(f"  x {url}: {e}", file=sys.stderr)
                continue
            if re.search(r"punish|captcha|_____tmd_____|slide", html, re.I):
                print(f"  x {url}: 触发风控页 —— 改用官方 API", file=sys.stderr)
                continue
            yield _from_html(url, html)


# ---------------------------------------------------------------------------
# 解析
# ---------------------------------------------------------------------------

def _dig_products(payload):
    """在 TOP 响应里找到商品数组 —— 字段层级随版本变化，这里做宽松查找。"""
    def walk(o):
        if isinstance(o, dict):
            if "products" in o and isinstance(o["products"], (list, dict)):
                p = o["products"]
                return p if isinstance(p, list) else p.get("product", [])
            for v in o.values():
                r = walk(v)
                if r:
                    return r
        return None
    return walk(payload) or []


def _num(x, default=0):
    try:
        return float(re.sub(r"[^\d.]", "", str(x)) or default)
    except (TypeError, ValueError):
        return default


def _from_affiliate(it):
    imgs = it.get("product_small_image_urls") or {}
    if isinstance(imgs, dict):
        imgs = imgs.get("string", [])
    return {
        "name": it.get("product_title", ""),
        "source_url": it.get("product_detail_url", ""),
        "ali_price_kes": _num(it.get("target_sale_price") or it.get("sale_price")),
        "orders": _num(it.get("lastest_volume")),
        "reviews": _num(it.get("evaluate_rate_count") or it.get("evaluation_count")),
        "reviews_90d_pct": "",              # 联盟接口不提供，需详情页或人工
        "sellers": "",                      # 同款卖家数需图搜反查
        "main_imgs": len(imgs) if imgs else "",
        "detail_imgs": "",                  # 需商品详情接口
        "has_video": "",
        "category": it.get("second_level_category_name") or it.get("first_level_category_name", ""),
        "variants": "",
        "image_url": it.get("product_main_image_url", ""),
        "notes": "affiliate",
    }


def _from_html(url, html):
    def grab(pat, d=""):
        m = re.search(pat, html)
        return m.group(1) if m else d
    imgs = set(re.findall(r'(https://ae\d*[-\w.]*alicdn\.com/kf/[\w.\-]+\.(?:jpg|png|webp))', html))
    return {
        "name": grab(r'<title>\s*(.*?)\s*(?:\||</title>)'),
        "source_url": url,
        "ali_price_kes": _num(grab(r'"(?:formatedActivityPrice|formatedPrice)"\s*:\s*"([^"]+)"')),
        "orders": _num(grab(r'"tradeCount"\s*:\s*"?(\d+)')),
        "reviews": _num(grab(r'"totalValidNum"\s*:\s*"?(\d+)')),
        "reviews_90d_pct": "", "sellers": "",
        "main_imgs": len(imgs) or "", "detail_imgs": "",
        "has_video": 1 if re.search(r'"videoId"\s*:\s*"?\d', html) else 0,
        "category": "", "variants": "",
        "image_url": next(iter(imgs), ""),
        "notes": "html",
    }


# ---------------------------------------------------------------------------
# 速卖通侧过滤
# ---------------------------------------------------------------------------

def check(row):
    """返回 (硬伤列表, 待补数据列表)。数据缺失不算硬伤 —— 只是还没法判断。"""
    fails, missing = [], []

    def val(k):
        v = str(row.get(k, "")).strip()
        return _num(v) if v else None

    checks = [
        ("ali_price_kes", lambda v: v >= RULES["min_price_kes"],
         f"售价 < {RULES['min_price_kes']:,} KES"),
        ("orders", lambda v: v >= RULES["min_orders"], f"销量 < {RULES['min_orders']}"),
        ("reviews", lambda v: v >= RULES["min_reviews"], f"评论 < {RULES['min_reviews']}"),
        ("reviews_90d_pct", lambda v: v >= RULES["min_reviews_90d_pct"],
         f"近90天评论占比 < {RULES['min_reviews_90d_pct']}% (衰退期)"),
        ("sellers", lambda v: v <= RULES["max_sellers_same_item"],
         f"同款卖家 > {RULES['max_sellers_same_item']} (素材烂大街)"),
        ("main_imgs", lambda v: v >= RULES["min_main_imgs"],
         f"主图 < {RULES['min_main_imgs']}"),
        ("detail_imgs", lambda v: v >= RULES["min_detail_imgs"],
         f"详情图 < {RULES['min_detail_imgs']}"),
    ]
    for key, ok, msg in checks:
        v = val(key)
        if v is None:
            missing.append(key)
        elif not ok(v):
            fails.append(msg)

    v = val("has_video")
    if v is None:
        missing.append("has_video")
    elif RULES["require_video"] and not v:
        fails.append("无产品视频")
    return fails, missing


def main():
    ap = argparse.ArgumentParser(description="候选品发现：速卖通侧采集 + 一次过滤")
    ap.add_argument("input", nargs="?", help="csv 源的输入文件")
    ap.add_argument("--source", choices=("csv", "affiliate", "html"), default="csv")
    ap.add_argument("--keywords", help="affiliate 源：逗号分隔的搜索词")
    ap.add_argument("--urls", help="html 源：URL 列表文件（一行一个）")
    ap.add_argument("--rate", type=float, default=0.2, help="html 源：每秒请求数，默认 0.2")
    ap.add_argument("--pages", type=int, default=3)
    ap.add_argument("-o", "--out", default="candidate-queue.csv")
    args = ap.parse_args()

    if args.source == "csv":
        if not args.input:
            ap.error("csv 源需要输入文件")
        src = CsvSource(args.input)
    elif args.source == "affiliate":
        if not args.keywords:
            ap.error("affiliate 源需要 --keywords")
        src = AffiliateSource([k.strip() for k in args.keywords.split(",")], pages=args.pages)
    else:
        if not args.urls:
            ap.error("html 源需要 --urls")
        print("⚠ html 源违反速卖通 ToS、结构脆弱、不含任何反爬绕过。遇验证码请改用官方 API。",
              file=sys.stderr)
        src = HtmlSource(args.urls, rate=args.rate)

    kept, killed, partial = [], 0, 0
    for row in src.fetch():
        out = {c: row.get(c, "") for c in OUT_COLS}
        fails, missing = check(out)
        if fails:
            killed += 1
            continue
        if missing:
            partial += 1
            out["notes"] = f"{out.get('notes','')} 待补:{','.join(missing)}".strip()
        kept.append(out)

    with open(args.out, "w", encoding="utf-8-sig", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=OUT_COLS)
        wr.writeheader()
        wr.writerows(kept)

    print(f"\n保留 {len(kept)}（其中 {partial} 个数据不全）， 砍掉 {killed}")
    print(f"已写入 {args.out}")
    print("\n下一步：补齐 cost_cny / weight_kg / l_cm,w_cm,h_cm（1688 反查），再跑")
    print(f"  python3 tools/screen.py {args.out}")
    print("速卖通没有重量和体积 —— 这一步决定生死，无法从本工具得到。")


if __name__ == "__main__":
    main()
