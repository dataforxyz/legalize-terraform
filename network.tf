# --------------------------------------------------------------------------
# Legalize Server — Networking
# --------------------------------------------------------------------------

# ── VPC ──────────────────────────────────────────────────────────────────

resource "google_compute_network" "vpc" {
  name                    = "legalize-vpc"
  auto_create_subnetworks = false
  project                 = google_project.legalize.project_id

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "legalize-subnet"
  ip_cidr_range            = "10.0.2.0/24"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# ── Cloud NAT (outbound internet for scraping) ──────────────────────────

resource "google_compute_router" "router" {
  name    = "legalize-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "legalize-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ALL"
  }
}

# ── Firewall Rules ───────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "legalize-allow-ssh-iap"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP tunnel range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["legalize-server"]
}

resource "google_compute_firewall" "allow_ssh_public" {
  name    = "legalize-allow-ssh-public"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["legalize-server"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "legalize-allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.2.0/24"]
}
