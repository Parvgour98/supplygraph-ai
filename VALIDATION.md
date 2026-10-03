# Validation Report: SupplyGraph AI

Final end-to-end validation, 2026-10-03, account `YLCULZU-ZI04332` (AWS ap-south-1), warehouse
`COMPUTE_WH`. Run after the enrichment release (Plant, Days of Inventory, Landed Cost, IoT,
source-system definitions).

## Summary: before vs after enrichment

| Area | Before enrichment | After enrichment | Blocking issues |
|---|---|---|---|
| Cortex Analyst NL questions | 15/15 | **22/22** (15 original still pass + 7 new) | 0 |
| Metrics vs independent SQL on raw sources | 9/9 | **18/18** (9 original unchanged + 9 new) | 0 |
| Verified queries executable | 12/12 | **21/21** | 0 |
| Wording consistency (IoT risk, 6 phrasings × 2 runs) | 3 phrasings gave 2 different filters | **12/12 identical** | 0 |
| Hero demo persona consistency | IDENTICAL | **IDENTICAL** | 0 |
| Persona KPI fingerprint | `ec8773a9f799` (8 KPIs) | **`fcb10b862e85`** (13 KPIs), identical for all 3 personas | 0 |
| Streamlit headless scenarios | 9/9 | **14/14** | 0 |
| Repository SQL compiles | 16/16 | **30/30** | 0 |
| Semantic view | 7 tables · 7 rel · 26 facts · 46 dims · 20 metrics | **12 tables · 11 rel · 44 facts · 80 dims · 39 metrics** | 0 |
| Secrets in repository | none | **none** | 0 |

The fingerprint changed only because the governed KPI set grew from 8 to 13 metrics. It is
identical across personas, which is what the check verifies.

## 1. Cortex Analyst: 22 natural-language questions

### Original 15: still passing after the semantic-view extension

| # | Question | Rows | Evidence (first row) |
|---|---|---|---|
| 1 | What is the total spend across all shipments? | 1 | TOTAL_SPEND = 218,102,224,856.44 |
| 2 | What is the on-time delivery rate? | 1 | 36.79 |
| 3 | What is the fill rate by market segment? | 5 | FURNITURE 75.42 |
| 4 | What is the average lead time by supplier region? | 5 | AMERICA 76.5 |
| 5 | Who are the top 10 suppliers by performance score? | 10 | Supplier#000006948, INDONESIA |
| 6 | What is the total spend by supplier region? | 5 | AMERICA 44,480,915,501.08 |
| 7 | What is the on-time delivery rate by shipping mode? | 7 | RAIL 36.84 |
| 8 | What is the monthly spend trend for 1997? | 12 | 1997-01 2,783,198,706.41 |
| 9 | Which suppliers have the worst performance? | 10 | Supplier#000008565, GERMANY |
| 10 | What is the spend concentration across top suppliers? | 20 | Supplier#000005994 28,698,575.67 |
| 11 | How has supply chain performance changed year over year? | 7 | 1992 33,009,798,732.77 |
| 12 | What is the average lead time by order priority? | 5 | 1-URGENT 76.5 |
| 13 | What is the total inventory value by supplier region? | 5 | AMERICA 407,942,718,701.84 |
| 14 | What percentage of shipments are cross-region? | 2 | Cross Region 4,802,374 |
| 15 | What is the return rate by brand? | 25 | Brand#25 24.86 |

### New 7: enrichment coverage

| # | Requirement covered | Question | Rows | Evidence |
|---|---|---|---|---|
| 16 | Plant performance | Which plant has the highest on-time delivery rate? | 1 | Pune Fabrication, ASIA, 36.88 |
| 17 | Days of inventory | What is the days of inventory by plant? | 10 | Nairobi Assembly 63,114.2 |
| 18 | Landed cost | What is the total landed cost by supplier region broken down into purchase, freight and duty? | 5 | AMERICA purchase 15,600,416,328.52, freight 112,727,670.60 |
| 19 | Landed cost | What is the landed cost per unit by ship mode? | 7 | AIR 526.77/unit, freight 8.10/unit |
| 20 | IoT shipment risk | Which ship modes have the highest IoT temperature excursion rate? | 7 | SHIP 5.53% |
| 21 | Cross-source definitions | How do ERP, logistics and supplier portal define on-time delivery differently, and what value does each produce compared to the governed definition? | 4 | GOVERNED row first, with definition text and formula |
| 22 | Cross-domain (cost + IoT + plant) | For each plant, what is the total landed cost and the IoT shipment risk rate? | 10 | Shenzhen 8,076,309,556.38, risk 4.404 |

Q22 was additionally verified row by row: all 10 plants' landed cost and IoT risk match an
independent join of V_SHIPMENT_LANDED_COST and SYN_IOT_SHIPMENT_EVENTS.

## 2. Metric consistency (sql/07_validation.sql)

Direct values are recomputed from **raw TPC-H tables and SYN_ tables only**, never from the
curated views.

| Metric | Data origin | Semantic view | Direct SQL | Status |
|---|---|---|---|---|
| Total Spend | TPC-H | 218,102,224,856.44 | 218,102,224,856.44 | PASS |
| On-Time Delivery Rate | TPC-H | 36.7912 | 36.7912 | PASS |
| Fill Rate | TPC-H | 75.3572 | 75.3572 | PASS |
| Average Lead Time | TPC-H | 76.482014 | 76.482014 | PASS |
| Return Rate | TPC-H | 24.6428 | 24.6428 | PASS |
| Shipment Count | TPC-H | 6,001,215 | 6,001,215 | PASS |
| Order Count | TPC-H | 1,500,000 | 1,500,000 | PASS |
| Supplier Count | TPC-H | 10,000 | 10,000 | PASS |
| Total Inventory Value | TPC-H | 2,003,609,409,006.92 | 2,003,609,409,006.92 | PASS |
| **Days of Inventory** | TPC-H | 62,910.158145 | 62,910.158145 | PASS |
| **Total Purchase Cost** | TPC-H | 76,587,390,310.93 | 76,587,390,310.93 | PASS |
| **Total Freight Cost** | TPC-H + SYNTHETIC tariff | 590,540,749.60 | 590,540,749.60 | PASS |
| **Total Duty Cost** | TPC-H + SYNTHETIC tariff | 2,842,742,437.89 | 2,842,742,437.89 | PASS |
| **Total Landed Cost** | TPC-H + SYNTHETIC tariff | 80,020,673,498.42 | 80,020,673,498.42 | PASS |
| **Landed Cost per Unit** | TPC-H + SYNTHETIC tariff | 522.741726 | 522.741726 | PASS |
| **Plant Count** | SYNTHETIC | 10 | 10 | PASS |
| **Temperature Excursion Rate** | SYNTHETIC | 2.9547 | 2.9547 | PASS |
| **Condition Risk Rate** | SYNTHETIC | 4.4040 | 4.4040 | PASS |

The first 9 rows are byte-identical to the pre-enrichment validation; the enrichment changed no
existing metric.

## 3. Definition conflict (V_METRIC_DEFINITION_COMPARISON)

| Metric | ERP | Logistics TMS | Supplier portal | Governed |
|---|---|---|---|---|
| On-Time Delivery | 49.5948% (+34.8%) | 38.4438% (+4.5%) | 100.0000% (+171.8%) | **36.7912%** |
| Fill Rate | 49.9268% (−33.8%) | n/a | 75.3593% (≈0.0%) | **75.3572%** |
| Total Spend | $229.58B (+5.3%) | $226.83B (+4.0%) | n/a | **$218.10B** |

The governed values equal the semantic-view metrics in §2.

## 4. Persona consistency

| Persona | Phrasing | Result |
|---|---|---|
| Planning | "What is the on-time delivery rate by supplier region?" | AFRICA 36.81 · AMERICA 36.81 · ASIA 36.77 · EUROPE 36.78 · MIDDLE EAST 36.79 |
| Procurement | "Which supplier regions deliver on time most often? …" | identical |
| Logistics | "Show the OTD percentage for each source region." | identical |
| Governed reference | `SEMANTIC_VIEW(… DIMENSIONS shipments.supplier_region METRICS shipments.on_time_delivery_rate)` | identical |

## 5. Streamlit app (headless `streamlit.testing.v1.AppTest`, Streamlit 1.52.0, live data)

| # | Scenario | Result |
|---|---|---|
| 1 | Initial render: 9 tabs, 6 header KPIs ($218.10B · 36.79% · 75.36% · 76.5 days · 62,910 DOI · $80.02B landed) | PASS |
| 2 | Hero Demo: 3 personas live → IDENTICAL | PASS |
| 3 | Definition Conflict: On-Time Delivery (36.79% to 100.00% spread) | PASS |
| 4 | Definition Conflict: Fill Rate (49.93% to 75.36%) | PASS |
| 5 | Definition Conflict: Total Spend ($218.10B to $229.58B) | PASS |
| 6 | Ask SupplyGraph: days of inventory by plant | PASS |
| 7 | Ask SupplyGraph: IoT temperature excursion question | PASS |
| 8–10 | Persona views: Planning, Procurement, Logistics, all with fingerprint `fcb10b862e85` | PASS |
| 11 | Analyst unreachable → labelled verified query (landed cost) | PASS |
| 12 | Analyst unreachable + no match → explicit error | PASS |
| 13 | Supplier tab: region filter + bottom performers | PASS |
| 14 | Row-level question ("Which shipments have IoT risk signals?") capped at 1,000 rows with notice, no MessageSizeError | PASS |

Metrics & Evidence tab live check: 7/7 MATCH (spend, OTD, fill rate, lead time, shipment count,
days of inventory, landed cost).

Deployment: `SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLYGRAPH_AI_APP`, url_id `wz5v63kscgkyed73aqsp`.

**Not verified:** visual rendering in the Snowsight browser, and the `_snowflake` Analyst call from
inside the SiS runtime. The headless test routed that call to the same Cortex Analyst service.
Open the app once and press the Hero Demo button to confirm.

## 6. Wording consistency: governed term "IoT risk"

**Issue found:** "Which shipments have IoT risk signal(s)?" used `iot_alert_flag` (~64% of shipments, includes
delays), while "Which shipments have IoT risk?" used `condition_risk_flag` (~4.4%), and row-level queries had no
unique ORDER BY, so the 1,000 rows shown changed between runs.

**Fix (semantic view only, app unchanged):** "IoT risk / risk signal(s) / at-risk shipments" is now a governed
term meaning `condition_risk_flag = 1` (temperature excursion OR shock). The any-alert flag is documented as
*not* IoT risk. Row-level results must ORDER BY the full primary key. 3 verified queries were added.

| Phrasing | Runs | Filter used | Stable ORDER BY | First 1,000 rows |
|---|---|---|---|---|
| Which shipments have IoT risk signal? | 2 | condition_risk_flag = 1 | yes | identical |
| Which shipments have IoT risk? | 2 | condition_risk_flag = 1 | yes | identical |
| Which shipments have IoT risk signals? | 2 | condition_risk_flag = 1 | yes | identical |
| Show me the shipments with IoT risk | 2 | condition_risk_flag = 1 | yes | identical |
| List shipments at IoT risk | 2 | condition_risk_flag = 1 | yes | identical |
| Which shipments have IoT risk signals (no "?") | 2 | condition_risk_flag = 1 | yes | identical |

All 12 calls returned one identical row set. The deployed app (headless test) showed identical rows, every one
with `CONDITION_RISK_FLAG = 1`. After the change: 22/22 questions, 18/18 metrics, hero IDENTICAL, 21/21 verified queries.

## 7. Remaining limitations

See README §12. None are blocking.
