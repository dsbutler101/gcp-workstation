data "archive_file" "function_archive" {
  type        = "zip"
  source_dir  = "./app"
  output_path = "app.zip"
}


data "google_project" "project" {
   project_id = var.project
}

resource "google_service_account" "function" {
  account_id   = "workstation-manager"
  display_name = "Manages workstation instance"
}

resource "google_project_iam_custom_role" "function" {
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

resource "google_project_iam_member" "function" {
  project = var.project
  role    = google_project_iam_custom_role.function.id
  member  = "serviceAccount:${google_service_account.function.email}"
}

resource "google_service_account" "instance" {
  account_id   = "workstation-instance"
  display_name = "Access granted to workstation instance"
}

resource "google_project_iam_member" "instance_binding" {
  project = var.project
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_storage_bucket_object" "function_source" {
  name   = "workstation-manager-${data.archive_file.function_archive.output_md5}.zip"
  bucket = google_storage_bucket.artifact_store.name
  source = data.archive_file.function_archive.output_path
}

resource "google_cloudfunctions_function" "function" {
  name                  = "workstation-manager"
  description           = "workstation-manager"
  runtime               = "python37"
  max_instances         = 1
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.artifact_store.name
  source_archive_object = google_storage_bucket_object.function_source.name
  trigger_http          = true
  timeout               = 30
  entry_point           = "workstation_manager"
  service_account_email = google_service_account.function.email
  environment_variables = {
    API_KEY_SHA256 = var.api_key_sha256
    REGION         = var.region
    ZONE           = var.zone
    USER           = var.user
    SSH_PUBLIC_KEY = var.ssh_public_key
  }
}

resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.function.project
  region         = google_cloudfunctions_function.function.region
  cloud_function = google_cloudfunctions_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_project_iam_member" "scheduler" {
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
    google_project_iam_member.scheduler,
  ]
  http_target {
    http_method = "DELETE"
    uri         = "https://compute.googleapis.com/compute/v1/projects/${var.project}/zones/${var.zone}/instances/centos8"
    oauth_token {
      service_account_email = google_service_account.function.email
    }
  }
}
