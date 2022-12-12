# terraform-aws-container-pipeline
Terraform module which creates CodePipeline resources for building OCI containers within AWS environment.

The following resources will be created:

## Example 1 Build [x86_64 (amd64)] container image and push to AWS ecr:
``` hcl
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "build_container_and_push_to_ecr" {
  source  = "../../"
  version = "1.0.0"

  project_name = "example-project"

  enable_container_features = true

  provider_type = "GitHub"

  ## NOTE Env vars must be in PLAINTEXT format as the iam role for ECR access is generated by terraform and uses their PLAINTEXT value.

  build_environment_variables = [{
    name  = "AWS_DEFAULT_REGION"
    value = "us-east-1"
    type  = "PLAINTEXT"
    },
    {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
      type  = "PLAINTEXT"
    },
    {
      name  = "IMAGE_REPO_NAME"
      value = "example-ecr-repo-name"
      type  = "PLAINTEXT"
    },
    {
      name  = "IMAGE_TAG"
      value = "latest"
      type  = "PLAINTEXT"
  }]

  full_repository_id = "github-user/example-project"

  branch_name = "main"

  enable_codestar_notifications = true
  
  pipeline_artifact_access_log_storage_bucket = "example-s3-bucket-name"

  tags = {
    Name = "example-project"
  }
}
```

Example buildspec.yml for a dockerfile build
``` yaml
version: 0.2
phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG
```

## Example 2 Build [arm64, amd64] multi architecture container image and push to AWS ecr:
- requires a buildspec.yml in the branch root that follows the buildspec.yml syntax.
  https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html
- In addition, you will be required to add buildspec-manifest.yml file to your repository root. Example of buildspec-manifest.yml is provided below.
``` hcl
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

module "build_container_and_push_to_ecr" {
  source  = "../../"
  version = "1.0.0"

  project_name = "example-project"

  enable_multi_architecture_image_builds = true

  provider_type = "GitHub"

  ## NOTE Env vars must be in PLAINTEXT format as the iam role for ECR access is generated by terraform and uses their PLAINTEXT value.

  build_environment_variables = [{
    name  = "AWS_DEFAULT_REGION"
    value = "us-east-1"
    type  = "PLAINTEXT"
    },
    {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
      type  = "PLAINTEXT"
    },
    {
      name  = "IMAGE_REPO_NAME"
      value = "example-ecr-repo-name"
      type  = "PLAINTEXT"
    },
    {
      name  = "IMAGE_TAG"
      value = "latest"
      type  = "PLAINTEXT"
  }]

  full_repository_id = "github-user/example-project"

  branch_name = "main"

  enable_codestar_notifications = true
  
  pipeline_artifact_access_log_storage_bucket = "example-s3-bucket-name"

  tags = {
    Name = "example-project"
  }
}
```

Example buildspec-manifest.yml required in addition to buildspec.yml for a dockerfile build when using multi architecture enabled.
``` yaml
version: 0.2
phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker manifest...
      - export DOCKER_CLI_EXPERIMENTAL=enabled
      - docker manifest create $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest-arm64 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest-amd64
      - docker manifest annotate --arch arm64 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest-arm64
      - docker manifest annotate --arch amd64 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:latest-amd64
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker image...
      - docker manifest push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
      - docker manifest inspect $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
```
