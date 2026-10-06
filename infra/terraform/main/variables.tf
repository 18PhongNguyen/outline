variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "domain" {
  type    = string
  default = "outline.launch-mate.com"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "github_repo" {
  type    = string
  default = "18PhongNguyen/outline"
}

variable "github_repo_immutable" {
  description = "owner@id/repo@id form used in GitHub immutable OIDC subjects (gh api repos/<repo>/actions/oidc/customization/sub)"
  type        = string
  default     = "18PhongNguyen@147136144/outline@1406969370"
}

variable "name" {
  type    = string
  default = "outline"
}
