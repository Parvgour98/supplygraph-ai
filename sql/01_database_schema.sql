-- SupplyGraph AI: Database and Schema Setup
-- Challenge 5: Supply Chain Ontology and Governed Conversational Analytics

CREATE DATABASE IF NOT EXISTS SUPPLYGRAPH_AI
  COMMENT = 'Supply Chain Ontology and Governed Conversational Analytics - Hackathon Challenge 5';

CREATE SCHEMA IF NOT EXISTS SUPPLYGRAPH_AI.SUPPLY_CHAIN
  COMMENT = 'Curated supply chain views and ontology on TPC-H data';
