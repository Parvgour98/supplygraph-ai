-- SupplyGraph AI: Streamlit in Snowflake deployment
-- PUT must run from a client (Snowflake CLI, SnowSQL or CoCo), not from a Snowsight worksheet.
-- Alternatively, upload both files to the stage through the Snowsight UI.

CREATE STAGE IF NOT EXISTS SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for SupplyGraph AI Streamlit app';

-- PUT 'file:///<repo>/streamlit_app.py' @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
-- PUT 'file:///<repo>/environment.yml'  @SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT SUPPLYGRAPH_AI.SUPPLY_CHAIN.SUPPLYGRAPH_AI_APP
  ROOT_LOCATION = '@SUPPLYGRAPH_AI.SUPPLY_CHAIN.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  TITLE = 'SupplyGraph AI'
  COMMENT = 'Supply Chain Ontology & Governed Conversational Analytics - Hackathon Challenge 5';

SHOW STREAMLITS IN SCHEMA SUPPLYGRAPH_AI.SUPPLY_CHAIN;
