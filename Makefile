.PHONY: help init fmt validate validate-% up up-% down down-% hosts hosts-% all

TERRAFORM_DIR := terraform
CLIENTS := airbnb nike mcdonalds

help:
	@echo "Targets:";
	@echo "  make init            - terraform init";
	@echo "  make fmt             - terraform fmt (recursive)";
	@echo "  make up-<client>      - apply + update hosts + validate";
	@echo "  make down-<client>    - destroy + remove hosts entries";
	@echo "  make up              - up for all clients (sequential)";
	@echo "  make validate-<client> - validate endpoints";

init:
	terraform -chdir=$(TERRAFORM_DIR) init

fmt:
	terraform -chdir=$(TERRAFORM_DIR) fmt -recursive

select-%:
	terraform -chdir=$(TERRAFORM_DIR) workspace select $* 2>/dev/null || terraform -chdir=$(TERRAFORM_DIR) workspace new $*

apply-%: select-%
	terraform -chdir=$(TERRAFORM_DIR) apply -auto-approve

destroy-%: select-%
	terraform -chdir=$(TERRAFORM_DIR) destroy -auto-approve

hosts-%:
	./scripts/update-hosts.sh $*

rmhosts-%:
	./scripts/update-hosts.sh $* --remove

validate-%:
	./scripts/validate.sh $*

up-%: apply-% hosts-% validate-%

down-%: destroy-% rmhosts-%

up: $(addprefix up-,$(CLIENTS))

down: $(addprefix down-,$(CLIENTS))

validate: $(addprefix validate-,$(CLIENTS))