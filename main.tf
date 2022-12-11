locals {
  container_architectures      = var.enable_multi_architecture_image_builds ? ["arm64", "amd64"] :  ["amd64"]
  enable_manifest_creation     = var.enable_multi_architecture_image_builds ? [true] : []
  code_build_project_arns = [
    try(module.code_build_container[0].aws_codebuild_project_arn, null),
    try(module.code_build_container[1].aws_codebuild_project_arn, null),
    try(module.code_build_manifest[0].aws_codebuild_project_arn, null),
  ]
}

module "codestar_connection" {
  source  = "tim0git/codestar-connection/aws"
  version = "1.1.1"

  name = var.project_name

  provider_type = var.provider_type

  tags = var.tags
}

module "code_build_container" {
  count   = length(local.container_architectures)
  source  = "tim0git/codebuild/aws"
  version = "1.6.0"

  project_name = "${var.project_name}-${local.container_architectures[count.index]}"

  environment_variables = var.enable_multi_architecture_image_builds ? concat([for v in var.build_environment_variables : v if v.value != "latest"], [{ name = "IMAGE_TAG", value = "latest-${local.container_architectures[count.index]}", type = "PLAINTEXT" }]) : var.build_environment_variables

  enable_container_features = var.enable_container_features

  container_architecture = local.container_architectures[count.index]

  codedbuild_service_role_kms_key_alias = aws_kms_key.codepipeline_bucket_key.arn

  tags = var.tags
}

module "code_build_manifest" {
  count   = var.enable_multi_architecture_image_builds ? 1 : 0
  source  = "tim0git/codebuild/aws"
  version = "1.6.0"

  project_name = "${var.project_name}-manifest"

  enable_container_features = var.enable_container_features

  environment_variables = var.build_environment_variables

  buildspec = "buildspec-manifest.yml"

  codedbuild_service_role_kms_key_alias = aws_kms_key.codepipeline_bucket_key.arn

  tags = var.tags
}

resource "aws_codepipeline" "codepipeline" {
  name     = "${var.project_name}-build-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = module.codestar_connection.arn
        FullRepositoryId = var.full_repository_id
        BranchName       = var.branch_name
      }
    }
  }

  stage {
    name = "Build"

    dynamic "action" {
      for_each = local.container_architectures
      content {
        name             = action.value
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        input_artifacts  = ["source_output"]
        output_artifacts = ["build_output-${action.value}"]
        version          = "1"

        configuration = {
          ProjectName = "${var.project_name}-${action.value}-codebuild"
        }
      }
    }
  }

  dynamic "stage" {
    for_each = local.enable_manifest_creation
    content {
      name = "CreateManifest"

      action {
        name             = "PublishManifest"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        input_artifacts  = ["source_output"]
        output_artifacts = ["build_output-manifest"]
        version          = "1"

        configuration = {
          ProjectName = "${var.project_name}-manifest-codebuild"
        }
      }
    }
  }

  tags = var.tags
}

resource "aws_kms_key" "codepipeline_bucket_key" {
  description             = "This key is used to encrypt ${var.project_name} code pipeline artifacts"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "codepipeline_bucket_key" {
  target_key_id = aws_kms_key.codepipeline_bucket_key.key_id
  name          = "alias/${var.project_name}"
}

#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = lower("${var.project_name}-codepipeline-artifacts-store")
  tags   = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_bucket_encryption_configuration" {
  bucket = aws_s3_bucket.codepipeline_bucket.bucket

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.codepipeline_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_versioning" "codepipeline_bucket_versioning" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_acl" "codepipeline_bucket_acl" {
  bucket = aws_s3_bucket.codepipeline_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "codepipeline_bucket_public_access_block" {
  bucket = aws_s3_bucket.codepipeline_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_logging" "example" {
  count  = var.pipeline_artifact_access_log_storage_bucket == "" ? 0 : 1
  bucket = aws_s3_bucket.codepipeline_bucket.id

  target_bucket = var.pipeline_artifact_access_log_storage_bucket
  target_prefix = "${aws_s3_bucket.codepipeline_bucket.bucket}-access-log/"
}

resource "aws_sns_topic" "pipeline_notifications" {
  count = var.enable_codestar_notifications ? 1 : 0
  name  = "${var.project_name}-build-pipeline"
  tags  = var.tags
}

resource "aws_codestarnotifications_notification_rule" "pipeline_notifications" {
  count          = var.enable_codestar_notifications ? 1 : 0
  detail_type    = "BASIC"
  event_type_ids = ["codepipeline-pipeline-pipeline-execution-started", "codepipeline-pipeline-pipeline-execution-succeeded", "codepipeline-pipeline-pipeline-execution-failed", "codepipeline-pipeline-pipeline-execution-canceled"]
  name           = "${var.project_name}-build-pipeline"
  resource       = aws_codepipeline.codepipeline.arn

  target {
    address = aws_sns_topic.pipeline_notifications[count.index].arn
  }

  tags = var.tags
}

resource "aws_sns_topic_policy" "pipeline_notifications" {
  count  = var.enable_codestar_notifications ? 1 : 0
  arn    = aws_sns_topic.pipeline_notifications[count.index].arn
  policy = data.aws_iam_policy_document.pipeline_notifications[count.index].json
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${var.project_name}-codepipeline-service-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_role.json
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "${var.project_name}-codepipeline-policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}
