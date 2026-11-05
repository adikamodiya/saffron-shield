-- Databricks notebook source
-- drop table claims.gold.hospital_monthly_designer;

select * from claims.gold.hospital_monthly;

-- COMMAND ----------

select claim_id , failed_rules  from claims.silver.claims_quarantine ;

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