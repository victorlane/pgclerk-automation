.PHONY: help install lint test syntax catalogue-check tf-fmt tf-validate

help:
	@echo "Targets:"
	@echo "  install            install Ansible + collections + Terraform tooling"
	@echo "  lint               ansible-lint over playbooks/"
	@echo "  syntax             ansible-playbook --syntax-check on every playbook"
	@echo "  test               run molecule scenarios for all roles"
	@echo "  catalogue-check    validate meta/catalogue.yml shape + playbook references"
	@echo "  tf-fmt             terraform fmt -recursive terraform/"
	@echo "  tf-validate        terraform validate every module"

install:
	pip install -r requirements.txt jsonschema
	ansible-galaxy collection install -r ansible/collections/requirements.yml

lint:
	ansible-lint ansible/playbooks/

syntax:
	@for f in $$(find ansible/playbooks -name '*.yml'); do \
		echo "==> $$f"; ansible-playbook --syntax-check "$$f" || exit 1; \
	done

test:
	@for d in ansible/roles/*; do \
		[ -d "$$d/molecule" ] && (cd "$$d" && molecule test); \
	done

catalogue-check:
	scripts/validate-catalogue.py

tf-fmt:
	terraform fmt -recursive terraform/

tf-validate:
	@for m in terraform/modules/*; do \
		(cd "$$m" && terraform init -backend=false && terraform validate); \
	done
