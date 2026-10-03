# SupplyGraph AI

**Supply Chain Ontology and Governed Conversational Analytics**
Snowflake CoCo CLI Hackathon, GCC Edition · Challenge 5

> One supply-chain ontology. One set of governed metrics. The same answer for every persona.

---

## 1. Problem

Supply-chain data lives in separate ERP, logistics, supplier and IoT systems, each with its own
definition of the same metric. We demonstrate this live on the same 6 million shipment lines:

| Metric | ERP | Logistics TMS | Supplier portal | **Governed** |
|---|---|---|---|---|
| On-Time Delivery | 49.59% (shipped by commit date) | 38.44% (received within commit + 2-day grace) | 100.00% (received within 30 days of ship) | **36.79%** (received by commit date) |
| Fill Rate | 49.93% (line status F) | n/a | 75.36% (quantity-weighted) | **75.36%** (lines not returned) |
| Total Spend | $229.58B (gross) | $226.83B (after discount, incl. tax) | n/a | **$218.10B** (net of discount) |

Asking "what is our on-time delivery?" returns anything from 36.79% to 100%, depending on which
system you ask.

## 2. Solution

SupplyGraph AI expresses the supply chain as an **industry ontology inside a Snowflake Semantic
View** and makes that semantic view the only path to a number:

- **Ontology:** Supplier → Supplier-Part → Part → **Plant**; Shipment → Part → Plant;
  Shipment → Order → Customer. Plus Supplier Performance, Part Inventory, Shipment Landed Cost,
  IoT Shipment Event and Source-System Definition, as 12 logical tables with keys, relationships,
  synonyms and comments.
- **Canonical metrics** defined once: On-Time Delivery, Fill Rate, **Days of Inventory**,
  **Landed Cost**, Total Spend, Average Lead Time, Supplier Performance, Spend Concentration and
  IoT shipment risk (39 governed metrics in total).
- **Governed conversational analytics:** Cortex Analyst answers natural-language and
  cross-domain questions grounded in the ontology, guided by 21 verified queries.
- **Streamlit in Snowflake app:** every KPI is a `SEMANTIC_VIEW()` query. Every answer shows its
  SQL, metric definition and source, and the app proves live that Planning, Procurement and
  Logistics get identical answers.

### Hero demo: "One question, three personas"

| Persona | Question as asked |
|---|---|
| Planning | *What is the on-time delivery rate by supplier region?* |
| Procurement | *Which supplier regions deliver on time most often? Show on-time delivery percentage by supplier region.* |
| Logistics | *Show the OTD percentage for each source region.* |

Cortex Analyst resolves all three to the governed metric `on_time_delivery_rate = AVG(is_on_time) * 100`
on the ontology dimension `supplier_region`, and the app shows **IDENTICAL** against a direct
`SEMANTIC_VIEW()` query.

---

## 3. Data: what is real, what is synthetic, what is governed

| Category | Content | Objects |
|---|---|---|
| **Original TPC-H** | Suppliers, parts, supplier-parts, customers, orders, 6M shipment lines, nations, regions | `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` via `V_*` views |
| **Genuine metric on TPC-H** | Days of Inventory (PARTSUPP availability vs LINEITEM demand) | `V_PART_INVENTORY` |
| **SYNTHETIC enrichment** | ERP plant master (10 plants), logistics freight tariff, customs duty tariff, IoT shipment telemetry | `SYN_PLANTS`, `SYN_FREIGHT_RATES`, `SYN_DUTY_RATES`, `SYN_IOT_SHIPMENT_EVENTS` |
| **Illustrative definitions** | How ERP / TMS / supplier portal define metrics; values **computed live on TPC-H** | `SOURCE_SYSTEM_DEFINITIONS`, `V_METRIC_DEFINITION_COMPARISON` |
| **Governed canonical definitions** | Every metric used by dashboards, personas and Cortex Analyst | `SUPPLY_CHAIN_ONTOLOGY` semantic view |

Synthetic rules (deterministic and reproducible):
- **Plant assignment:** `PLANT_KEY = MOD(PART_KEY, 10) + 1`.
- **Freight:** quantity × rate per unit, by ship mode and lane type. A lane is DOMESTIC when the
  supplier region equals the plant region, otherwise CROSS_REGION.
- **Duty:** purchase cost × duty rate, by supplier region → plant region; 0 within the same region.
- **IoT:** temperature, shock and GPS values are hash-seeded per shipment. The delay alert is
  derived from the shipment's **real** TPC-H receipt vs commit dates.

---

## 4. Architecture

```
 Streamlit in Snowflake (SUPPLYGRAPH_AI_APP)
   Hero Demo · Executive · Plant Network · Supplier · Regional · Ask SupplyGraph ·
   Definition Conflict · Metrics & Evidence · Persona Views
        │ SEMANTIC_VIEW() queries                 │ Cortex Analyst REST API
        ▼                                          ▼
 SEMANTIC VIEW  SUPPLY_CHAIN_ONTOLOGY
   12 logical tables · 11 relationships · 44 facts · 80 dimensions · 39 metrics
   21 verified queries · AI_SQL_GENERATION instructions
        ▼
 VIEWS (zero-copy)                                   SYNTHETIC ENRICHMENT (labelled SYN_)
   V_SHIPMENTS · V_ORDERS · V_SUPPLIERS · V_PARTS      SYN_PLANTS · SYN_FREIGHT_RATES
   V_CUSTOMERS · V_SUPPLIER_PARTS · V_REGIONS          SYN_DUTY_RATES · SYN_IOT_SHIPMENT_EVENTS
   V_SUPPLIER_PERFORMANCE · V_PART_INVENTORY           SOURCE_SYSTEM_DEFINITIONS
   V_SHIPMENT_LANDED_COST · V_METRIC_DEFINITION_COMPARISON
        ▼
 SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (LINEITEM 6.0M · ORDERS 1.5M · PARTSUPP 800K · PART 200K ·
                                  CUSTOMER 150K · SUPPLIER 10K · NATION 25 · REGION 5)
```

Details: [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 5. Ontology

```
                   SUPPLIER ◀── supplier_part_to_supplier ── SUPPLIER-PART ── supplier_part_to_part ──▶ PART ── part_to_plant ──▶ PLANT*
                      ▲                                                                                  ▲
 SUPPLIER PERFORMANCE ┘ perf_to_supplier                                         inventory_to_part ── PART INVENTORY
                      ▲                                                                                  │
                      └── shipment_to_supplier ── SHIPMENT ── shipment_to_part ─────────────────────────┘
                                                    │  ▲  ▲
                              shipment_to_order ────┘  │  └── iot_to_shipment ── IOT SHIPMENT EVENT*
                                     ▼                 └───── cost_to_shipment ── SHIPMENT LANDED COST (freight/duty*)
                                   ORDER ── order_to_customer ──▶ CUSTOMER
 (* = synthetic enrichment)          SOURCE-SYSTEM DEFINITION (metadata for the governed metrics)
```

| Entity | Logical table | Key | Origin |
|---|---|---|---|
| Supplier | `suppliers` | SUPPLIER_KEY | TPC-H |
| Supplier-Part | `supplier_parts` | PART_KEY + SUPPLIER_KEY | TPC-H |
| Part | `parts` | PART_KEY | TPC-H |
| **Plant** | `plants` | PLANT_KEY | SYNTHETIC |
| Shipment | `shipments` | ORDER_KEY + LINE_NUMBER | TPC-H |
| Order | `orders` | ORDER_KEY | TPC-H |
| Customer | `customers` | CUSTOMER_KEY | TPC-H |
| Supplier Performance | `supplier_performance` | SUPPLIER_KEY | TPC-H (aggregated) |
| Part Inventory | `part_inventory` | PART_KEY | TPC-H |
| Shipment Landed Cost | `shipment_costs` | ORDER_KEY + LINE_NUMBER | TPC-H + SYNTHETIC tariffs |
| IoT Shipment Event | `iot_events` | ORDER_KEY + LINE_NUMBER | SYNTHETIC |
| Source-System Definition | `source_definitions` | METRIC_NAME + SOURCE_SYSTEM | Illustrative (values live on TPC-H) |

**Hierarchies:** Region → Nation → Supplier / Customer / Plant · Plant Region → Plant → Part ·
Manufacturer → Brand → Part · Order Year → Quarter → Month → Date.

Plant is reached **through Part**, not linked to Shipment directly. This keeps a single
unambiguous join path in the semantic view.

---

## 6. Canonical metrics

| Metric | Semantic view object | Definition | Data |
|---|---|---|---|
| **On-Time Delivery** | `shipments.on_time_delivery_rate` | `AVG(receipt_date ≤ commit_date) × 100` | TPC-H |
| **Fill Rate** | `shipments.fill_rate` | `(1 − AVG(return_flag = 'R')) × 100` | TPC-H |
| **Days of Inventory** | `part_inventory.days_of_inventory` | `SUM(available_qty) / (SUM(qty_shipped) / demand_days)`, demand_days = 2,406 | TPC-H |
| **Landed Cost** | `shipment_costs.total_landed_cost` | `SUM(purchase + freight + duty)`; purchase = qty × supply_cost | TPC-H + SYNTHETIC tariffs |
| Total Spend | `shipments.total_spend` | `SUM(extended_price × (1 − discount))` | TPC-H |
| Average Lead Time | `shipments.average_lead_time` | `AVG(receipt_date − order_date)` | TPC-H |
| Supplier Performance Score | `supplier_performance.supplier_performance_score` | `0.40·OTD + 0.35·Fill + 0.25·(100 − Return)` | TPC-H |
| Spend Concentration | derived from `total_spend` | supplier spend ÷ total spend | TPC-H |
| Landed Cost per Unit | `shipment_costs.landed_cost_per_unit` | `SUM(landed_cost) / SUM(quantity)` | TPC-H + SYNTHETIC |
| Temperature Excursion Rate | `iot_events.temperature_excursion_rate` | `AVG(max_temp_c > 8) × 100` | SYNTHETIC |
| **IoT Risk** (governed term) | `iot_events.condition_risk_rate`, `at_risk_shipment_count` | `condition_risk_flag = 1` (temperature excursion OR shock). "Any alert incl. delays" is a separate, explicitly named metric | SYNTHETIC |

Full list (39 metrics): `sql/05_semantic_view.sql`.

---

## 7. Snowflake components

| Component | Objects |
|---|---|
| Database / schema | `SUPPLYGRAPH_AI.SUPPLY_CHAIN` |
| Views (11, zero-copy) | 8 core `V_*` views + `V_PART_INVENTORY`, `V_SHIPMENT_LANDED_COST`, `V_METRIC_DEFINITION_COMPARISON` |
| Tables (5, synthetic enrichment) | `SYN_PLANTS` (10), `SYN_FREIGHT_RATES` (14), `SYN_DUTY_RATES` (25), `SOURCE_SYSTEM_DEFINITIONS` (10), `SYN_IOT_SHIPMENT_EVENTS` (6,001,215) |
| **Semantic View** | `SUPPLY_CHAIN_ONTOLOGY` |
| **Cortex Analyst** | REST API with `semantic_view` |
| **Streamlit in Snowflake** | `SUPPLYGRAPH_AI_APP` on `COMPUTE_WH`, Streamlit 1.52.0 |
| Stage | `STREAMLIT_STAGE` |

No external services, API keys or credentials are used.

---

## 8. How Cortex Code (CoCo) CLI was used

| Step | CoCo capability |
|---|---|
| Environment discovery, Cortex model availability | SQL execution through the active connection |
| Semantic view DDL research | `cortex search docs` |
| Building views, synthetic enrichment, semantic view, app | SQL execution, `PUT` |
| Testing NL questions | `cortex analyst query --view=...` |
| **Analyst hardening** | Diagnosed that Analyst's per-table CTEs only select columns registered on that logical table; registered denormalised dimensions on every holding table (6/15 → 9/15 → 15/15), then applied the same pattern to the enrichment tables (22/22) |
| Gap analysis vs the exact challenge brief | Requirement-by-requirement review, leading to the Plant / DOI / Landed Cost / IoT / definitions enrichment |
| Headless end-to-end app test | Python REPL + Streamlit `AppTest` (14 scenarios) |
| Validation, docs, Git commit | SQL, file tools, `git` |

---

## 9. Validation results

Full report: [VALIDATION.md](VALIDATION.md). Reproducible: [sql/07_validation.sql](sql/07_validation.sql).

| Check | Result |
|---|---|
| Cortex Analyst NL questions | **22/22** (15 original + 7 new: plant, DOI, landed cost ×2, IoT, definitions, cross-domain) |
| Metrics vs independent SQL on raw sources | **18/18 exact** (9 original + 9 new) |
| Verified queries executable | **21/21** |
| Wording consistency: 6 phrasings of "which shipments have IoT risk" × 2 runs | **12/12 identical** (same governed filter, same ordered rows) |
| Hero demo: 3 persona phrasings | **IDENTICAL** |
| Persona views: governed KPI fingerprint | **Same** (`fcb10b862e85`) for all three personas |
| Streamlit app headless test | **14/14** scenarios |
| Repository SQL compiles | **30/30** statements |
| Secrets in repository | **None** |

---

## 10. Run / deploy

**Prerequisites:** a role that can create databases, tables and Streamlit apps (built with
`ACCOUNTADMIN`), warehouse `COMPUTE_WH`, access to `SNOWFLAKE_SAMPLE_DATA`, Cortex Analyst
available in the region (app users need `SNOWFLAKE.CORTEX_USER`).

Run in order, from Snowsight worksheets or the Snowflake CLI:

```bash
snow sql -f sql/01_database_schema.sql
snow sql -f sql/02_synthetic_reference_data.sql   # SYNTHETIC plants, tariffs, definitions
snow sql -f sql/03_curated_views.sql
snow sql -f sql/04_synthetic_iot_events.sql       # SYNTHETIC IoT telemetry (6M rows, ~1 min on XS)
snow sql -f sql/05_semantic_view.sql
```

Deploy the app (`PUT` must run from a client, not a Snowsight worksheet):

```sql
PUT 'file:///<repo>/streamlit_app.py' @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT 'file:///<repo>/environment.yml'  @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- then: sql/06_deploy_streamlit.sql
```

Validate:

```bash
snow sql -f sql/07_validation.sql   # every metric row must say PASS
```

Open in Snowsight: **Projects → Streamlit → SupplyGraph AI**.

---

## 11. Repository

```
supplygraph-ai/
├── README.md · ARCHITECTURE.md · VALIDATION.md · SUBMISSION.md · LICENSE
├── streamlit_app.py            Streamlit in Snowflake app (9 tabs)
├── environment.yml             streamlit 1.52.0 pin
└── sql/
    ├── 01_database_schema.sql
    ├── 02_synthetic_reference_data.sql   SYNTHETIC plants, freight, duty, source definitions
    ├── 03_curated_views.sql              TPC-H views + inventory, landed cost, definition comparison
    ├── 04_synthetic_iot_events.sql       SYNTHETIC IoT telemetry
    ├── 05_semantic_view.sql              The ontology (semantic view)
    ├── 06_deploy_streamlit.sql
    └── 07_validation.sql                 18-metric validation vs raw sources
```

---

## 12. Known limitations

1. **Synthetic enrichment.** Plants, freight and duty tariffs, IoT telemetry and the source-system
   definition variants are synthetic and clearly labelled. They demonstrate the ontology and
   governance pattern, not real business facts.
2. **Days of Inventory is very high (~62,910 days).** It is computed genuinely from TPC-H, but
   TPC-H's `PS_AVAILQTY` is not calibrated to demand. The formula and its governance are the point
   here, not the absolute value.
3. **Uniform synthetic data.** TPC-H and the hash-seeded enrichment are evenly distributed, so
   differences between regions and plants are small. The demo shows consistency and traceability,
   not dramatic findings.
4. **Fill Rate is a proxy** (lines not returned); there is no backorder data.
5. **Supplier Performance Score double-counts returns** (fill = 100 − return). The formula is
   kept stable and documented.
6. **Multi-source is simulated within one account.** There are no live ERP/TMS/IoT connectors;
   the source systems are represented by labelled tables.
7. **Governance is semantic, not access control.** Row-access policies, masking and custom RBAC
   are not implemented.
8. **Cortex Agents not used.** They are available on the account; the solution uses Semantic View
   + Cortex Analyst by design.
9. **Cortex Analyst is probabilistic.** Governed terms, verified queries and a deterministic-ordering rule make answers stable for tested phrasings (12/12 identical); very different wording can still be interpreted differently. If the API is
   unreachable, the app falls back to a labelled verified query or an explicit error.
10. Historical period only (orders 1992-01-01 to 1998-08-02).

---

*Built with the Snowflake Cortex Code (CoCo) CLI.*
