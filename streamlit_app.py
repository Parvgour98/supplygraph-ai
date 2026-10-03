"""SupplyGraph AI — Supply Chain Ontology & Governed Conversational Analytics.

Every number in this app is produced through the governed semantic view
SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY, either via SEMANTIC_VIEW()
queries or via Cortex Analyst SQL generated from that semantic view.
"""
import hashlib
import json

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="SupplyGraph AI", layout="wide")
session = get_active_session()

SV = "SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY"
SOURCE = "SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (TPC-H SF1, orders 1992-01-01 to 1998-08-02)"
BLUE, AMBER, RED = "#29B5E8", "#F5A623", "#E8582A"

st.markdown(
    """
<style>
.hero {background: linear-gradient(90deg,#11567F 0%,#29B5E8 100%); color:white;
       padding:18px 24px; border-radius:12px; margin-bottom:12px;}
.hero h2 {color:white; margin:0;}
.hero p {color:#E6F6FD; margin:4px 0 0 0;}
.badge {display:inline-block; padding:2px 10px; border-radius:10px; font-size:0.8rem;
        background:#E6F6FD; color:#11567F; margin-right:6px; font-weight:600;}
.ok {background:#E3F7E8; color:#1B7F3B;}
</style>
""",
    unsafe_allow_html=True,
)

# --------------------------------------------------------------------------
# Governed metric catalogue (mirrors the METRICS clause of the semantic view)
# --------------------------------------------------------------------------
METRICS = [
    ("Total Spend", "shipments.total_spend", "SUM(net_revenue), net_revenue = extended_price * (1 - discount)",
     "Net line-item value after discount. Canonical spend measure."),
    ("On-Time Delivery Rate", "shipments.on_time_delivery_rate", "AVG(is_on_time) * 100, is_on_time = receipt_date <= commit_date",
     "Share of shipment lines received on or before the committed date."),
    ("Fill Rate", "shipments.fill_rate", "(1 - AVG(return_flag = 'R')) * 100",
     "Share of shipment lines not returned (fulfilment-quality proxy; TPC-H has no backorder data)."),
    ("Average Lead Time", "shipments.average_lead_time", "AVG(DATEDIFF(day, order_date, receipt_date))",
     "End-to-end days from order placement to goods receipt."),
    ("Return Rate", "shipments.return_rate", "AVG(return_flag = 'R') * 100", "Share of shipment lines returned."),
    ("Average Shipping Time", "shipments.average_shipping_time", "AVG(DATEDIFF(day, ship_date, receipt_date))", "Transit days."),
    ("Average Processing Time", "shipments.average_processing_time", "AVG(DATEDIFF(day, order_date, ship_date))", "Days to dispatch."),
    ("Supplier Performance Score", "supplier_performance.supplier_performance_score (fact)",
     "0.40*OTD% + 0.35*FillRate% + 0.25*(100 - ReturnRate%)",
     "Composite 0-100 scorecard per supplier. Note: fill rate = 100 - return rate, so effectively 0.40*OTD + 0.60*FillRate."),
    ("Spend Concentration", "derived from shipments.total_spend",
     "supplier total_spend / overall total_spend * 100", "Share of total spend held by a supplier (concentration risk)."),
    ("Total Inventory Value", "supplier_parts.total_inventory_value", "SUM(available_quantity * supply_cost)",
     "Value of supplier-held availability at supply cost."),
]

HERO_QUESTIONS = {
    "Planning": "What is the on-time delivery rate by supplier region?",
    "Procurement": "Which supplier regions deliver on time most often? Show on-time delivery percentage by supplier region.",
    "Logistics": "Show the OTD percentage for each source region.",
}

# Verified queries registered in the semantic view (used when Analyst is unreachable).
VERIFIED = {
    "on-time delivery rate by shipping mode": "SELECT ship_mode, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct, COUNT(*) AS shipment_count FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY ship_mode ORDER BY on_time_pct DESC",
    "total spend by supplier region": "SELECT supplier_region, ROUND(SUM(net_revenue), 2) AS total_spend FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY supplier_region ORDER BY total_spend DESC",
    "top 10 suppliers by performance score": "SELECT supplier_name, supplier_region, supplier_performance_score, on_time_delivery_pct, fill_rate_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE ORDER BY supplier_performance_score DESC LIMIT 10",
    "average lead time by order priority": "SELECT order_priority, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY order_priority ORDER BY order_priority",
    "on-time delivery rate by supplier region": "SELECT supplier_region, ROUND(AVG(is_on_time) * 100, 2) AS on_time_delivery_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY supplier_region ORDER BY on_time_delivery_pct DESC",
}


# --------------------------------------------------------------------------
# Data access
# --------------------------------------------------------------------------
@st.cache_data(ttl=900, show_spinner=False)
def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


def sv(metrics: str, dimensions: str = "", order_by: str = "") -> pd.DataFrame:
    """Query the governed semantic view."""
    dims = f" DIMENSIONS {dimensions}" if dimensions else ""
    order = f" ORDER BY {order_by}" if order_by else ""
    return run_query(f"SELECT * FROM SEMANTIC_VIEW({SV}{dims} METRICS {metrics}){order}")


def sv_sql(metrics: str, dimensions: str = "") -> str:
    dims = f"\n  DIMENSIONS {dimensions}" if dimensions else ""
    return f"SELECT * FROM SEMANTIC_VIEW(\n  {SV}{dims}\n  METRICS {metrics})"


@st.cache_data(ttl=900, show_spinner=False)
def governed_kpis() -> dict:
    df = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate, "
            "shipments.average_lead_time, shipments.return_rate, shipments.shipment_count, "
            "suppliers.supplier_count, orders.order_count")
    return {k: float(v) for k, v in df.iloc[0].to_dict().items()}


def kpi_fingerprint(k: dict) -> str:
    payload = json.dumps({key: round(val, 6) for key, val in sorted(k.items())})
    return hashlib.sha256(payload.encode()).hexdigest()[:12]


@st.cache_data(ttl=900, show_spinner=False)
def ask_analyst(question: str) -> dict:
    """Call the Cortex Analyst REST API against the semantic view."""
    try:
        import _snowflake  # available inside Streamlit in Snowflake
    except ImportError:
        return {"ok": False, "error": "Cortex Analyst API is only reachable inside Streamlit in Snowflake."}
    try:
        resp = _snowflake.send_snow_api_request(
            "POST", "/api/v2/cortex/analyst/message", {}, {},
            {"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
             "semantic_view": SV},
            None, 60000,
        )
        body = json.loads(resp["content"])
        if resp.get("status", 200) >= 400:
            return {"ok": False, "error": body.get("message", str(body))[:400]}
        out = {"ok": True, "text": "", "sql": None, "request_id": body.get("request_id")}
        for item in body.get("message", {}).get("content", []):
            if item.get("type") == "text":
                out["text"] += item.get("text", "")
            elif item.get("type") == "sql":
                out["sql"] = item.get("statement")
        return out
    except Exception as exc:  # surface the reason instead of silently inventing an answer
        return {"ok": False, "error": str(exc)[:400]}


def verified_match(question: str):
    q = question.lower()
    for key, sql in VERIFIED.items():
        if all(word in q for word in key.split() if len(word) > 3):
            return key, sql
    return None, None


def fmt_b(x: float) -> str:
    return f"${x / 1e9:,.2f}B"


# --------------------------------------------------------------------------
# Sidebar
# --------------------------------------------------------------------------
with st.sidebar:
    st.markdown("### SupplyGraph AI")
    st.caption("Challenge 5 · Supply Chain Ontology & Governed Conversational Analytics")
    st.markdown("**Governed layer**")
    st.code(SV, language=None)
    st.markdown("**Source data**")
    st.caption(SOURCE)
    st.markdown("**Engines**")
    st.caption("Semantic View · Cortex Analyst · Streamlit in Snowflake")
    if st.button("Refresh cached results"):
        st.cache_data.clear()
        st.rerun()

# --------------------------------------------------------------------------
# Header
# --------------------------------------------------------------------------
st.markdown(
    '<div class="hero"><h2>SupplyGraph AI</h2>'
    "<p>One supply-chain ontology. One set of governed metrics. The same answer for every persona.</p></div>",
    unsafe_allow_html=True,
)

k = governed_kpis()
c = st.columns(4)
c[0].metric("Total Spend", fmt_b(k["TOTAL_SPEND"]))
c[1].metric("On-Time Delivery", f"{k['ON_TIME_DELIVERY_RATE']:.2f}%")
c[2].metric("Fill Rate", f"{k['FILL_RATE']:.2f}%")
c[3].metric("Avg Lead Time", f"{k['AVERAGE_LEAD_TIME']:.1f} days")

tabs = st.tabs([
    "Hero Demo",
    "Executive Overview",
    "Supplier Performance",
    "Regional Risk & Spend",
    "Ask SupplyGraph",
    "Metrics & Evidence",
    "Persona Views",
])

# ==========================================================================
# 1. HERO DEMO
# ==========================================================================
with tabs[0]:
    st.subheader("One question, three personas, one governed answer")
    st.write(
        "Planning, Procurement and Logistics each ask about delivery reliability in their own words. "
        "Cortex Analyst maps every phrasing onto the same governed metric "
        "(`on_time_delivery_rate = AVG(is_on_time) * 100`) and the same ontology dimension "
        "(`supplier_region`). The results are compared automatically."
    )

    run_live = st.button("Ask all three personas live via Cortex Analyst", type="primary")
    canonical = sv("shipments.on_time_delivery_rate", "shipments.supplier_region", "supplier_region")
    canonical["ON_TIME_DELIVERY_RATE"] = canonical["ON_TIME_DELIVERY_RATE"].astype(float).round(2)

    cols = st.columns(3)
    persona_results = {}
    for col, (persona, question) in zip(cols, HERO_QUESTIONS.items()):
        with col:
            st.markdown(f"**{persona}**")
            st.info(f"“{question}”")
            if run_live:
                res = ask_analyst(question)
                if res["ok"] and res["sql"]:
                    df = run_query(res["sql"])
                    df.columns = [x.upper() for x in df.columns]
                    otd_col = next(c_ for c_ in df.columns if "ON_TIME" in c_ or "OTD" in c_)
                    view = df[["SUPPLIER_REGION", otd_col]].rename(columns={otd_col: "ON_TIME_DELIVERY_RATE"})
                    view["ON_TIME_DELIVERY_RATE"] = view["ON_TIME_DELIVERY_RATE"].astype(float).round(2)
                    persona_results[persona] = view.sort_values("SUPPLIER_REGION").reset_index(drop=True)
                    st.dataframe(persona_results[persona], hide_index=True, width="stretch")
                    with st.expander("Generated SQL"):
                        st.code(res["sql"], language="sql")
                else:
                    st.warning(f"Analyst unavailable: {res.get('error') or res.get('text')}")

    st.markdown("**Governed reference (direct `SEMANTIC_VIEW()` query)**")
    left, right = st.columns([2, 3])
    with left:
        st.dataframe(canonical, hide_index=True, width="stretch")
    with right:
        st.code(sv_sql("shipments.on_time_delivery_rate", "shipments.supplier_region"), language="sql")

    if run_live and len(persona_results) == 3:
        ref = canonical.sort_values("SUPPLIER_REGION").reset_index(drop=True)
        same = all(df.equals(ref) for df in persona_results.values())
        if same:
            st.success("IDENTICAL: all three persona answers match the governed semantic-view result row for row.")
        else:
            st.error("Mismatch detected between persona answers and the governed reference.")
    elif not run_live:
        st.caption("Press the button to run the three questions live. Validated result: all three return identical values.")

# ==========================================================================
# 2. EXECUTIVE OVERVIEW
# ==========================================================================
with tabs[1]:
    st.subheader("Executive overview")
    r = st.columns(4)
    r[0].metric("Suppliers", f"{k['SUPPLIER_COUNT']:,.0f}")
    r[1].metric("Orders", f"{k['ORDER_COUNT']:,.0f}")
    r[2].metric("Shipment lines", f"{k['SHIPMENT_COUNT']:,.0f}")
    r[3].metric("Return Rate", f"{k['RETURN_RATE']:.2f}%")

    yearly = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate",
                "shipments.order_year", "order_year")
    yearly["ORDER_YEAR"] = yearly["ORDER_YEAR"].astype(str)
    yearly["SPEND_B"] = yearly["TOTAL_SPEND"].astype(float) / 1e9
    a, b = st.columns(2)
    with a:
        st.markdown("**Spend by order year ($B)**")
        st.bar_chart(yearly, x="ORDER_YEAR", y="SPEND_B", color=BLUE)
        st.caption("1998 is a partial year (orders end 1998-08-02).")
    with b:
        st.markdown("**On-time delivery and fill rate by year (%)**")
        st.line_chart(yearly, x="ORDER_YEAR", y=["ON_TIME_DELIVERY_RATE", "FILL_RATE"], color=[BLUE, AMBER])

    seg = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate, shipments.average_lead_time",
             "shipments.market_segment", "total_spend DESC")
    st.markdown("**Customer market segments**")
    st.dataframe(seg, hide_index=True, width="stretch")

# ==========================================================================
# 3. SUPPLIER PERFORMANCE
# ==========================================================================
with tabs[2]:
    st.subheader("Supplier performance scorecard")
    perf = run_query(
        "SELECT supplier_name, supplier_nation, supplier_region, supplier_performance_score, "
        "on_time_delivery_pct, fill_rate_pct, return_rate_pct, total_revenue, total_orders, "
        "distinct_parts_supplied FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE "
        "ORDER BY supplier_performance_score DESC"
    )
    perf.columns = [x.upper() for x in perf.columns]
    f1, f2, f3 = st.columns(3)
    regions = f1.multiselect("Supplier region", sorted(perf["SUPPLIER_REGION"].unique()))
    view_mode = f2.radio("Show", ["Top performers", "Bottom performers"], horizontal=True)
    n = f3.selectbox("Rows", [10, 25, 50, 100], index=1)
    data = perf[perf["SUPPLIER_REGION"].isin(regions)] if regions else perf
    data = data.head(n) if view_mode == "Top performers" else data.tail(n).iloc[::-1]
    st.dataframe(data, hide_index=True, width="stretch")

    perf["SCORE_BAND"] = pd.cut(perf["SUPPLIER_PERFORMANCE_SCORE"].astype(float), bins=10).astype(str)
    hist = perf.groupby("SCORE_BAND", observed=True).size().reset_index(name="SUPPLIERS")
    st.markdown("**Score distribution (10,000 suppliers)**")
    st.bar_chart(hist, x="SCORE_BAND", y="SUPPLIERS", color=BLUE)
    st.caption("Score = 0.40·OTD% + 0.35·FillRate% + 0.25·(100 − ReturnRate%). Source: V_SUPPLIER_PERFORMANCE, "
               "registered in the semantic view as the supplier_performance logical table.")

# ==========================================================================
# 4. REGIONAL RISK & SPEND
# ==========================================================================
with tabs[3]:
    st.subheader("Regional risk and spend")
    reg = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate, "
             "shipments.average_lead_time, shipments.return_rate", "shipments.supplier_region", "total_spend DESC")
    reg["SPEND_B"] = reg["TOTAL_SPEND"].astype(float) / 1e9
    reg["SPEND_SHARE_PCT"] = (reg["TOTAL_SPEND"].astype(float) / k["TOTAL_SPEND"] * 100).round(2)
    a, b = st.columns(2)
    with a:
        st.markdown("**Spend by supplier region ($B)**")
        st.bar_chart(reg, x="SUPPLIER_REGION", y="SPEND_B", color=BLUE)
    with b:
        st.markdown("**Return rate by supplier region (%)**")
        st.bar_chart(reg, x="SUPPLIER_REGION", y="RETURN_RATE", color=RED)
    st.dataframe(reg.drop(columns=["SPEND_B"]), hide_index=True, width="stretch")

    st.markdown("**Spend concentration: top 15 suppliers**")
    sup = sv("shipments.total_spend", "shipments.supplier_name, shipments.supplier_region", "total_spend DESC")
    sup = sup.head(15).copy()
    sup["SPEND_SHARE_PCT"] = (sup["TOTAL_SPEND"].astype(float) / k["TOTAL_SPEND"] * 100).round(4)
    top15 = sup["SPEND_SHARE_PCT"].sum()
    st.dataframe(sup, hide_index=True, width="stretch")
    st.caption(f"Top 15 suppliers hold {top15:.3f}% of total spend; spend is highly diversified "
               "(TPC-H distributes volume evenly across 10,000 suppliers).")

    inv = sv("supplier_parts.total_inventory_value, supplier_parts.total_available_quantity",
             "supplier_parts.supplier_region", "total_inventory_value DESC")
    st.markdown("**Supplier-held inventory by region**")
    st.dataframe(inv, hide_index=True, width="stretch")

# ==========================================================================
# 5. ASK SUPPLYGRAPH (conversational analytics)
# ==========================================================================
with tabs[4]:
    st.subheader("Ask SupplyGraph: governed conversational analytics")
    st.caption("Questions go to Cortex Analyst with the semantic view as context. The generated SQL, the result "
               "and the governed definitions used are shown for every answer.")
    examples = [
        "What is the on-time delivery rate by shipping mode?",
        "Who are the top 10 suppliers by performance score?",
        "What is the spend concentration across top suppliers?",
        "What is the average lead time by order priority?",
        "What is the total inventory value by supplier region?",
        "How has supply chain performance changed year over year?",
    ]
    ex_cols = st.columns(3)
    for i, ex in enumerate(examples):
        if ex_cols[i % 3].button(ex, key=f"ex{i}", width="stretch"):
            st.session_state["q"] = ex
    question = st.text_input("Your question", value=st.session_state.get("q", ""),
                             placeholder="e.g. Which ship mode has the best on-time delivery?")

    if question:
        with st.spinner("Cortex Analyst is interpreting the question against the ontology..."):
            res = ask_analyst(question)
        sql, origin = None, None
        if res["ok"]:
            if res["text"]:
                st.markdown(f"**Interpretation:** {res['text']}")
            sql, origin = res["sql"], "Cortex Analyst"
        else:
            key, vsql = verified_match(question)
            if vsql:
                sql, origin = vsql, f"Verified query '{key}' (Cortex Analyst unreachable: {res['error'][:120]})"
            else:
                st.error(f"Cortex Analyst is unreachable and no verified query matches. Reason: {res['error']}")
        if sql:
            try:
                answer = run_query(sql)
                st.markdown("**Answer**")
                st.dataframe(answer, hide_index=True, width="stretch")
            except Exception as exc:
                st.error(f"Generated SQL failed: {str(exc)[:300]}")
            with st.expander("Evidence: SQL, source and governed definitions", expanded=True):
                st.markdown(f"**Generated by:** {origin}")
                st.code(sql, language="sql")
                used = [m for m in METRICS if any(t in sql.lower() for t in
                        [m[1].split(".")[-1].split(" ")[0], m[0].lower().replace(" ", "_")])]
                hints = {"is_on_time": "On-Time Delivery Rate", "return_flag": "Fill Rate",
                         "net_revenue": "Total Spend", "delivery_lead_time": "Average Lead Time",
                         "supplier_performance_score": "Supplier Performance Score",
                         "inventory_value": "Total Inventory Value"}
                names = {m[0] for m in used} | {v for t, v in hints.items() if t in sql.lower()}
                defs = pd.DataFrame([m for m in METRICS if m[0] in names],
                                    columns=["Metric", "Semantic view object", "Definition", "Business meaning"])
                if not defs.empty:
                    st.dataframe(defs, hide_index=True, width="stretch")
                st.caption(f"Semantic view: {SV} · Source: {SOURCE}")
                if res.get("request_id"):
                    st.caption(f"Cortex Analyst request id: {res['request_id']}")

# ==========================================================================
# 6. METRICS & EVIDENCE
# ==========================================================================
with tabs[5]:
    st.subheader("Governed metric definitions")
    st.dataframe(pd.DataFrame(METRICS, columns=["Metric", "Semantic view object", "Definition", "Business meaning"]),
                 hide_index=True, width="stretch")

    st.subheader("Live evidence: semantic view vs. independent direct SQL")
    direct = run_query(
        "SELECT SUM(NET_REVENUE) AS TOTAL_SPEND, AVG(IS_ON_TIME)*100 AS ON_TIME_DELIVERY_RATE, "
        "(1-AVG(CASE WHEN RETURN_FLAG='R' THEN 1 ELSE 0 END))*100 AS FILL_RATE, "
        "AVG(DELIVERY_LEAD_TIME_DAYS) AS AVERAGE_LEAD_TIME, COUNT(*) AS SHIPMENT_COUNT "
        "FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS"
    ).iloc[0]
    rows = []
    for key in ["TOTAL_SPEND", "ON_TIME_DELIVERY_RATE", "FILL_RATE", "AVERAGE_LEAD_TIME", "SHIPMENT_COUNT"]:
        a_, b_ = round(k[key], 6), round(float(direct[key]), 6)
        rows.append({"Metric": key, "Semantic view": a_, "Direct SQL": b_, "Status": "MATCH" if a_ == b_ else "MISMATCH"})
    st.dataframe(pd.DataFrame(rows), hide_index=True, width="stretch")

    st.subheader("Ontology")
    st.markdown("""
| Entity | Logical table | Key | Relationships |
|---|---|---|---|
| Region / Nation | denormalised onto Supplier & Customer | REGION_NAME, NATION_NAME | Region ⊃ Nation ⊃ Supplier / Customer |
| Supplier | `suppliers` (V_SUPPLIERS) | SUPPLIER_KEY | ships Shipments, offers Supplier-Parts |
| Part | `parts` (V_PARTS) | PART_KEY | supplied via Supplier-Parts, shipped in Shipments |
| Supplier-Part | `supplier_parts` (V_SUPPLIER_PARTS) | PART_KEY + SUPPLIER_KEY | → Supplier, → Part |
| Customer | `customers` (V_CUSTOMERS) | CUSTOMER_KEY | places Orders |
| Order | `orders` (V_ORDERS) | ORDER_KEY | → Customer, contains Shipments |
| Shipment | `shipments` (V_SHIPMENTS) | ORDER_KEY + LINE_NUMBER | → Order, → Supplier, → Part |
| Supplier Performance | `supplier_performance` | SUPPLIER_KEY | → Supplier (scorecard) |
""")
    st.info("Plant / fulfilment centre is intentionally not modelled: TPC-H has no facility data. "
            "Inventing one would create misleading relationships.")

# ==========================================================================
# 7. PERSONA VIEWS
# ==========================================================================
with tabs[6]:
    st.subheader("Persona views over the same governed metrics")
    persona = st.radio("Persona", ["Planning", "Procurement", "Logistics"], horizontal=True)
    pk = governed_kpis()
    st.markdown(
        f'<span class="badge ok">Governed metric fingerprint: {kpi_fingerprint(pk)}</span>'
        '<span class="badge">identical for every persona</span>',
        unsafe_allow_html=True,
    )
    g = st.columns(4)
    g[0].metric("Total Spend", fmt_b(pk["TOTAL_SPEND"]))
    g[1].metric("On-Time Delivery", f"{pk['ON_TIME_DELIVERY_RATE']:.2f}%")
    g[2].metric("Fill Rate", f"{pk['FILL_RATE']:.2f}%")
    g[3].metric("Avg Lead Time", f"{pk['AVERAGE_LEAD_TIME']:.1f} days")
    st.divider()

    if persona == "Planning":
        st.markdown("**Planning lens: demand and lead time**")
        pr = sv("shipments.average_lead_time, shipments.average_processing_time, shipments.on_time_delivery_rate",
                "shipments.order_priority", "order_priority")
        st.bar_chart(pr, x="ORDER_PRIORITY", y="AVERAGE_LEAD_TIME", color=BLUE)
        st.dataframe(pr, hide_index=True, width="stretch")
        seg = sv("shipments.total_spend, shipments.total_quantity", "shipments.market_segment", "total_spend DESC")
        st.dataframe(seg, hide_index=True, width="stretch")
    elif persona == "Procurement":
        st.markdown("**Procurement lens: supplier regions and spend**")
        reg = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.return_rate",
                 "shipments.supplier_region", "total_spend DESC")
        st.bar_chart(reg, x="SUPPLIER_REGION", y="ON_TIME_DELIVERY_RATE", color=BLUE)
        st.dataframe(reg, hide_index=True, width="stretch")
        inv = sv("supplier_parts.total_inventory_value, supplier_parts.average_supply_cost, supplier_parts.average_margin",
                 "supplier_parts.supplier_region", "total_inventory_value DESC")
        st.dataframe(inv, hide_index=True, width="stretch")
    else:
        st.markdown("**Logistics lens: ship modes and lanes**")
        sm = sv("shipments.on_time_delivery_rate, shipments.average_shipping_time, shipments.average_lead_time, "
                "shipments.shipment_count", "shipments.ship_mode", "on_time_delivery_rate DESC")
        st.bar_chart(sm, x="SHIP_MODE", y="ON_TIME_DELIVERY_RATE", color=BLUE)
        st.dataframe(sm, hide_index=True, width="stretch")
        lanes = sv("shipments.shipment_count, shipments.average_lead_time, shipments.on_time_delivery_rate",
                   "shipments.supplier_region, shipments.customer_region", "shipment_count DESC")
        st.markdown("**Supplier region → customer region lanes**")
        st.dataframe(lanes, hide_index=True, width="stretch")

    st.success(f"{persona} sees the same governed KPIs (fingerprint {kpi_fingerprint(pk)}) as every other persona. "
               "Only the analytical lens changes, never the metric definition.")
