# Architecture: SupplyGraph AI

Four layers, all Snowflake-native. Original TPC-H data and labelled synthetic enrichment
feed one governed semantic view, which is the only path from data to an answer.

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ L4 APPLICATION: Streamlit in Snowflake (SUPPLYGRAPH_AI_APP, COMPUTE_WH)        │
│    Hero Demo · Executive · Plant Network · Supplier · Regional · Ask ·         │
│    Definition Conflict · Metrics & Evidence · Persona Views                    │
│        │ SEMANTIC_VIEW() queries              │ Cortex Analyst REST API        │
└────────┼──────────────────────────────────────┼────────────────────────────────┘
         ▼                                      ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│ L3 GOVERNED SEMANTIC LAYER: SUPPLY_CHAIN_ONTOLOGY                              │
│    12 logical tables · 11 relationships · 44 facts · 80 dimensions ·           │
│    39 metrics · 21 verified queries · AI_SQL_GENERATION                        │
└────────┬───────────────────────────────────────────────────────────────────────┘
         ▼
┌──────────────────────────────────────────┬─────────────────────────────────────┐
│ L2 CURATED VIEWS (zero-copy)             │ L2 SYNTHETIC ENRICHMENT (SYN_)       │
│  V_SHIPMENTS V_ORDERS V_SUPPLIERS        │  SYN_PLANTS            (ERP)         │
│  V_PARTS V_CUSTOMERS V_SUPPLIER_PARTS    │  SYN_FREIGHT_RATES     (TMS)         │
│  V_SUPPLIER_PERFORMANCE V_REGIONS        │  SYN_DUTY_RATES        (customs)     │
│  V_PART_INVENTORY                        │  SYN_IOT_SHIPMENT_EVENTS (IoT)       │
│  V_SHIPMENT_LANDED_COST                  │  SOURCE_SYSTEM_DEFINITIONS (metadata)│
│  V_METRIC_DEFINITION_COMPARISON          │                                      │
└────────┬─────────────────────────────────┴─────────────────────────────────────┘
         ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│ L1 SOURCE: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (read-only)                          │
└────────────────────────────────────────────────────────────────────────────────┘
```

## L1: Source (original TPC-H)

| Table | Rows | Supply-chain meaning |
|---|---|---|
| LINEITEM | 6,001,215 | Shipment line: qty, price, ship/commit/receipt dates, mode, return flag |
| ORDERS | 1,500,000 | Customer order |
| PARTSUPP | 800,000 | Supplier-part availability and supply cost |
| PART | 200,000 | Product catalogue |
| CUSTOMER | 150,000 | Buyer |
| SUPPLIER | 10,000 | Vendor |
| NATION / REGION | 25 / 5 | Geography |

## L2: Curated views and synthetic enrichment

**TPC-H views** rename columns to business language and compute line-level facts once
(`NET_REVENUE`, `DELIVERY_LEAD_TIME_DAYS`, `IS_ON_TIME`, `DAYS_LATE`, …). V_PARTS, V_SUPPLIER_PARTS
and V_SHIPMENTS gained `PLANT_KEY / PLANT_NAME / PLANT_REGION` columns. No existing column changed,
which is why all earlier validations still pass unchanged.

**New views**

| View | Grain | Logic | Origin |
|---|---|---|---|
| V_PART_INVENTORY | part | availability (PARTSUPP) vs demand (LINEITEM) over 2,406 days | TPC-H |
| V_SHIPMENT_LANDED_COST | shipment line | purchase (qty × supply cost) + freight (qty × tariff) + duty (purchase × tariff) | TPC-H + SYNTHETIC |
| V_METRIC_DEFINITION_COMPARISON | metric × source system | each system's formula evaluated live on LINEITEM vs the governed formula | Illustrative definitions, real values |

**Synthetic enrichment (deterministic, reproducible, labelled SYNTHETIC in comments, UI and docs)**

| Table | Simulated source | Rule |
|---|---|---|
| SYN_PLANTS | ERP plant master | 10 plants in TPC-H nations; `PLANT_KEY = MOD(PART_KEY, 10) + 1` |
| SYN_FREIGHT_RATES | Logistics TMS tariff | USD/unit by ship mode × lane (DOMESTIC / CROSS_REGION) |
| SYN_DUTY_RATES | Customs tariff | Rate by origin region × destination (plant) region; 0 if same region |
| SYN_IOT_SHIPMENT_EVENTS | IoT tracker telemetry | Hash-seeded temperature/shock/GPS per line; excursion probability rises with slower modes; **delay alert = real TPC-H lateness** |
| SOURCE_SYSTEM_DEFINITIONS | Metric definitions per system | 3 metrics × ERP / TMS / supplier portal / GOVERNED |

## L3: Semantic view (the ontology)

### Relationship graph

```
supplier_parts ─supplier_part_to_supplier─▶ suppliers ◀─perf_to_supplier── supplier_performance
supplier_parts ─supplier_part_to_part─────▶ parts ─part_to_plant─▶ plants
part_inventory ─inventory_to_part─────────▶ parts
shipments ─shipment_to_supplier─▶ suppliers
shipments ─shipment_to_part─────▶ parts (─▶ plants)
shipments ─shipment_to_order────▶ orders ─order_to_customer─▶ customers
shipment_costs ─cost_to_shipment─▶ shipments
iot_events ─iot_to_shipment──────▶ shipments
source_definitions   (stand-alone governance metadata)
```

**Design decision: one path to Plant.** Plant is an attribute of Part, so Shipment reaches Plant
through Part. Adding a direct Shipment → Plant relationship would create two join paths and an
ambiguous semantic view.

### Key finding: dimension registration for Cortex Analyst

Cortex Analyst emits one CTE per logical table, and that CTE selects **only columns registered
as facts or dimensions on that logical table**. Denormalised columns referenced by the outer query
must therefore be registered on every logical table that physically holds them. Applying this
took the original question set from 6/15 → 9/15 → 15/15. Applying it from the start to the
enrichment tables (for example `plant_name` on shipments, shipment_costs, iot_events and
part_inventory) gave 7/7 on the new questions.

### Governed metric design notes

- **Governed terms, not just metrics.** "IoT risk" is bound to `condition_risk_flag` in fact comments, synonyms,
  instructions and verified queries, so every phrasing resolves to it (12/12 identical). Row-level answers must
  ORDER BY the full primary key, so the rows shown are deterministic.

- **Days of Inventory** is a *ratio of sums* (`SUM(available) / (SUM(shipped) / demand_days)`).
  The per-part ratio is deliberately not exposed as a fact, so it can't be averaged incorrectly.
- **Landed Cost** components are rounded per line, and the metric sums the rounded components. The
  independent validation recomputes from raw tables with the same rule and matches exactly.

## L4: Application

| Path | Mechanism | Governance guarantee |
|---|---|---|
| KPIs, charts, persona views, plant network | `SELECT * FROM SEMANTIC_VIEW(...)` | Metric expressions come only from the semantic view |
| Ask SupplyGraph, Hero Demo | Cortex Analyst REST API, `semantic_view` = ontology | SQL generated from the ontology and displayed |
| Analyst unreachable | Matching verified query, labelled | No invented numbers; otherwise an explicit error |
| Definition Conflict tab | `V_METRIC_DEFINITION_COMPARISON` | Shows the ungoverned spread, then the governed value |

Consistency proofs visible in the app: Hero Demo (**IDENTICAL**), persona KPI fingerprint
(`fcb10b862e85`), and Metrics & Evidence live MATCH checks for 7 KPIs.

## Security and governance notes

No credentials in code; the app runs inside Snowflake with owner's rights. Not implemented
(documented): row-access policies, masking policies, custom RBAC roles, live source-system connectors.
