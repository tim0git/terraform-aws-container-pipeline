output "aws_codepipeline_name" {
  value = aws_codepipeline.codepipeline.name
}
output "aws_codepipeline_role_policy_arn" {
  value = aws_iam_role.codepipeline_role.arn
}
output "codepipeline_bucket_name" {
  value = aws_s3_bucket.codepipeline_bucket.bucket
}
output "aws_codepipeline_role_arn" {
  value = aws_iam_role.codepipeline_role.arn
}

