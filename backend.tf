# Remote state backend (S3 + DynamoDB locking).
# Bucket, key, region, and lock table are supplied per environment at init
# time via a partial-configuration file:
#
#   tofu init -backend-config=envs/dev.s3.tfbackend
#
# See README.md ("First-time AWS setup") for creating the bucket and table.
terraform {
  backend "s3" {}
}
