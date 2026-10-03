# Validation Report: SupplyGraph AI

Final end-to-end validation, run 2026-10-03 on account `YLCULZU-ZI04332` (AWS ap-south-1),
warehouse `COMPUTE_WH`.

## Summary

| Area | Result | Blocking issues |
|---|---|---|
| Cortex Analyst NL questions | **15/15 PASS** | 0 |
| Metric consistency (semantic view vs raw TPC-H) | **9/9 exact match** | 0 |
| Hero demo: persona phrasing consistency | **IDENTICAL** (3/3) | 0 |
| Persona views: governed KPIs | **Identical**, fingerprint `ec8773a9f799` | 0 |
| Streamlit app (headless `AppTest`, Streamlit 1.52.0) | **9/9 scenarios pass** | 0 |
| Semantic view | Valid: 7 tables, 7 relationships, 26 facts, 46 dimensions, 20 metrics, 12 VQRs | 0 |
| SQL scripts compile | **16/16 statements** | 0 |
| Secrets / credentials in repo | **None found** | 0 |

## 1. Cortex Analyst: 15 natural-language questions

Each question was sent to Cortex Analyst with `semantic_view = SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY`.
The generated SQL was executed and the first result row recorded.

| # | Question | Rows | First result row (evidence) |
|---|---|---|---|
| 1 | What is the total spend across all shipments? | 1 | TOTAL_SPEND = 218,102,224,856.44 |
| 2 | What is the on-time delivery rate? | 1 | ON_TIME_DELIVERY_RATE = 36.79 |
| 3 | What is the fill rate by market segment? | 5 | FURNITURE, FILL_RATE_PCT = 75.42 |
| 4 | What is the average lead time by supplier region? | 5 | ASIA, AVG_LEAD_TIME = 76.5 |
| 5 | Who are the top 10 suppliers by performance score? | 10 | Supplier#000006948, INDONESIA, ASIA |
| 6 | What is the total spend by supplier region? | 5 | AMERICA, TOTAL_SPEND = 44,480,915,501.08 |
| 7 | What is the on-time delivery rate by shipping mode? | 7 | RAIL, ON_TIME_PCT = 36.84 |
| 8 | What is the monthly spend trend for 1997? | 12 | 1997-01, TOTAL_SPEND = 2,783,198,706.41 |
| 9 | Which suppliers have the worst performance? | 10 | Supplier#000008565, GERMANY, EUROPE |
| 10 | What is the spend concentration across top suppliers? | 20 | Supplier#000005994, AFRICA, 28,698,575.67 |
| 11 | How has supply chain performance changed year over year? | 7 | 1992, TOTAL_SPEND = 33,009,798,732.77 |
| 12 | What is the average lead time by order priority? | 5 | 1-URGENT, AVG_LEAD_TIME = 76.5 |
| 13 | What is the total inventory value by supplier region? | 5 | AMERICA, 407,942,718,701.84 |
| 14 | What percentage of shipments are cross-region? | 2 | Cross Region, 4,802,374 shipments |
| 15 | What is the return rate by brand? | 25 | Brand#25, RETURN_RATE_PCT = 24.86 |

Hardening history: 6/15 → 9/15 → 15/15 (see ARCHITECTURE.md, "Key finding").

## 2. Metric consistency

Reproduce with `sql/05_validation.sql`. Direct values are computed on the **raw TPC-H tables**,
independently of the curated views.

| Metric | Semantic view | Direct SQL (raw TPC-H) | Status |
|---|---|---|---|
| Total Spend | 218,102,224,856.44 | 218,102,224,856.44 | PASS |
| On-Time Delivery Rate | 36.791200 | 36.791200 | PASS |
| Fill Rate | 75.357200 | 75.357200 | PASS |
| Average Lead Time | 76.482014 | 76.482014 | PASS |
| Return Rate | 24.642800 | 24.642800 | PASS |
| Shipment Count | 6,001,215 | 6,001,215 | PASS |
| Order Count | 1,500,000 | 1,500,000 | PASS |
| Supplier Count | 10,000 | 10,000 | PASS |
| Total Inventory Value | 2,003,609,409,006.92 | 2,003,609,409,006.92 | PASS |

## 3. Persona consistency (hero demo)

| Persona | Phrasing | Metric Analyst chose | Result |
|---|---|---|---|
| Planning | "What is the on-time delivery rate by supplier region?" | `ROUND(AVG(is_on_time) * 100, 2)` by `supplier_region` | AFRICA 36.81 · AMERICA 36.81 · ASIA 36.77 · EUROPE 36.78 · MIDDLE EAST 36.79 |
| Procurement | "Which supplier regions deliver on time most often? Show on-time delivery percentage by supplier region." | same | identical |
| Logistics | "Show the OTD percentage for each source region." | same | identical |
| Governed reference | `SEMANTIC_VIEW(... DIMENSIONS shipments.supplier_region METRICS shipments.on_time_delivery_rate)` | n/a | identical (after rounding to 2 dp) |

The app's Hero Demo tab performs this comparison live and reported **IDENTICAL**.

## 4. Streamlit app

Tested headlessly with `streamlit.testing.v1.AppTest` against live Snowflake data. Cortex Analyst
calls were routed to the real Analyst service.

| Scenario | Result |
|---|---|
| Initial render: 7 tabs, header KPIs ($218.10B, 36.79%, 75.36%, 76.5 days) | PASS |
| Hero Demo: 3 personas live, verdict IDENTICAL | PASS |
| Ask SupplyGraph: free-text question → interpretation, answer, SQL, definitions | PASS |
| Persona view: Planning | PASS |
| Persona view: Procurement | PASS |
| Persona view: Logistics | PASS |
| Analyst unreachable → verified-query fallback, labelled | PASS |
| Analyst unreachable + no match → explicit error, no invented answer | PASS |
| Supplier tab: region filter + bottom performers | PASS |

Deployment: `SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLYGRAPH_AI_APP` (url_id `d47yuk6gc2ugtjs77ufl`), stage
contains `streamlit_app.py` and `environment.yml` (streamlit 1.52.0).

**Not verified:** visual rendering inside the Snowsight browser UI, and the `_snowflake` Cortex
Analyst call from within the SiS runtime itself. The headless test emulated that call by routing to
the same Analyst service. Open the app once in Snowsight and press the Hero Demo button to confirm.

## 5. Remaining limitations

See README.md §11. None are blocking.
