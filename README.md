# HR documents — retrieval-augmented generation (RAG) on Azure

Answers questions about the ten HR documents (policies and leave requests) by
**retrieving** the relevant passages at question time and letting
`gpt-4.1-mini` answer from them, with a citation. No model is trained: the
knowledge lives in an index, not in weights. Change a document, re-index,
the answer changes.

```
Blob curated/documents/doc-hr-*.txt  ->  Foundry vector store (chunk + embed)  --+
                                                                                 v
User -> Foundry agent (gpt-4.1-mini) -> file_search tool -> matching chunks -> answer + citation
```

This is the third of three ways the project gives a model knowledge:

| Dataset | Method | Where the knowledge lives | Repo |
|---|---|---|---|
| Finance | fine-tune Qwen2.5-3B (QLoRA) | adapter weights | Azure-FineTuning-Foundry-Agent |
| Employee | new model trained from scratch | the model's weights | Azure-Employee-Pretraining |
| HR | RAG | an index, read at inference | this repo |

---

## Azure services used

No training compute and no endpoint: this track is the AI Services account
and Blob Storage only.

| Service | What it does in this project |
|---|---|
| **Blob Storage** (ingestion account) | holds the OCR'd HR texts under `curated/documents/doc-hr-*.txt` |
| **Document Intelligence** | produced those texts from the generated PDFs (ingestion repo) |
| **Entra ID** | your identity reads the container (Storage Blob Data Contributor) and calls the agents API (Foundry User) |
| **AI Services account** | hosts the model deployment, the project and the vector store |
| **Azure OpenAI deployment `gpt-4.1-mini`** | reads the retrieved chunks and writes the answer with a citation |
| **Foundry project `docintel-finance`** | hosts `docintel-hr-agent` |
| **Foundry files + vector store `hr-documents`** | the ten texts uploaded; Foundry chunks, embeds and indexes them (managed RAG store) |
| **Foundry `file_search` tool** | embeds the question, retrieves the matching chunks, feeds them to the model |
| **Azure Bot Service** (optional, created by Publish) | exposes the agent in Microsoft 365 Copilot |

Not used, on purpose: Azure AI Search (the managed vector store is enough for
ten documents), Azure ML, any endpoint.

---

## Prerequisites

- The ingestion repo has run (`run_all.sh`), so `curated/documents/doc-hr-*.txt`
  exist in its Blob container; its Terraform gave you **Storage Blob Data
  Contributor** there
- Steps 1 and 5 of **Azure-FineTuning-Foundry-Agent** have run: the AI
  Services account with `gpt-4.1-mini`, the Foundry project `docintel-finance`
  and your Foundry User role exist
- Python 3.11+, `az login`

```bash
python -m venv .venv
.venv/Scripts/pip install -r rag/requirements.txt
```

On Windows run from Git Bash with `MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8`
in front of the Python commands.

---

## Step 1 — fetch the documents

```bash
python rag/fetch_documents.py        # -> data/hr/doc-hr-001.txt ... doc-hr-010.txt
```

Downloads the OCR text the ingestion repo produced (Document Intelligence
`prebuilt-read` over the generated PDFs). `data/hr/` is gitignored.

Set `AZURE_STORAGE_ACCOUNT` to the ingestion repo's storage account (its
`terraform output storage_account`); the script's default is the one used
during development.

---

## Step 2 — index and create the agent

```bash
python rag/create_agent.py
```

What it does:

1. Uploads the ten files to the Foundry project and creates a **vector
   store** named `hr-documents`. Foundry chunks each file, embeds the chunks
   and builds the search index — that is the "chunk → embed → index" step.
2. Creates (or updates) the agent `docintel-hr-agent` on `gpt-4.1-mini` with
   the `file_search` tool bound to that store. The instructions require a
   search before every answer, quoting the figure and naming the document.
3. Asks three questions and reports whether retrieval was used:

```
Q  How much notice does the Flexible Hours Policy require?
A  ... requests must be submitted at least 7 business days in advance ...
   policy reference HR-209【doc-hr-001.txt】
   retrieval used: yes
Q  Who approves requests under the Flexible Hours Policy?
A  ... approved by the team lead ... HR-209【doc-hr-001.txt】
   retrieval used: yes
Q  What is the capital of France?
A  I can only answer questions related to the company's HR documents ...
   retrieval used: NO
```

The store is reused on later runs; `--reindex` rebuilds it after the
documents change. `--ask "..."` sends your own question.

---

## Test questions

| Ask | Expect |
|---|---|
| How much notice does the Flexible Hours Policy require? | 7 business days, HR-209 |
| Who approves requests under the Flexible Hours Policy? | the team lead, HR-209 |
| List every leave request and its status. | 5 requests: Santos (Pending), Okafor, Lindqvist, O'Brien (Approved), Petrova (Pending), each with its LR number |
| Was Daniel Okafor's sick leave approved? | yes, LR-31758, approver S. Brooks |
| What is the parental leave allowance? | not in the documents |

Every answer carries a `【…†doc-hr-NNN.txt】` citation — that is the
retrieved chunk the answer came from.

**Portal:** https://ai.azure.com → New Foundry → project `docintel-finance` →
Agents → `docintel-hr-agent` → Save as new agent → Playground. The vector
store appears under the agent's *Knowledge*.

---

## How it differs from the other two tracks

| | Fine-tune (finance) | From scratch (employee) | RAG (HR) |
|---|---|---|---|
| Training run | 3 h on a T4 | 77 s on a T4 | none |
| Knowledge update | retrain the adapter | retrain the model | re-upload the file |
| Answers cite a source | no | no | yes |
| Can answer about a document it never saw | no | no | yes, once indexed |
| Works with a changing corpus | poorly | poorly | yes |
| Cost at idle | endpoint per hour | endpoint per hour | vector store storage only |

RAG is the right tool when the corpus changes or must be cited; training is
the right tool when the knowledge must be available with no retrieval step,
or must be served by a model you fully own.

---

## Cost and teardown

Nothing here runs by the hour. The vector store bills for storage (the first
GB is free; these files are 10 KB). `gpt-4.1-mini` bills per token.

```bash
python - <<'EOF'
from rag.create_agent import *
c = AgentsClient(endpoint=project_endpoint(), credential=AzureCliCredential())
for s in c.vector_stores.list():
    if s.name == STORE_NAME: c.vector_stores.delete(s.id)
for a in c.list_agents():
    if a.name == AGENT_NAME: c.delete_agent(a.id)
EOF
```

---

## Files

```
rag/
  fetch_documents.py    Blob -> data/hr/
  create_agent.py       vector store + agent + test
  requirements.txt
data/hr/                the ten OCR texts (gitignored)
```
