# --------------------------------------------------------------------------
# Legalize Server — Compute (GCE Instance)
# --------------------------------------------------------------------------

resource "google_compute_instance" "server" {
  name         = "legalize-server"
  machine_type = var.machine_type
  zone         = var.zone
  project      = google_project.legalize.project_id

  tags = ["legalize-server"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {
      # Ephemeral public IP — required for direct SSH from anywhere.
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    "vm-makefile"      = file("${path.module}/templates/vm-Makefile")
    "update-tools-sh"  = file("${path.module}/vm-files/update-tools.sh")
    "enable-oslogin"   = "FALSE"
    "block-project-ssh-keys" = "TRUE"
    "ssh-keys"         = join("\n", [for k in var.ssh_authorized_keys : "${var.dev_username}:${k}"])
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    dev_username      = var.dev_username
    legalize_repo_url = var.legalize_repo_url
    git_branch        = var.git_branch
    anthropic_api_key = var.anthropic_api_key
    openai_api_key    = var.openai_api_key
  })

  allow_stopping_for_update = true

  lifecycle {
    # Ignore out-of-band IP rotations (gcloud delete-access-config / add-access-config).
    ignore_changes = [
      metadata_startup_script,
      boot_disk[0].initialize_params[0].size,
      network_interface[0].access_config,
    ]
  }

  depends_on = [
    google_project_iam_member.vm_roles,
    google_org_policy_policy.disable_os_login,
    google_org_policy_policy.allow_external_ip,
  ]
}
