"""Pull the OCR'd HR documents out of the ingestion repo's Blob container.

    python rag/fetch_documents.py            # -> data/hr/doc-hr-001.txt ... doc-hr-010.txt

Reads curated/documents/doc-hr-*.txt with the caller's Entra identity
(shared keys are disabled on that account). These are the raw texts the
vector store is built from; nothing here is training data.
"""

from __future__ import annotations

import os
from pathlib import Path

from azure.identity import AzureCliCredential
from azure.storage.blob import BlobServiceClient

# No default: the ingestion storage account name carries a random suffix, so
# any baked-in value is wrong for every deployment but one.
ACCOUNT = os.environ.get("AZURE_STORAGE_ACCOUNT", "")
if not ACCOUNT:
    raise SystemExit(
        "AZURE_STORAGE_ACCOUNT is not set. It is the ingestion repo's "
        "`terraform output storage_account`, or load this repo's outputs with: "
        'eval "$(terraform -chdir=terraform output -raw agent_env)"'
    )
CONTAINER, PREFIX = "curated", "documents/doc-hr-"
OUT = Path(__file__).resolve().parent.parent / "data" / "hr"


def main() -> None:
    svc = BlobServiceClient(f"https://{ACCOUNT}.blob.core.windows.net", credential=AzureCliCredential())
    container = svc.get_container_client(CONTAINER)
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    for blob in container.list_blobs(name_starts_with=PREFIX):
        if not blob.name.endswith(".txt"):
            continue
        target = OUT / Path(blob.name).name
        target.write_bytes(container.download_blob(blob.name).readall())
        n += 1
        print(f"  {blob.name} -> {target.relative_to(OUT.parent.parent)}")
    print(f"{n} HR documents fetched")


if __name__ == "__main__":
    main()
