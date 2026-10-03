"""SupplyGraph AI — Supply Chain Ontology & Governed Conversational Analytics.

Every number in this app is produced through the governed semantic view
SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY, either via SEMANTIC_VIEW()
queries or via Cortex Analyst SQL generated from that semantic view.
"""
import hashlib
import itertools
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
    ("Days of Inventory", "part_inventory.days_of_inventory",
     "SUM(available_quantity) / (SUM(quantity_shipped) / demand_days), demand_days = 2,406",
     "Days current availability would cover average daily demand. Ratio of sums; TPC-H availability is not calibrated to demand, so values are very high."),
    ("Landed Cost", "shipment_costs.total_landed_cost",
     "SUM(purchase_cost + freight_cost + duty_cost); purchase = qty * supply_cost; freight = qty * rate(ship mode, lane); duty = purchase * rate(origin, plant region)",
     "Full cost of a part delivered to its plant. Purchase cost is TPC-H; freight and duty tariffs are SYNTHETIC."),
    ("Landed Cost per Unit", "shipment_costs.landed_cost_per_unit", "SUM(landed_cost) / SUM(quantity)", "Unit cost to serve."),
    ("Temperature Excursion Rate", "iot_events.temperature_excursion_rate", "AVG(max_temp_c > 8) * 100",
     "Share of shipments breaching the 8 C cold-chain limit (SYNTHETIC IoT)."),
    ("IoT Condition Risk Rate", "iot_events.condition_risk_rate", "AVG(temperature excursion OR shock) * 100",
     "Share of shipments with a condition alert (SYNTHETIC IoT)."),
]

DATA_ORIGIN = pd.DataFrame([
    ("Original TPC-H", "Suppliers, parts, supplier-parts, customers, orders, shipments, regions",
     "SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 via V_* views"),
    ("Genuine metric on TPC-H", "Days of Inventory", "V_PART_INVENTORY (PARTSUPP availability vs LINEITEM demand)"),
    ("SYNTHETIC enrichment", "Plants (ERP), freight & duty tariffs (logistics/customs), IoT telemetry",
     "SYN_PLANTS, SYN_FREIGHT_RATES, SYN_DUTY_RATES, SYN_IOT_SHIPMENT_EVENTS"),
    ("Illustrative definitions", "How ERP / TMS / supplier portal define metrics (values computed live on TPC-H)",
     "SOURCE_SYSTEM_DEFINITIONS, V_METRIC_DEFINITION_COMPARISON"),
    ("Governed canonical definitions", "Every metric used by the app and by Cortex Analyst",
     "SUPPLY_CHAIN_ONTOLOGY semantic view"),
], columns=["Category", "Content", "Objects"])

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
    "days of inventory by plant": "SELECT plant_name, ROUND(SUM(available_quantity) / NULLIF(SUM(quantity_shipped) / MAX(demand_days), 0), 1) AS days_of_inventory FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_PART_INVENTORY GROUP BY plant_name ORDER BY days_of_inventory DESC",
    "landed cost per unit by ship mode": "SELECT ship_mode, ROUND(SUM(landed_cost) / NULLIF(SUM(quantity), 0), 2) AS landed_cost_per_unit FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENT_LANDED_COST GROUP BY ship_mode ORDER BY landed_cost_per_unit DESC",
    "temperature excursion rate ship modes": "SELECT ship_mode, ROUND(AVG(temp_excursion_flag) * 100, 2) AS temperature_excursion_rate FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS GROUP BY ship_mode ORDER BY temperature_excursion_rate DESC",
}


# --------------------------------------------------------------------------
# Data access
# --------------------------------------------------------------------------
@st.cache_data(ttl=900, show_spinner=False)
def run_query(sql: str) -> pd.DataFrame:
    return session.sql(sql).to_pandas()


ANSWER_ROW_LIMIT = 1000


@st.cache_data(ttl=900, show_spinner=False)
def run_answer(sql: str) -> tuple:
    """Run generated SQL unchanged but fetch at most ANSWER_ROW_LIMIT + 1 rows; returns (df, truncated).

    Streaming with to_local_iterator (instead of wrapping the SQL in a LIMIT subquery) keeps the
    generated ORDER BY intact and never transfers row-level results of millions of rows.
    """
    result = session.sql(sql)
    rows = list(itertools.islice(result.to_local_iterator(), ANSWER_ROW_LIMIT + 1))
    df = pd.DataFrame([r.as_dict() for r in rows]) if rows else pd.DataFrame(columns=result.columns)
    return df.head(ANSWER_ROW_LIMIT), len(df) > ANSWER_ROW_LIMIT


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
            "suppliers.supplier_count, orders.order_count, plants.plant_count, "
            "part_inventory.days_of_inventory, shipment_costs.total_landed_cost, "
            "shipment_costs.landed_cost_per_unit, iot_events.condition_risk_rate")
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
    st.caption("SYNTHETIC enrichment (clearly labelled): plants, freight & duty tariffs, IoT telemetry.")
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
c = st.columns(6)
c[0].metric("Total Spend", fmt_b(k["TOTAL_SPEND"]))
c[1].metric("On-Time Delivery", f"{k['ON_TIME_DELIVERY_RATE']:.2f}%")
c[2].metric("Fill Rate", f"{k['FILL_RATE']:.2f}%")
c[3].metric("Avg Lead Time", f"{k['AVERAGE_LEAD_TIME']:.1f} days")
c[4].metric("Days of Inventory", f"{k['DAYS_OF_INVENTORY']:,.0f}",
            help="SUM(available qty) / (SUM(qty shipped) / 2,406 days). TPC-H availability is not calibrated to demand.")
c[5].metric("Landed Cost", fmt_b(k["TOTAL_LANDED_COST"]),
            help="Purchase (TPC-H) + freight + duty (SYNTHETIC tariffs)")

tabs = st.tabs([
    "Hero Demo",
    "Executive Overview",
    "Plant Network",
    "Supplier Performance",
    "Regional Risk & Spend",
    "Ask SupplyGraph",
    "Definition Conflict",
    "Metrics & Evidence",
    "Persona Views",
])
TAB = dict(zip(["hero", "exec", "plant", "supplier", "region", "ask", "defs", "metrics", "persona"], tabs))

# ==========================================================================
# 1. HERO DEMO
# ==========================================================================
with TAB["hero"]:
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
with TAB["exec"]:
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
with TAB["supplier"]:
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
with TAB["region"]:
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
with TAB["ask"]:
    st.subheader("Ask SupplyGraph: governed conversational analytics")
    st.caption("Questions go to Cortex Analyst with the semantic view as context. The generated SQL, the result "
               "and the governed definitions used are shown for every answer.")
    examples = [
        "What is the on-time delivery rate by shipping mode?",
        "Which plant has the highest on-time delivery rate?",
        "What is the days of inventory by plant?",
        "What is the landed cost per unit by ship mode?",
        "Which ship modes have the highest IoT temperature excursion rate?",
        "How do ERP, logistics and supplier portal define on-time delivery differently?",
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
                answer, truncated = run_answer(sql)
                st.markdown("**Answer**")
                if truncated:
                    st.info(f"This question returns row-level detail; showing the first {ANSWER_ROW_LIMIT:,} rows. "
                            "Ask for a summary (for example 'by ship mode' or 'by plant') to aggregate.")
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
                         "inventory_value": "Total Inventory Value",
                         "quantity_shipped": "Days of Inventory", "demand_days": "Days of Inventory",
                         "landed_cost": "Landed Cost", "temp_excursion": "Temperature Excursion Rate",
                         "condition_risk": "IoT Condition Risk Rate"}
                names = {m[0] for m in used} | {v for t, v in hints.items() if t in sql.lower()}
                defs = pd.DataFrame([m for m in METRICS if m[0] in names],
                                    columns=["Metric", "Semantic view object", "Definition", "Business meaning"])
                if not defs.empty:
                    st.dataframe(defs, hide_index=True, width="stretch")
                st.caption(f"Semantic view: {SV} · Source: {SOURCE}")
                if res.get("request_id"):
                    st.caption(f"Cortex Analyst request id: {res['request_id']}")

# ==========================================================================
# PLANT NETWORK
# ==========================================================================
with TAB["plant"]:
    st.subheader("Plant network: Supplier → Part → Plant → Shipment → Order → Customer")
    st.caption("SYNTHETIC ERP plant master (10 plants). Each TPC-H part is assigned to one plant by the "
               "deterministic rule PLANT_KEY = MOD(PART_KEY, 10) + 1. Shipment, order and customer data are original TPC-H.")
    pm = sv("plants.plant_count", "plants.plant_name, plants.plant_code, plants.plant_type, plants.plant_city, "
            "plants.plant_nation, plants.plant_region", "plant_name")
    perf_p = sv("shipments.on_time_delivery_rate, shipments.total_spend, shipments.average_lead_time, shipments.shipment_count",
                "shipments.plant_name", "plant_name")
    cost_p = sv("shipment_costs.total_landed_cost, shipment_costs.landed_cost_per_unit, shipment_costs.freight_and_duty_share",
                "shipment_costs.plant_name", "plant_name")
    inv_p = sv("part_inventory.days_of_inventory", "part_inventory.plant_name", "plant_name")
    iot_p = sv("iot_events.condition_risk_rate, iot_events.temperature_excursion_rate", "iot_events.plant_name", "plant_name")
    net = (pm.drop(columns=["PLANT_COUNT"]).merge(perf_p, on="PLANT_NAME").merge(cost_p, on="PLANT_NAME")
           .merge(inv_p, on="PLANT_NAME").merge(iot_p, on="PLANT_NAME"))
    net["LANDED_COST_B"] = net["TOTAL_LANDED_COST"].astype(float) / 1e9
    a, b = st.columns(2)
    with a:
        st.markdown("**Landed cost by plant ($B)**")
        st.bar_chart(net, x="PLANT_NAME", y="LANDED_COST_B", color=BLUE)
    with b:
        st.markdown("**IoT condition risk rate by plant (%)**")
        st.bar_chart(net, x="PLANT_NAME", y="CONDITION_RISK_RATE", color=RED)
    st.dataframe(net.drop(columns=["LANDED_COST_B"]), hide_index=True, width="stretch")
    lane = sv("shipment_costs.total_landed_cost, shipment_costs.total_freight_cost, shipment_costs.total_duty_cost, "
              "shipment_costs.landed_cost_per_unit", "shipment_costs.lane_type", "lane_type")
    st.markdown("**Domestic vs cross-region inbound lanes** (supplier region vs plant region)")
    st.dataframe(lane, hide_index=True, width="stretch")
    st.caption("Landed cost = purchase cost (TPC-H) + freight (SYNTHETIC tariff by ship mode and lane) "
               "+ duty (SYNTHETIC tariff by supplier region → plant region).")

# ==========================================================================
# DEFINITION CONFLICT
# ==========================================================================
with TAB["defs"]:
    st.subheader("Same question, different systems, different answers, until the ontology governs it")
    st.caption("Each source system's definition is evaluated live on the same TPC-H shipment lines. "
               "Definitions are illustrative of real ERP / TMS / supplier-portal differences; the values are real computations.")
    comp = run_query("SELECT metric_name, source_system, definition_text, sql_expression, is_governed, metric_value, "
                     "governed_value, variance_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_METRIC_DEFINITION_COMPARISON "
                     "ORDER BY metric_name, is_governed, source_system")
    comp.columns = [x.upper() for x in comp.columns]
    metric_pick = st.radio("Metric", sorted(comp["METRIC_NAME"].unique(), reverse=True), horizontal=True)
    sub = comp[comp["METRIC_NAME"] == metric_pick].copy()
    cols_ = st.columns(len(sub))
    for col, (_, r) in zip(cols_, sub.iterrows()):
        val = float(r["METRIC_VALUE"])
        shown = fmt_b(val) if metric_pick == "Total Spend" else f"{val:.2f}%"
        delta = None if r["IS_GOVERNED"] else f"{float(r['VARIANCE_PCT']):+.1f}% vs governed"
        col.metric(("GOVERNED" if r["IS_GOVERNED"] else r["SOURCE_SYSTEM"]), shown, delta, delta_color="off")
        col.caption(r["DEFINITION_TEXT"])
    st.dataframe(sub.drop(columns=["METRIC_NAME"]), hide_index=True, width="stretch")
    spread = sub["METRIC_VALUE"].astype(float)
    st.warning(f"Without governance, '{metric_pick}' ranges from "
               f"{(fmt_b(spread.min()) if metric_pick == 'Total Spend' else f'{spread.min():.2f}%')} to "
               f"{(fmt_b(spread.max()) if metric_pick == 'Total Spend' else f'{spread.max():.2f}%')} depending on the system asked.")
    gov = sub[sub["IS_GOVERNED"]].iloc[0]
    st.success(f"Governed definition in the semantic view: **{gov['DEFINITION_TEXT']}** (`{gov['SQL_EXPRESSION']}`). "
               "Every dashboard, persona and Cortex Analyst answer uses this one.")

# ==========================================================================
# METRICS & EVIDENCE
# ==========================================================================
with TAB["metrics"]:
    st.subheader("Governed metric definitions")
    st.dataframe(pd.DataFrame(METRICS, columns=["Metric", "Semantic view object", "Definition", "Business meaning"]),
                 hide_index=True, width="stretch")

    st.subheader("Live evidence: semantic view vs. independent direct SQL")
    direct = run_query(
        "SELECT SUM(NET_REVENUE) AS TOTAL_SPEND, AVG(IS_ON_TIME)*100 AS ON_TIME_DELIVERY_RATE, "
        "(1-AVG(CASE WHEN RETURN_FLAG='R' THEN 1 ELSE 0 END))*100 AS FILL_RATE, "
        "AVG(DELIVERY_LEAD_TIME_DAYS) AS AVERAGE_LEAD_TIME, COUNT(*) AS SHIPMENT_COUNT, "
        "(SELECT SUM(LANDED_COST) FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENT_LANDED_COST) AS TOTAL_LANDED_COST, "
        "(SELECT SUM(AVAILABLE_QUANTITY) / (SUM(QUANTITY_SHIPPED) / MAX(DEMAND_DAYS)) "
        " FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_PART_INVENTORY) AS DAYS_OF_INVENTORY "
        "FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS"
    ).iloc[0]
    rows = []
    for key in ["TOTAL_SPEND", "ON_TIME_DELIVERY_RATE", "FILL_RATE", "AVERAGE_LEAD_TIME", "SHIPMENT_COUNT",
                "DAYS_OF_INVENTORY", "TOTAL_LANDED_COST"]:
        a_, b_ = round(k[key], 4), round(float(direct[key]), 4)
        rows.append({"Metric": key, "Semantic view": a_, "Direct SQL": b_, "Status": "MATCH" if a_ == b_ else "MISMATCH"})
    st.dataframe(pd.DataFrame(rows), hide_index=True, width="stretch")
    st.caption("The full 18-metric check against raw TPC-H and SYN_ tables is in sql/07_validation.sql.")

    st.subheader("Data provenance")
    st.dataframe(DATA_ORIGIN, hide_index=True, width="stretch")

    st.subheader("Ontology")
    st.markdown("""
| Entity | Logical table | Key | Relationships | Origin |
|---|---|---|---|---|
| Supplier | `suppliers` (V_SUPPLIERS) | SUPPLIER_KEY | ships Shipments, offers Supplier-Parts | TPC-H |
| Supplier-Part | `supplier_parts` (V_SUPPLIER_PARTS) | PART_KEY + SUPPLIER_KEY | → Supplier, → Part | TPC-H |
| Part | `parts` (V_PARTS) | PART_KEY | → Plant | TPC-H |
| **Plant** | `plants` (SYN_PLANTS) | PLANT_KEY | ← Part | **SYNTHETIC** |
| Shipment | `shipments` (V_SHIPMENTS) | ORDER_KEY + LINE_NUMBER | → Order, → Supplier, → Part (→ Plant) | TPC-H |
| Order | `orders` (V_ORDERS) | ORDER_KEY | → Customer | TPC-H |
| Customer | `customers` (V_CUSTOMERS) | CUSTOMER_KEY | places Orders | TPC-H |
| Supplier Performance | `supplier_performance` | SUPPLIER_KEY | → Supplier | TPC-H |
| Part Inventory | `part_inventory` (V_PART_INVENTORY) | PART_KEY | → Part | TPC-H |
| Shipment Landed Cost | `shipment_costs` (V_SHIPMENT_LANDED_COST) | ORDER_KEY + LINE_NUMBER | → Shipment | TPC-H + SYNTHETIC tariffs |
| IoT Shipment Event | `iot_events` (SYN_IOT_SHIPMENT_EVENTS) | ORDER_KEY + LINE_NUMBER | → Shipment | **SYNTHETIC** |
| Source Definition | `source_definitions` (V_METRIC_DEFINITION_COMPARISON) | METRIC_NAME + SOURCE_SYSTEM | n/a | Illustrative |

**Hierarchies:** Region → Nation → Supplier / Customer / Plant · Year → Quarter → Month → Date · Manufacturer → Brand → Part · Plant region → Plant → Part.
""")

# ==========================================================================
# 7. PERSONA VIEWS
# ==========================================================================
with TAB["persona"]:
    st.subheader("Persona views over the same governed metrics")
    persona = st.radio("Persona", ["Planning", "Procurement", "Logistics"], horizontal=True)
    pk = governed_kpis()
    st.markdown(
        f'<span class="badge ok">Governed metric fingerprint: {kpi_fingerprint(pk)}</span>'
        '<span class="badge">identical for every persona</span>',
        unsafe_allow_html=True,
    )
    g = st.columns(6)
    g[0].metric("Total Spend", fmt_b(pk["TOTAL_SPEND"]))
    g[1].metric("On-Time Delivery", f"{pk['ON_TIME_DELIVERY_RATE']:.2f}%")
    g[2].metric("Fill Rate", f"{pk['FILL_RATE']:.2f}%")
    g[3].metric("Avg Lead Time", f"{pk['AVERAGE_LEAD_TIME']:.1f} days")
    g[4].metric("Days of Inventory", f"{pk['DAYS_OF_INVENTORY']:,.0f}")
    g[5].metric("Landed Cost", fmt_b(pk["TOTAL_LANDED_COST"]))
    st.divider()

    if persona == "Planning":
        st.markdown("**Planning lens: demand, lead time and inventory cover**")
        pr = sv("shipments.average_lead_time, shipments.average_processing_time, shipments.on_time_delivery_rate",
                "shipments.order_priority", "order_priority")
        st.bar_chart(pr, x="ORDER_PRIORITY", y="AVERAGE_LEAD_TIME", color=BLUE)
        st.dataframe(pr, hide_index=True, width="stretch")
        doi = sv("part_inventory.days_of_inventory, part_inventory.average_daily_demand, part_inventory.total_part_availability",
                 "part_inventory.plant_name", "days_of_inventory DESC")
        st.markdown("**Days of inventory by plant**")
        st.dataframe(doi, hide_index=True, width="stretch")
    elif persona == "Procurement":
        st.markdown("**Procurement lens: supplier regions, spend and landed cost**")
        reg = sv("shipments.total_spend, shipments.on_time_delivery_rate, shipments.return_rate",
                 "shipments.supplier_region", "total_spend DESC")
        st.bar_chart(reg, x="SUPPLIER_REGION", y="ON_TIME_DELIVERY_RATE", color=BLUE)
        st.dataframe(reg, hide_index=True, width="stretch")
        lc = sv("shipment_costs.total_purchase_cost, shipment_costs.total_freight_cost, shipment_costs.total_duty_cost, "
                "shipment_costs.total_landed_cost", "shipment_costs.supplier_region", "total_landed_cost DESC")
        st.markdown("**Landed cost by supplier region** (freight & duty tariffs SYNTHETIC)")
        st.dataframe(lc, hide_index=True, width="stretch")
    else:
        st.markdown("**Logistics lens: ship modes, lanes and IoT shipment risk**")
        sm = sv("shipments.on_time_delivery_rate, shipments.average_shipping_time, shipments.average_lead_time, "
                "shipments.shipment_count", "shipments.ship_mode", "on_time_delivery_rate DESC")
        st.bar_chart(sm, x="SHIP_MODE", y="ON_TIME_DELIVERY_RATE", color=BLUE)
        st.dataframe(sm, hide_index=True, width="stretch")
        iot = sv("iot_events.temperature_excursion_rate, iot_events.shock_event_rate, iot_events.condition_risk_rate, "
                 "iot_events.at_risk_shipment_count", "iot_events.ship_mode", "condition_risk_rate DESC")
        st.markdown("**IoT shipment risk by ship mode** (SYNTHETIC telemetry)")
        st.bar_chart(iot, x="SHIP_MODE", y="TEMPERATURE_EXCURSION_RATE", color=RED)
        st.dataframe(iot, hide_index=True, width="stretch")
        lanes = sv("shipments.shipment_count, shipments.average_lead_time, shipments.on_time_delivery_rate",
                   "shipments.supplier_region, shipments.customer_region", "shipment_count DESC")
        st.markdown("**Supplier region → customer region lanes**")
        st.dataframe(lanes, hide_index=True, width="stretch")

    st.success(f"{persona} sees the same governed KPIs (fingerprint {kpi_fingerprint(pk)}) as every other persona. "
               "Only the analytical lens changes, never the metric definition.")
