locals {
   function_name = "workstation-manager"
}

provider "google" {
  version = "~> 3.31.0"
  project = var.project
  region  = var.region
  zone    = var.zone
}

provider "archive" {
  version = "~> 1.3.0"
}

data "archive_file" "function_dist" {
  type        = "zip"
  source_dir  = "./app"
  output_path = "app.zip"
}

resource "google_service_account" "workstation_manager" {
  account_id   = "workstation-manager"
  display_name = "Manages workstation instance"
}

resource "google_project_iam_custom_role" "workstation_manager" {
  role_id     = "workstationManager"
  title       = "Workstation Manager"
  description = "Custom role for managing workstation instance"
  permissions = [
    "compute.disks.use",
    "compute.firewalls.get",
    "compute.firewalls.update",
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.setTags",
    "compute.instances.start",
    "compute.instances.stop",
    "compute.networks.updatePolicy",
    "compute.subnetworks.use",
    "compute.subnetworks.useExternalIp",
    "dns.changes.create",
    "dns.changes.get",
    "dns.changes.list",
    "dns.resourceRecordSets.create",
    "dns.resourceRecordSets.delete",
    "dns.resourceRecordSets.list",
    "dns.resourceRecordSets.update",
    "iam.serviceAccounts.actAs"]
}

resource "google_project_iam_member" "workstation_manager" {
  project = var.project
  role    = google_project_iam_custom_role.workstation_manager.id
  member  = "serviceAccount:${google_service_account.workstation_manager.email}"
}

resource "google_service_account" "workstation_developer" {
  account_id   = "workstation-developer"
  display_name = "Access granted to workstation instance"
}

resource "google_project_iam_member" "workstation_developer" {
  project = var.project
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.workstation_developer.email}"
}

resource "google_storage_bucket" "bucket" {
  name     = "${var.project}-artifact-store"
  location = var.region
}

resource "google_storage_bucket_object" "archive" {
  name   = "${local.function_name}.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.function_dist.output_path
}

resource "google_cloudfunctions_function" "function" {
  name                  = local.function_name
  description           = local.function_name
  runtime               = "python37"
  max_instances         = 1
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.bucket.name
  source_archive_object = google_storage_bucket_object.archive.name
  trigger_http          = true
  timeout               = 30
  entry_point           = replace(local.function_name, "-", "_")
  service_account_email = google_service_account.workstation_manager.email
  environment_variables = {
    API_KEY_SHA256 = var.api_key_sha256
  }
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}
