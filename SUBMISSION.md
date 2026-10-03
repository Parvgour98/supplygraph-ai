# Hack2Skill Submission Package: SupplyGraph AI

Copy each section into the matching form field. Items in `<angle brackets>` need your input.

---

### Project title
SupplyGraph AI: Governed Supply Chain Ontology & Conversational Analytics

### One-line elevator pitch
On-time delivery is 49.6%, 38.4% or 100% depending on which system you ask. SupplyGraph AI encodes
the supply-chain ontology in a Snowflake Semantic View so every team, dashboard and AI answer
gets the same governed 36.79%.

### Problem statement
Supply-chain data is scattered across ERP, logistics, supplier and IoT systems that each define
metrics differently. Evaluated on the same 6 million shipment lines, "on-time delivery" is 49.6%
in the ERP definition, 38.4% in the logistics definition and 100% in the supplier-portal
definition. Planning, Procurement and Logistics therefore get different answers to the same
question, and AI chat tools add yet another ungoverned interpretation.

### Solution description
SupplyGraph AI builds an industry ontology (Supplier → Supplier-Part → Part → Plant;
Shipment → Part → Plant; Shipment → Order → Customer, plus Part Inventory, Shipment Landed Cost,
IoT Shipment Events and Source-System Definitions) as a single Snowflake Semantic View: 12 logical
tables, 11 relationships and 39 governed metrics. Canonical definitions cover On-Time Delivery,
Fill Rate, Days of Inventory, Landed Cost, Total Spend, Lead Time, Supplier Performance, Spend
Concentration and IoT shipment risk. Cortex Analyst answers natural-language and cross-domain
questions grounded in the ontology, helped by 21 verified queries. A Streamlit in Snowflake app
computes every KPI through `SEMANTIC_VIEW()`, shows each answer's SQL, definition and source,
contrasts the per-system definitions with the governed one, and proves live that Planning,
Procurement and Logistics get identical answers.

Data honesty: the core data is original TPC-H (6M shipment lines, 10K suppliers). The plant
master, freight/duty tariffs and IoT telemetry are clearly labelled synthetic enrichment
representing source systems TPC-H lacks. Days of Inventory is computed genuinely from TPC-H.

### Key innovation
1. **The ontology is the governance layer.** One semantic view serves as the business entity
   model, the metric registry and the AI's grounding context.
2. **The definition conflict is shown, not just described.** The ERP, TMS and supplier-portal
   formulas are evaluated live on the same data (on-time delivery from 36.79% to 100%), and the
   governed definition resolves the conflict.
3. **Proven persona consistency.** Three differently worded persona questions go live to Cortex
   Analyst and are checked automatically against a governed reference: IDENTICAL.
4. **Cross-domain answers through the ontology.** "Landed cost and IoT risk per plant" combines
   cost, IoT and plant data; Analyst resolved it correctly, verified row by row.
5. **A practical Analyst-hardening technique.** Registering denormalised dimensions on every
   logical table that holds them took accuracy from 6/15 to 15/15; applied from the start to the
   new tables, it gave 22/22.

### Snowflake technologies used
Semantic Views (ontology, relationships, metrics, synonyms, `AI_SQL_GENERATION`,
`AI_VERIFIED_QUERIES`) · `SEMANTIC_VIEW()` query construct · Cortex Analyst REST API · Streamlit in
Snowflake · zero-copy views · tables for synthetic enrichment · internal stage · Snowflake
Sample Data (TPC-H SF1) · Cortex Code CLI.

### CoCo CLI usage
Built end to end from the Cortex Code CLI: environment discovery, `cortex search docs` for
semantic-view DDL, creation of all views, enrichment tables, the semantic view and the Streamlit
app, and `cortex analyst query` to test every natural-language question. CoCo diagnosed the root
cause of failing Analyst SQL, iterated the semantic view to 15/15, and ran a requirement-by-requirement
gap analysis against the challenge brief that led to the Plant / Days of Inventory / Landed Cost /
IoT / definitions enrichment (22/22). It also ran a headless Streamlit `AppTest` suite (13
scenarios), validated 18 metrics against raw sources, and produced the documentation and Git commits.

### Architecture summary
(1) `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` →
(2) 11 zero-copy views plus 5 labelled synthetic enrichment tables (ERP plants, TMS freight,
customs duty, IoT telemetry, source-system definitions) →
(3) `SUPPLY_CHAIN_ONTOLOGY` semantic view (12 tables, 11 relationships, 44 facts, 80 dimensions,
39 metrics, 21 verified queries) →
(4) Streamlit in Snowflake app via `SEMANTIC_VIEW()` and Cortex Analyst.
No external services, credentials or data copies of TPC-H.

### Business impact
- One definition per KPI across Planning, Procurement and Logistics, which ends the reconciliation
  of 36.79% vs 49.6% vs 100% on-time.
- Cross-domain questions (cost × plant × IoT risk × inventory) answered in plain language within
  the governed metric set.
- Every answer is traceable to its SQL, definition and source, so it can be checked rather than
  trusted blindly.
- Zero data movement and no new infrastructure; it runs on an existing warehouse.

### Validation results
- Cortex Analyst: **22/22** natural-language questions (15 original + 7 new covering plant
  performance, days of inventory, landed cost, IoT risk, source definitions and a cross-domain question).
- Metric consistency: **18/18** semantic-view metrics match independent SQL on the raw source
  tables exactly; the original 9 are unchanged after enrichment.
- Persona consistency: **IDENTICAL** for 3 phrasings, and the same governed KPI fingerprint across personas.
- Streamlit: **14/14** headless end-to-end scenarios, including outage fallback.
- Wording consistency: 6 phrasings of "which shipments have IoT risk" × 2 runs return **identical** governed rows (12/12).
- **21/21** verified queries and **30/30** SQL statements validated; no secrets in the repo.

### Demo flow
1. **Definition Conflict tab:** on-time delivery is 49.6% (ERP), 38.4% (TMS), 100% (supplier
   portal). The governed definition gives 36.79%.
2. **Hero Demo tab:** click *Ask all three personas live*. Three different phrasings return the
   same metric, verdict **IDENTICAL**.
3. **Plant Network tab:** Supplier → Part → Plant → Shipment → Order → Customer, with landed cost,
   days of inventory and IoT risk per plant (synthetic plants labelled).
4. **Ask SupplyGraph tab:** "For each plant, what is the total landed cost and the IoT shipment
   risk rate?" Walk through interpretation → answer → SQL → governed definitions → source.
5. **Persona Views tab:** switch personas. The lens changes; the 6 KPIs and the fingerprint don't.
6. **Metrics & Evidence tab:** metric catalogue, data provenance (TPC-H vs synthetic vs governed),
   live MATCH checks, ontology table.

### Known limitations
- Plants, freight/duty tariffs, IoT telemetry and the per-system definition variants are
  synthetic, and labelled as such everywhere; source systems are simulated, with no live connectors.
- Days of Inventory (~62,910 days) is computed genuinely, but TPC-H availability isn't calibrated to
  demand, so the absolute value has no business meaning; the formula and governance do.
- Synthetic and TPC-H data are uniform, so plant and region differences are small.
- Fill rate is a proxy (lines not returned). The Supplier Performance Score double-counts returns
  (documented).
- Governance covers metric semantics; row-access policies, masking and RBAC are not implemented.
- Cortex Agents not used by design; Cortex Analyst is probabilistic for untested phrasings.

### GitHub URL
https://github.com/Parvgour98/supplygraph-ai

### Deployed application
Streamlit in Snowflake app `SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLYGRAPH_AI_APP`
(account `YLCULZU-ZI04332`, url_id `wz5v63kscgkyed73aqsp`). Snowsight: Projects → Streamlit → SupplyGraph AI.

---

## 2-minute demo script

**0:00 to 0:20: The problem, live.** *(Definition Conflict tab)*
"Same six million shipments, one question: what's our on-time delivery? ERP says 49.6%,
logistics says 38.4%, the supplier portal says 100%. That's the real problem in supply chain:
not missing data, but conflicting definitions."

**0:20 to 0:40: The ontology.** *(Plant Network, then Metrics & Evidence)*
"SupplyGraph AI models the supply chain as an ontology in a Snowflake Semantic View: supplier to
part to plant to shipment to order to customer, plus inventory, landed cost and IoT events. Each
metric, on-time, fill rate, days of inventory, landed cost, is defined exactly once. Governed
on-time delivery is 36.79%."

**0:40 to 1:05: Hero demo.** *(Hero Demo tab, click the button)*
"Planning, Procurement and Logistics ask about delivery reliability in their own words. Three
phrasings go live to Cortex Analyst. Open the SQL: same governed metric, same ontology dimension.
The app checks against the semantic view: identical."

**1:05 to 1:30: Cross-domain conversational analytics.** *(Ask SupplyGraph tab)*
"Now a cross-domain question: for each plant, landed cost and IoT shipment risk. That spans cost,
IoT and plant data, and the ontology joins them correctly. Here's the answer, the SQL, the
definitions used and the sources, with synthetic enrichment clearly labelled."

**1:30 to 1:45: Personas and proof.** *(Persona Views, then Metrics & Evidence)*
"Every persona sees the same six governed KPIs, with the same fingerprint. All 18 metrics match
independent SQL on the raw data, and 22 of 22 natural-language questions pass."

**1:45 to 2:00: Close.**
"Fully Snowflake-native: semantic view, Cortex Analyst, Streamlit. Built and hardened with the
Cortex Code CLI. One ontology, one definition, one answer, for every team."

---

## 30-second judge pitch

"Ask three systems for on-time delivery and you get 49.6%, 38.4% and 100%, from the same
shipments. SupplyGraph AI fixes that with a supply-chain ontology in a Snowflake Semantic View:
supplier, part, plant, shipment, order and customer, with on-time delivery, fill rate, days of
inventory and landed cost each defined once. Every dashboard and every Cortex Analyst answer goes
through it. Planning, Procurement and Logistics ask the same question three different ways and
the app proves live they get the identical governed answer, with SQL and definitions on screen.
22 of 22 questions pass and 18 of 18 metrics match independent SQL exactly. It's fully
Snowflake-native and was built with the CoCo CLI."
