# Retrieval-Augmented Generation (RAG) on Azure

> Read **[Azure-Document-Ingestion](https://github.com/Auxin-io/Azure-Document-Ingestion#readme)** first. It covers prerequisites. It has produced the data, and the shared foundation exists.

In this project Answers questions about the ten HR documents (policies and leave requests) by
**retrieving** the relevant passages at question time and letting
`gpt-4.1-mini` answer from them, with a citation. The
knowledge lives in an index. Change a document, re-index,
the answer changes.

```
Blob curated/documents/doc-hr-*.txt  ->  Foundry vector store (chunk + embed)  --+
                                                                                 v
User -> Foundry agent (gpt-4.1-mini) -> file_search tool -> matching chunks -> answer + citation
```

Training data comes from the
[Azure-Document-Ingestion](https://github.com/Auxin-io/Azure-Document-Ingestion).

---

## Workflow diagram

The diagram below shows the workflow of the project.

<img width="3120" height="1086" alt="AI Project#1 - Doc Intel AWS v2 - RAG-Workflow" src="https://github.com/user-attachments/assets/14b06475-1662-4e7c-b934-3ae9215988b4" />

`fetch_documents.py` pulls the OCR texts from the ingestion Blob
with your Entra identity, `create_agent.py` uploads them (purpose `agents`), builds the
Foundry-managed vector store `hr-documents` and creates `hr-agent` with the
`file_search` tool. At question time the tool retrieves the top chunks, gpt-4.1-mini answers
with a `doc-hr-NNN.txt` citation, and questions outside the documents are refused.

## Azure services used

| Service | What it does in this project |
|---|---|
| **Blob Storage** (ingestion account) | holds the OCR'd HR texts under `curated/documents/doc-hr-*.txt` |
| **Document Intelligence** | produced those texts from the generated PDFs (ingestion repo) |
| **Entra ID** | your identity reads the container (Storage Blob Data Contributor) and calls the agents API (Foundry User) |
| **AI Services account** | hosts the model deployment, the project and the vector store |
| **Azure OpenAI deployment `gpt-4.1-mini`** | reads the retrieved chunks and writes the answer with a citation |
| **Foundry project `<project>`** | hosts `hr-agent` |
| **Foundry files + vector store `hr-documents`** | the ten texts uploaded; Foundry chunks, embeds and indexes them (managed RAG store) |
| **Foundry `file_search` tool** | embeds the question, retrieves the matching chunks, feeds them to the model |
| **Azure Bot Service** (optional, created by Publish) | exposes the agent in Microsoft 365 Copilot |

---

## Prerequisites

- Azure CLI 2.89+, Terraform >= 1.9; Python 3.11+
- `az login` into a subscription where you are **Owner** (Terraform and the
  steps below assign roles)

```bash
az login
```

---

## Step 1 — infrastructure

```bash
cd terraform
terraform init
terraform apply
terraform output
cd ..
```

Creates, in `<prefix>-rag-rg`: an AI Services account with a `gpt-4.1-mini`
deployment **and a `text-embedding-3-small` deployment**, a Foundry project,
and three role assignments - Blob read on the ingestion container so you can
fetch the documents, plus the two data-plane roles you need to build a vector
store and run agents.

Then load the resource names the two scripts need:

```bash
eval "$(terraform -chdir=terraform output -raw agent_env)"
```

That sets `AZURE_STORAGE_ACCOUNT` too, which `fetch_documents.py` now requires
- it has no default, because the ingestion storage account name carries a
random suffix.

---

## Step 1 — fetch the documents

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r rag/requirements.txt
python3 rag/fetch_documents.py        # -> data/hr/doc-hr-001.txt ... doc-hr-010.txt
```

Downloads the OCR text the ingestion repo produced (Document Intelligence
`prebuilt-read` over the generated PDFs). `data/hr/` is gitignored.

Set `AZURE_STORAGE_ACCOUNT` to the ingestion repo's storage account (its
`terraform output storage_account`); the script's default is the one used
during development.

---

## Step 2 — index and create the agent

```bash
python3 rag/create_agent.py
```

What it does:

1. Uploads the ten files to the Foundry project and creates a **vector
   store** named `hr-documents`. Foundry chunks each file, embeds the chunks
   and builds the search index — that is the "chunk → embed → index" step.
2. Creates (or updates) the agent `hr-agent` on `gpt-4.1-mini` with
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

**Portal:** https://ai.azure.com → New Foundry → project `<project>` →
Agents → `hr-agent` → Save as new agent → Playground. The vector
store appears under the agent's *Knowledge*.

---

## Step 3 — publish to Microsoft 365 Copilot (optional)

In the agent click **Publish → Teams and Microsoft 365**, fill in the
descriptions, keep the generated bot name, and finish. This creates an Azure
Bot Service (free F0) and a service principal.

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

---

---

## Cost and teardown

Teradown the project by terraform destroy

```bash
cd terraform && terraform destroy 
```

---

## Files

```
rag/
  fetch_documents.py    Blob -> data/hr/
  create_agent.py       vector store + agent + test
  publish_version.py    pushes new INSTRUCTIONS to the migrated (versioned) agent
  requirements.txt
data/hr/                the ten OCR texts (gitignored)
```
