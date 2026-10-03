# SupplyGraph AI

**Supply Chain Ontology and Governed Conversational Analytics**
Snowflake CoCo CLI Hackathon, GCC Edition · Challenge 5

> One supply-chain ontology. One set of governed metrics. The same answer for every persona.

---

## 1. Problem

Planning, Procurement and Logistics teams ask the same questions ("How reliable are our deliveries?",
"Where is our spend concentrated?") but answer them with their own SQL, filters and definitions.
"On-time" means receipt date to one team and ship date to another. Spend includes discount in one
dashboard but not the next. The numbers disagree, trust erodes, and meetings turn into reconciliation
exercises.

## 2. Solution

SupplyGraph AI models the supply chain as an **ontology inside a Snowflake Semantic View** and makes
that semantic view the only path to a number:

- **Ontology**: Supplier, Part, Supplier-Part, Customer, Order, Shipment and Supplier Performance
  as logical tables with keys, relationships, synonyms and comments.
- **Governed metrics**: On-Time Delivery, Fill Rate, Total Spend, Average Lead Time, Supplier
  Performance and Spend Concentration, each defined once with a canonical SQL expression.
- **Conversational analytics**: **Cortex Analyst** turns natural-language questions into SQL
  grounded in the semantic view, guided by 12 verified queries and custom SQL-generation instructions.
- **Streamlit in Snowflake app**: every KPI and chart is a `SEMANTIC_VIEW()` query, and every
  conversational answer shows its generated SQL, the source and the metric definitions used.

### Hero demo: "One question, three personas"

| Persona | Question as asked |
|---|---|
| Planning | *What is the on-time delivery rate by supplier region?* |
| Procurement | *Which supplier regions deliver on time most often? Show on-time delivery percentage by supplier region.* |
| Logistics | *Show the OTD percentage for each source region.* |

Cortex Analyst resolves all three phrasings to the same governed metric
(`on_time_delivery_rate = AVG(is_on_time) * 100`) over the same ontology dimension
(`supplier_region`). The app compares the three results with a direct `SEMANTIC_VIEW()` query and
prints **IDENTICAL**.

---

## 3. Architecture

```
 Streamlit in Snowflake  (SUPPLYGRAPH_AI_APP)
 ├─ Hero Demo ─ Executive ─ Supplier ─ Regional ─ Ask SupplyGraph ─ Metrics & Evidence ─ Personas
 │        │                                         │
 │  SEMANTIC_VIEW() queries                Cortex Analyst REST API
 │        │                                (/api/v2/cortex/analyst/message)
 ▼        ▼                                         ▼
 SEMANTIC VIEW  SUPPLY_CHAIN_ONTOLOGY
   7 logical tables · 7 relationships · 26 facts · 46 dimensions · 20 metrics
   12 verified queries · AI_SQL_GENERATION instructions
 ▼
 CURATED VIEWS (zero-copy, SUPPLYGRAPH_AI.SUPPLY_CHAIN)
   V_SHIPMENTS · V_ORDERS · V_SUPPLIERS · V_PARTS · V_CUSTOMERS
   V_SUPPLIER_PARTS · V_SUPPLIER_PERFORMANCE · V_REGIONS
 ▼
 SNOWFLAKE_SAMPLE_DATA.TPCH_SF1  (LINEITEM 6.0M · ORDERS 1.5M · PARTSUPP 800K · PART 200K
                                  CUSTOMER 150K · SUPPLIER 10K · NATION 25 · REGION 5)
```

Details: [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 4. Ontology

```
 REGION ─contains─▶ NATION ─locates─▶ SUPPLIER ◀─offered by─ SUPPLIER-PART ─offers─▶ PART
                         └─locates─▶ CUSTOMER                      ▲                   ▲
                                         │ places                  │ scored as         │ shipped as
                                         ▼                   SUPPLIER PERFORMANCE      │
                                       ORDER ─contains─▶ SHIPMENT ─shipped by─▶ SUPPLIER
                                                            └────────── of part ───────┘
```

| Entity | Logical table | Key | Relationships in the semantic view |
|---|---|---|---|
| Shipment (line item) | `shipments` → V_SHIPMENTS | ORDER_KEY + LINE_NUMBER | → orders, → suppliers, → parts |
| Order | `orders` → V_ORDERS | ORDER_KEY | → customers |
| Customer | `customers` → V_CUSTOMERS | CUSTOMER_KEY | (via nation and region attributes) |
| Supplier | `suppliers` → V_SUPPLIERS | SUPPLIER_KEY | referenced by shipments, supplier_parts, supplier_performance |
| Part | `parts` → V_PARTS | PART_KEY | referenced by shipments, supplier_parts |
| Supplier-Part | `supplier_parts` → V_SUPPLIER_PARTS | PART_KEY + SUPPLIER_KEY | → suppliers, → parts |
| Supplier Performance | `supplier_performance` → V_SUPPLIER_PERFORMANCE | SUPPLIER_KEY | → suppliers |

**Hierarchies:** Region → Nation → Supplier/Customer (geography); Order Year → Quarter → Month → Date
(time); Manufacturer → Brand → Part (product).

**Region/Nation:** stored as attributes on Supplier, Customer and Shipment rather than as a separate
logical table, because a single Region table would be ambiguous between supplier and customer
geography.

**Plant / fulfilment centre: deliberately not modelled.** TPC-H contains no facility, warehouse or
plant data. Inventing one would create misleading relationships, so the limitation is documented
instead.

---

## 5. Canonical metrics

| Metric | Semantic view object | Definition |
|---|---|---|
| Total Spend | `shipments.total_spend` | `SUM(net_revenue)`, where `net_revenue = extended_price × (1 − discount)` |
| On-Time Delivery Rate | `shipments.on_time_delivery_rate` | `AVG(is_on_time) × 100`, where on time means `receipt_date ≤ commit_date` |
| Fill Rate | `shipments.fill_rate` | `(1 − AVG(return_flag = 'R')) × 100` |
| Average Lead Time | `shipments.average_lead_time` | `AVG(receipt_date − order_date)` in days |
| Supplier Performance Score | `supplier_performance.supplier_performance_score` | `0.40·OTD% + 0.35·Fill% + 0.25·(100 − Return%)` |
| Spend Concentration | derived from `total_spend` | supplier spend ÷ total spend × 100 |
| Return Rate, Shipping Time, Processing Time, Inventory Value, Margin, counts | see `sql/03_semantic_view.sql` | 20 metrics in total |

---

## 6. Snowflake components

| Component | Object | Role |
|---|---|---|
| Database / schema | `SUPPLYGRAPH_AI.SUPPLY_CHAIN` | Project namespace |
| Views (8) | `V_*` | Zero-copy curated layer over TPC-H; no data duplicated |
| **Semantic View** | `SUPPLY_CHAIN_ONTOLOGY` | Ontology and governed metrics |
| **Cortex Analyst** | REST API with `semantic_view` | Natural-language-to-SQL grounded in the ontology |
| Verified queries (12) | `AI_VERIFIED_QUERIES` | Pre-validated SQL for core business questions |
| SQL-generation instructions | `AI_SQL_GENERATION` | Business rules and value lists for Analyst |
| **Streamlit in Snowflake** | `SUPPLYGRAPH_AI_APP` | Demo application on warehouse `COMPUTE_WH` |
| Stage | `STREAMLIT_STAGE` | App source (`streamlit_app.py`, `environment.yml`) |

No external services, ETL tools, API keys or copied data are used.

---

## 7. How Cortex Code (CoCo) CLI was used

The whole solution was built, debugged and validated from the CoCo CLI:

| Step | CoCo capability |
|---|---|
| Environment discovery (role, warehouse, databases, Cortex model availability) | SQL execution through the active connection |
| Semantic view DDL syntax research | `cortex search docs` |
| Building views, semantic view, stage and Streamlit | SQL execution, `PUT` upload |
| Testing NL questions against the ontology | `cortex analyst query --view=...` |
| **Root-cause analysis of Analyst failures** | Inspecting generated SQL. Analyst builds per-table CTEs that only select columns registered as facts or dimensions *on that table*, so denormalised columns had to be registered on every table that holds them. Pass rate went 6/15 → 9/15 → **15/15** over three iterations. |
| Headless end-to-end test of the app (all tabs, hero demo, chat, personas, fallback path) | Python REPL with Streamlit `AppTest` |
| Documentation, Git commit | File tools and `git` |

---

## 8. Validation results

Full report: [VALIDATION.md](VALIDATION.md). Reproducible script: [sql/05_validation.sql](sql/05_validation.sql).

| Check | Result |
|---|---|
| Cortex Analyst natural-language questions | **15/15** generate executable SQL that returns results |
| Semantic-view metrics vs independent SQL on raw TPC-H tables | **9/9 exact match** |
| Hero demo: 3 persona phrasings vs governed reference | **IDENTICAL**, row for row |
| Persona views: governed KPI fingerprint | **Same** (`ec8773a9f799`) for Planning, Procurement and Logistics |
| Streamlit app headless test (Streamlit `AppTest`, 9 scenarios) | **9/9 pass** |
| Secrets / credentials in repository | **None** |

---

## 9. Run / deploy

**Prerequisites:** a role that can create databases and Streamlit apps (built with `ACCOUNTADMIN`), a
warehouse named `COMPUTE_WH`, access to `SNOWFLAKE_SAMPLE_DATA`, and Cortex Analyst enabled in the
region (app users need the `SNOWFLAKE.CORTEX_USER` database role).

Run the scripts in order, pasting each into a Snowsight worksheet or using the Snowflake CLI:

```bash
snow sql -f sql/01_database_schema.sql
snow sql -f sql/02_curated_views.sql
snow sql -f sql/03_semantic_view.sql
```

Deploy the app:

```sql
CREATE STAGE IF NOT EXISTS SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE DIRECTORY = (ENABLE = TRUE);
PUT 'file:///<repo>/streamlit_app.py' @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT 'file:///<repo>/environment.yml'  @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- then run sql/04_deploy_streamlit.sql
```

Validate:

```bash
snow sql -f sql/05_validation.sql   # every metric row must say PASS
```

Open the app in Snowsight: **Projects → Streamlit → SupplyGraph AI**.

---

## 10. Repository

```
supplygraph-ai/
├── README.md               Project overview (this file)
├── ARCHITECTURE.md         Layers, design decisions, data flow, governance model
├── VALIDATION.md           Final validation report
├── SUBMISSION.md           Hackathon submission package and demo script
├── LICENSE                 MIT
├── streamlit_app.py        Streamlit in Snowflake application
├── environment.yml         SiS package pin (streamlit 1.52.0)
└── sql/
    ├── 01_database_schema.sql
    ├── 02_curated_views.sql
    ├── 03_semantic_view.sql    Ontology / semantic view (final, 15/15 version)
    ├── 04_deploy_streamlit.sql
    └── 05_validation.sql       Metric vs raw-TPC-H validation
```

---

## 11. Known limitations

1. **Synthetic, uniform data.** TPC-H spreads volume evenly, so regional and supplier differences
   are small (for example, OTD ranges only from 36.77% to 36.81% by region). The demo shows
   consistency and traceability, not dramatic business findings.
2. **Fill Rate is a proxy:** it counts lines not returned, because TPC-H has no backorder or
   short-shipment data.
3. **Supplier Performance Score double-counts returns.** Since fill rate = 100 − return rate, the
   score is effectively `0.40·OTD + 0.60·Fill`. The formula is kept stable for metric continuity
   and documented here.
4. **No plant / fulfilment-centre entity**, because the source has no facility data.
5. **Governance is semantic, not access control.** Metric definitions are governed centrally;
   row-access policies, masking policies and custom RBAC roles were not implemented.
6. **Cortex Agents not used.** Agents are available on the account (`SHOW AGENTS` works), but the
   solution deliberately uses Semantic View + Cortex Analyst as the conversational layer.
7. **Cortex Analyst is non-deterministic.** Phrasings outside the tested set may generate different
   SQL. If the Analyst API is unreachable, the app falls back to a matching verified query and labels
   it as such; otherwise it shows an explicit error instead of an unverified answer.
8. **Historical period only** (orders 1992-01-01 to 1998-08-02; 1998 is partial).

---

*Built with the Snowflake Cortex Code (CoCo) CLI.*
