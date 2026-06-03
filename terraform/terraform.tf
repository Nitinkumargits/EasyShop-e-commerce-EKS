terraform {
  backend "s3" {
    bucket = "easyshop-tfstate-637423357842-apsouth1"
    key    = "backend-locking"
    region = "ap-south-1"
    use_lockfile = true
  }
}