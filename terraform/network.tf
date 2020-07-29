resource "google_compute_network" "main" {
  name = "main"
  auto_create_subnetworks = false
  
}

resource "google_compute_subnetwork" "main" {
  name          = "main-${var.region}"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_firewall" "ssh-from-iap-to-workstation" {
  name    = "ssh-from-iap-to-workstation"
  network = google_compute_network.main.name

  source_ranges = [ "35.235.240.0/20" ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags = ["workstation"]
}

resource "google_compute_firewall" "ssh-from-roaming-to-workstation" {
  name    = "ssh-from-roaming-to-workstation"
  network = google_compute_network.main.name

  source_ranges = [ "86.179.254.164/32" ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  allow {
    protocol = "udp"
    ports    = ["60000-61000"]
  }

  target_tags = ["workstation"]
}
