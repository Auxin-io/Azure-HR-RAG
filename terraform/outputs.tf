output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "ai_services_account" {
  value = azurerm_cognitive_account.ai.name
}

output "ai_services_endpoint" {
  value = azurerm_cognitive_account.ai.endpoint
}

output "foundry_project" {
  value = azapi_resource.project.name
}

output "foundry_project_endpoint" {
  value = "https://${azurerm_cognitive_account.ai.custom_subdomain_name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "agent_model_deployment" {
  value = azurerm_cognitive_deployment.agent_model.name
}

output "embedding_deployment" {
  value = azurerm_cognitive_deployment.embedding.name
}

output "ingest_storage_account" {
  value = data.azurerm_storage_account.ingest.name
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

# Everything the two scripts need, so neither has to hardcode a name.
#   eval "$(terraform output -raw agent_env)"
output "agent_env" {
  description = "Shell exports consumed by rag/fetch_documents.py and rag/create_agent.py"
  value = join("\n", [
    "export AZURE_STORAGE_ACCOUNT=${data.azurerm_storage_account.ingest.name}",
    "export AZURE_RESOURCE_GROUP=${azurerm_resource_group.this.name}",
    "export AZURE_AI_SERVICES=${azurerm_cognitive_account.ai.name}",
    "export FOUNDRY_PROJECT=${azapi_resource.project.name}",
    "export AGENT_MODEL=${azurerm_cognitive_deployment.agent_model.name}",
  ])
}
