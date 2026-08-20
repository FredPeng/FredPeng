#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
上架自动化 —— 把通过筛选的品批量转成 WooCommerce 可导入的 CSV。

对每个品用 Claude 生成：
  - 面向 Google 搜索的英文标题（不是"好看"，是让肯尼亚人搜得到）
  - 规格表、描述、SEO meta
  - FAQ（专门回答"为什么要先付款""要等多久"）
  - 肯尼亚本地搜索词  -> 据此判定该品该投 Google 还是 Meta/TikTok
  - 风险标记（电池/液体/磁铁/易碎/尺码）-> 零备货模式下这些是硬伤

信任模块、交期、M-Pesa 标识由代码确定性拼接，全站统一，不交给模型。

用法：
    export ANTHROPIC_API_KEY=...
    python3 tools/listing.py business-plan/candidates.csv -o out.csv
    python3 tools/listing.py business-plan/candidates.csv --dry-run   # 只看提示词，不调 API
    python3 tools/listing.py business-plan/candidates.csv --limit 3 --workers 4
"""

import argparse, csv, json, os, sys, textwrap
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_economics import Assumptions, Product, landed_cost, price_for_target

MODEL = "claude-opus-5"

# ---------------------------------------------------------------------------
# 交付承诺 —— 全站统一，改这里即可全站生效
# ---------------------------------------------------------------------------
SHIPPING = {
    "cutoffs": "Tuesday & Friday",
    "days_min": 10,
    "days_max": 14,
}

TRUST_BLOCK = """
<div class="ke-trust">
  <ul>
    <li><strong>Pay with M-Pesa</strong> — secure checkout, no card needed.</li>
    <li><strong>Delivered in {days_min}–{days_max} days</strong> — we ship every {cutoffs}. You get a
        WhatsApp update every 3 days until it arrives.</li>
    <li><strong>All duties and taxes included</strong> — the price you see is the price you pay.
        No surprise KRA charges.</li>
    <li><strong>A real person to call</strong> — WhatsApp us any time before or after you buy.</li>
    <li><strong>Not what you expected?</strong> Tell us within 7 days of delivery and we will make it right.</li>
  </ul>
</div>
""".strip()

SYSTEM = """You write product listings for a Kenyan e-commerce store that imports from China.

Business model, which shapes every choice you make:
- Customers pay in FULL and IN ADVANCE by M-Pesa, then wait 10-14 days for delivery.
  Nothing is stocked locally. So the listing must do the persuading that a shelf and a
  return policy normally do.
- The store is NOT competing on price with AliExpress. It competes on M-Pesa payment,
  tax-inclusive pricing, local accountability, and being roughly twice as fast.
- Prices are in Kenyan Shillings (KES).

Rules for the title:
- Write it for Google search, not for looks. A Kenyan typing into Google must find it.
- Use the words Kenyans actually use for the product, then key specs, then "Price in Kenya".
- 60-70 characters. No ALL CAPS, no emoji, no "Hot Sale", no "Free Shipping".

Rules for the body:
- Plain, concrete English. Kenyan English conventions. No hype, no invented awards,
  no fake scarcity, no health or medical claims.
- Never invent certifications, warranties, brand names, or country of manufacture.
- If the source data does not state a spec, leave it out rather than guessing.
- Address the two objections this model always faces: why pay before delivery,
  and why the wait is normal for an imported item.

Channel routing - decide one:
- "search"    = customers already know this product category and search for it
                (they can buy it locally but it is expensive). Route to Google Search/Shopping.
- "discovery" = nobody in Kenya is searching for this because they have never seen it.
                Demand must be created. Route to Meta/TikTok video.

Risk flags - list any that apply, because there is no local stock to swap a bad unit:
battery, liquid, magnet, powder, fragile, sizing, complex_electronics, branded_lookalike.
"""

SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "short_description": {"type": "string"},
        "description_html": {"type": "string"},
        "specifications": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"label": {"type": "string"}, "value": {"type": "string"}},
                "required": ["label", "value"],
                "additionalProperties": False,
            },
        },
        "seo_title": {"type": "string"},
        "seo_meta_description": {"type": "string"},
        "faq": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"q": {"type": "string"}, "a": {"type": "string"}},
                "required": ["q", "a"],
                "additionalProperties": False,
            },
        },
        "google_keywords": {"type": "array", "items": {"type": "string"}},
        "category": {"type": "string"},
        "tags": {"type": "array", "items": {"type": "string"}},
        "channel": {"type": "string", "enum": ["search", "discovery"]},
        "channel_reason": {"type": "string"},
        "risk_flags": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["title", "short_description", "description_html", "specifications",
                 "seo_title", "seo_meta_description", "faq", "google_keywords",
                 "category", "tags", "channel", "channel_reason", "risk_flags"],
    "additionalProperties": False,
}


def user_prompt(row, price):
    src = {k: v for k, v in row.items() if v and v.strip()}
    return textwrap.dedent(f"""\
        Write the listing for this product.

        Source data (from 1688 / AliExpress; Chinese product names are the supplier's,
        do not carry them over literally):
        {json.dumps(src, ensure_ascii=False, indent=2)}

        Selling price in Kenya: KES {price:,.0f}
        Kenyan local retail price for comparable items: {src.get('local_price_kes', 'unknown')}

        Produce the listing fields.""")


def build_client():
    try:
        import anthropic
    except ImportError:
        sys.exit("需要先安装 SDK：pip install anthropic")
    return anthropic.Anthropic()


def generate(client, row, price):
    resp = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        thinking={"type": "adaptive"},
        system=[{"type": "text", "text": SYSTEM, "cache_control": {"type": "ephemeral"}}],
        messages=[{"role": "user", "content": user_prompt(row, price)}],
        output_config={"format": {"type": "json_schema", "schema": SCHEMA}},
    )
    text = next(b.text for b in resp.content if b.type == "text")
    return json.loads(text)


def render_body(g):
    specs = "".join(f"<tr><th>{s['label']}</th><td>{s['value']}</td></tr>"
                    for s in g["specifications"])
    faq = "".join(f"<h4>{i['q']}</h4><p>{i['a']}</p>" for i in g["faq"])
    return (f"{g['description_html']}"
            f"<h3>Specifications</h3><table class=\"ke-specs\">{specs}</table>"
            f"<h3>Delivery &amp; Payment</h3>{TRUST_BLOCK.format(**SHIPPING)}"
            f"<h3>Questions</h3>{faq}")


WOO_COLS = ["Type", "SKU", "Name", "Published", "Visibility in catalogue",
            "Short description", "Description", "Regular price", "Categories", "Tags",
            "Meta: _yoast_wpseo_title", "Meta: _yoast_wpseo_metadesc",
            "Meta: _ke_channel", "Meta: _ke_keywords", "Meta: _ke_risk_flags",
            "Meta: _ke_landed_cost_kes"]


def woo_row(g, sku, price, landed):
    return {
        "Type": "simple", "SKU": sku, "Name": g["title"], "Published": 1,
        "Visibility in catalogue": "visible",
        "Short description": g["short_description"],
        "Description": render_body(g),
        "Regular price": f"{price:.0f}",
        "Categories": g["category"], "Tags": ", ".join(g["tags"]),
        "Meta: _yoast_wpseo_title": g["seo_title"],
        "Meta: _yoast_wpseo_metadesc": g["seo_meta_description"],
        "Meta: _ke_channel": g["channel"],
        "Meta: _ke_keywords": ", ".join(g["google_keywords"]),
        "Meta: _ke_risk_flags": ", ".join(g["risk_flags"]),
        "Meta: _ke_landed_cost_kes": f"{landed:.0f}",
    }


def price_of(row, a):
    cost = float(row["cost_cny"])
    wt = float(row.get("weight_kg") or 0)
    dims = None
    if all(row.get(k) for k in ("l_cm", "w_cm", "h_cm")):
        dims = tuple(float(row[k]) for k in ("l_cm", "w_cm", "h_cm"))
    p = Product(row.get("name", "?"), cost_cny=cost, weight_kg=wt, dims_cm=dims)
    landed = landed_cost(p, a)["落地成本"]
    return max(landed / 0.35, price_for_target(p, a, 0.25)), landed


def main():
    ap = argparse.ArgumentParser(description="上架自动化：候选品 CSV -> WooCommerce 导入 CSV")
    ap.add_argument("csv")
    ap.add_argument("-o", "--out", default="woocommerce-import.csv")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--cpa", type=float)
    ap.add_argument("--dry-run", action="store_true", help="只打印将发送的提示词，不调 API")
    args = ap.parse_args()

    a = Assumptions()
    if args.cpa is not None:
        a.cpa_kes = args.cpa

    with open(args.csv, encoding="utf-8-sig") as fh:
        rows = [r for r in csv.DictReader(fh) if (r.get("cost_cny") or "").strip()]
    if args.limit:
        rows = rows[:args.limit]

    if args.dry_run:
        price, landed = price_of(rows[0], a)
        print("=== SYSTEM ===\n" + SYSTEM)
        print(f"\n=== USER (第 1 个品) ===\n{user_prompt(rows[0], price)}")
        print(f"\n=== 确定性拼接的信任模块 ===\n{TRUST_BLOCK.format(**SHIPPING)}")
        print(f"\n共 {len(rows)} 个品待生成，model={MODEL}")
        return

    client = build_client()
    out = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {}
        for i, row in enumerate(rows, 1):
            price, landed = price_of(row, a)
            futs[ex.submit(generate, client, row, price)] = (i, row, price, landed)
        for fut in as_completed(futs):
            i, row, price, landed = futs[fut]
            try:
                g = fut.result()
            except Exception as e:
                print(f"  x [{i}] {row.get('name','?')}: {e}", file=sys.stderr)
                continue
            out.append(woo_row(g, f"KE{i:04d}", price, landed))
            flags = f"  ⚠ {', '.join(g['risk_flags'])}" if g["risk_flags"] else ""
            print(f"  ✓ [{i}] {g['title'][:58]}")
            print(f"       KES {price:,.0f} · {g['channel']} · {g['channel_reason'][:60]}{flags}")

    with open(args.out, "w", encoding="utf-8-sig", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=WOO_COLS)
        wr.writeheader()
        wr.writerows(out)
    print(f"\n{len(out)} 个品已写入 {args.out}（WooCommerce > 产品 > 导入 直接吃这个格式）")


if __name__ == "__main__":
    main()
