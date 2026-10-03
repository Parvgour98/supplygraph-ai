-- SupplyGraph AI: Governed metric validation
-- Compares every canonical semantic-view metric with an INDEPENDENT computation on the raw
-- source tables (TPC-H and the SYN_ enrichment tables), never on the curated views.
-- Every row must return PASS.

WITH sv AS (
    SELECT * FROM SEMANTIC_VIEW(
        SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY
        METRICS shipments.total_spend, shipments.on_time_delivery_rate, shipments.fill_rate,
                shipments.average_lead_time, shipments.return_rate, shipments.shipment_count,
                orders.order_count, suppliers.supplier_count,
                supplier_parts.total_inventory_value,
                plants.plant_count,
                part_inventory.days_of_inventory,
                shipment_costs.total_landed_cost, shipment_costs.total_purchase_cost,
                shipment_costs.total_freight_cost, shipment_costs.total_duty_cost,
                shipment_costs.landed_cost_per_unit,
                iot_events.temperature_excursion_rate, iot_events.condition_risk_rate)
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
        (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS)                           AS order_count,
        (SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER)                         AS supplier_count,
        (SELECT SUM(ps_availqty * ps_supplycost) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP) AS total_inventory_value,
        (SELECT COUNT(*) FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_PLANTS)                         AS plant_count,
        -- Days of inventory: total availability / (total demand / demand-window days)
        (SELECT SUM(ps_availqty) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP)
          / ((SELECT SUM(l_quantity) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM)
             / (SELECT DATEDIFF('day', MIN(o_orderdate), MAX(o_orderdate)) + 1 FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS))
                                                                                               AS days_of_inventory
),
raw_cost AS (
    -- Landed cost recomputed from LINEITEM + PARTSUPP + SYN tariffs (independent of V_SHIPMENT_LANDED_COST)
    SELECT
        SUM(ROUND(l.l_quantity * ps.ps_supplycost, 2))                                         AS purchase,
        SUM(ROUND(l.l_quantity * fr.freight_rate_per_unit, 2))                                 AS freight,
        SUM(ROUND(l.l_quantity * ps.ps_supplycost * dr.duty_rate, 2))                          AS duty,
        SUM(l.l_quantity)                                                                      AS qty
    FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM l
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP ps ON ps.ps_partkey = l.l_partkey AND ps.ps_suppkey = l.l_suppkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER s ON s.s_suppkey = l.l_suppkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION n ON n.n_nationkey = s.s_nationkey
    JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION r ON r.r_regionkey = n.n_regionkey
    JOIN SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_PLANTS p ON p.plant_key = MOD(l.l_partkey, 10) + 1
    JOIN SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_FREIGHT_RATES fr
      ON fr.ship_mode = l.l_shipmode AND fr.lane_type = IFF(r.r_name = p.plant_region, 'DOMESTIC', 'CROSS_REGION')
    JOIN SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_DUTY_RATES dr
      ON dr.origin_region = r.r_name AND dr.destination_region = p.plant_region
),
raw_iot AS (
    SELECT AVG(temp_excursion_flag) * 100 AS temp_exc, AVG(GREATEST(temp_excursion_flag, shock_event_flag)) * 100 AS cond_risk
    FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS
)
SELECT metric, data_origin, semantic_view_value, direct_sql_value,
       IFF(ABS(semantic_view_value - direct_sql_value) <= 0.000001 * GREATEST(1, ABS(direct_sql_value)), 'PASS', 'FAIL') AS status
FROM (
    SELECT 'Total Spend' AS metric, 'TPC-H' AS data_origin, sv.total_spend AS semantic_view_value, raw.total_spend AS direct_sql_value FROM sv, raw
    UNION ALL SELECT 'On-Time Delivery Rate', 'TPC-H', sv.on_time_delivery_rate, raw.on_time_delivery_rate FROM sv, raw
    UNION ALL SELECT 'Fill Rate', 'TPC-H', sv.fill_rate, raw.fill_rate FROM sv, raw
    UNION ALL SELECT 'Average Lead Time', 'TPC-H', sv.average_lead_time, raw.average_lead_time FROM sv, raw
    UNION ALL SELECT 'Return Rate', 'TPC-H', sv.return_rate, raw.return_rate FROM sv, raw
    UNION ALL SELECT 'Shipment Count', 'TPC-H', sv.shipment_count, raw.shipment_count FROM sv, raw
    UNION ALL SELECT 'Order Count', 'TPC-H', sv.order_count, raw_other.order_count FROM sv, raw_other
    UNION ALL SELECT 'Supplier Count', 'TPC-H', sv.supplier_count, raw_other.supplier_count FROM sv, raw_other
    UNION ALL SELECT 'Total Inventory Value', 'TPC-H', sv.total_inventory_value, raw_other.total_inventory_value FROM sv, raw_other
    UNION ALL SELECT 'Days of Inventory', 'TPC-H', sv.days_of_inventory, raw_other.days_of_inventory FROM sv, raw_other
    UNION ALL SELECT 'Plant Count', 'SYNTHETIC', sv.plant_count, raw_other.plant_count FROM sv, raw_other
    UNION ALL SELECT 'Total Purchase Cost', 'TPC-H', sv.total_purchase_cost, raw_cost.purchase FROM sv, raw_cost
    UNION ALL SELECT 'Total Freight Cost', 'TPC-H + SYNTHETIC tariff', sv.total_freight_cost, raw_cost.freight FROM sv, raw_cost
    UNION ALL SELECT 'Total Duty Cost', 'TPC-H + SYNTHETIC tariff', sv.total_duty_cost, raw_cost.duty FROM sv, raw_cost
    UNION ALL SELECT 'Total Landed Cost', 'TPC-H + SYNTHETIC tariff', sv.total_landed_cost, raw_cost.purchase + raw_cost.freight + raw_cost.duty FROM sv, raw_cost
    UNION ALL SELECT 'Landed Cost per Unit', 'TPC-H + SYNTHETIC tariff', sv.landed_cost_per_unit, (raw_cost.purchase + raw_cost.freight + raw_cost.duty) / raw_cost.qty FROM sv, raw_cost
    UNION ALL SELECT 'Temperature Excursion Rate', 'SYNTHETIC', sv.temperature_excursion_rate, raw_iot.temp_exc FROM sv, raw_iot
    UNION ALL SELECT 'Condition Risk Rate', 'SYNTHETIC', sv.condition_risk_rate, raw_iot.cond_risk FROM sv, raw_iot
)
ORDER BY data_origin, metric;

-- Persona consistency: the three persona phrasings resolve to this governed query.
SELECT * FROM SEMANTIC_VIEW(
    SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY
    DIMENSIONS shipments.supplier_region
    METRICS shipments.on_time_delivery_rate)
ORDER BY supplier_region;

-- Definition conflict: the same metric under each source-system definition vs the governed one.
SELECT metric_name, source_system, metric_value, governed_value, variance_pct, is_governed
FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_METRIC_DEFINITION_COMPARISON
ORDER BY metric_name, is_governed DESC, source_system;
