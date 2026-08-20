#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
选品批量筛选器 —— 跨境集货 / 全额预付 / 零本地库存

输入一份候选品 CSV，输出：硬门槛通过与否、落地成本、建议售价、评分与排序。
硬门槛来自 unit_economics.py 的同一套参数，改那里的 Assumptions 即可同步生效。

用法：
    python3 tools/screen.py --init candidates.csv      # 生成带示例的模板
    python3 tools/screen.py candidates.csv             # 跑筛选
    python3 tools/screen.py candidates.csv --cpa 1800  # 用你的真实 CPA
    python3 tools/screen.py candidates.csv --all       # 连被砍的一起显示（含原因）

CSV 列（缺失的留空即可，只是不参与打分）：
    name              品名
    cost_cny          1688 单件采购价 (CNY)
    weight_kg         实重 (kg)
    l_cm,w_cm,h_cm    外箱尺寸 (cm)  ← 抛货比 5000 下这是第一约束，务必填
    ali_price_kes     速卖通售价 (KES)，用于成本合理性校验
    local_price_kes   肯尼亚本地零售价 (KES)，用于定价空间判断
    reviews           速卖通评论数（真实销量代理）
    reviews_90d_pct   近 90 天评论占比 (0-100)，判断上升期还是衰退期
    sellers           同款卖家数
    main_imgs         主图数
    has_video         1/0
    variants          变体数
    suppliers_1688    可用 1688 供应商数
"""

import argparse, csv, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_economics import (Assumptions, Product, landed_cost, chargeable_weight,
                            economics, price_for_target)

TEMPLATE = """name,cost_cny,weight_kg,l_cm,w_cm,h_cm,ali_price_kes,local_price_kes,reviews,reviews_90d_pct,sellers,main_imgs,has_video,variants,suppliers_1688
示例A 折叠收纳袋(软货),45,0.6,30,22,8,7800,14000,2400,38,6,8,1,2,3
示例B 塑料收纳箱(刚性抛货),30,1.2,40,30,30,5200,9000,900,12,25,7,1,3,4
示例C 小型美容仪,175,0.5,22,16,9,13500,26000,1800,45,4,9,1,1,2
"""

FAIL = {
    "freight":   "运费占售价过高",
    "landed":    "落地成本超过售价 35%",
    "floor":     "售价低于 CPA 下限",
    "suppliers": "1688 供应商不足 2 家",
    "variants":  "变体超过 2 个",
    "nodims":    "缺外箱尺寸，无法计算体积重",
}


def f(row, key, default=None, cast=float):
    v = (row.get(key) or "").strip()
    if not v:
        return default
    try:
        return cast(v)
    except ValueError:
        return default


def evaluate(row, a, freight_pct_max=0.12, landed_ratio_max=0.35):
    name = (row.get("name") or "?").strip()
    cost = f(row, "cost_cny")
    wt = f(row, "weight_kg", 0.0)
    l, w, h = f(row, "l_cm"), f(row, "w_cm"), f(row, "h_cm")
    dims = (l, w, h) if None not in (l, w, h) else None

    if cost is None:
        return {"name": name, "fails": ["缺 1688 采购价"], "score": 0}

    p = Product(name, cost_cny=cost, weight_kg=wt, dims_cm=dims)
    lc = landed_cost(p, a)
    cw = chargeable_weight(p, a)

    # 建议售价：取「落地成本倍数」与「CPA 下限」的大者
    price_by_cost = lc["落地成本"] / landed_ratio_max
    price_by_cpa = price_for_target(p, a, 0.25)
    price = max(price_by_cost, price_by_cpa)

    fails = []
    if dims is None:
        fails.append(FAIL["nodims"])
    if lc["跨境运费"] / price > freight_pct_max:
        fails.append(f"{FAIL['freight']}（{lc['跨境运费']/price:.0%}）")
    if (f(row, "suppliers_1688", 0, int) or 0) < 2:
        fails.append(FAIL["suppliers"])
    if (f(row, "variants", 0, int) or 0) > 2:
        fails.append(FAIL["variants"])

    # --- 评分（满分 100，仅用于排序，不构成通过条件）---
    score, notes = 0.0, []

    # 毛利空间 30：落地成本占建议售价越低越好
    ratio = lc["落地成本"] / price
    score += max(0.0, min(30.0, (landed_ratio_max - ratio) / landed_ratio_max * 30 + 15))

    # 体积效率 20：计费重 / 实重，越接近 1 越好（可压缩性代理）
    if dims and wt:
        bulk = cw / wt
        score += 20 if bulk <= 1.0 else max(0.0, 20 - (bulk - 1) * 8)
        if bulk > 2:
            notes.append(f"抛货 {bulk:.1f}x，先问供应商能否发散装")

    # 需求信号 25：评论数（对数）+ 近 90 天占比
    rev, pct = f(row, "reviews", 0), f(row, "reviews_90d_pct", 0)
    if rev:
        score += min(12.0, (rev ** 0.5) / 50 * 12)
    if pct:
        score += min(13.0, pct / 40 * 13)
        if pct < 15:
            notes.append(f"近 90 天评论仅 {pct:.0f}%，疑似衰退期")

    # 竞争 15：卖家少但有销量最优
    sellers = f(row, "sellers")
    if sellers is not None:
        score += 15 if sellers <= 5 else max(0.0, 15 - (sellers - 5) * 1.2)
        if sellers > 20:
            notes.append(f"{sellers:.0f} 家在卖，素材烂大街")

    # 素材 10
    score += min(6.0, (f(row, "main_imgs", 0) or 0) / 6 * 6)
    score += 4 if f(row, "has_video", 0) else 0

    # 定价空间提示
    local = f(row, "local_price_kes")
    ali = f(row, "ali_price_kes")
    if local and price > local * 0.85:
        notes.append(f"建议售价 {price:,.0f} vs 本地零售 {local:,.0f} —— 相对本地无价格优势")
    if ali and price > ali * 1.3:
        notes.append(f"建议售价比速卖通高 {price/ali-1:.0%}，需要有理由（交付/服务/本地化）")
    if ali and lc["落地成本"] > ali * 0.55:
        notes.append("落地成本 > 速卖通价 55%，采购成本偏高")


    return {"name": name, "cost": cost, "cw": cw, "landed": lc["落地成本"],
            "freight": lc["跨境运费"], "price": price, "local": local,
            "fails": fails, "score": round(score, 1), "notes": notes,
            "no_signal": (not rev and not pct and sellers is None)}


def main():
    ap = argparse.ArgumentParser(description="选品批量筛选器")
    ap.add_argument("csv", nargs="?", help="候选品 CSV")
    ap.add_argument("--init", metavar="PATH", help="生成 CSV 模板")
    ap.add_argument("--cpa", type=float, help="每单获客成本 (KES)")
    ap.add_argument("--all", action="store_true", help="连被砍的一起显示")
    args = ap.parse_args()

    if args.init:
        with open(args.init, "w", encoding="utf-8-sig") as fh:
            fh.write(TEMPLATE)
        print(f"模板已写入 {args.init}")
        return
    if not args.csv:
        ap.error("需要指定 CSV，或用 --init 生成模板")

    a = Assumptions()
    if args.cpa is not None:
        a.cpa_kes = args.cpa

    with open(args.csv, encoding="utf-8-sig") as fh:
        rows = [evaluate(r, a) for r in csv.DictReader(fh)]

    passed = sorted([r for r in rows if not r["fails"]], key=lambda r: -r["score"])
    killed = [r for r in rows if r["fails"]]

    print(f"\n候选 {len(rows)} 个 -> 通过 {len(passed)}，砍掉 {len(killed)}"
          f"   （CPA {a.cpa_kes:,.0f}，$"
          f"{a.freight_linear_usd_per_kg:.0f}/kg，抛货比 {a.volumetric_divisor}）")

    if passed and all(r.get("no_signal") for r in passed):
        print("\n  ⚠ 需求信号列（reviews / reviews_90d_pct / sellers）全部为空 ——")
        print("    下表的「分」仅反映经济性，不构成排序依据。真正的排序需先填这三列。")

    if passed:
        print(f"\n{'#':<3}{'品名':<26}{'分':>5}{'采购¥':>7}{'计费kg':>8}"
              f"{'落地':>8}{'建议售价':>10}{'运费%':>7}")
        print("-" * 76)
        for i, r in enumerate(passed, 1):
            print(f"{i:<3}{r['name'][:24]:<26}{r['score']:>5.0f}{r['cost']:>7.0f}"
                  f"{r['cw']:>8.2f}{r['landed']:>8,.0f}{r['price']:>10,.0f}"
                  f"{r['freight']/r['price']:>7.0%}")
            for n in r["notes"]:
                print(f"      ! {n}")

    if killed and (args.all or True):
        print(f"\n砍掉：")
        for r in killed:
            print(f"  x {r['name'][:30]:<32}{'；'.join(r['fails'])}")
    print()


if __name__ == "__main__":
    main()
