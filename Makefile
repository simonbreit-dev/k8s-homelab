.DEFAULT_GOAL := help
SHELL := /bin/sh

VENV := ansible/.venv
PYTHON := $(VENV)/bin/python

.PHONY: help setup plan deploy configure check destroy _controller
# Infrastructure operations must stay sequential, including with make -j.
.NOTPARALLEL:

help:
	@printf '%s\n' \
	  'Usage: make <command>' \
	  '' \
	  '  setup      Install the Python controller and Ansible collections' \
	  '  plan       Initialize Terraform and preview infrastructure changes' \
	  '  deploy     Apply infrastructure, generate inventory and configure Kubernetes' \
	  '  configure  Run Ansible with the existing inventory' \
	  '  check      Run formatting, validation, syntax and regression checks' \
	  '  destroy    Destroy infrastructure with the normal Terraform confirmation' \
	  '  help       Show this help'

setup:
	python3 -m venv "$(VENV)"
	"$(PYTHON)" -m pip install -r ansible/requirements.txt
	"$(VENV)/bin/ansible-galaxy" collection install -r ansible/requirements.yml

plan:
	terraform -chdir=terraform init
	terraform -chdir=terraform plan

deploy: _controller
	terraform -chdir=terraform init
	PATH="$(abspath $(VENV))/bin:$$PATH" terraform -chdir=terraform apply
	cd ansible && .venv/bin/ansible-playbook playbooks/site.yml

configure: _controller
	cd ansible && .venv/bin/ansible-playbook playbooks/site.yml

check: _controller
	terraform -chdir=terraform init -backend=false -input=false -lockfile=readonly
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform validate
	PATH="$(CURDIR)/tests/bin:$$PATH" terraform -chdir=terraform test
	cd ansible && .venv/bin/ansible-playbook -i ../tests/inventory.yml --syntax-check playbooks/site.yml
	"$(PYTHON)" -m unittest discover -s tests -v

destroy: _controller
	terraform -chdir=terraform init
	PATH="$(abspath $(VENV))/bin:$$PATH" terraform -chdir=terraform destroy

_controller:
	@test -x "$(PYTHON)" && test -x "$(VENV)/bin/ansible-playbook" || { \
	  printf '%s\n' 'Controller environment missing. Run make setup first.' >&2; \
	  exit 1; \
	}
