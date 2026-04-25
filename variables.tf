# --------------------------------------------------------------------------
# Legalize Server — Terraform Variables
# --------------------------------------------------------------------------

# ── GCP Project ──────────────────────────────────────────────────────────

variable "project_name" {
  description = "Display name for the GCP project"
  type        = string
  default     = "legalize-server"
}

variable "project_id" {
  description = "Globally unique GCP project ID"
  type        = string
}

variable "org_id" {
  description = "GCP organization ID"
  type        = string
  default     = "564163886903"
}

variable "billing_account" {
  description = "GCP billing account ID"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "southamerica-east1"
}

variable "zone" {
  description = "GCP zone for compute resources"
  type        = string
  default     = "southamerica-east1-a"
}

# ── Compute ──────────────────────────────────────────────────────────────

variable "machine_type" {
  description = "GCE machine type. e2-standard-8 = 8 vCPU, 32 GB RAM."
  type        = string
  default     = "e2-standard-8"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 60
}

# ── SSH Access ───────────────────────────────────────────────────────────

variable "ssh_authorized_keys" {
  description = "Public SSH keys (one per line, raw key only — no 'user:' prefix). All keys are added to the dev user. Password auth is disabled."
  type        = list(string)
  default     = []
}

# ── AI Tools ─────────────────────────────────────────────────────────────

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key for Codex CLI"
  type        = string
  default     = ""
  sensitive   = true
}

# ── Git ──────────────────────────────────────────────────────────────────

variable "legalize_repo_url" {
  description = "legalize-pipeline git repo URL"
  type        = string
  default     = "https://github.com/jaredgoldman/legalize-pipeline.git"
}

variable "git_branch" {
  description = "Git branch to clone"
  type        = string
  default     = "feat/mx-scaffold"
}

# ── Dev User ─────────────────────────────────────────────────────────────

variable "dev_username" {
  description = "Linux username for the development user"
  type        = string
  default     = "dev"
}
