# leading comment with { brace
resource "google_compute_instance" "vm-1" {
  name = "vm-1"
  zone = "${var.zone}-a"
  labels = {
    env = "prod"
    team = "x"
  }
  empty = ""
  neg = -3
  negf = -0.5
  flag = TRUE
  note = "a // not a comment"
  hash = "x # not a comment"
}

resource "kubernetes_namespace" "ns" {
  metadata {
    name = "demo"
  }
}

locals {
  x = 1
}

provider "google" {
  project = "p"
}

resource "x" "y" {
  a = <<EOT
heredoc
EOT
  b = "after"
}
