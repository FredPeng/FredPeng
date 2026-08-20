#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
1688 侧补数 —— 把候选队列补齐到 screen.py 能判生死的程度。

为什么不是纯爬虫：
    决定生死的两个数（准确实重、外箱尺寸）在 1688 商品页上经常根本没有，
    外箱尺寸大多数页面完全不写。官方 API 也给不了。这两个数只能问供应商。
    => 该自动化的不是「查」，是「问」和「解析回复」。

三个子命令：
    ask     为每个候选品生成标准询盘话术（含压缩体积那一问，单件可值 5,000+ KES）
    parse   把供应商的自由文本回复批量解析成结构化字段，回填 CSV
    api     1688 开放平台适配器骨架（拍立淘图搜找同款 + 商品详情）

用法：
    python3 tools/enrich_1688.py ask queue.csv -o inquiries.txt
    python3 tools/enrich_1688.py parse queue.csv replies.txt -o enriched.csv
    python3 tools/screen.py enriched.csv
"""

import argparse, csv, hashlib, json, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

MODEL = "claude-opus-5"

INQUIRY = """\
您好，我们是肯尼亚的电商，长期采购，想咨询这款：{name}
{url}

麻烦确认以下几项，我们据此核算能不能上架：

1. 单件价格？起订量多少？一件代发支持吗？
2. 单件**实重**多少公斤（含包装）？
3. 单件**外箱尺寸**（长×宽×高，厘米）？—— 我们走空运按体积计费，这项最关键
4. 能否**去掉零售彩盒、散装发货**？软货能否真空压缩？
   （我们到货后要重新分装，零售包装对我们没用，但体积会让运费翻几倍）
5. 常规备货量多少？断货补货要多久？
6. 有质量问题的退换怎么处理？

我们会先下小批量试单，跑通后长期返单。谢谢。
"""

SCHEMA = {
    "type": "object",
    "properties": {
        "cost_cny": {"type": ["number", "null"], "description": "单件价格 CNY"},
        "moq": {"type": ["number", "null"]},
        "dropship_ok": {"type": ["boolean", "null"], "description": "是否支持一件代发"},
        "weight_kg": {"type": ["number", "null"], "description": "单件实重 kg，含包装"},
        "l_cm": {"type": ["number", "null"]},
        "w_cm": {"type": ["number", "null"]},
        "h_cm": {"type": ["number", "null"]},
        "bulk_packing_ok": {"type": ["boolean", "null"], "description": "能否去零售包装散装发货"},
        "compressible": {"type": ["boolean", "null"], "description": "软货能否真空压缩"},
        "restock_days": {"type": ["number", "null"]},
        "unanswered": {"type": "array", "items": {"type": "string"},
                       "description": "供应商未回答或答得含糊的项，需要追问"},
    },
    "required": ["cost_cny", "moq", "dropship_ok", "weight_kg", "l_cm", "w_cm", "h_cm",
                 "bulk_packing_ok", "compressible", "restock_days", "unanswered"],
    "additionalProperties": False,
}

SYSTEM = """You extract structured sourcing data from Chinese 1688 supplier chat replies.

Rules:
- Only record what the supplier actually stated. If a field was not answered, or was
  answered vaguely ("大概", "差不多", "应该是"), set it to null and list it in `unanswered`.
- Never estimate, infer, or fill in a plausible number. A null is useful; a guess is not —
  these numbers decide whether a product is profitable.
- Dimensions: convert to centimetres. If the supplier gave carton dimensions for a
  multi-unit carton, divide to per-unit only if they state the units per carton;
  otherwise null it and flag in `unanswered`.
- Weight: kilograms, including packaging. Convert grams/斤 as needed (1斤 = 0.5kg).
- Price: CNY per single unit. If they only gave a tiered price, take the lowest tier
  whose MOQ they stated, and note the tier in `unanswered` if ambiguous.
"""


def load_rows(path):
    with open(path, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def cmd_ask(args):
    rows = load_rows(args.input)
    out = []
    for i, r in enumerate(rows, 1):
        out.append(f"===== [{i}] {r.get('name','?')} =====\n"
                   + INQUIRY.format(name=r.get("name", ""), url=r.get("source_url", "")))
    text = "\n".join(out)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"{len(rows)} 条询盘已写入 {args.out}")
    print("\n发给供应商后，把回复按同样的 ===== [n] ===== 分隔贴进一个文件，然后：")
    print(f"  python3 tools/enrich_1688.py parse {args.input} replies.txt -o enriched.csv")


def split_replies(path):
    """按 ===== [n] ===== 分段；没有分隔符时整体当作第 1 条。"""
    raw = open(path, encoding="utf-8").read()
    blocks, cur, idx = {}, [], None
    for line in raw.splitlines():
        m = line.strip().startswith("=====") and line.strip().strip("= ").split("]")[0]
        if m and m.startswith("["):
            if idx is not None:
                blocks[idx] = "\n".join(cur).strip()
            idx, cur = int(m[1:]), []
        else:
            cur.append(line)
    if idx is not None:
        blocks[idx] = "\n".join(cur).strip()
    elif raw.strip():
        blocks[1] = raw.strip()
    return blocks


def cmd_parse(args):
    try:
        import anthropic
    except ImportError:
        sys.exit("需要先安装 SDK：pip install anthropic")
    client = anthropic.Anthropic()

    rows = load_rows(args.input)
    replies = split_replies(args.replies)
    print(f"候选 {len(rows)} 个，收到回复 {len(replies)} 条")

    extra = ["cost_cny", "moq", "dropship_ok", "weight_kg", "l_cm", "w_cm", "h_cm",
             "bulk_packing_ok", "compressible", "restock_days", "suppliers_1688", "notes"]
    cols = list(dict.fromkeys(list(rows[0].keys()) + extra)) if rows else extra

    for i, row in enumerate(rows, 1):
        reply = replies.get(i)
        if not reply:
            row["notes"] = f"{row.get('notes','')} 无回复".strip()
            continue
        resp = client.messages.create(
            model=MODEL, max_tokens=16000,
            thinking={"type": "adaptive"},
            system=[{"type": "text", "text": SYSTEM,
                     "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content":
                       f"Product: {row.get('name','')}\n\nSupplier reply:\n{reply}"}],
            output_config={"format": {"type": "json_schema", "schema": SCHEMA}},
        )
        g = json.loads(next(b.text for b in resp.content if b.type == "text"))
        for k in ("cost_cny", "moq", "weight_kg", "l_cm", "w_cm", "h_cm", "restock_days"):
            if g.get(k) is not None:
                row[k] = g[k]
        for k in ("dropship_ok", "bulk_packing_ok", "compressible"):
            if g.get(k) is not None:
                row[k] = int(bool(g[k]))
        if g["unanswered"]:
            row["notes"] = f"{row.get('notes','')} 待追问:{','.join(g['unanswered'])}".strip()

        have = all(row.get(k) for k in ("cost_cny", "weight_kg", "l_cm", "w_cm", "h_cm"))
        mark = "✓" if have else "…"
        bulk = " [可散装]" if g.get("bulk_packing_ok") else ""
        print(f"  {mark} [{i}] {row.get('name','?')[:34]:<36}"
              f"¥{g.get('cost_cny') or '?'}  {g.get('weight_kg') or '?'}kg"
              f"  {g.get('l_cm') or '?'}x{g.get('w_cm') or '?'}x{g.get('h_cm') or '?'}{bulk}")
        if g["unanswered"]:
            print(f"        追问：{', '.join(g['unanswered'])}")

    with open(args.out, "w", encoding="utf-8-sig", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        wr.writeheader()
        wr.writerows(rows)
    ready = sum(1 for r in rows
                if all(r.get(k) for k in ("cost_cny", "weight_kg", "l_cm", "w_cm", "h_cm")))
    print(f"\n{ready}/{len(rows)} 个已可判定，写入 {args.out}")
    print(f"  python3 tools/screen.py {args.out}")


class Open1688:
    """1688 开放平台适配器骨架。

    ⚠️ 需企业认证 + 订购对应 API 权限；接口名与字段随版本变化，接入前对照官方文档核对。
       拍立淘图搜用于找同款、比价、数供应商数量 —— 这是 API 真正能替你做的部分。
    """
    GATEWAY = "https://gw.open.1688.com/openapi"

    def __init__(self):
        self.app_key = os.getenv("ALIBABA_APP_KEY")
        self.app_secret = os.getenv("ALIBABA_APP_SECRET")
        self.token = os.getenv("ALIBABA_ACCESS_TOKEN")
        if not all((self.app_key, self.app_secret, self.token)):
            sys.exit("需要 ALIBABA_APP_KEY / ALIBABA_APP_SECRET / ALIBABA_ACCESS_TOKEN")

    def _sign(self, path, params):
        base = path + "".join(f"{k}{params[k]}" for k in sorted(params))
        import hmac
        return hmac.new(self.app_secret.encode(), base.encode(),
                        hashlib.sha1).hexdigest().upper()

    def call(self, namespace, name, version, params):
        path = f"param2/{version}/{namespace}/{name}/{self.app_key}"
        params = {**params, "access_token": self.token}
        params["_aop_signature"] = self._sign(path, params)
        req = urllib.request.Request(f"{self.GATEWAY}/{path}",
                                     data=urllib.parse.urlencode(params).encode())
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())

    def search_by_image(self, image_url, page=1):
        """拍立淘找同款 —— 用于比价和统计同款供应商数量。"""
        return self.call("com.alibaba.fenxiao.crossborder", "product.search.byImage",
                         "1", {"imageUrl": image_url, "page": str(page)})


def cmd_api(args):
    api = Open1688()
    rows = load_rows(args.input)
    for i, row in enumerate(rows, 1):
        img = row.get("image_url")
        if not img:
            print(f"  x [{i}] 无 image_url，跳过图搜")
            continue
        try:
            data = api.search_by_image(img)
        except Exception as e:
            print(f"  x [{i}] {e}", file=sys.stderr)
            continue
        print(f"  [{i}] {row.get('name','?')[:40]}")
        print(f"      {json.dumps(data, ensure_ascii=False)[:200]}")
        time.sleep(0.5)
    print("\n注：返回字段随 API 版本变化，按你订购的接口调整解析后再回填 CSV。")


def main():
    ap = argparse.ArgumentParser(description="1688 侧补数")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("ask", help="生成询盘话术")
    a.add_argument("input"); a.add_argument("-o", "--out", default="inquiries.txt")
    a.set_defaults(fn=cmd_ask)

    p = sub.add_parser("parse", help="解析供应商回复并回填")
    p.add_argument("input"); p.add_argument("replies")
    p.add_argument("-o", "--out", default="enriched.csv")
    p.set_defaults(fn=cmd_parse)

    q = sub.add_parser("api", help="1688 开放平台图搜（需权限）")
    q.add_argument("input")
    q.set_defaults(fn=cmd_api)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
