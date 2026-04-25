.PHONY: help init plan apply destroy ssh tunnel logs status output fmt validate clean claude codex start stop push-makefile push-update-script push-all update-tools update-claude update-codex revert-claude revert-codex update-log

# Read from tfvars for gcloud commands
ZONE    := $(shell grep '^zone ' terraform.tfvars 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
PROJECT := $(shell grep '^project_id ' terraform.tfvars 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
ZONE    := $(or $(ZONE),southamerica-east1-a)
PROJECT := $(or $(PROJECT),legalize-server)
VM_NAME := legalize-server
export CLOUDSDK_PYTHON_SITEPACKAGES := 1

_SSH_CMD = gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap
_UPDATE_SCRIPT = /home/dev/vm-files/update-tools.sh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Terraform lifecycle ---

init: ## Initialize Terraform (download providers)
	terraform init

plan: ## Preview infrastructure changes
	terraform plan

apply: ## Create or update the infrastructure
	terraform apply

destroy: ## Tear down all infrastructure
	terraform destroy

output: ## Show Terraform outputs
	terraform output

# --- Terraform utilities ---

fmt: ## Format .tf files
	terraform fmt -recursive

validate: ## Validate Terraform configuration
	terraform validate

# --- Remote VM access ---

ssh: ## SSH into the VM (as dev user) via IAP
	-gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		-- -tt "exec sudo -iu dev bash"

PORT :=
REMOTE :=
tunnel: ## Forward a VM port to localhost (PORT=8080 [REMOTE=host:port])
	@[ -n "$(PORT)" ] || { echo "Usage: make tunnel PORT=8080 [REMOTE=host:port]"; exit 1; }
	gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		-- -NL $(PORT):$(or $(REMOTE),localhost:$(PORT))

logs: ## Tail the startup script log on the VM
	gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		--command='sudo tail -f /var/log/legalize-startup.log'

status: ## Check VM status
	@echo "--- VM instance ---"
	gcloud compute instances describe $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) \
		--format='table(name, status, machineType.basename())' 2>/dev/null || echo "  VM not found (run 'make apply' first)"

# --- AI coding tools ---

N :=
_CLAUDE_SESSION = claude$(if $(N),-$(N))
_CODEX_SESSION  = codex$(if $(N),-$(N))

claude: ## Launch Claude Code (N=1 for extra session)
	-gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		-- -tt "exec sudo -iu dev bash -lc 'tmux new-session -As \"$(_CLAUDE_SESSION)\" -c /home/dev/legalize-pipeline \"claude --dangerously-skip-permissions\"'"

codex: ## Launch Codex CLI (N=1 for extra session)
	-gcloud compute ssh $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap \
		-- -tt "exec sudo -iu dev bash -lc 'tmux new-session -As \"$(_CODEX_SESSION)\" -c /home/dev/legalize-pipeline \"codex --dangerously-bypass-approvals-and-sandbox\"'"

# --- Remote management ---

push-makefile: ## Push templates/vm-Makefile to the VM
	gcloud compute scp templates/vm-Makefile $(VM_NAME):/tmp/vm-Makefile --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap
	$(_SSH_CMD) --command='sudo mv /tmp/vm-Makefile /home/dev/Makefile && sudo chown dev:dev /home/dev/Makefile'

push-update-script: ## Push update-tools.sh to the VM
	gcloud compute scp vm-files/update-tools.sh $(VM_NAME):/tmp/update-tools.sh --zone=$(ZONE) --project=$(PROJECT) --tunnel-through-iap
	$(_SSH_CMD) --command='sudo mkdir -p /home/dev/vm-files && sudo mv /tmp/update-tools.sh /home/dev/vm-files/update-tools.sh && sudo chmod +x /home/dev/vm-files/update-tools.sh && sudo chown -R dev:dev /home/dev/vm-files'

push-all: push-makefile push-update-script ## Push Makefile + update script

# --- Lifecycle helpers ---

start: ## Start a stopped VM
	gcloud compute instances start $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT)

stop: ## Stop the VM (saves cost)
	gcloud compute instances stop $(VM_NAME) --zone=$(ZONE) --project=$(PROJECT)

# --- Tool updates ---

VER :=

update-tools: ## Update both Claude Code and Codex CLI on the VM
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) all'

update-claude: ## Update only Claude Code on the VM
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) claude'

update-codex: ## Update only Codex CLI on the VM
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) codex'

revert-claude: ## Revert Claude to a specific version (VER=x.y.z)
	@[ -n "$(VER)" ] || { echo "Usage: make revert-claude VER=x.y.z"; exit 1; }
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) claude --revert $(VER)'

revert-codex: ## Revert Codex to a specific version (VER=x.y.z)
	@[ -n "$(VER)" ] || { echo "Usage: make revert-codex VER=x.y.z"; exit 1; }
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) codex --revert $(VER)'

update-log: ## Show update history from the VM
	$(_SSH_CMD) --command='sudo $(_UPDATE_SCRIPT) all --log'

# --- Cleanup ---

clean: ## Remove local Terraform state and cache
	rm -rf .terraform .terraform.lock.hcl
	@echo "Run 'make init' to re-initialize"
