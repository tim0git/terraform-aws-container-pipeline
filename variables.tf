variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "codepipeline"
}

variable "provider_type" {
  description = "The provider type"
  type        = string
  default     = "GitHub"
}

variable "full_repository_id" {
  description = "The full repository id"
  type        = string
  default     = ""
}

variable "branch_name" {
  description = "The branch name"
  type        = string
  default     = "develop"
}

variable "build_environment_variables" {
  description = "The build environment variables"
  type        = any
  default     = []
}

variable "enable_codestar_notifications" {
  description = "Enable codestar notifications and sns topic"
  type        = bool
  default     = false
}

variable "enable_container_features" {
  description = "If true, build project will run in privileged mode, and ecr actions required for build and deploy will be added to build project iam role"
  type        = bool
  default     = true
}

variable "enable_multi_architecture_image_builds" {
  description = "If true, two build projects will be created, one for amd64 and one for arm64. In addition a manifest stage will be created to create publish the manifest to ecr"
  type        = bool
  default     = false
}

variable "pipeline_artifact_access_log_storage_bucket" {
  description = "The log bucket id where you want to store the pipeline artifact access logs, if no id is passed, logging will be disabled"
  type        = string
  default     = ""
}

variable "codedbuild_service_role_kms_key_alias" {
  description = "The kms key alias for codedbuild service role"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "The tags to apply to the project"
  type        = map(string)
  default = {
    "CodePipeline" = "true"
  }
}
