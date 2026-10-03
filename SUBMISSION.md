# Hack2Skill Submission Package: SupplyGraph AI

Copy each section into the matching form field. Items in `<angle brackets>` need your input.

---

### Project title
SupplyGraph AI: Governed Supply Chain Ontology & Conversational Analytics

### One-line elevator pitch
A Snowflake-native supply-chain ontology where every persona asks in their own words, and every
answer comes from the same governed metric, with the SQL and definition shown alongside it.

### Problem statement
Planning, Procurement and Logistics teams ask the same supply-chain questions but compute the
answers with different SQL, filters and definitions of "on-time", "fill rate" or "spend". The
numbers disagree, decisions stall, and AI chat tools make it worse by generating yet another
ungoverned interpretation for every question.

### Solution description
SupplyGraph AI models the supply chain (Supplier, Part, Supplier-Part, Customer, Order, Shipment,
Supplier Performance) as an ontology inside a Snowflake Semantic View over the TPC-H dataset (6M
shipment lines, 10K suppliers). Six canonical metrics (On-Time Delivery, Fill Rate, Total Spend,
Average Lead Time, Supplier Performance, Spend Concentration) are defined once, alongside 20 governed
semantic-view metrics in total. Cortex Analyst answers natural-language questions grounded in that ontology, helped by 12
verified queries. A Streamlit in Snowflake app computes every KPI through `SEMANTIC_VIEW()`, shows
the generated SQL, source and metric definition for each answer, and proves live that Planning,
Procurement and Logistics get identical governed answers.

### Key innovation
1. **The ontology is the governance layer.** One semantic view serves as the business model, the
   metric registry and the AI's grounding context.
2. **Proven persona consistency.** Three differently worded persona questions are sent live to
   Cortex Analyst and checked automatically against a governed `SEMANTIC_VIEW()` reference
   (result: IDENTICAL).
3. **A practical Analyst-hardening technique.** Root-causing Cortex Analyst's per-table CTE
   behaviour, and registering denormalised dimensions on every logical table that holds them,
   lifted accuracy from 6/15 to 15/15.
4. **No invented answers.** If Analyst is unreachable the app uses a labelled verified query or
   shows an explicit error, never LLM-generated numbers.

### Snowflake technologies used
Semantic Views (ontology, metrics, synonyms, `AI_SQL_GENERATION`, `AI_VERIFIED_QUERIES`) ·
Cortex Analyst (REST API) · Streamlit in Snowflake · Snowflake views (zero-copy) · internal
stage · `SEMANTIC_VIEW()` query construct · Snowflake Sample Data (TPC-H SF1) · Cortex Code CLI.

### CoCo CLI usage
Built entirely from the Cortex Code CLI: environment discovery, `cortex search docs` for
semantic-view DDL, creation of all views, the semantic view, the stage and the Streamlit app, and
`cortex analyst query` for testing natural-language questions. CoCo was then used to inspect the
generated SQL and diagnose the root cause of failing Analyst queries, iterating the semantic view
from 6/15 to 15/15. It also ran a headless Streamlit `AppTest` of all app tabs, validated every
metric against raw TPC-H, and produced the documentation and Git commit.

### Architecture summary
Four layers, all inside Snowflake:
(1) `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` source →
(2) 8 zero-copy curated views computing line-level business facts →
(3) `SUPPLY_CHAIN_ONTOLOGY` semantic view (7 tables, 7 relationships, 26 facts, 46 dimensions,
20 metrics, 12 verified queries) →
(4) Streamlit in Snowflake app querying via `SEMANTIC_VIEW()` and Cortex Analyst.
No external services, credentials or data copies.

### Business impact
- One definition of each KPI across Planning, Procurement and Logistics, which removes
  reconciliation work.
- Self-service natural-language analytics that stays inside the governed metric set.
- Full traceability: every answer exposes its SQL, metric definition and source, so users can
  check it instead of taking it on trust.
- Zero data movement and no extra infrastructure; it runs on an existing warehouse.

### Validation results
- Cortex Analyst: **15/15** natural-language questions produce executable SQL with results.
- Metric consistency: **9/9** semantic-view metrics exactly match independent SQL on raw TPC-H.
- Persona consistency: **IDENTICAL** answers for 3 persona phrasings, and an identical governed KPI
  fingerprint (`ec8773a9f799`) across persona views.
- Streamlit app: **9/9** headless end-to-end scenarios pass, including the degraded-mode fallback.
- **16/16** deployment SQL statements compile; no secrets in the repository.

### Demo flow
1. **Header KPIs:** $218.10B spend, 36.79% OTD, 75.36% fill rate, 76.5-day lead time, all from the semantic view.
2. **Hero Demo tab:** click *Ask all three personas live*. Three different phrasings produce three
   SQL statements that use the same metric, then a green **IDENTICAL** verdict against the governed reference.
3. **Ask SupplyGraph tab:** ask "What is the spend concentration across top suppliers?" and walk
   through the interpretation → answer → generated SQL → governed definitions → source.
4. **Metrics & Evidence tab:** the metric catalogue, live semantic view vs direct SQL check (all
   MATCH), and the ontology table.
5. **Persona Views tab:** switch Planning → Procurement → Logistics. The lens changes; the KPIs and
   fingerprint stay the same.
6. **Executive / Supplier / Regional tabs:** a quick tour of the governed dashboards.

### Known limitations
- TPC-H is synthetic and uniform, so regional and supplier differences are small. The demo
  emphasises consistency, not dramatic insights.
- Fill rate is a proxy (lines not returned) because the source has no backorder data. The
  Supplier Performance Score effectively weights returns twice; this is documented.
- No plant/fulfilment-centre entity, because the source has no facility data.
- Governance covers metric semantics; row-access policies, masking and custom RBAC are not implemented.
- Cortex Agents were not used (Semantic View + Cortex Analyst by design).
- Cortex Analyst is probabilistic; untested phrasings may produce different SQL.

### GitHub URL
`<https://github.com/<your-user>/supplygraph-ai>`

### Deployed application
Streamlit in Snowflake app `SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLYGRAPH_AI_APP`
(account `YLCULZU-ZI04332`, url_id `d47yuk6gc2ugtjs77ufl`). Snowsight: Projects → Streamlit → SupplyGraph AI.

---

## 2-minute demo script

**0:00 to 0:15: Hook.**
"Ask three supply-chain teams for the on-time delivery rate and you usually get three numbers.
SupplyGraph AI makes that impossible."

**0:15 to 0:35: Ontology.** *(Metrics & Evidence tab)*
"We modelled the supply chain as an ontology in a Snowflake Semantic View: suppliers, parts,
orders, shipments, customers and supplier performance, with their relationships. Six canonical
metrics are defined exactly once, and here they are with their formulas."

**0:35 to 1:05: Hero demo.** *(Hero Demo tab, click the button)*
"Planning asks for on-time delivery by supplier region. Procurement asks which regions deliver on
time most often. Logistics asks for OTD by source region. Three different phrasings go live to
Cortex Analyst. Open the SQL: all three use the same governed metric on the same ontology
dimension. The app checks them against the semantic view: identical."

**1:05 to 1:30: Conversational analytics with evidence.** *(Ask SupplyGraph tab)*
"Any question works the same way. Spend concentration across top suppliers: here's the answer,
the exact SQL, the governed definition used, and the source. If Analyst were unavailable we'd
fall back to a verified query, never an invented number."

**1:30 to 1:45: Personas and proof.** *(Persona Views, then Metrics & Evidence)*
"Planning, Procurement and Logistics each get their own lens, but the KPIs carry the same
fingerprint. Every semantic-view metric matches independent SQL on the raw data, and all 15
test questions pass."

**1:45 to 2:00: Close.**
"Fully Snowflake-native: semantic view, Cortex Analyst, Streamlit, no data copied. Built and
hardened entirely with the Cortex Code CLI. One ontology, one truth, every persona."

---

## 30-second judge pitch

"Supply-chain teams don't disagree because of bad data. They disagree because each team defines
'on-time' and 'spend' differently. SupplyGraph AI puts the supply-chain ontology and its metric
definitions into one Snowflake Semantic View, and makes it the only path to a number: every
dashboard tile and every Cortex Analyst answer goes through it. In our hero demo, Planning,
Procurement and Logistics ask the same question three different ways, and the app proves live that
all three get the identical governed answer, with SQL and definitions on screen. 15 of 15
natural-language questions pass, and every metric matches independent SQL exactly. It's fully
Snowflake-native and was built with the CoCo CLI."
