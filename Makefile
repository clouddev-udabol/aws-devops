# ============================================================
# iaapp — UDABOL — Makefile
# Comandos uniformes para validación, plan y deploy de stacks.
#
# Uso:
#   make help                              Muestra esta ayuda
#   make lint                              cfn-lint + checkov local
#   make plan ENV=dev STACK=vpc            ChangeSet preview (no aplica)
#   make deploy ENV=dev STACK=vpc          Despliegue real (asume SSO activo)
#   make diff ENV=dev STACK=vpc            Diff entre estado AWS y local
#   make outputs ENV=dev STACK=vpc         Imprime outputs del stack desplegado
#   make delete ENV=dev STACK=vpc          Elimina el stack (con confirmación)
#
# Variables override-ables:
#   ENV       dev | qa | prod                       (default: dev)
#   STACK     vpc | budgets | ...                   (requerido en plan/deploy)
#   REGION    AWS region                            (default: us-east-1)
#   PROJECT   Nombre del proyecto                   (default: iaapp)
# ============================================================

.PHONY: help lint plan deploy diff outputs delete bootstrap clean
.DEFAULT_GOAL := help

# -- Variables ---------------------------------------------------
PROJECT  ?= iaapp
COMPANY  ?= udabol
REGION   ?= us-east-1
ENV      ?= dev
STACK    ?=
SHA      := $(shell git rev-parse --short HEAD 2>/dev/null || echo "manual")
DATE     := $(shell date -u +%Y-%m-%d)

STACK_NAME := $(PROJECT)-$(STACK)-$(ENV)

# -- Help --------------------------------------------------------
help:
	@echo ""
	@echo "  iaapp — UDABOL — Makefile"
	@echo "  ========================="
	@echo ""
	@echo "  Comandos disponibles:"
	@echo ""
	@echo "    make lint                          Validación local (cfn-lint + checkov)"
	@echo "    make plan ENV=<env> STACK=<stack>  ChangeSet preview"
	@echo "    make deploy ENV=<env> STACK=<stack>  Despliegue real"
	@echo "    make diff ENV=<env> STACK=<stack>  Diff AWS vs local"
	@echo "    make outputs ENV=<env> STACK=<stack>  Imprimir outputs"
	@echo "    make delete ENV=<env> STACK=<stack>  Eliminar stack"
	@echo "    make clean                         Limpiar packaged templates"
	@echo ""
	@echo "  Ambientes válidos: dev | qa | prod"
	@echo "  Stacks disponibles: vpc | budgets | (agregar nuevos en stacks/)"
	@echo ""
	@echo "  Ejemplo:"
	@echo "    make plan ENV=dev STACK=vpc"
	@echo "    make deploy ENV=qa STACK=vpc"
	@echo ""

# -- Lint --------------------------------------------------------
lint:
	@echo "[CI-LNT] cfn-lint..."
	@cfn-lint cloudformation/**/*.yaml budgets/*.yaml .github/oidc/*.yaml || (echo "FAIL cfn-lint"; exit 1)
	@echo "[CI-SEC] checkov..."
	@checkov --directory cloudformation --framework cloudformation --quiet --compact || (echo "FAIL checkov"; exit 1)
	@echo "OK — lint + security scan limpios"

# -- Plan (ChangeSet preview) -----------------------------------
plan:
	@test -n "$(STACK)" || (echo "ERROR: STACK no definido. Uso: make plan ENV=dev STACK=vpc"; exit 1)
	@./scripts/diff-changeset.sh $(ENV) $(STACK)

# -- Deploy ------------------------------------------------------
deploy:
	@test -n "$(STACK)" || (echo "ERROR: STACK no definido. Uso: make deploy ENV=dev STACK=vpc"; exit 1)
	@./scripts/deploy.sh $(ENV) $(STACK)

# -- Diff (estado actual vs local) ------------------------------
diff:
	@test -n "$(STACK)" || (echo "ERROR: STACK no definido"; exit 1)
	@aws cloudformation get-template \
		--stack-name $(STACK_NAME) \
		--region $(REGION) \
		--query TemplateBody \
		--output yaml > /tmp/$(STACK_NAME)-deployed.yaml
	@diff -u /tmp/$(STACK_NAME)-deployed.yaml cloudformation/modules/$(STACK)/$(STACK).yaml || true

# -- Outputs -----------------------------------------------------
outputs:
	@test -n "$(STACK)" || (echo "ERROR: STACK no definido"; exit 1)
	@aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--region $(REGION) \
		--query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
		--output table

# -- Delete (con confirmación) -----------------------------------
delete:
	@test -n "$(STACK)" || (echo "ERROR: STACK no definido"; exit 1)
	@echo ""
	@echo "  ⚠️  Vas a ELIMINAR el stack: $(STACK_NAME)"
	@echo "  Cuenta: $$(aws sts get-caller-identity --query Account --output text)"
	@echo "  Región: $(REGION)"
	@echo ""
	@read -p "Escribe 'eliminar' para confirmar: " confirm; \
	if [ "$$confirm" = "eliminar" ]; then \
		aws cloudformation delete-stack --stack-name $(STACK_NAME) --region $(REGION); \
		echo "Stack en proceso de eliminación..."; \
	else \
		echo "Cancelado."; \
	fi

# -- Bootstrap inicial de cuenta --------------------------------
bootstrap:
	@./scripts/bootstrap-account.sh $(ENV)

# -- Limpieza local ---------------------------------------------
clean:
	@rm -f packaged-*.yaml *.pkg.yaml /tmp/$(PROJECT)-*-deployed.yaml
	@echo "OK — limpio"
