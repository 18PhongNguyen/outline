output "elastic_ip" {
  value = aws_eip.outline.public_ip
}

output "instance_id" {
  value = aws_instance.outline.id
}

output "ecr_registry" {
  value = local.ecr_registry
}

output "deploy_bucket" {
  value = local.deploy_bucket
}

output "aws_region" {
  value = var.region
}

output "deploy_role_arn" {
  value = aws_iam_role.gh_deploy.arn
}

output "plan_role_arn" {
  value = aws_iam_role.gh_plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.gh_apply.arn
}

output "tf_state_bucket" {
  value = "outline-tfstate-${local.account_id}"
}
