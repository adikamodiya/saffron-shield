# Saffron Shield - GenAI Claims Agent (GenAi-2 / Paper 5)

End-to-end LLM claims-adjudication agent on Databricks: Unity Catalog tool functions, a tool-calling agent with guardrails and memory, a multi-specialist supervisor, MCP transport, a UC-registered + served agent, and a Databricks Apps chat UI.

## Environment & Global Config

| Setting | Value |
| --- | --- |
| Workspace | dbc-de868f4b-f279.cloud.databricks.com (Free Edition) |
| Root folder | `/Workspace/Users/custom001x@gmail.com/saffron-shield/GenAi-2` |
| Catalog | `claims` (schemas: `raw`, `silver`, `gold`, `genai`) |
| CHAT_MODEL | `databricks-meta-llama-3-3-70b-instruct` |
| EMBED_MODEL | `databricks-gte-large-en` |
| Temperature | `0.0` on every LLM call (deterministic demos) |
| SQL warehouse | Serverless Starter `78d419cb76b1d7e9` |
| Serving endpoint | `claims-agent` (CPU, Small, scale-to-zero, serves v10 = champion) |
| Databricks App | `claims-agent-chat` |
| MLflow experiment | `/Users/custom001x@gmail.com/saffron-shield/genai2-agent` |

## Repository Layout

```
GenAi-2/
  R1..R8 notebooks        one notebook per round (R1 SQL tools ... R8 app wiring)
  src/guardrails.py       R3 input/output guardrails (stdlib only)
  agent/prompts/          system_v1.md, system_v2.md (v2 = v1 + memory rule), r5_specialists.md
  agent/traces/           probe + supervisor trace receipts (r2_*.json, r5_attempt_1.json, r6_mcp_agent.json)
  agent/mcp_stdio_server.py  R6 FastMCP stdio server exposing the 4 UC functions
  app/                    R8 Databricks App (app.py, app.yaml, requirements.txt)
  evidence/               round evidence JSONs, r8_demo.gif, screenshots/
```

## Rounds - What Was Built

| Round | Deliverable | Evidence |
| --- | --- | --- |
| R1 | 4 UC SQL functions in `claims.genai`: `lookup_claim`, `plan_at`, `search_policy` (hybrid vector+keyword), `compute_payable` (7-arg payable calculator); 20/20 agreement with the adjudication answer key | `evidence/r1_tools.json` |
| R2 | Single-turn tool-calling agent (LangChain `ChatDatabricks` + hand-rolled loop, temp 0) over the 4 tools; probe traces logged to MLflow | `evidence/r2_agent.json`, `agent/traces/r2_status_probe.json`, `agent/traces/r2_policy_probe.json`, `evidence/screenshots/r2_trace.png` |
| R3 | Guardrails: input screen (payout promises / PII / off-topic) + output screen; 10/10 client probes correct | `evidence/r3_guardrails.json`, `src/guardrails.py` |
| R4 | Memory: short-term in-context history + long-term Delta table `claims.genai.adjuster_notes` with `recall_notes`/`save_note` tools; `system_v2.md` = v1 + memory rule | `evidence/r4_memory.json`, `agent/prompts/system_v2.md` |
| R5 | Supervisor + 3 LLM specialists (data / policy / adjudication) + deterministic verifier recomputed from R1 functions; verdict matched the answer key on attempt 1 | `agent/traces/r5_attempt_1.json`, `agent/prompts/r5_specialists.md`, `evidence/screenshots/r5_trace.png` |
| R6 | MCP transport: managed MCP preview not enabled -> permitted stdio fallback (`FastMCP` server calling the UC functions via SQL Statement Execution API); MCP `compute_payable` result == verified answer | `evidence/r6_mcp.json`, `agent/traces/r6_mcp_agent.json` |
| R7 | Agent as MLflow pyfunc -> UC registry `claims.genai.claims_agent` (v9 = prompt v1 sha 9d7623f004ea, v10 = prompt v2 sha 47371a1d0f83, alias `champion`) + serving endpoint `claims-agent` with automatic auth passthrough (resources: 4 UC functions, warehouse, chat endpoint) | `evidence/r7_registry.json`, `evidence/screenshots/r7_endpoint.png` |
| R8 | Databricks App `claims-agent-chat`: Flask chat page; app service principal queries the endpoint (resource key `serving-endpoint`, CAN_QUERY); no LLM calls in the app | `evidence/r8_app.json` (`mode: endpoint`), `evidence/screenshots/r8_app.png`, `evidence/r8_demo.gif` |

## How To Reproduce (Run Order)

1. **R1** - run notebook `R1`: creates + verifies the 4 UC functions and writes `evidence/r1_tools.json`.
2. **R2** - run `R2`: builds the agent loop, runs the two probes, logs traces, writes `evidence/r2_agent.json`.
3. **R3** - run `R3`: guardrail screen + agent pipeline, writes `evidence/r3_guardrails.json`.
4. **R4** - run `R4`: memory rounds + Delta notes table, writes `evidence/r4_memory.json`.
5. **R5** - run `R5`: supervisor/specialists/verifier, writes `agent/traces/r5_attempt_1.json`.
6. **R6** - run `R6`: stdio MCP server + MCP-driven agent run, writes `evidence/r6_mcp.json`.
7. **R7** - run `R7` cells in order: registers v9/v10 with resource dependencies, updates the `claims-agent` endpoint to the champion version, writes `evidence/r7_registry.json`. Endpoint is READY and live-tested.
8. **R8** - app source lives in `app/` (deployed to app `claims-agent-chat` via `databricks apps deploy --source-code-path ...`). Resource `serving-endpoint` -> `claims-agent` with **Can query** is attached to the app; status RUNNING. `evidence/r8_app.json` is the receipt; `evidence/r8_demo.gif` is the demo.

### Query the live agent

- **Endpoint (any HTTP client):** `POST /serving-endpoints/claims-agent/invocations` with body `{"dataframe_records": [{"question": "..."}]}` -> `{answer, tool_calls, cited_chunk_ids}`.
- **App:** open `claims-agent-chat` in the Apps list and chat (see `evidence/screenshots/r8_app.png`).

## Notes & Key Design Decisions

- **Determinism**: temperature 0 everywhere; R5 verdict is taken from the deterministic verifier (recomputed via R1 functions), not from LLM output.
- **Auth passthrough (R7)**: the pyfunc model declares `DatabricksFunction` x4 + `DatabricksSQLWarehouse` + `DatabricksServingEndpoint` as resources so model serving grants the endpoint principal access. `pip_requirements` pins `mlflow>=2.16.0,<3` (langchain-databricks 0.1.2 -> databricks-vectorsearch<0.41 requires mlflow-skinny<3).
- **MCP (R6)**: managed MCP is a preview feature not enabled on this workspace; stdio transport with `FastMCP` is the documented permitted fallback and exposes the same 4 tools.
- **App resources (R8)**: the app never talks to the LLM or UC directly - it only forwards questions to `claims-agent`; its service principal got CAN_QUERY via the app resource.

## Verification Checklist

- [x] R1 functions agree with `claims.genai.adjudication_verifier` on all 20 probe claims
- [x] R2 probes answered with real tool calls; traces in MLflow + JSON receipts
- [x] R3 blocks 6/6 malicious probes, allows 4/4 benign
- [x] R4 short-term + long-term memory verified (references recalled from Delta table)
- [x] R5 supervisor verdict agrees with the deterministic verifier and answer key
- [x] R6 MCP tool result == verified answer (stdio fallback documented)
- [x] R7 champion (v10) registered, tagged, alias set; endpoint READY; live query returns answer + tool_calls
- [x] R8 app RUNNING; live chat answered in browser; demo recorded
- [ ] `evidence/scorecard.json` - written by the course grader notebook (`00_grader`)
