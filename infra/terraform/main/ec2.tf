data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "outline" {
  ami                     = data.aws_ssm_parameter.al2023_ami.value
  instance_type           = var.instance_type
  subnet_id               = sort(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids  = [aws_security_group.outline.id]
  iam_instance_profile    = aws_iam_instance_profile.outline.name
  disable_api_termination = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region             = var.region
    ecr_registry       = local.ecr_registry
    deploy_bucket      = local.deploy_bucket
    backup_bucket      = local.backups_bucket
    attachments_bucket = local.attachments_bucket
    domain             = var.domain
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "outline" {
  instance = aws_instance.outline.id
  domain   = "vpc"

  tags = {
    Name = var.name
  }
}
