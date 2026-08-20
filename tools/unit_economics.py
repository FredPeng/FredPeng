#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨境一件代发 / 全额预付 / 零本地库存 —— 单位经济模型计算器

用途：在选品阶段判断一个 SKU 在给定售价下是否赚钱，以及
      - 能承受的最高广告 CPA（盈亏平衡 CPA）
      - 要达到目标贡献毛利率，售价应该定在多少
      - 运费占售价比（一件代发模式下的头号杀手）

用法：
    python3 tools/unit_economics.py                      # 跑内置示例
    python3 tools/unit_economics.py --cost-cny 210 --weight 0.8 --price 9500
    python3 tools/unit_economics.py --cost-cny 210 --weight 0.8 --sweep

注意：所有汇率和费率是占位默认值，第一次用之前必须用你自己的
      货代报价、M-Pesa 费率、实际 CPA 和退款率替换。
"""

import argparse
from dataclasses import dataclass, field


# --------------------------------------------------------------------------
# 参数默认值 —— 用你的真实数据覆盖
# --------------------------------------------------------------------------

@dataclass
class Assumptions:
    # 汇率（占位值，需按当期校准）
    cny_to_kes: float = 18.5
    usd_to_kes: float = 131.0

    # 跨境专线运费（首重 + 续重结构）—— 按货代报价填
    freight_first_kg: float = 0.5          # 首重重量 (kg)
    freight_first_usd: float = 10.0        # 首重费用 (USD)
    freight_addl_usd_per_kg: float = 6.5   # 续重费用 (USD/kg)
    volumetric_divisor: int = 6000         # 体积重系数 (cm^3/kg)，空运常用 6000

    # 中国端成本
    qc_handling_cny: float = 3.5           # 转运仓开箱验货 + 换箱 + 贴单
    domestic_cn_freight_cny: float = 8.0   # 1688 到转运仓的国内快递

    # 肯尼亚端成本
    last_mile_cost_kes: float = 350.0      # 你付给本地配送的钱
    last_mile_charged_kes: float = 300.0   # 你向客户收的配送费
    payment_fee_pct: float = 0.02          # M-Pesa / 支付网关费率
    cs_cost_kes: float = 120.0             # 分摊到每单的客服成本（预付模式要全程告知，比有货时重）

    # 风险预留 —— 零备货 + 预付模式下这项显著高于有备货模式
    refund_reserve_pct: float = 0.06       # 退款 / 丢件 / 换货 / 扣关

    # 获客
    cpa_kes: float = 2200.0                # 每单获客成本（预付 + 等两周，转化低，CPA 高）

    # 并单：一票里发几件（组合装 / 同客户并单能摊薄首重）
    items_per_parcel: int = 1


@dataclass
class Product:
    name: str
    cost_cny: float                        # 1688 单件采购价
    weight_kg: float                       # 实重
    dims_cm: tuple = None                  # (长, 宽, 高)，给了就算体积重
    duty_rate: float = 0.25                # 关税率（肯尼亚消费品多为 25%）
    vat_rate: float = 0.16                 # VAT
    misc_levy_rate: float = 0.045          # IDF 2.5% + RDL 2%
    tax_included_line: bool = True         # True = 走双清包税线，税已含在运费里


# --------------------------------------------------------------------------
# 计算
# --------------------------------------------------------------------------

def chargeable_weight(p: Product, a: Assumptions) -> float:
    """计费重 = max(实重, 体积重)"""
    if not p.dims_cm:
        return p.weight_kg
    l, w, h = p.dims_cm
    vol = (l * w * h) / a.volumetric_divisor
    return max(p.weight_kg, vol)


def freight_kes(p: Product, a: Assumptions) -> float:
    """一票的跨境运费，按首重+续重；一票多件时按总计费重算，再摊到每件"""
    cw = chargeable_weight(p, a) * a.items_per_parcel
    if cw <= a.freight_first_kg:
        usd = a.freight_first_usd
    else:
        usd = a.freight_first_usd + (cw - a.freight_first_kg) * a.freight_addl_usd_per_kg
    per_item_usd = usd / a.items_per_parcel
    return per_item_usd * a.usd_to_kes


def landed_cost(p: Product, a: Assumptions) -> dict:
    """单件落地成本拆解 (KES)"""
    goods = p.cost_cny * a.cny_to_kes
    cn_domestic = a.domestic_cn_freight_cny * a.cny_to_kes
    qc = a.qc_handling_cny * a.cny_to_kes
    fr = freight_kes(p, a)

    if p.tax_included_line:
        tax = 0.0  # 双清包税：税费已含在专线运费里
    else:
        cif = goods + fr
        duty = cif * p.duty_rate
        levy = cif * p.misc_levy_rate
        tax = duty + levy + (cif + duty + levy) * p.vat_rate

    total = goods + cn_domestic + qc + fr + tax
    return {
        "货值": goods,
        "国内快递": cn_domestic,
        "验货/转运": qc,
        "跨境运费": fr,
        "税费": tax,
        "落地成本": total,
    }


def economics(p: Product, a: Assumptions, price_kes: float) -> dict:
    lc = landed_cost(p, a)
    cost = lc["落地成本"]
    gross = price_kes - cost

    delivery_net = a.last_mile_cost_kes - a.last_mile_charged_kes
    payment = price_kes * a.payment_fee_pct
    refund = price_kes * a.refund_reserve_pct
    variable = a.cpa_kes + delivery_net + payment + refund + a.cs_cost_kes

    contribution = gross - variable

    # 盈亏平衡 CPA：其他成本不变时，最多能出多少获客成本
    breakeven_cpa = gross - (delivery_net + payment + refund + a.cs_cost_kes)

    return {
        "落地明细": lc,
        "落地成本": cost,
        "售价": price_kes,
        "毛利": gross,
        "毛利率": gross / price_kes if price_kes else 0,
        "加价倍数": price_kes / cost if cost else 0,
        "运费占售价": lc["跨境运费"] / price_kes if price_kes else 0,
        "CPA": a.cpa_kes,
        "配送净支出": delivery_net,
        "支付费": payment,
        "退款预留": refund,
        "客服": a.cs_cost_kes,
        "贡献额": contribution,
        "贡献毛利率": contribution / price_kes if price_kes else 0,
        "盈亏平衡CPA": breakeven_cpa,
    }


def price_for_target(p: Product, a: Assumptions, target_contrib_pct: float) -> float:
    """求达到目标贡献毛利率所需的售价（解一元一次方程）"""
    lc = landed_cost(p, a)
    cost = lc["落地成本"]
    fixed = a.cpa_kes + (a.last_mile_cost_kes - a.last_mile_charged_kes) + a.cs_cost_kes
    # P - cost - fixed - P*(pay + refund) = target * P
    denom = 1 - a.payment_fee_pct - a.refund_reserve_pct - target_contrib_pct
    if denom <= 0:
        return float("inf")
    return (cost + fixed) / denom


# --------------------------------------------------------------------------
# 输出
# --------------------------------------------------------------------------

def kes(x): return f"{x:>10,.0f}"
def pct(x): return f"{x*100:>6.1f}%"


def report(p: Product, a: Assumptions, price: float):
    e = economics(p, a, price)
    print(f"\n{'='*62}")
    print(f"  {p.name}")
    print(f"{'='*62}")
    print(f"  1688 采购 ¥{p.cost_cny:.0f}   实重 {p.weight_kg}kg   计费重 {chargeable_weight(p,a):.2f}kg"
          f"   一票 {a.items_per_parcel} 件")

    print(f"\n  落地成本拆解 (KES)")
    for k, v in e["落地明细"].items():
        if k == "落地成本":
            print(f"    {'-'*40}")
        print(f"    {k:<12}{kes(v)}")

    print(f"\n  单位经济 (KES)")
    print(f"    {'售价':<12}{kes(e['售价'])}")
    print(f"    {'落地成本':<12}{kes(-e['落地成本'])}")
    print(f"    {'毛利':<12}{kes(e['毛利'])}   毛利率 {pct(e['毛利率'])}  加价 {e['加价倍数']:.2f}x")
    print(f"    {'广告 CPA':<12}{kes(-e['CPA'])}")
    print(f"    {'配送净支出':<12}{kes(-e['配送净支出'])}")
    print(f"    {'支付手续费':<12}{kes(-e['支付费'])}")
    print(f"    {'退款预留':<12}{kes(-e['退款预留'])}")
    print(f"    {'客服':<12}{kes(-e['客服'])}")
    print(f"    {'-'*40}")
    print(f"    {'贡献额':<12}{kes(e['贡献额'])}   贡献毛利率 {pct(e['贡献毛利率'])}")

    print(f"\n  判定")
    fr_pct = e["运费占售价"]
    checks = [
        ("运费占售价 ≤ 12%", fr_pct <= 0.12, f"{pct(fr_pct)}"),
        ("售价 ≥ 6,000 KES", price >= 6000, f"{price:,.0f}"),
        ("毛利率 ≥ 65%", e["毛利率"] >= 0.65, pct(e["毛利率"])),
        ("贡献毛利率 ≥ 25%", e["贡献毛利率"] >= 0.25, pct(e["贡献毛利率"])),
    ]
    for label, ok, val in checks:
        print(f"    [{'PASS' if ok else 'FAIL'}] {label:<22} 实际 {val}")

    print(f"\n    盈亏平衡 CPA        {e['盈亏平衡CPA']:,.0f} KES"
          f"   (当前 {a.cpa_kes:,.0f}，余量 {e['盈亏平衡CPA']-a.cpa_kes:+,.0f})")
    for t in (0.25, 0.30):
        print(f"    贡献毛利率 {t*100:.0f}% 所需售价  {price_for_target(p,a,t):,.0f} KES")


def sweep(p: Product, a: Assumptions, lo: float, hi: float, step: float):
    print(f"\n  售价敏感性 —— {p.name}")
    print(f"  {'售价':>9} {'毛利率':>8} {'加价':>7} {'运费%':>7} {'贡献额':>10} {'贡献率':>8}")
    print(f"  {'-'*54}")
    price = lo
    while price <= hi:
        e = economics(p, a, price)
        flag = " <=" if e["贡献毛利率"] >= 0.25 and e["贡献毛利率"] < 0.25 + 0.05 else ""
        print(f"  {price:>9,.0f} {pct(e['毛利率'])} {e['加价倍数']:>6.2f}x"
              f" {pct(e['运费占售价'])} {e['贡献额']:>10,.0f} {pct(e['贡献毛利率'])}{flag}")
        price += step


DEMO = [
    # 反例：低价小件 —— 一件代发下运费吃掉一切
    (Product("反例 A：低价小件（3,000 KES 档）", cost_cny=55, weight_kg=0.5), 3000),
    # 及格线附近
    (Product("样例 B：中价（6,000 KES 档）", cost_cny=110, weight_kg=0.8), 6000),
    # 目标品：本地买不到、高价值密度
    (Product("样例 C：目标品（10,000 KES 档）", cost_cny=175, weight_kg=0.8), 10000),
]


def main():
    ap = argparse.ArgumentParser(description="跨境一件代发预付模式单位经济计算器")
    ap.add_argument("--cost-cny", type=float, help="1688 采购价 (CNY)")
    ap.add_argument("--weight", type=float, help="实重 (kg)")
    ap.add_argument("--dims", type=str, help="尺寸 cm，格式 30x20x10（算体积重）")
    ap.add_argument("--price", type=float, help="售价 (KES)")
    ap.add_argument("--cpa", type=float, help="每单获客成本 (KES)")
    ap.add_argument("--items-per-parcel", type=int, help="一票发几件")
    ap.add_argument("--refund-reserve", type=float, help="退款预留比例，如 0.06")
    ap.add_argument("--name", type=str, default="自定义 SKU")
    ap.add_argument("--sweep", action="store_true", help="输出售价敏感性表")
    args = ap.parse_args()

    a = Assumptions()
    if args.cpa is not None:
        a.cpa_kes = args.cpa
    if args.items_per_parcel is not None:
        a.items_per_parcel = args.items_per_parcel
    if args.refund_reserve is not None:
        a.refund_reserve_pct = args.refund_reserve

    if args.cost_cny is None or args.weight is None:
        print("\n【内置示例】所有费率为占位默认值，用你的真实报价替换后再做决策。")
        for p, price in DEMO:
            report(p, a, price)
        sweep(DEMO[2][0], a, 6000, 16000, 2000)
        print("\n提示：python3 tools/unit_economics.py --cost-cny 175 --weight 0.8 --sweep\n")
        return

    dims = None
    if args.dims:
        dims = tuple(float(x) for x in args.dims.lower().split("x"))
    p = Product(args.name, cost_cny=args.cost_cny, weight_kg=args.weight, dims_cm=dims)

    price = args.price or price_for_target(p, a, 0.28)
    report(p, a, price)
    if args.sweep:
        base = landed_cost(p, a)["落地成本"]
        sweep(p, a, round(base * 2 / 500) * 500, round(base * 4 / 500) * 500, 1000)


if __name__ == "__main__":
    main()
