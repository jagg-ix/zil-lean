resource "aws_s3_bucket" "b" {
  bucket = "my-bucket"
}
variable "v" {}
output "o" { value = 1 }
