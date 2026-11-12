-- Databricks notebook source
select max(billed_amount) , max(settled_ts) , max(admission_date) ,max(discharge_date),max(submitted_ts) from claims.bronze.claims;

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