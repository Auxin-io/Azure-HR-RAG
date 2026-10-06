# RAG over the HR documents. No training, no endpoint, no GPU.
#
#   AI Services + gpt-4.1-mini      answers from the retrieved chunks
#   + text-embedding-3-small        embeds the chunks and the question
#   Foundry project                 holds the agent and its managed vector store
#
# This is the whole stack. There is no ML workspace, no compute cluster, no
# container registry and no datastore, because nothing here trains or serves
# a model of its own - the vector store is managed by Foundry.
#
# Its only dependency on another repository is the ingestion storage account,
# passed in as two variables. You read the documents yourself with your own
# identity (rag/fetch_documents.py), so the grant below is to you, not to a
# workspace.
#
# NOTHING IN THIS STACK BILLS BY THE HOUR. The models bill per token and the
# vector store bills for storage - these files are about 10 KB.

data "azurerm_client_config" "current" {}

# The one thing this stack needs from another repository.
data "azurerm_storage_account" "ingest" {
  name                = var.ingest_storage_account_name
  resource_group_name = var.ingest_resource_group_name
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  sfx = random_string.suffix.result
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rag-rg"
  location = var.location
  tags     = var.tags
}

# -------------------------------------------------- AI Services + models ---
resource "azurerm_cognitive_account" "ai" {
  name                  = "${var.name_prefix}-rag-ais-${local.sfx}"
  resource_group_name   = azurerm_resource_group.this.name
  location              = azurerm_resource_group.this.location
  kind                  = "AIServices"
  sku_name              = "S0"
  custom_subdomain_name = "${var.name_prefix}-rag-ais-${local.sfx}"

  # lets the account host native Foundry projects
  project_management_enabled = true

  identity {
    type = "SystemAssigned"
  }
  tags = var.tags
}

resource "azurerm_cognitive_deployment" "agent_model" {
  name                 = var.agent_model
  cognitive_account_id = azurerm_cognitive_account.ai.id

  model {
    format  = "OpenAI"
    name    = var.agent_model
    version = var.agent_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = var.agent_model_capacity
  }
}

# The managed vector store needs an embedding deployment on the same account.
# Without it, creating the store fails and the file_search tool has nothing
# to search.
resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_model
  cognitive_account_id = azurerm_cognitive_account.ai.id

  # Same 409 RequestConflict rule: two deployments on one account cannot be
  # created at the same time.
  depends_on = [azurerm_cognitive_deployment.agent_model]

  model {
    format  = "OpenAI"
    name    = var.embedding_model
    version = var.embedding_model_version
  }

  sku {
    name     = "Standard"
    capacity = 120
  }
}

# ------------------------------------------------------- Foundry project ---
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = var.project_name
  parent_id = azurerm_cognitive_account.ai.id
  location  = azurerm_resource_group.this.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {}
  }

  # Both deployments must land first. The embedding one because nothing can
  # build a vector store in this project without it - and both of them because
  # Azure permits one mutating operation at a time per Cognitive Services
  # account and rejects concurrent ones with 409 RequestConflict.
  depends_on = [
    azurerm_cognitive_deployment.embedding,
    azurerm_cognitive_deployment.agent_model,
  ]
}

# ------------------------------------------------------------------ roles ---
# Note: there is deliberately no "me_reads_ingest" assignment here.
# The ingestion repo already grants whoever ran it Storage Blob Data
# Contributor on that account, which covers read. Granting it again from a
# track stack fails with 409 RoleAssignmentExists as soon as a second track is
# deployed, because Azure keys an assignment on (principal, role, scope) and
# the person is the same in all of them.
#
# Deploying a track as a DIFFERENT identity than the one that ran ingestion?
# Grant yourself read once, by hand:
#   az role assignment create --assignee <you> --role "Storage Blob Data Reader" \
#     --scope $(az storage account show -n <ingest-storage> -g <ingest-rg> --query id -o tsv)

resource "azurerm_role_assignment" "me_openai" {
  scope                = azurerm_cognitive_account.ai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Foundry data plane: upload files, build vector stores, create and run agents.
# Owner does not include it - it is a data action. Referenced by id because
# the display name differs between tenants ("Azure AI User" / "Foundry User").
resource "azurerm_role_assignment" "me_foundry_user" {
  scope              = azurerm_cognitive_account.ai.id
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
  principal_id       = data.azurerm_client_config.current.object_id
}
