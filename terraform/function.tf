data "google_project" "project" {
   project_id = var.project
}

resource "google_storage_bucket" "artifact-store" {
  name     = "${var.project}-artifact-store"
  location = var.region
}

resource "google_project_iam_custom_role" "function-custom-role" {
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
    "compute.zoneOperations.get",
    "dns.changes.create",
    "dns.changes.get",
    "dns.changes.list",
    "dns.resourceRecordSets.create",
    "dns.resourceRecordSets.delete",
    "dns.resourceRecordSets.list",
    "dns.resourceRecordSets.update",
    "iam.serviceAccounts.actAs"]
}

resource "google_service_account" "function-service-account" {
  account_id   = "workstation-manager"
  display_name = "Manages workstation instance"
}

resource "google_project_iam_member" "function-binding" {
  project = var.project
  role    = google_project_iam_custom_role.function-custom-role.id
  member  = "serviceAccount:${google_service_account.function-service-account.email}"
}

resource "google_project_iam_member" "function-deployer-binding" {
  project = var.project
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_service_account" "instance-service-account" {
  account_id   = "workstation-instance"
  display_name = "Access granted to workstation instance"
}

resource "google_project_iam_member" "instance-binding" {
  project = var.project
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.instance-service-account.email}"
}

data "archive_file" "function-archive" {
  type        = "zip"
  source_dir  = "./app"
  output_path = "app.zip"
}

resource "google_storage_bucket_object" "function-source" {
  name   = "workstation-manager-${data.archive_file.function-archive.output_md5}.zip"
  bucket = google_storage_bucket.artifact-store.name
  source = data.archive_file.function-archive.output_path
}

resource "google_cloudfunctions_function" "function" {
  name                  = "workstation"
  description           = "workstation"
  runtime               = "python37"
  max_instances         = 1
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.artifact-store.name
  source_archive_object = google_storage_bucket_object.function-source.name
  trigger_http          = true
  timeout               = 30
  entry_point           = "handler"
  service_account_email = google_service_account.function-service-account.email
  environment_variables = {
    API_KEY_SHA256 = var.api_key_sha256
    REGION         = var.region
    ZONE           = var.zone
    USER           = var.user
    SSH_PUBLIC_KEY = var.ssh_public_key
  }
  depends_on = [
    google_project_iam_member.function-deployer-binding,
  ]
}

resource "google_cloudfunctions_function_iam_member" "invoker-binding" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_project_iam_member" "scheduler-binding" {
  project = var.project
  role    = "roles/cloudscheduler.serviceAgent"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

resource "google_cloud_scheduler_job" "daily-stop-instance" {
  name             = "daily-stop-instance"
  description      = "Stop workstation instance on a daily basis"
  schedule         = "0 3 * * *"
  time_zone        = "Europe/London"
  attempt_deadline = "320s"
  depends_on = [
    google_project_iam_member.scheduler-binding,
  ]
  http_target {
    http_method = "DELETE"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.project}/zones/${var.zone}/instances/centos8"
    oauth_token {
      service_account_email = google_service_account.function-service-account.email
    }
  }
}
