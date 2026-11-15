-- Databricks notebook source
drop catalog if exists tata_multi_brand cascade; 

-- COMMAND ----------

select * from claims.silver.dim_policy_scd2 where policy_id='POL-0072';

-- COMMAND ----------

select * from claims.silver.claims_clean where claim_id = 'CLM-10001';

-- COMMAND ----------

show tables in claims.silver

-- COMMAND ----------

show tables in claims.silver;

-- COMMAND ----------

desc claims.bronze.members;

-- COMMAND ----------

select * from claims.bronze.claims;