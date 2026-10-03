# Architecture: SupplyGraph AI

SupplyGraph AI is a four-layer, Snowflake-native architecture. No external infrastructure, ETL
tools, API keys or copied data are involved.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ L4  APPLICATION: Streamlit in Snowflake (SUPPLYGRAPH_AI_APP, COMPUTE_WH)     │
│     Hero Demo · Executive · Supplier · Regional · Ask SupplyGraph ·          │
│     Metrics & Evidence · Persona Views                                       │
│        │ SEMANTIC_VIEW() queries          │ Cortex Analyst REST API          │
└────────┼──────────────────────────────────┼──────────────────────────────────┘
         ▼                                  ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ L3  GOVERNED SEMANTIC LAYER: SUPPLY_CHAIN_ONTOLOGY (Semantic View)           │
│     7 logical tables · 7 relationships · 26 facts · 46 dimensions ·          │
│     20 metrics · 12 verified queries · AI_SQL_GENERATION instructions        │
└────────┬─────────────────────────────────────────────────────────────────────┘
         ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ L2  CURATED VIEWS (zero-copy): V_SHIPMENTS · V_ORDERS · V_SUPPLIERS ·        │
│     V_PARTS · V_CUSTOMERS · V_SUPPLIER_PARTS · V_SUPPLIER_PERFORMANCE ·      │
│     V_REGIONS                                                                │
└────────┬─────────────────────────────────────────────────────────────────────┘
         ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ L1  SOURCE: SNOWFLAKE_SAMPLE_DATA.TPCH_SF1 (read-only share)                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

## L1: Source

| Table | Rows | Supply-chain meaning |
|---|---|---|
| LINEITEM | 6,001,215 | Shipment line: qty, price, ship/commit/receipt dates, mode, return flag |
| ORDERS | 1,500,000 | Customer order with date, priority and status |
| PARTSUPP | 800,000 | Supplier-part availability and supply cost |
| PART | 200,000 | Product catalogue |
| CUSTOMER | 150,000 | Buyer with market segment |
| SUPPLIER | 10,000 | Vendor |
| NATION / REGION | 25 / 5 | Geography |

## L2: Curated views

Views rename columns to business language and compute line-level business facts once:
`NET_REVENUE`, `GROSS_REVENUE`, `DELIVERY_LEAD_TIME_DAYS`, `SHIPPING_LEAD_TIME_DAYS`,
`PROCESSING_TIME_DAYS`, `IS_ON_TIME`, `IS_LATE`, `DAYS_LATE`, `RETURN_STATUS`, `INVENTORY_VALUE`,
`MARGIN_PERCENTAGE`. `V_SUPPLIER_PERFORMANCE` pre-aggregates the supplier scorecard.

**Design decision: denormalised `V_SHIPMENTS`.** Supplier, customer, part and order attributes are
carried on the shipment line. This keeps every shipment-grain question answerable from one logical
table, which is the shape Cortex Analyst handles most reliably.

## L3: Semantic view (the ontology)

The semantic view does three jobs:

1. **Ontology**: entities (logical tables with primary keys), relationships (foreign-key graph),
   synonyms ("vendors" → suppliers, "OTD" → on-time delivery) and comments.
2. **Governance**: each metric is defined once (for example `on_time_delivery_rate =
   AVG(is_on_time) * 100`) and every consumer, human or AI, reuses that definition.
3. **AI grounding**: `AI_SQL_GENERATION` gives Cortex Analyst business rules and valid values, and
   `AI_VERIFIED_QUERIES` provide 12 vetted question→SQL pairs.

### Relationship graph

```
shipments ──shipment_to_order──────▶ orders ──order_to_customer──▶ customers
    │ ──shipment_to_supplier─────▶ suppliers ◀──perf_to_supplier── supplier_performance
    │ ──shipment_to_part─────────▶ parts                    ▲
supplier_parts ──supplier_part_to_supplier──────────────────┘
supplier_parts ──supplier_part_to_part──────▶ parts
```

### Key finding: dimension registration for Cortex Analyst

The first version passed only 6/15 Analyst questions. Inspecting the generated SQL showed the
pattern: Analyst emits one CTE per logical table, and that CTE selects **only columns registered
as facts or dimensions on that logical table**. The outer query then referenced denormalised
columns, such as `ORDER_YEAR` on shipments or `SUPPLIER_NAME` on supplier_performance, that the
CTE had not selected, causing `invalid identifier` errors.

Fixes, applied in two iterations:
1. Fact and dimension names were made identical to physical column names (6 → 9 of 15).
2. Every denormalised column was registered as a dimension on **each** logical table that
   physically holds it (9 → **15 of 15**).

The resulting duplication (for example `SUPPLIER_NAME` on four tables) is intentional.

## L4: Application

| Path | Mechanism | Governance guarantee |
|---|---|---|
| KPI tiles, charts, persona views | `SELECT * FROM SEMANTIC_VIEW(... METRICS ... DIMENSIONS ...)` | Metric expression comes from the semantic view, never from app code |
| Ask SupplyGraph, Hero Demo | Cortex Analyst REST API (`_snowflake.send_snow_api_request`, `semantic_view` = ontology FQN) | SQL generated from the semantic view and shown to the user |
| Analyst unreachable | Matching **verified query** from the semantic view, labelled as such | No unverified or LLM-invented numbers; unmatched questions show an explicit error |
| Supplier scorecard table | Direct read of `V_SUPPLIER_PERFORMANCE` (registered in the semantic view as `supplier_performance`) | Same object the semantic view exposes |

### Consistency mechanisms visible in the app

- **Hero Demo**: three persona phrasings go through live Cortex Analyst, each result is compared
  with a direct `SEMANTIC_VIEW()` query, and the app shows `IDENTICAL`.
- **Persona Views**: all personas render the same `governed_kpis()` result, with a SHA-256
  fingerprint shown as a badge (`ec8773a9f799`).
- **Metrics & Evidence**: semantic-view values are recomputed with independent direct SQL and
  shown as MATCH/MISMATCH.

## Data flow for a conversational question

```
User question
  └─▶ Cortex Analyst (semantic_view = SUPPLY_CHAIN_ONTOLOGY)
        ├─ interprets with synonyms, metric definitions, verified queries
        └─▶ SQL ──▶ executed on COMPUTE_WH ──▶ result table
                     └─▶ app shows: interpretation · answer · SQL · metric definitions · source
```

## Security and governance notes

- The app runs with owner's rights inside Snowflake; there are no credentials in code.
- The `_snowflake` module is used only for the Cortex Analyst call.
- Not implemented (documented limitation): row-access policies, masking policies, custom RBAC roles.
