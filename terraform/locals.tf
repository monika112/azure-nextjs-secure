locals {
  prefix = "${var.project}-${var.environment}"
  tags = merge(var.tags, {
    environment = var.environment
    project     = var.project
  })
}

resource "random_string" "unique" {
  length  = 6
  upper   = false
  special = false
}
