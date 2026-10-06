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

variable "name" {
  type    = string
  default = "outline"
}
