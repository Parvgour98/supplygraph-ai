-- SupplyGraph AI: Semantic View (Supply Chain Ontology)
-- Final hardened version, identical in content to the deployed object.
-- Validated: 15/15 Cortex Analyst questions, 9/9 metrics vs raw TPC-H (see VALIDATION.md).

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
      COMMENT = 'Pre-aggregated supplier performance scores'
  )

  RELATIONSHIPS (
    shipment_to_order AS shipments (ORDER_KEY) REFERENCES orders,
    shipment_to_supplier AS shipments (SUPPLIER_KEY) REFERENCES suppliers,
    shipment_to_part AS shipments (PART_KEY) REFERENCES parts,
    order_to_customer AS orders (CUSTOMER_KEY) REFERENCES customers,
    supplier_part_to_supplier AS supplier_parts (SUPPLIER_KEY) REFERENCES suppliers,
    supplier_part_to_part AS supplier_parts (PART_KEY) REFERENCES parts,
    perf_to_supplier AS supplier_performance (SUPPLIER_KEY) REFERENCES suppliers
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
    supplier_performance.distinct_customers_served AS DISTINCT_CUSTOMERS_SERVED COMMENT = 'Distinct customers'
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
    supplier_parts.part_type AS supplier_parts.PART_TYPE COMMENT = 'Part type in catalog'
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
    supplier_parts.average_margin AS AVG(supplier_parts.margin_percentage) COMMENT = 'Avg margin percentage'
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
    )
  );
