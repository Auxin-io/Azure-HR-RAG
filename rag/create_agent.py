"""Build the HR vector store and the agent that answers from it.

    python rag/create_agent.py                   # index data/hr/*.txt, create agent, ask 3 questions
    python rag/create_agent.py --ask "Who approves flexible hours requests?"
    python rag/create_agent.py --reindex         # rebuild the vector store from data/hr

    user question -> agent (gpt-4.1-mini) -> file_search tool
                  -> vector store: HR documents chunked + embedded at upload time
                  -> the matching chunks are put in the prompt
                  -> gpt-4.1-mini answers from those chunks, with a citation

Nothing is trained. The knowledge lives in the index and is read at inference
time - change a policy, re-upload the file, the answer changes.
"""

from __future__ import annotations

import argparse
import subprocess
import shutil
from pathlib import Path

from azure.ai.agents import AgentsClient
from azure.ai.agents.models import FilePurpose, FileSearchTool, RunStepToolCallDetails
from azure.identity import AzureCliCredential

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent / "data" / "hr"
RG, PROJECT = "docintel-ml-rg", "docintel-finance"
AGENT_NAME, MODEL, STORE_NAME = "docintel-hr-agent", "gpt-4.1-mini", "hr-documents"

INSTRUCTIONS = """You are an HR assistant. You answer questions about the company's HR documents:
policies (scope, approval, notice periods, review cycle) and leave requests (who, what
type, how many days, dates, status, approver).
ALWAYS search the HR documents with the file_search tool before answering, and answer
only from what the search returns. Quote the exact figure or wording and name the
document it came from (its title and policy or request reference). If the documents do
not contain the answer, say so plainly - do not guess and do not use general HR knowledge.
For anything that is not an HR-document question, answer normally."""

AZ = shutil.which("az") or shutil.which("az.cmd") or "az"


def az(*args: str) -> str:
    return subprocess.check_output([AZ, *args], text=True).strip()


def project_endpoint() -> str:
    account = az("cognitiveservices", "account", "list", "-g", RG,
                 "--query", "[?kind=='AIServices'].name | [0]", "-o", "tsv")
    return f"https://{account}.services.ai.azure.com/api/projects/{PROJECT}"


def vector_store(client: AgentsClient, reindex: bool) -> str:
    """Reuse the store by name unless asked to rebuild it."""
    existing = next((s for s in client.vector_stores.list() if s.name == STORE_NAME), None)
    if existing and not reindex:
        print(f"vector store {existing.id} ({existing.file_counts.completed} files) reused")
        return existing.id
    if existing:
        client.vector_stores.delete(existing.id)
    files = sorted(DOCS.glob("doc-hr-*.txt"))
    if not files:
        raise SystemExit(f"no documents in {DOCS} - run rag/fetch_documents.py first")
    ids = [client.files.upload_and_poll(file_path=str(f), purpose=FilePurpose.AGENTS).id for f in files]
    store = client.vector_stores.create_and_poll(file_ids=ids, name=STORE_NAME)
    print(f"vector store {store.id}: {store.file_counts.completed} files indexed")
    return store.id


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ask", action="append")
    ap.add_argument("--reindex", action="store_true")
    args = ap.parse_args()

    client = AgentsClient(endpoint=project_endpoint(), credential=AzureCliCredential())
    tool = FileSearchTool(vector_store_ids=[vector_store(client, args.reindex)])

    agent = next((a for a in client.list_agents() if a.name == AGENT_NAME), None)
    if agent:
        agent = client.update_agent(agent.id, model=MODEL, instructions=INSTRUCTIONS,
                                    tools=tool.definitions, tool_resources=tool.resources)
        print(f"updated agent {agent.id}")
    else:
        agent = client.create_agent(model=MODEL, name=AGENT_NAME, instructions=INSTRUCTIONS,
                                    tools=tool.definitions, tool_resources=tool.resources)
        print(f"created agent {agent.id}")

    questions = args.ask or ["How much notice does the Flexible Hours Policy require?",
                             "Who approves requests under the Flexible Hours Policy?",
                             "What is the capital of France?"]
    thread = client.threads.create()
    for q in questions:
        client.messages.create(thread_id=thread.id, role="user", content=q)
        run = client.runs.create_and_process(thread_id=thread.id, agent_id=agent.id)
        print("=" * 78)
        print(f"Q  {q}")
        if run.status != "completed":
            print(f"   run {run.status}: {run.last_error}")
            continue
        reply = next(m for m in client.messages.list(thread_id=thread.id) if m.role == "assistant")
        text = "".join(getattr(c, "text").value for c in reply.content if hasattr(c, "text"))
        searched = any(isinstance(s.step_details, RunStepToolCallDetails)
                       for s in client.run_steps.list(thread_id=thread.id, run_id=run.id))
        print(f"A  {text}")
        print(f"   retrieval used: {'yes' if searched else 'NO'}")


if __name__ == "__main__":
    main()
