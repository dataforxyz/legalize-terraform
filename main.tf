# --------------------------------------------------------------------------
# Legalize Server — Main Configuration
# --------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "legalize-server-26042598-tfstate"
    prefix = "legalize-server"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Aliased provider with quota project set — required for orgpolicy.googleapis.com
# which always charges quota to the calling project (no global quota).
provider "google" {
  alias                 = "billing"
  project               = var.project_id
  region                = var.region
  zone                  = var.zone
  billing_project       = var.project_id
  user_project_override = true
}

# ── GCP Project ──────────────────────────────────────────────────────────

resource "google_project" "legalize" {
  name            = var.project_name
  project_id      = var.project_id
  org_id          = var.org_id
  billing_account = var.billing_account

  deletion_policy = "DELETE"
}

# ── Enable APIs ──────────────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "orgpolicy.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  project            = google_project.legalize.project_id
  service            = each.value
  disable_on_destroy = false

  depends_on = [google_project.legalize]
}

# ── Service Account ──────────────────────────────────────────────────────

resource "google_service_account" "vm" {
  account_id   = "legalize-vm-sa"
  display_name = "Legalize VM Service Account"
  project      = google_project.legalize.project_id

  depends_on = [google_project_service.apis]
}

# ── Org Policy Overrides (project-level) ─────────────────────────────────
# Allow SSH-key-based auth (no OS Login) and external IPs on this project.

resource "google_org_policy_policy" "disable_os_login" {
  provider = google.billing
  name     = "projects/${google_project.legalize.project_id}/policies/compute.requireOsLogin"
  parent   = "projects/${google_project.legalize.project_id}"

  spec {
    inherit_from_parent = false
    rules {
      enforce = "FALSE"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_org_policy_policy" "allow_external_ip" {
  provider = google.billing
  name     = "projects/${google_project.legalize.project_id}/policies/compute.vmExternalIpAccess"
  parent   = "projects/${google_project.legalize.project_id}"

  spec {
    rules {
      allow_all = "TRUE"
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "vm_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = google_project.legalize.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}
