provider "google" {
  version = "~> 3.31.0"
  project = var.project
  region  = var.region
  zone    = var.zone
}

provider "archive" {
  version = "~> 1.3.0"
}

terraform {
  backend "gcs" {
    bucket = "tfstate-data-kefa-uk"
    prefix = "workstation" 
  }
}
