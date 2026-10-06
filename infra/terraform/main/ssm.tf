resource "random_id" "secret_key" {
  byte_length = 32
}

resource "random_id" "utils_secret" {
  byte_length = 32
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "secret_key" {
  name  = "/outline/SECRET_KEY"
  type  = "SecureString"
  value = random_id.secret_key.hex
}

resource "aws_ssm_parameter" "utils_secret" {
  name  = "/outline/UTILS_SECRET"
  type  = "SecureString"
  value = random_id.utils_secret.hex
}

resource "aws_ssm_parameter" "postgres_password" {
  name  = "/outline/POSTGRES_PASSWORD"
  type  = "SecureString"
  value = random_password.postgres.result
}

resource "aws_ssm_parameter" "google_client_id" {
  name  = "/outline/GOOGLE_CLIENT_ID"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "google_client_secret" {
  name  = "/outline/GOOGLE_CLIENT_SECRET"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "smtp_username" {
  name  = "/outline/SMTP_USERNAME"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "smtp_password" {
  name  = "/outline/SMTP_PASSWORD"
  type  = "SecureString"
  value = "CHANGE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}
