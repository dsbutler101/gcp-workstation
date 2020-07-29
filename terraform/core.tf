
resource "google_compute_disk" "workstation-centos8" {
  name  = "workstation-centos8"
  type  = "pd-standard"
  zone  = var.zone
  image = "centos-8-v20200714"
  size  = "20"
}
