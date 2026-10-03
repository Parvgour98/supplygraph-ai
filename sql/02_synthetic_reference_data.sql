-- SupplyGraph AI: SYNTHETIC reference data
-- =====================================================================
-- Everything in this file is SYNTHETIC enrichment. It is NOT TPC-H data.
-- It models source systems TPC-H does not contain (ERP plant master,
-- logistics freight/duty tariffs, per-system metric definitions) so the
-- full Challenge 5 ontology can be demonstrated. All objects are prefixed
-- SYN_ (or documented as definitional metadata) and commented SYNTHETIC.
-- =====================================================================

-- ERP-style plant master (10 plants, located in TPC-H nations/regions)
CREATE OR REPLACE TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_PLANTS (
    PLANT_KEY      NUMBER       NOT NULL PRIMARY KEY,
    PLANT_CODE     VARCHAR(10)  NOT NULL,
    PLANT_NAME     VARCHAR(40)  NOT NULL,
    PLANT_TYPE     VARCHAR(25)  NOT NULL,
    PLANT_CITY     VARCHAR(30)  NOT NULL,
    PLANT_NATION   VARCHAR(25)  NOT NULL,
    PLANT_REGION   VARCHAR(25)  NOT NULL,
    SOURCE_SYSTEM  VARCHAR(20)  NOT NULL
) COMMENT = 'SYNTHETIC ERP plant master. Parts are assigned deterministically: PLANT_KEY = MOD(PART_KEY, 10) + 1.';

INSERT INTO SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_PLANTS VALUES
 (1,  'PLT-CHI', 'Chicago Assembly',          'Assembly',            'Chicago',   'UNITED STATES', 'AMERICA',     'SYNTHETIC_ERP'),
 (2,  'PLT-TOR', 'Toronto Fabrication',       'Fabrication',         'Toronto',   'CANADA',        'AMERICA',     'SYNTHETIC_ERP'),
 (3,  'PLT-SAO', 'Sao Paulo Distribution',    'Distribution Center', 'Sao Paulo', 'BRAZIL',        'AMERICA',     'SYNTHETIC_ERP'),
 (4,  'PLT-STR', 'Stuttgart Assembly',        'Assembly',            'Stuttgart', 'GERMANY',       'EUROPE',      'SYNTHETIC_ERP'),
 (5,  'PLT-LYO', 'Lyon Fabrication',          'Fabrication',         'Lyon',      'FRANCE',        'EUROPE',      'SYNTHETIC_ERP'),
 (6,  'PLT-SZX', 'Shenzhen Assembly',         'Assembly',            'Shenzhen',  'CHINA',         'ASIA',        'SYNTHETIC_ERP'),
 (7,  'PLT-PNQ', 'Pune Fabrication',          'Fabrication',         'Pune',      'INDIA',         'ASIA',        'SYNTHETIC_ERP'),
 (8,  'PLT-NGO', 'Nagoya Distribution',       'Distribution Center', 'Nagoya',    'JAPAN',         'ASIA',        'SYNTHETIC_ERP'),
 (9,  'PLT-DMM', 'Dammam Distribution',       'Distribution Center', 'Dammam',    'SAUDI ARABIA',  'MIDDLE EAST', 'SYNTHETIC_ERP'),
 (10, 'PLT-NBO', 'Nairobi Assembly',          'Assembly',            'Nairobi',   'KENYA',         'AFRICA',      'SYNTHETIC_ERP');

-- Logistics (TMS-style) freight tariff: USD per unit, by ship mode and lane type.
-- DOMESTIC = supplier region equals plant region; CROSS_REGION otherwise.
CREATE OR REPLACE TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_FREIGHT_RATES (
    SHIP_MODE              VARCHAR(10)   NOT NULL,
    LANE_TYPE              VARCHAR(12)   NOT NULL,
    FREIGHT_RATE_PER_UNIT  NUMBER(10,2)  NOT NULL,
    SOURCE_SYSTEM          VARCHAR(20)   NOT NULL,
    PRIMARY KEY (SHIP_MODE, LANE_TYPE)
) COMMENT = 'SYNTHETIC logistics freight tariff (USD per unit) by ship mode and lane type.';

INSERT INTO SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_FREIGHT_RATES VALUES
 ('AIR',     'DOMESTIC', 4.50, 'SYNTHETIC_TMS'), ('AIR',     'CROSS_REGION', 9.00, 'SYNTHETIC_TMS'),
 ('REG AIR', 'DOMESTIC', 3.80, 'SYNTHETIC_TMS'), ('REG AIR', 'CROSS_REGION', 7.60, 'SYNTHETIC_TMS'),
 ('MAIL',    'DOMESTIC', 2.50, 'SYNTHETIC_TMS'), ('MAIL',    'CROSS_REGION', 5.50, 'SYNTHETIC_TMS'),
 ('TRUCK',   'DOMESTIC', 1.20, 'SYNTHETIC_TMS'), ('TRUCK',   'CROSS_REGION', 3.40, 'SYNTHETIC_TMS'),
 ('RAIL',    'DOMESTIC', 0.80, 'SYNTHETIC_TMS'), ('RAIL',    'CROSS_REGION', 2.20, 'SYNTHETIC_TMS'),
 ('SHIP',    'DOMESTIC', 0.40, 'SYNTHETIC_TMS'), ('SHIP',    'CROSS_REGION', 1.10, 'SYNTHETIC_TMS'),
 ('FOB',     'DOMESTIC', 0.60, 'SYNTHETIC_TMS'), ('FOB',     'CROSS_REGION', 1.50, 'SYNTHETIC_TMS');

-- Import duty rate (fraction of purchase cost) by supplier (origin) region and plant (destination) region.
-- Same-region movements carry no duty.
CREATE OR REPLACE TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_DUTY_RATES (
    ORIGIN_REGION       VARCHAR(25)  NOT NULL,
    DESTINATION_REGION  VARCHAR(25)  NOT NULL,
    DUTY_RATE           NUMBER(6,4)  NOT NULL,
    SOURCE_SYSTEM       VARCHAR(20)  NOT NULL,
    PRIMARY KEY (ORIGIN_REGION, DESTINATION_REGION)
) COMMENT = 'SYNTHETIC customs duty tariff (fraction of purchase cost) by origin and destination region.';

INSERT INTO SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_DUTY_RATES
SELECT o.R_NAME, d.R_NAME,
       IFF(o.R_NAME = d.R_NAME, 0,
           CASE d.R_NAME WHEN 'AMERICA' THEN 0.0350 WHEN 'EUROPE' THEN 0.0420 WHEN 'ASIA' THEN 0.0550
                         WHEN 'MIDDLE EAST' THEN 0.0500 WHEN 'AFRICA' THEN 0.0600 END),
       'SYNTHETIC_CUSTOMS'
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION o CROSS JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION d;

-- How different source systems define the same metric (definitional metadata).
-- The variant formulas are illustrative of real ERP / TMS / supplier-portal differences;
-- the values they produce are computed live from TPC-H in V_METRIC_DEFINITION_COMPARISON.
CREATE OR REPLACE TABLE SUPPLYGRAPH_AI.SUPPLY_CHAIN.SOURCE_SYSTEM_DEFINITIONS (
    METRIC_NAME      VARCHAR(30)   NOT NULL,
    SOURCE_SYSTEM    VARCHAR(30)   NOT NULL,
    DEFINITION_TEXT  VARCHAR(300)  NOT NULL,
    SQL_EXPRESSION   VARCHAR(300)  NOT NULL,
    IS_GOVERNED      BOOLEAN       NOT NULL,
    PRIMARY KEY (METRIC_NAME, SOURCE_SYSTEM)
) COMMENT = 'Definitional metadata: how ERP, logistics (TMS) and supplier-portal systems define key metrics vs the GOVERNED semantic-view definition. Variants are SYNTHETIC illustrations.';

INSERT INTO SUPPLYGRAPH_AI.SUPPLY_CHAIN.SOURCE_SYSTEM_DEFINITIONS VALUES
 ('On-Time Delivery', 'ERP',             'Line shipped on or before the commit date (measures dispatch, not arrival)',      'AVG(ship_date <= commit_date) * 100',                          FALSE),
 ('On-Time Delivery', 'LOGISTICS_TMS',   'Line received within commit date plus a 2-day carrier grace window',             'AVG(receipt_date <= commit_date + 2) * 100',                    FALSE),
 ('On-Time Delivery', 'SUPPLIER_PORTAL', 'Line received within 30 days of ship date (supplier-promised transit)',          'AVG(receipt_date - ship_date <= 30) * 100',                     FALSE),
 ('On-Time Delivery', 'GOVERNED',        'Line received on or before the commit date',                                       'AVG(receipt_date <= commit_date) * 100',                        TRUE),
 ('Fill Rate',        'ERP',             'Share of lines with line status F (closed/fulfilled)',                              'AVG(line_status = ''F'') * 100',                                FALSE),
 ('Fill Rate',        'SUPPLIER_PORTAL', 'Share of shipped quantity not returned (quantity-weighted)',                       'SUM(IFF(return_flag <> ''R'', quantity, 0)) / SUM(quantity) * 100', FALSE),
 ('Fill Rate',        'GOVERNED',        'Share of lines not returned',                                                       '(1 - AVG(return_flag = ''R'')) * 100',                          TRUE),
 ('Total Spend',      'ERP',             'Gross extended price before discount',                                              'SUM(extended_price)',                                           FALSE),
 ('Total Spend',      'LOGISTICS_TMS',   'Invoice value after discount including tax',                                        'SUM(extended_price * (1 - discount) * (1 + tax))',              FALSE),
 ('Total Spend',      'GOVERNED',        'Net extended price after discount',                                                 'SUM(extended_price * (1 - discount))',                          TRUE);
