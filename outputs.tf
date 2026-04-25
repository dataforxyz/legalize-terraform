# --------------------------------------------------------------------------
# Legalize Server — Outputs
# --------------------------------------------------------------------------

output "ssh_command" {
  description = "SSH into the VM via IAP tunnel"
  value       = "gcloud compute ssh legalize-server --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap"
}

output "public_ip" {
  description = "Public IP of the VM (for direct SSH)"
  value       = google_compute_instance.server.network_interface[0].access_config[0].nat_ip
}

output "ssh_direct" {
  description = "Direct SSH command (uses authorized key)"
  value       = "ssh ${var.dev_username}@${coalesce(google_compute_instance.server.network_interface[0].access_config[0].nat_ip, "pending")}"
}

output "startup_log_command" {
  description = "Tail the startup script log"
  value       = "gcloud compute ssh legalize-server --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap -- sudo tail -f /var/log/legalize-startup.log"
}

output "dev_info" {
  description = "Development environment paths and useful info"
  value       = <<-EOT
    After SSH:    sudo su - ${var.dev_username}   (switch to dev user)
    Pipeline:     ~/legalize-pipeline
    Docker:       docker ps
    Claude:       make claude   (Claude Code in tmux)
    Codex:        make codex    (Codex CLI in tmux)
  EOT
}
