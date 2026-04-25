.PHONY: help init plan apply destroy ssh tunnel logs status output fmt validate clean claude codex start stop push-makefile push-update-script push-all update-tools update-claude update-codex revert-claude revert-codex update-log

# ── Config (read from terraform.tfvars / outputs) ────────────────────────

ZONE     := $(shell grep '^zone ' terraform.tfvars 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
PROJECT  := $(shell grep '^project_id ' terraform.tfvars 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
ZONE     := $(or $(ZONE),southamerica-east1-a)
PROJECT  := $(or $(PROJECT),legalize-server)
VM_NAME  := legalize-server
SSH_USER := dev
VM_IP    := $(or $(VM_IP),$(shell terraform output -raw public_ip 2>/dev/null))
export CLOUDSDK_PYTHON_SITEPACKAGES := 1

# ── Transport: auto-pick gcloud IAP vs plain ssh ─────────────────────────
# Override with `make ... TRANSPORT=ssh` or `TRANSPORT=gcloud`.
# gcloud mode = admin (manages infra). ssh mode = anyone with an authorized key.

TRANSPORT ?= $(if $(shell command -v gcloud 2>/dev/null),gcloud,ssh)

ifeq ($(TRANSPORT),gcloud)
  SSH_RUN  = gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap --command
  SSH_INT  = gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap --
  SCP_TO   = gcloud compute scp --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap
  SCP_DEST = $(VM_NAME)
  AS_DEV   = sudo -iu dev
else
  ifeq ($(VM_IP),)
    $(warning VM_IP unset; run `terraform init && terraform refresh` or pass VM_IP=<ip>)
  endif
  SSH_RUN  = ssh $(SSH_USER)@$(VM_IP)
  SSH_INT  = ssh -t $(SSH_USER)@$(VM_IP)
  SCP_TO   = scp
  SCP_DEST = $(SSH_USER)@$(VM_IP)
  AS_DEV   =
endif

_UPDATE_SCRIPT = /home/dev/vm-files/update-tools.sh

help: ## Show this help
	@echo "Transport: $(TRANSPORT)$(if $(filter ssh,$(TRANSPORT)), (VM_IP=$(VM_IP)),)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Terraform lifecycle (gcloud mode only — admin) ---

init: ## Initialize Terraform (download providers, configure backend)
	terraform init

plan: ## Preview infrastructure changes
	terraform plan

apply: ## Create or update the infrastructure
	terraform apply

destroy: ## Tear down all infrastructure
	terraform destroy

output: ## Show Terraform outputs
	terraform output

fmt: ## Format .tf files
	terraform fmt -recursive

validate: ## Validate Terraform configuration
	terraform validate

# --- Remote VM access ---

ssh: ## SSH into the VM as the dev user
	-$(SSH_INT) "$(AS_DEV) bash"

PORT :=
REMOTE :=
tunnel: ## Forward a VM port to localhost (PORT=8080 [REMOTE=host:port])
	@[ -n "$(PORT)" ] || { echo "Usage: make tunnel PORT=8080 [REMOTE=host:port]"; exit 1; }
ifeq ($(TRANSPORT),gcloud)
	gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		-- -NL $(PORT):$(or $(REMOTE),localhost:$(PORT))
else
	ssh -NL $(PORT):$(or $(REMOTE),localhost:$(PORT)) $(SSH_USER)@$(VM_IP)
endif

logs: ## Tail the startup script log on the VM
	$(SSH_RUN) 'sudo tail -f /var/log/legalize-startup.log'

status: ## Check VM status (gcloud only)
	@gcloud compute instances describe $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) \
		--format='table(name, status, machineType.basename())' 2>/dev/null || echo "  VM not found or gcloud unavailable"

# --- AI coding tools ---

N :=
_CLAUDE_SESSION = claude$(if $(N),-$(N))
_CODEX_SESSION  = codex$(if $(N),-$(N))
_LEGALIZE_DIR   = /home/dev/legalize-pipeline

claude: ## Launch Claude Code (N=1 for extra session)
ifeq ($(TRANSPORT),gcloud)
	-$(SSH_INT) -tt "exec sudo -iu dev bash -lc 'tmux new-session -As \"$(_CLAUDE_SESSION)\" -c $(_LEGALIZE_DIR) \"claude --dangerously-skip-permissions\"'"
else
	-$(SSH_INT) "tmux new-session -As '$(_CLAUDE_SESSION)' -c $(_LEGALIZE_DIR) 'claude --dangerously-skip-permissions'"
endif

codex: ## Launch Codex CLI (N=1 for extra session)
ifeq ($(TRANSPORT),gcloud)
	-$(SSH_INT) -tt "exec sudo -iu dev bash -lc 'tmux new-session -As \"$(_CODEX_SESSION)\" -c $(_LEGALIZE_DIR) \"codex --dangerously-bypass-approvals-and-sandbox\"'"
else
	-$(SSH_INT) "tmux new-session -As '$(_CODEX_SESSION)' -c $(_LEGALIZE_DIR) 'codex --dangerously-bypass-approvals-and-sandbox'"
endif

# --- Remote management (push files to VM) ---

push-makefile: ## Push templates/vm-Makefile to the VM
	$(SCP_TO) templates/vm-Makefile $(SCP_DEST):/tmp/vm-Makefile
	$(SSH_RUN) 'sudo mv /tmp/vm-Makefile /home/dev/Makefile && sudo chown dev:dev /home/dev/Makefile'

push-update-script: ## Push update-tools.sh to the VM
	$(SCP_TO) vm-files/update-tools.sh $(SCP_DEST):/tmp/update-tools.sh
	$(SSH_RUN) 'sudo mkdir -p /home/dev/vm-files && sudo mv /tmp/update-tools.sh /home/dev/vm-files/update-tools.sh && sudo chmod +x /home/dev/vm-files/update-tools.sh && sudo chown -R dev:dev /home/dev/vm-files'

push-all: push-makefile push-update-script ## Push Makefile + update script

# --- Lifecycle helpers (gcloud only) ---

start: ## Start a stopped VM
	gcloud compute instances start $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT)

stop: ## Stop the VM (saves cost)
	gcloud compute instances stop $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT)

# --- Tool updates ---

VER :=

update-tools: ## Update both Claude Code and Codex CLI on the VM
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) all'

update-claude: ## Update only Claude Code on the VM
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) claude'

update-codex: ## Update only Codex CLI on the VM
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) codex'

revert-claude: ## Revert Claude to a specific version (VER=x.y.z)
	@[ -n "$(VER)" ] || { echo "Usage: make revert-claude VER=x.y.z"; exit 1; }
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) claude --revert $(VER)'

revert-codex: ## Revert Codex to a specific version (VER=x.y.z)
	@[ -n "$(VER)" ] || { echo "Usage: make revert-codex VER=x.y.z"; exit 1; }
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) codex --revert $(VER)'

update-log: ## Show update history from the VM
	$(SSH_RUN) 'sudo $(_UPDATE_SCRIPT) all --log'

# --- Cleanup ---

clean: ## Remove local Terraform state and cache
	rm -rf .terraform .terraform.lock.hcl
	@echo "Run 'make init' to re-initialize"
