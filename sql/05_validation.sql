-- SupplyGraph AI: Governed metric validation
-- Compares every canonical semantic-view metric with an independent computation
-- on the raw TPC-H tables (not the curated views). Every row must return PASS.

WITH sv AS (
    SELECT * FROM SEMANTIC_VIEW(
        SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY
        METRICS shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate,
                shipments.average_lead_time, shipments.return_rate, shipments.shipment_count,
                orders.order_count, suppliers.supplier_count,
                supplier_parts.total_inventory_value)
),
raw AS (
    SELECT
        SUM(ROUND(l.l_extendedprice * (1 - l.l_discount), 2))                     AS total_spend,
        AVG(IFF(l.l_receiptdate <= l.l_commitdate, 1, 0)) * 100                   AS on_time_delivery_rate,
        (1 - AVG(IFF(l.l_returnflag = 'R', 1, 0))) * 100                          AS fill_rate,
        AVG(DATEDIFF('day', o.o_orderdate, l.l_receiptdate))                      AS average_lead_time,
        AVG(IFF(l.l_returnflag = 'R', 1, 0)) * 100                                AS return_rate,
        COUNT(*)                                                                  AS shipment_count
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM l
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS o ON l.l_orderkey = o.o_orderkey
),
raw_other AS (
    SELECT
        (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)                       AS order_count,
        (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER)                     AS supplier_count,
        (SELECT SUM(ps_availqty * ps_supplycost) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP) AS total_inventory_value
)
SELECT metric, semantic_view_value, direct_sql_value,
       IFF(ABS(semantic_view_value - direct_sql_value) < 0.000001, 'PASS', 'FAIL') AS status
FROM (
    SELECT 'Total Spend' AS metric, sv.total_spend AS semantic_view_value, raw.total_spend AS direct_sql_value FROM sv, raw
    UNION ALL SELECT 'On-Time Delivery Rate', sv.on_time_delivery_rate, raw.on_time_delivery_rate FROM sv, raw
    UNION ALL SELECT 'Fill Rate', sv.fill_rate, raw.fill_rate FROM sv, raw
    UNION ALL SELECT 'Average Lead Time', sv.average_lead_time, raw.average_lead_time FROM sv, raw
    UNION ALL SELECT 'Return Rate', sv.return_rate, raw.return_rate FROM sv, raw
    UNION ALL SELECT 'Shipment Count', sv.shipment_count, raw.shipment_count FROM sv, raw
    UNION ALL SELECT 'Order Count', sv.order_count, raw_other.order_count FROM sv, raw_other
    UNION ALL SELECT 'Supplier Count', sv.supplier_count, raw_other.supplier_count FROM sv, raw_other
    UNION ALL SELECT 'Total Inventory Value', sv.total_inventory_value, raw_other.total_inventory_value FROM sv, raw_other
)
ORDER BY metric;

-- Persona consistency: the three persona phrasings resolve to this governed query.
SELECT * FROM SEMANTIC_VIEW(
    SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY
    DIMENSIONS shipments.supplier_region
    METRICS shipments.on_time_delivery_rate)
ORDER BY supplier_region;
