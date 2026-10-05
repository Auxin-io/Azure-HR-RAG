variable "name_prefix" {
  description = "Prefix for every resource name. Change it and all names follow."
  type        = string
  default     = "docintel"
}

variable "location" {
  description = "Needs gpt-4.1-mini availability. No GPU quota is required for this track."
  type        = string
  default     = "eastus"
}

variable "agent_model" {
  description = "Azure OpenAI model that reads the retrieved chunks and writes the answer."
  type        = string
  default     = "gpt-4.1-mini"
}

variable "agent_model_version" {
  type    = string
  default = "2025-04-14"
}

variable "agent_model_capacity" {
  description = "Thousands of tokens per minute. 10 rate-limits a live demo as soon as two people ask at once."
  type        = number
  default     = 150
}

variable "embedding_model" {
  description = "Model the managed vector store uses to embed chunks and questions."
  type        = string
  default     = "text-embedding-3-small"
}

variable "embedding_model_version" {
  type    = string
  default = "1"
}

variable "project_name" {
  description = "Foundry project that holds the HR agent and its vector store. Created by this stack."
  type        = string
  default     = "hr"
}

# ------------------------------------------------------------------- inputs
# The ONLY dependency this stack has on another repository: the storage
# account that Azure-Document-Ingestion created. Read them from that repo's
#   terraform output storage_account
#   terraform output resource_group
variable "ingest_storage_account_name" {
  description = "Storage account created by Azure-Document-Ingestion, holding the OCR'd HR texts."
  type        = string
}

variable "ingest_resource_group_name" {
  description = "Resource group of that storage account."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = { project = "hr-rag", managed_by = "terraform" }
}
