# R8 - claims-agent-chat: Databricks App chat page backed by the claims-agent serving endpoint.
# The app makes NO LLM calls of its own: it forwards each question to SERVING_ENDPOINT
# (model claims.genai.claims_agent, champion version - agent v2 prompt, temperature 0)
# and renders the agent's answer, tool calls and cited chunks.
import os

from databricks.sdk import WorkspaceClient
from flask import Flask, jsonify, render_template_string, request

# app.yaml maps this env var to the app resource "serving-endpoint" (valueFrom: serving-endpoint);
# Databricks sets it to the endpoint NAME (claims-agent).
SERVING_ENDPOINT = os.environ["SERVING_ENDPOINT"]
PORT = int(os.environ.get("DATABRICKS_APP_PORT", "8000"))

# Inside Databricks Apps, WorkspaceClient() authenticates as the app's service principal
# via the injected OAuth credentials. The serving-endpoint resource grants that principal
# CAN_QUERY on the endpoint, so this query call is authorized without any secrets in code.
_w = WorkspaceClient()

app = Flask(__name__)

PAGE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>claims-agent-chat</title>
<style>
 body { font-family: system-ui, sans-serif; background: #0f1117; color: #e6e6e6; margin: 0; }
 .wrap { max-width: 720px; margin: 24px auto; padding: 0 16px; }
 h1 { font-size: 20px; }
 .sub { color: #9aa0aa; font-size: 13px; margin-bottom: 16px; }
 #log { border: 1px solid #2a2f3a; border-radius: 8px; padding: 12px; height: 60vh; overflow-y: auto; background: #141821; }
 .msg { padding: 8px 10px; border-radius: 8px; margin: 6px 0; white-space: pre-line; }
 .user { background: #1d2b45; margin-left: 15%; }
 .bot { background: #1a2f22; margin-right: 15%; }
 .meta { color: #8fbf9f; font-size: 12px; margin-right: 15%; }
 form { display: flex; gap: 8px; margin-top: 12px; }
 input { flex: 1; padding: 10px; border-radius: 8px; border: 1px solid #2a2f3a; background: #141821; color: #e6e6e6; }
 button { padding: 10px 18px; border-radius: 8px; border: 0; background: #2f6feb; color: white; cursor: pointer; }
</style>
</head>
<body>
<div class="wrap">
 <h1>Saffron Shield - Claims Agent Chat</h1>
 <div class="sub">serving endpoint: {{ endpoint }} (agent answers via lookup_claim / plan_at / search_policy / compute_payable)</div>
 <div id="log"></div>
 <form id="f">
  <input id="q" placeholder="Ask about a claim, plan or policy..." autocomplete="off">
  <button>Send</button>
 </form>
</div>
<script>
const log = document.getElementById("log");
function add(cls, text) {
 const d = document.createElement("div");
 d.className = "msg " + cls;
 d.textContent = text;
 log.appendChild(d);
 log.scrollTop = log.scrollHeight;
 return d;
}
document.getElementById("f").addEventListener("submit", async (e) => {
 e.preventDefault();
 const q = document.getElementById("q").value.trim();
 if (!q) return;
 add("user", q);
 document.getElementById("q").value = "";
 const t = add("bot", "thinking...");
 try {
 const r = await fetch("/api/chat", {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({question: q})});
 const j = await r.json();
 if (j.error) { t.textContent = "Error: " + j.error; return; }
 t.textContent = j.answer;
 if (j.tool_calls && j.tool_calls.length) add("meta", "tools: " + j.tool_calls.join(", "));
 if (j.cited_chunk_ids && j.cited_chunk_ids.length) add("meta", "cited: " + j.cited_chunk_ids.join(", "));
 } catch (err) { t.textContent = "Request failed: " + err; }
});
</script>
</body>
</html>"""


@app.get("/")
def index():
    return render_template_string(PAGE, endpoint=SERVING_ENDPOINT)


@app.post("/api/chat")
def chat():
    q = (request.get_json(silent=True) or {}).get("question", "").strip()
    if not q:
        return jsonify({"error": "empty question"}), 400
    try:
        r = _w.serving_endpoints.query(
            name=SERVING_ENDPOINT,
            dataframe_records=[{"question": q}],
        )
        pred = r.predictions
        if isinstance(pred, list):
            pred = pred[0]
        return jsonify({
            "answer": pred.get("answer"),
            "tool_calls": pred.get("tool_calls", []),
            "cited_chunk_ids": pred.get("cited_chunk_ids", []),
        })
    except Exception as e:  # surface endpoint errors to the chat instead of crashing
        return jsonify({"error": str(e)}), 502


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)