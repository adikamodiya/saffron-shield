
# MCP stdio server exposing the four Saffron Shield R1 UC functions as MCP tools.
# Permitted-fallback transport: Databricks managed MCP servers (Public Preview) are not
# enabled in this workspace, so this local server speaks MCP over stdio and executes the
# UC functions through the SQL Statement Execution API on the workspace SQL warehouse.
import json
import os
import time

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import Disposition, Format, StatementState
from mcp.server.fastmcp import FastMCP

WAREHOUSE_ID = os.environ["MCP_WAREHOUSE_ID"]
w = WorkspaceClient()

def q(s) -> str:
    return str(s).replace(chr(39), chr(39) + chr(39))

def run_sql(sql: str) -> list:
    resp = w.statement_execution.execute_statement(
        warehouse_id=WAREHOUSE_ID, statement=sql,
        disposition=Disposition.INLINE, format=Format.JSON_ARRAY, wait_timeout="50s")
    while resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(2)
        resp = w.statement_execution.get_statement(resp.statement_id)
    if resp.status.error is not None:
        raise RuntimeError(f"statement failed: {resp.status.error.error_code} {resp.status.error.message}")
    if resp.status.state != StatementState.SUCCEEDED:
        raise RuntimeError(f"statement ended in state {resp.status.state}")
    cols = [c.name for c in resp.manifest.schema.columns]
    rows = [dict(zip(cols, r)) for r in (resp.result.data_array or [])]
    result = resp.result
    while result.next_chunk_index is not None:
        result = w.statement_execution.get_statement_result_chunk_n(resp.statement_id, result.next_chunk_index)
        rows.extend(dict(zip(cols, r)) for r in (result.data_array or []))
    return rows

mcp = FastMCP("claims-genai")

@mcp.tool()
def lookup_claim(claim_id: str) -> str:
    "Look up ONE insurance claim by its exact claim id (example: CLM-10642). Returns every stored fact of that claim as JSON: member_id, policy_id, hospital_id, status, claim_type, admission and discharge dates, billed and approved amounts, plan code at admission, room rent and cap, network flag, policy start date and tenure, days since policy start. Use for ANY question about a specific claim."
    return json.dumps(run_sql(f"SELECT * FROM claims.genai.lookup_claim('{q(claim_id)}')"), default=str)

@mcp.tool()
def plan_at(member_id: str, as_of_date: str) -> str:
    "Look up the Saffron Shield plan terms that were VALID on a given date (YYYY-MM-DD) for a member id (example: MEM-0493). Returns plan_code, plan_family, room_rent_cap_per_day, copay_pct, ped_waiting_months, initial_waiting_days, valid_from, valid_to. Use with the member id and admission date from lookup_claim when a claim question needs plan terms."
    return json.dumps(run_sql(f"SELECT * FROM claims.genai.plan_at('{q(member_id)}', DATE'{q(as_of_date)}')"), default=str)

@mcp.tool()
def search_policy(query: str) -> str:
    "Search the Saffron Shield policy binder (hybrid keyword + semantic). Returns up to 5 chunks with chunk_id, doc_name, heading and full text. Use for ANY question about what the policy says: waiting periods, room rent caps, co-payments, network hospitals, exclusions. Always read each chunk's 'Applies to' line before quoting it."
    return json.dumps(run_sql(f"SELECT * FROM claims.genai.search_policy('{q(query)}')"), default=str)

@mcp.tool()
def compute_payable(plan_code: str, is_pre_existing: bool, policy_tenure_months: int, days_since_policy_start: int, is_network_at_admission: bool, room_rent_per_day: int, billed_amount: float) -> str:
    "Decide how much a claim pays, strictly by the policy Definitions. Pass the claim facts from lookup_claim (tenure months, days since policy start, pre-existing flag, network flag, room rent per day, billed amount) and the plan_code from plan_at. Returns JSON with payable, reason, room_rent_deduction_pct, copay_pct and payable_amount. Never decide a payout without this tool."
    pe = "true" if is_pre_existing else "false"
    nw = "true" if is_network_at_admission else "false"
    rows = run_sql(f"SELECT claims.genai.compute_payable('{q(plan_code)}', {pe}, {int(policy_tenure_months)}, {int(days_since_policy_start)}, {nw}, {int(room_rent_per_day)}, CAST({float(billed_amount)} AS DOUBLE)) AS s")
    return rows[0]["s"]

if __name__ == "__main__":
    mcp.run()
