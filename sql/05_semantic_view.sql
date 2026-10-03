-- SupplyGraph AI: Semantic View (Supply Chain Ontology)
-- Final version, identical in content to the deployed object. Requires scripts 01-04.
-- Logical tables plants, shipment_costs (freight/duty), iot_events and source_definitions
-- are backed by SYNTHETIC enrichment; all other tables are original TPC-H data.
-- Validated: see VALIDATION.md.

CREATE OR REPLACE SEMANTIC VIEW SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLY_CHAIN_ONTOLOGY

  TABLES (
    shipments AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS
      PRIMARY KEY (ORDER_KEY, LINE_NUMBER)
      WITH SYNONYMS ('line items', 'deliveries', 'shipment lines', 'order lines')
      COMMENT = 'Central fact table: every line item shipped, with delivery metrics, revenue, and lead times',
    orders AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_ORDERS
      PRIMARY KEY (ORDER_KEY)
      WITH SYNONYMS ('purchase orders', 'sales orders')
      COMMENT = 'Customer purchase orders with status, priority, and time dimensions',
    suppliers AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIERS
      PRIMARY KEY (SUPPLIER_KEY)
      WITH SYNONYMS ('vendors', 'seller', 'provider')
      COMMENT = 'Supplier master data with location and account information',
    parts AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_PARTS
      PRIMARY KEY (PART_KEY)
      WITH SYNONYMS ('products', 'items', 'materials', 'SKUs', 'components')
      COMMENT = 'Part/product catalog with brand, type, and pricing',
    customers AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_CUSTOMERS
      PRIMARY KEY (CUSTOMER_KEY)
      WITH SYNONYMS ('buyers', 'accounts', 'clients')
      COMMENT = 'Customer master data with market segment and location',
    supplier_parts AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PARTS
      PRIMARY KEY (PART_KEY, SUPPLIER_KEY)
      WITH SYNONYMS ('catalog', 'supplier catalog', 'part availability', 'inventory')
      COMMENT = 'Supplier-part relationships with availability, cost, and margin data',
    supplier_performance AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE
      PRIMARY KEY (SUPPLIER_KEY)
      WITH SYNONYMS ('supplier scorecard', 'vendor performance', 'supplier metrics')
      COMMENT = 'Pre-aggregated supplier performance scores',
    plants AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_PLANTS
      PRIMARY KEY (PLANT_KEY)
      WITH SYNONYMS ('plant', 'factory', 'facility', 'site', 'manufacturing plant', 'fulfillment center')
      COMMENT = 'SYNTHETIC ERP plant master (10 plants). Each part is assigned to one plant.',
    part_inventory AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_PART_INVENTORY
      PRIMARY KEY (PART_KEY)
      WITH SYNONYMS ('inventory position', 'days of supply', 'stock cover')
      COMMENT = 'Per-part inventory position from TPC-H: available quantity across suppliers vs shipped demand',
    shipment_costs AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENT_LANDED_COST
      PRIMARY KEY (ORDER_KEY, LINE_NUMBER)
      WITH SYNONYMS ('landed cost', 'freight', 'duty', 'logistics cost', 'total cost to serve')
      COMMENT = 'Per-shipment-line landed cost: TPC-H purchase cost plus SYNTHETIC freight and duty tariffs',
    iot_events AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS
      PRIMARY KEY (ORDER_KEY, LINE_NUMBER)
      WITH SYNONYMS ('IoT', 'telemetry', 'sensor events', 'shipment monitoring', 'cold chain')
      COMMENT = 'SYNTHETIC IoT shipment telemetry: temperature excursion, shock, delay alerts per shipment line',
    source_definitions AS SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_METRIC_DEFINITION_COMPARISON
      PRIMARY KEY (METRIC_NAME, SOURCE_SYSTEM)
      WITH SYNONYMS ('metric definitions', 'source system definitions', 'definition comparison')
      COMMENT = 'How ERP, logistics TMS and supplier portal define metrics vs the GOVERNED definition, with values'
  )

  RELATIONSHIPS (
    shipment_to_order AS shipments (ORDER_KEY) REFERENCES orders,
    shipment_to_supplier AS shipments (SUPPLIER_KEY) REFERENCES suppliers,
    shipment_to_part AS shipments (PART_KEY) REFERENCES parts,
    order_to_customer AS orders (CUSTOMER_KEY) REFERENCES customers,
    supplier_part_to_supplier AS supplier_parts (SUPPLIER_KEY) REFERENCES suppliers,
    supplier_part_to_part AS supplier_parts (PART_KEY) REFERENCES parts,
    perf_to_supplier AS supplier_performance (SUPPLIER_KEY) REFERENCES suppliers,
    part_to_plant AS parts (PLANT_KEY) REFERENCES plants,
    inventory_to_part AS part_inventory (PART_KEY) REFERENCES parts,
    cost_to_shipment AS shipment_costs (ORDER_KEY, LINE_NUMBER) REFERENCES shipments,
    iot_to_shipment AS iot_events (ORDER_KEY, LINE_NUMBER) REFERENCES shipments
  )

  FACTS (
    shipments.net_revenue AS NET_REVENUE COMMENT = 'Revenue after discount',
    shipments.gross_revenue AS GROSS_REVENUE COMMENT = 'Revenue after discount and tax',
    shipments.extended_price AS EXTENDED_PRICE COMMENT = 'Raw price before discount',
    shipments.discount AS DISCOUNT COMMENT = 'Discount rate',
    shipments.tax AS TAX COMMENT = 'Tax rate',
    shipments.quantity AS QUANTITY COMMENT = 'Quantity shipped',
    shipments.delivery_lead_time_days AS DELIVERY_LEAD_TIME_DAYS COMMENT = 'Days from order to receipt',
    shipments.shipping_lead_time_days AS SHIPPING_LEAD_TIME_DAYS COMMENT = 'Days from ship to receipt',
    shipments.processing_time_days AS PROCESSING_TIME_DAYS COMMENT = 'Days from order to ship',
    shipments.is_on_time AS IS_ON_TIME COMMENT = '1 if on time, 0 if late',
    shipments.is_late AS IS_LATE COMMENT = '1 if late, 0 if on time',
    shipments.days_late AS DAYS_LATE COMMENT = 'Days past commit date',
    supplier_parts.inventory_value AS INVENTORY_VALUE COMMENT = 'Qty times supply cost',
    supplier_parts.available_quantity AS AVAILABLE_QUANTITY COMMENT = 'Units available',
    supplier_parts.supply_cost AS SUPPLY_COST COMMENT = 'Per-unit supply cost',
    supplier_parts.margin_percentage AS MARGIN_PERCENTAGE COMMENT = 'Margin pct',
    supplier_performance.supplier_performance_score AS SUPPLIER_PERFORMANCE_SCORE COMMENT = 'Composite score 0-100',
    supplier_performance.on_time_delivery_pct AS ON_TIME_DELIVERY_PCT COMMENT = 'On-time delivery pct',
    supplier_performance.fill_rate_pct AS FILL_RATE_PCT COMMENT = 'Fill rate pct',
    supplier_performance.return_rate_pct AS RETURN_RATE_PCT COMMENT = 'Return rate pct',
    supplier_performance.total_revenue AS TOTAL_REVENUE COMMENT = 'Total supplier revenue',
    supplier_performance.avg_delivery_lead_time_days AS AVG_DELIVERY_LEAD_TIME_DAYS COMMENT = 'Avg lead time',
    supplier_performance.total_orders AS TOTAL_ORDERS COMMENT = 'Total orders',
    supplier_performance.total_line_items AS TOTAL_LINE_ITEMS COMMENT = 'Total line items',
    supplier_performance.distinct_parts_supplied AS DISTINCT_PARTS_SUPPLIED COMMENT = 'Distinct parts',
    supplier_performance.distinct_customers_served AS DISTINCT_CUSTOMERS_SERVED COMMENT = 'Distinct customers',
    -- Part inventory (TPC-H). Per-part DAYS_OF_INVENTORY is intentionally not exposed: the governed metric is a ratio of sums.
    part_inventory.available_quantity AS AVAILABLE_QUANTITY COMMENT = 'Units available across all suppliers of the part',
    part_inventory.quantity_shipped AS QUANTITY_SHIPPED COMMENT = 'Units shipped (demand) over the order window',
    part_inventory.demand_days AS DEMAND_DAYS COMMENT = 'Days in the demand window (2406)',
    -- Landed cost (TPC-H purchase cost + SYNTHETIC tariffs)
    shipment_costs.quantity AS QUANTITY COMMENT = 'Quantity on the shipment line',
    shipment_costs.purchase_cost AS PURCHASE_COST COMMENT = 'Quantity times supplier unit supply cost (TPC-H)',
    shipment_costs.freight_cost AS FREIGHT_COST COMMENT = 'Quantity times SYNTHETIC freight rate per unit for ship mode and lane',
    shipment_costs.duty_cost AS DUTY_COST COMMENT = 'Purchase cost times SYNTHETIC duty rate for supplier region to plant region',
    shipment_costs.landed_cost AS LANDED_COST COMMENT = 'Purchase cost + freight cost + duty cost',
    -- IoT telemetry (SYNTHETIC)
    iot_events.max_temp_c AS MAX_TEMP_C COMMENT = 'Maximum recorded temperature in transit (C)',
    iot_events.temp_excursion_flag AS TEMP_EXCURSION_FLAG COMMENT = '1 if max temperature exceeded 8 C',
    iot_events.shock_event_flag AS SHOCK_EVENT_FLAG COMMENT = '1 if a shock event was recorded',
    iot_events.delay_alert_flag AS DELAY_ALERT_FLAG COMMENT = '1 if receipt was after commit date',
    iot_events.delay_hours AS DELAY_HOURS COMMENT = 'Hours late',
    iot_events.condition_risk_flag AS CONDITION_RISK_FLAG COMMENT = '1 if temperature excursion or shock',
    iot_events.iot_alert_flag AS IOT_ALERT_FLAG COMMENT = '1 if delay, temperature excursion or shock',
    iot_events.gps_ping_count AS GPS_PING_COUNT COMMENT = 'GPS pings received in transit',
    -- Source-system definitions
    source_definitions.metric_value AS METRIC_VALUE COMMENT = 'Metric value under this source system definition',
    source_definitions.governed_value AS GOVERNED_VALUE COMMENT = 'Metric value under the governed definition',
    source_definitions.variance_from_governed AS VARIANCE_FROM_GOVERNED COMMENT = 'Source value minus governed value',
    source_definitions.variance_pct AS VARIANCE_PCT COMMENT = 'Variance from governed value in percent'
  )

  DIMENSIONS (
    -- Suppliers
    suppliers.supplier_name AS SUPPLIER_NAME WITH SYNONYMS = ('vendor name') COMMENT = 'Supplier name',
    suppliers.supplier_nation AS NATION_NAME WITH SYNONYMS = ('supplier country') COMMENT = 'Supplier nation',
    suppliers.supplier_region AS REGION_NAME WITH SYNONYMS = ('supplier region') COMMENT = 'Supplier region',
    -- Parts
    parts.part_name AS PART_NAME WITH SYNONYMS = ('product name') COMMENT = 'Part name',
    parts.brand AS BRAND WITH SYNONYMS = ('product brand') COMMENT = 'Part brand',
    parts.part_type AS PART_TYPE WITH SYNONYMS = ('product type', 'category') COMMENT = 'Part type',
    parts.manufacturer AS MANUFACTURER WITH SYNONYMS = ('maker') COMMENT = 'Manufacturer',
    parts.container_type AS CONTAINER_TYPE COMMENT = 'Container type',
    parts.part_size_val AS PART_SIZE COMMENT = 'Part size',
    -- Customers
    customers.customer_name AS CUSTOMER_NAME WITH SYNONYMS = ('buyer name') COMMENT = 'Customer name',
    customers.market_segment AS MARKET_SEGMENT WITH SYNONYMS = ('segment', 'industry') COMMENT = 'Market segment',
    customers.customer_nation AS customers.NATION_NAME WITH SYNONYMS = ('customer country') COMMENT = 'Customer nation',
    customers.customer_region AS customers.REGION_NAME WITH SYNONYMS = ('customer region') COMMENT = 'Customer region',
    -- Orders
    orders.order_status AS ORDER_STATUS COMMENT = 'F=Fulfilled, O=Open, P=Partial',
    orders.order_priority AS ORDER_PRIORITY WITH SYNONYMS = ('priority') COMMENT = 'Order priority',
    orders.order_date AS ORDER_DATE COMMENT = 'Order date',
    orders.order_year AS ORDER_YEAR COMMENT = 'Year of order',
    orders.order_quarter AS ORDER_QUARTER COMMENT = 'Quarter 1-4',
    orders.order_month AS ORDER_MONTH COMMENT = 'Year-month YYYY-MM',
    -- Shipments (denormalized — critical for Cortex Analyst CTE generation)
    shipments.ship_mode AS SHIP_MODE WITH SYNONYMS = ('shipping method', 'transport mode') COMMENT = 'Shipping mode',
    shipments.return_status AS RETURN_STATUS COMMENT = 'Accepted, Returned, or None',
    shipments.ship_instruction AS SHIP_INSTRUCTION COMMENT = 'Shipping instruction',
    shipments.supplier_region AS SUPPLIER_REGION WITH SYNONYMS = ('source region') COMMENT = 'Supplier region per shipment',
    shipments.customer_region AS CUSTOMER_REGION WITH SYNONYMS = ('destination region') COMMENT = 'Customer region per shipment',
    shipments.supplier_nation AS SUPPLIER_NATION WITH SYNONYMS = ('source country') COMMENT = 'Supplier nation per shipment',
    shipments.customer_nation AS CUSTOMER_NATION WITH SYNONYMS = ('destination country') COMMENT = 'Customer nation per shipment',
    shipments.supplier_name AS shipments.SUPPLIER_NAME COMMENT = 'Supplier name per shipment',
    shipments.customer_name AS shipments.CUSTOMER_NAME COMMENT = 'Customer name per shipment',
    shipments.market_segment AS shipments.MARKET_SEGMENT COMMENT = 'Market segment per shipment',
    shipments.brand AS shipments.BRAND COMMENT = 'Part brand per shipment',
    shipments.part_name AS shipments.PART_NAME COMMENT = 'Part name per shipment',
    shipments.part_type AS shipments.PART_TYPE COMMENT = 'Part type per shipment',
    shipments.order_year AS shipments.ORDER_YEAR COMMENT = 'Year of order per shipment',
    shipments.order_quarter AS shipments.ORDER_QUARTER COMMENT = 'Quarter per shipment',
    shipments.order_month AS shipments.ORDER_MONTH COMMENT = 'Year-month per shipment',
    shipments.order_priority AS shipments.ORDER_PRIORITY COMMENT = 'Order priority per shipment',
    shipments.order_date AS shipments.ORDER_DATE COMMENT = 'Order date per shipment',
    -- Supplier Performance (denormalized)
    supplier_performance.supplier_name AS supplier_performance.SUPPLIER_NAME COMMENT = 'Supplier name in scorecard',
    supplier_performance.supplier_nation AS supplier_performance.SUPPLIER_NATION COMMENT = 'Supplier nation in scorecard',
    supplier_performance.supplier_region AS supplier_performance.SUPPLIER_REGION COMMENT = 'Supplier region in scorecard',
    -- Supplier Parts (denormalized)
    supplier_parts.supplier_region AS supplier_parts.SUPPLIER_REGION COMMENT = 'Supplier region in catalog',
    supplier_parts.supplier_name AS supplier_parts.SUPPLIER_NAME COMMENT = 'Supplier name in catalog',
    supplier_parts.supplier_nation AS supplier_parts.SUPPLIER_NATION COMMENT = 'Supplier nation in catalog',
    supplier_parts.part_name AS supplier_parts.PART_NAME COMMENT = 'Part name in catalog',
    supplier_parts.brand AS supplier_parts.BRAND COMMENT = 'Part brand in catalog',
    supplier_parts.part_type AS supplier_parts.PART_TYPE COMMENT = 'Part type in catalog',
    supplier_parts.plant_name AS supplier_parts.PLANT_NAME COMMENT = 'Plant the part is assigned to (SYNTHETIC)',
    -- Plants (SYNTHETIC)
    plants.plant_name AS plants.PLANT_NAME WITH SYNONYMS = ('plant', 'factory', 'site') COMMENT = 'Plant name',
    plants.plant_code AS PLANT_CODE COMMENT = 'Plant code',
    plants.plant_type AS PLANT_TYPE COMMENT = 'Assembly, Fabrication or Distribution Center',
    plants.plant_city AS PLANT_CITY COMMENT = 'Plant city',
    plants.plant_nation AS PLANT_NATION COMMENT = 'Plant country',
    plants.plant_region AS plants.PLANT_REGION COMMENT = 'Plant region',
    -- Plant attributes denormalised onto other entities (required for Cortex Analyst CTE generation)
    parts.plant_name AS parts.PLANT_NAME COMMENT = 'Plant the part is assigned to',
    parts.plant_region AS parts.PLANT_REGION COMMENT = 'Region of the plant the part is assigned to',
    shipments.plant_name AS shipments.PLANT_NAME WITH SYNONYMS = ('plant', 'receiving plant') COMMENT = 'Plant handling the shipped part',
    shipments.plant_region AS shipments.PLANT_REGION COMMENT = 'Region of the plant handling the shipped part',
    -- Part inventory dims
    part_inventory.part_name AS part_inventory.PART_NAME COMMENT = 'Part name',
    part_inventory.brand AS part_inventory.BRAND COMMENT = 'Part brand',
    part_inventory.part_type AS part_inventory.PART_TYPE COMMENT = 'Part type',
    part_inventory.plant_name AS part_inventory.PLANT_NAME COMMENT = 'Plant the part is assigned to',
    part_inventory.plant_region AS part_inventory.PLANT_REGION COMMENT = 'Region of the plant',
    -- Landed cost dims
    shipment_costs.plant_name AS shipment_costs.PLANT_NAME COMMENT = 'Destination plant',
    shipment_costs.plant_region AS shipment_costs.PLANT_REGION COMMENT = 'Destination plant region',
    shipment_costs.supplier_region AS shipment_costs.SUPPLIER_REGION COMMENT = 'Origin supplier region',
    shipment_costs.ship_mode AS shipment_costs.SHIP_MODE COMMENT = 'Shipping mode',
    shipment_costs.order_year AS shipment_costs.ORDER_YEAR COMMENT = 'Order year',
    shipment_costs.lane_type AS LANE_TYPE COMMENT = 'DOMESTIC (same region) or CROSS_REGION',
    -- IoT dims
    iot_events.device_id AS DEVICE_ID COMMENT = 'IoT tracker device id',
    iot_events.ship_mode AS iot_events.SHIP_MODE COMMENT = 'Shipping mode',
    iot_events.supplier_region AS iot_events.SUPPLIER_REGION COMMENT = 'Origin supplier region',
    iot_events.customer_region AS iot_events.CUSTOMER_REGION COMMENT = 'Destination customer region',
    iot_events.plant_name AS iot_events.PLANT_NAME COMMENT = 'Plant handling the shipped part',
    iot_events.plant_region AS iot_events.PLANT_REGION COMMENT = 'Plant region',
    iot_events.order_year AS iot_events.ORDER_YEAR COMMENT = 'Order year',
    -- Source definition dims
    source_definitions.metric_name AS METRIC_NAME COMMENT = 'On-Time Delivery, Fill Rate or Total Spend',
    source_definitions.source_system AS SOURCE_SYSTEM COMMENT = 'ERP, LOGISTICS_TMS, SUPPLIER_PORTAL or GOVERNED',
    source_definitions.definition_text AS DEFINITION_TEXT COMMENT = 'Business definition used by the source system',
    source_definitions.sql_expression AS SQL_EXPRESSION COMMENT = 'Formula used by the source system',
    source_definitions.is_governed AS IS_GOVERNED COMMENT = 'TRUE for the canonical governed definition'
  )

  METRICS (
    shipments.total_spend AS SUM(shipments.net_revenue) WITH SYNONYMS = ('total revenue', 'spend') COMMENT = 'Total net revenue after discount',
    shipments.total_gross_revenue AS SUM(shipments.gross_revenue) WITH SYNONYMS = ('gross revenue') COMMENT = 'Total gross revenue with tax',
    shipments.average_order_value AS AVG(shipments.net_revenue) WITH SYNONYMS = ('AOV') COMMENT = 'Avg revenue per line item',
    shipments.total_quantity AS SUM(shipments.quantity) WITH SYNONYMS = ('units shipped', 'volume') COMMENT = 'Total quantity shipped',
    shipments.on_time_delivery_rate AS AVG(shipments.is_on_time) * 100 WITH SYNONYMS = ('OTD', 'on-time delivery') COMMENT = 'Pct shipments on or before commit date',
    shipments.average_lead_time AS AVG(shipments.delivery_lead_time_days) WITH SYNONYMS = ('avg lead time') COMMENT = 'Avg days from order to receipt',
    shipments.average_shipping_time AS AVG(shipments.shipping_lead_time_days) WITH SYNONYMS = ('transit time') COMMENT = 'Avg days ship to receipt',
    shipments.average_processing_time AS AVG(shipments.processing_time_days) COMMENT = 'Avg days order to ship',
    shipments.average_days_late AS AVG(shipments.days_late) COMMENT = 'Avg days late',
    shipments.fill_rate AS (1 - AVG(CASE WHEN shipments.RETURN_FLAG = 'R' THEN 1 ELSE 0 END)) * 100 WITH SYNONYMS = ('fulfillment rate') COMMENT = 'Pct of items not returned',
    shipments.return_rate AS AVG(CASE WHEN shipments.RETURN_FLAG = 'R' THEN 1 ELSE 0 END) * 100 COMMENT = 'Pct of items returned',
    shipments.shipment_count AS COUNT(shipments.net_revenue) WITH SYNONYMS = ('line item count') COMMENT = 'Total shipment line items',
    orders.order_count AS COUNT(orders.ORDER_KEY) WITH SYNONYMS = ('total orders') COMMENT = 'Total orders',
    suppliers.supplier_count AS COUNT(suppliers.SUPPLIER_KEY) WITH SYNONYMS = ('vendor count') COMMENT = 'Supplier count',
    customers.customer_count AS COUNT(customers.CUSTOMER_KEY) WITH SYNONYMS = ('buyer count') COMMENT = 'Customer count',
    parts.part_count AS COUNT(parts.PART_KEY) WITH SYNONYMS = ('SKU count') COMMENT = 'Part count',
    supplier_parts.total_inventory_value AS SUM(supplier_parts.inventory_value) WITH SYNONYMS = ('stock value') COMMENT = 'Total inventory value',
    supplier_parts.total_available_quantity AS SUM(supplier_parts.available_quantity) WITH SYNONYMS = ('total stock') COMMENT = 'Total available units',
    supplier_parts.average_supply_cost AS AVG(supplier_parts.supply_cost) COMMENT = 'Avg supply cost per unit',
    supplier_parts.average_margin AS AVG(supplier_parts.margin_percentage) COMMENT = 'Avg margin percentage',
    plants.plant_count AS COUNT(plants.PLANT_KEY) WITH SYNONYMS = ('number of plants') COMMENT = 'Plant count',
    part_inventory.days_of_inventory AS SUM(part_inventory.available_quantity) / NULLIF(SUM(part_inventory.quantity_shipped) / MAX(part_inventory.demand_days), 0)
      WITH SYNONYMS = ('DOI', 'days of supply', 'inventory days', 'inventory cover')
      COMMENT = 'Days of inventory = SUM(available quantity) / (SUM(quantity shipped) / demand days). Ratio of sums, never an average of per-part ratios.',
    part_inventory.average_daily_demand AS SUM(part_inventory.quantity_shipped) / MAX(part_inventory.demand_days) COMMENT = 'Average units demanded per day',
    part_inventory.total_part_availability AS SUM(part_inventory.available_quantity) COMMENT = 'Total units available',
    shipment_costs.total_landed_cost AS SUM(shipment_costs.landed_cost) WITH SYNONYMS = ('landed cost', 'total cost to serve') COMMENT = 'SUM(purchase + freight + duty)',
    shipment_costs.total_purchase_cost AS SUM(shipment_costs.purchase_cost) WITH SYNONYMS = ('purchase cost', 'material cost') COMMENT = 'SUM(quantity * supply cost)',
    shipment_costs.total_freight_cost AS SUM(shipment_costs.freight_cost) WITH SYNONYMS = ('freight') COMMENT = 'SUM(freight cost)',
    shipment_costs.total_duty_cost AS SUM(shipment_costs.duty_cost) WITH SYNONYMS = ('duty', 'customs') COMMENT = 'SUM(duty cost)',
    shipment_costs.landed_cost_per_unit AS SUM(shipment_costs.landed_cost) / NULLIF(SUM(shipment_costs.quantity), 0) WITH SYNONYMS = ('unit landed cost') COMMENT = 'Landed cost per unit',
    shipment_costs.freight_and_duty_share AS (SUM(shipment_costs.freight_cost) + SUM(shipment_costs.duty_cost)) / NULLIF(SUM(shipment_costs.landed_cost), 0) * 100 COMMENT = 'Freight plus duty as percent of landed cost',
    iot_events.temperature_excursion_rate AS AVG(iot_events.temp_excursion_flag) * 100 WITH SYNONYMS = ('temperature excursion rate', 'cold chain breach rate') COMMENT = 'Pct of shipments with temperature excursion',
    iot_events.shock_event_rate AS AVG(iot_events.shock_event_flag) * 100 COMMENT = 'Pct of shipments with a shock event',
    iot_events.delay_alert_rate AS AVG(iot_events.delay_alert_flag) * 100 COMMENT = 'Pct of shipments with a delay alert',
    iot_events.condition_risk_rate AS AVG(iot_events.condition_risk_flag) * 100 WITH SYNONYMS = ('IoT risk rate', 'shipment risk rate') COMMENT = 'Pct of shipments with temperature excursion or shock',
    iot_events.iot_alert_rate AS AVG(iot_events.iot_alert_flag) * 100 COMMENT = 'Pct of shipments with any IoT alert',
    iot_events.at_risk_shipment_count AS SUM(iot_events.condition_risk_flag) COMMENT = 'Shipments with temperature excursion or shock',
    iot_events.average_max_temperature AS AVG(iot_events.max_temp_c) COMMENT = 'Average max in-transit temperature (C)',
    source_definitions.source_metric_value AS MAX(source_definitions.metric_value) COMMENT = 'Metric value for a source-system definition',
    source_definitions.variance_vs_governed_pct AS MAX(source_definitions.variance_pct) COMMENT = 'Variance vs governed value in percent'
  )

  COMMENT = 'SupplyGraph AI: Supply Chain Ontology for governed conversational analytics'

  AI_SQL_GENERATION '
    Supply chain ontology on TPC-H data (1992-1998). Entities: Suppliers, Parts, Customers, Orders, Shipments.
    Metric definitions: total_spend=SUM(net_revenue), on_time_delivery_rate=AVG(is_on_time)*100,
    fill_rate=(1-AVG(return=R))*100, average_lead_time=AVG(delivery_lead_time_days).
    Supplier Performance Score is a composite 0-100 from supplier_performance table.
    Use supplier_performance for rankings/scorecards. Use shipments for trends/drilldowns. Use supplier_parts for inventory.
    Regions: AFRICA, AMERICA, ASIA, EUROPE, MIDDLE EAST. Segments: AUTOMOBILE, BUILDING, FURNITURE, HOUSEHOLD, MACHINERY.
    Order status: F=Fulfilled, O=Open, P=Partial. Ship modes: AIR, FOB, MAIL, RAIL, REG AIR, SHIP, TRUCK.
    IMPORTANT: All denormalized columns (supplier_name, supplier_region, order_year, order_priority, market_segment, brand, etc.)
    are registered as dimensions on the shipments table. When querying shipments, all needed columns are available directly.
    Similarly, supplier_performance has supplier_name, supplier_nation, supplier_region as dimensions.
    And supplier_parts has supplier_region, supplier_name, supplier_nation as dimensions.
    EXTENDED ONTOLOGY (plants, freight, duty, IoT and source-system definitions are SYNTHETIC enrichment):
    Ontology chain: Supplier -> Supplier-Part -> Part -> Plant; Shipment -> Part -> Plant; Shipment -> Order -> Customer.
    Plant performance questions: use the shipments table grouped by plant_name (on-time, spend, lead time).
    Days of inventory: use part_inventory. Days of inventory = SUM(available_quantity) / (SUM(quantity_shipped) / MAX(demand_days)).
    Never average per-part ratios. Group by plant_name, part_type or brand on part_inventory.
    Landed cost: use shipment_costs. landed_cost = purchase_cost + freight_cost + duty_cost. Landed cost per unit = SUM(landed_cost) / SUM(quantity).
    IoT shipment risk: use iot_events. temperature_excursion_rate = AVG(temp_excursion_flag)*100; condition_risk_rate = AVG(condition_risk_flag)*100.
    Source-system definition questions: use source_definitions (metric_name, source_system, definition_text, metric_value, variance_pct).
    The GOVERNED source_system row is the canonical definition used everywhere else in this semantic view.
  '

  AI_VERIFIED_QUERIES (
    top_suppliers_by_performance AS (
      QUESTION 'Who are the top 10 suppliers by performance score?'
      SQL 'SELECT supplier_name, supplier_nation, supplier_region, supplier_performance_score, on_time_delivery_pct, fill_rate_pct, return_rate_pct, total_revenue FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE ORDER BY supplier_performance_score DESC LIMIT 10'
    ),
    worst_suppliers AS (
      QUESTION 'Which suppliers have the worst performance?'
      SQL 'SELECT supplier_name, supplier_nation, supplier_region, supplier_performance_score, on_time_delivery_pct, fill_rate_pct, return_rate_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE ORDER BY supplier_performance_score ASC LIMIT 10'
    ),
    spend_by_region AS (
      QUESTION 'What is the total spend by supplier region?'
      SQL 'SELECT supplier_region, ROUND(SUM(net_revenue), 2) AS total_spend, COUNT(*) AS shipment_count, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY supplier_region ORDER BY total_spend DESC'
    ),
    on_time_by_ship_mode AS (
      QUESTION 'What is the on-time delivery rate by shipping mode?'
      SQL 'SELECT ship_mode, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct, COUNT(*) AS shipment_count, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY ship_mode ORDER BY on_time_pct DESC'
    ),
    spend_concentration AS (
      QUESTION 'What is the spend concentration across top suppliers?'
      SQL 'WITH total AS (SELECT SUM(net_revenue) AS grand_total FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS) SELECT s.supplier_name, s.supplier_region, ROUND(SUM(s.net_revenue), 2) AS supplier_spend, ROUND(SUM(s.net_revenue) * 100.0 / t.grand_total, 4) AS spend_share_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS s CROSS JOIN total t GROUP BY s.supplier_name, s.supplier_region, t.grand_total ORDER BY supplier_spend DESC LIMIT 20'
    ),
    monthly_trend AS (
      QUESTION 'What is the monthly spend trend?'
      SQL 'SELECT order_month, ROUND(SUM(net_revenue), 2) AS total_spend, COUNT(*) AS shipment_count, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY order_month ORDER BY order_month'
    ),
    regional_performance AS (
      QUESTION 'How do suppliers perform by region?'
      SQL 'SELECT supplier_region, COUNT(*) AS supplier_count, ROUND(AVG(supplier_performance_score), 2) AS avg_score, ROUND(AVG(on_time_delivery_pct), 2) AS avg_on_time, ROUND(AVG(fill_rate_pct), 2) AS avg_fill_rate, ROUND(SUM(total_revenue), 2) AS total_revenue FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PERFORMANCE GROUP BY supplier_region ORDER BY avg_score DESC'
    ),
    fill_rate_by_segment AS (
      QUESTION 'What is the fill rate by customer market segment?'
      SQL 'SELECT market_segment, ROUND((1 - AVG(CASE WHEN return_flag = ''R'' THEN 1 ELSE 0 END)) * 100, 2) AS fill_rate_pct, COUNT(*) AS shipments, ROUND(SUM(net_revenue), 2) AS total_spend FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY market_segment ORDER BY fill_rate_pct DESC'
    ),
    inventory_by_region AS (
      QUESTION 'What is the total inventory value by supplier region?'
      SQL 'SELECT supplier_region, ROUND(SUM(inventory_value), 2) AS total_inventory_value, SUM(available_quantity) AS total_available_qty, COUNT(DISTINCT supplier_key) AS suppliers, COUNT(DISTINCT part_key) AS parts FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SUPPLIER_PARTS GROUP BY supplier_region ORDER BY total_inventory_value DESC'
    ),
    lead_time_by_priority AS (
      QUESTION 'What is the average lead time by order priority?'
      SQL 'SELECT order_priority, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time, ROUND(AVG(processing_time_days), 1) AS avg_processing_time, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct, COUNT(*) AS shipments FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY order_priority ORDER BY order_priority'
    ),
    yearly_trend AS (
      QUESTION 'How has supply chain performance changed year over year?'
      SQL 'SELECT order_year, ROUND(SUM(net_revenue), 2) AS total_spend, COUNT(*) AS shipments, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct, ROUND((1 - AVG(CASE WHEN return_flag = ''R'' THEN 1 ELSE 0 END)) * 100, 2) AS fill_rate_pct, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY order_year ORDER BY order_year'
    ),
    cross_region AS (
      QUESTION 'What percentage of shipments are cross-region?'
      SQL 'SELECT CASE WHEN supplier_region = customer_region THEN ''Same Region'' ELSE ''Cross Region'' END AS shipment_type, COUNT(*) AS shipment_count, ROUND(SUM(net_revenue), 2) AS total_spend, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time, ROUND(AVG(is_on_time) * 100, 2) AS on_time_pct FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY shipment_type ORDER BY shipment_count DESC'
    ),
    plant_performance AS (
      QUESTION 'How does each plant perform on on-time delivery, spend and lead time?'
      SQL 'SELECT plant_name, plant_region, ROUND(AVG(is_on_time) * 100, 2) AS on_time_delivery_rate, ROUND(SUM(net_revenue), 2) AS total_spend, ROUND(AVG(delivery_lead_time_days), 1) AS avg_lead_time, COUNT(*) AS shipment_count FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENTS GROUP BY plant_name, plant_region ORDER BY on_time_delivery_rate DESC'
    ),
    days_of_inventory_by_plant AS (
      QUESTION 'What is the days of inventory by plant?'
      SQL 'SELECT plant_name, ROUND(SUM(available_quantity) / NULLIF(SUM(quantity_shipped) / MAX(demand_days), 0), 1) AS days_of_inventory, SUM(available_quantity) AS available_quantity, SUM(quantity_shipped) AS quantity_shipped FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_PART_INVENTORY GROUP BY plant_name ORDER BY days_of_inventory DESC'
    ),
    landed_cost_breakdown AS (
      QUESTION 'What is the total landed cost by supplier region broken down into purchase, freight and duty?'
      SQL 'SELECT supplier_region, ROUND(SUM(purchase_cost), 2) AS purchase_cost, ROUND(SUM(freight_cost), 2) AS freight_cost, ROUND(SUM(duty_cost), 2) AS duty_cost, ROUND(SUM(landed_cost), 2) AS total_landed_cost FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENT_LANDED_COST GROUP BY supplier_region ORDER BY total_landed_cost DESC'
    ),
    landed_cost_per_unit_by_mode AS (
      QUESTION 'What is the landed cost per unit by ship mode?'
      SQL 'SELECT ship_mode, ROUND(SUM(landed_cost) / NULLIF(SUM(quantity), 0), 2) AS landed_cost_per_unit, ROUND(SUM(freight_cost) / NULLIF(SUM(quantity), 0), 2) AS freight_per_unit, ROUND(SUM(landed_cost), 2) AS total_landed_cost FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_SHIPMENT_LANDED_COST GROUP BY ship_mode ORDER BY landed_cost_per_unit DESC'
    ),
    iot_risk_by_ship_mode AS (
      QUESTION 'Which ship modes have the highest IoT temperature excursion and shipment risk rates?'
      SQL 'SELECT ship_mode, ROUND(AVG(temp_excursion_flag) * 100, 2) AS temperature_excursion_rate, ROUND(AVG(shock_event_flag) * 100, 2) AS shock_event_rate, ROUND(AVG(condition_risk_flag) * 100, 2) AS condition_risk_rate, SUM(condition_risk_flag) AS at_risk_shipments FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.SYN_IOT_SHIPMENT_EVENTS GROUP BY ship_mode ORDER BY condition_risk_rate DESC'
    ),
    source_definition_comparison AS (
      QUESTION 'How do the source systems define on-time delivery and how does each value compare to the governed definition?'
      SQL 'SELECT source_system, definition_text, metric_value, governed_value, variance_pct, is_governed FROM SUPPLYGRAPH_AI.SUPPLY_CHAIN.V_METRIC_DEFINITION_COMPARISON WHERE metric_name = ''On-Time Delivery'' ORDER BY is_governed DESC, source_system'
    )
  );
