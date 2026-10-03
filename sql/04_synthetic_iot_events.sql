-- SupplyGraph AI: SYNTHETIC IoT shipment telemetry
-- =====================================================================
-- SYNTHETIC. NOT TPC-H data. One telemetry summary per shipment line,
-- generated deterministically (HASH of the shipment key) so results are
-- reproducible. Only DELAY_ALERT_FLAG / DELAY_HOURS are derived from the
-- shipment's real TPC-H receipt vs commit dates; temperature, shock and
-- GPS values are simulated.
--   TEMP_EXCURSION_FLAG = MAX_TEMP_C > 8.0 (cold-chain threshold)
--   CONDITION_RISK_FLAG = temperature excursion OR shock event
--   IOT_ALERT_FLAG      = any of delay, temperature excursion, shock
-- Requires 03_curated_views.sql (V_SHIPMENTS).
-- =====================================================================

CREATE OR REPLACE TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS
  COMMENT = 'SYNTHETIC IoT shipment telemetry (deterministic). Delay alert derived from real TPC-H lateness; temperature/shock/GPS simulated.'
AS
WITH base AS (
    SELECT
        S.ORDER_KEY, S.LINE_NUMBER, S.SHIP_MODE, S.SUPPLIER_REGION, S.CUSTOMER_REGION,
        S.PLANT_KEY, S.PLANT_NAME, S.PLANT_REGION, S.ORDER_YEAR,
        S.SHIPPING_LEAD_TIME_DAYS, S.IS_LATE, S.DAYS_LATE,
        MOD(ABS(HASH(S.ORDER_KEY, S.LINE_NUMBER, 'temp')), 10000) AS H_TEMP,
        MOD(ABS(HASH(S.ORDER_KEY, S.LINE_NUMBER, 'excursion')), 1000) AS H_EXC,
        MOD(ABS(HASH(S.ORDER_KEY, S.LINE_NUMBER, 'shock')), 1000) AS H_SHOCK,
        MOD(ABS(HASH(S.ORDER_KEY, S.LINE_NUMBER, 'device')), 50000) AS H_DEV,
        CASE S.SHIP_MODE WHEN 'AIR' THEN 10 WHEN 'REG AIR' THEN 12 WHEN 'MAIL' THEN 25 WHEN 'TRUCK' THEN 30
                         WHEN 'FOB' THEN 35 WHEN 'RAIL' THEN 40 WHEN 'SHIP' THEN 55 ELSE 20 END AS EXC_PER_MILLE
    FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS S
), telemetry AS (
    SELECT B.*,
        IFF(H_EXC < EXC_PER_MILLE, 8.5 + MOD(H_TEMP, 500) / 100, 2 + MOD(H_TEMP, 600) / 100) AS MAX_TEMP_C,
        IFF(H_SHOCK < 15, 1, 0) AS SHOCK_EVENT_FLAG
    FROM base B
)
SELECT
    ORDER_KEY, LINE_NUMBER,
    'IOT-' || LPAD(H_DEV::VARCHAR, 5, '0') AS DEVICE_ID,
    'SYNTHETIC_IOT' AS SOURCE_SYSTEM,
    SHIP_MODE, SUPPLIER_REGION, CUSTOMER_REGION, PLANT_KEY, PLANT_NAME, PLANT_REGION, ORDER_YEAR,
    GREATEST(SHIPPING_LEAD_TIME_DAYS * 24 - MOD(H_TEMP, 5), 0) AS GPS_PING_COUNT,
    ROUND(MAX_TEMP_C, 2) AS MAX_TEMP_C,
    IFF(MAX_TEMP_C > 8.0, 1, 0) AS TEMP_EXCURSION_FLAG,
    SHOCK_EVENT_FLAG,
    IS_LATE AS DELAY_ALERT_FLAG,
    DAYS_LATE * 24 AS DELAY_HOURS,
    GREATEST(IFF(MAX_TEMP_C > 8.0, 1, 0), SHOCK_EVENT_FLAG) AS CONDITION_RISK_FLAG,
    GREATEST(IFF(MAX_TEMP_C > 8.0, 1, 0), SHOCK_EVENT_FLAG, IS_LATE) AS IOT_ALERT_FLAG
FROM telemetry;

ALTER TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS ADD PRIMARY KEY (ORDER_KEY, LINE_NUMBER);
