#!/usr/bin/env bash
# ============================================================
# iaapp — UDABOL — scripts/diff-changeset.sh
#
# Crea un ChangeSet de CloudFormation, lo imprime para revisión,
# y lo elimina sin ejecutar. NO modifica AWS.
#
# Uso:
#   ./scripts/diff-changeset.sh <env> <stack>
#
# Ejemplo:
#   ./scripts/diff-changeset.sh dev vpc
# ============================================================

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <env> <stack>"
  exit 1
fi

ENV="$1"
STACK="$2"
PROJECT="iaapp"
REGION="${AWS_REGION:-us-east-1}"

STACK_NAME="${PROJECT}-${STACK}-${ENV}"
TEMPLATE_FILE="cloudformation/modules/${STACK}/${STACK}.yaml"
PARAMS_FILE="parameters/${ENV}/${STACK}.json"
CHANGESET_NAME="diff-$(date +%s)"

if [ ! -f "${TEMPLATE_FILE}" ]; then
  if [ "${STACK}" = "budgets" ] && [ -f "budgets/budget-setup.yaml" ]; then
    TEMPLATE_FILE="budgets/budget-setup.yaml"
  fi
fi

[ -f "${TEMPLATE_FILE}" ] || { echo "ERROR: template no encontrado"; exit 2; }
[ -f "${PARAMS_FILE}" ]   || { echo "ERROR: parameters no encontrado"; exit 3; }

# -- ¿El stack ya existe? ---------------------------------------
if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  CHANGESET_TYPE=UPDATE
  echo "Stack existe — generando ChangeSet UPDATE"
else
  CHANGESET_TYPE=CREATE
  echo "Stack NO existe — generando ChangeSet CREATE (preview de creación)"
fi

# -- Crear ChangeSet --------------------------------------------
echo ""
echo "Creando ChangeSet '${CHANGESET_NAME}' para ${STACK_NAME}..."
aws cloudformation create-change-set \
  --stack-name "${STACK_NAME}" \
  --change-set-name "${CHANGESET_NAME}" \
  --change-set-type "${CHANGESET_TYPE}" \
  --template-body "file://${TEMPLATE_FILE}" \
  --parameters "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  >/dev/null

# -- Esperar a que termine de calcularse ------------------------
echo "Esperando a que el ChangeSet se calcule..."
aws cloudformation wait change-set-create-complete \
  --stack-name "${STACK_NAME}" \
  --change-set-name "${CHANGESET_NAME}" \
  --region "${REGION}" 2>/dev/null || true

# -- Imprimir resultado -----------------------------------------
echo ""
echo "=================================================="
echo "  ChangeSet preview — ${STACK_NAME}"
echo "=================================================="
aws cloudformation describe-change-set \
  --stack-name "${STACK_NAME}" \
  --change-set-name "${CHANGESET_NAME}" \
  --region "${REGION}" \
  --query 'Changes[*].[ResourceChange.Action,ResourceChange.ResourceType,ResourceChange.LogicalResourceId,ResourceChange.Replacement]' \
  --output table

# -- Limpiar el ChangeSet (era solo preview) -------------------
aws cloudformation delete-change-set \
  --stack-name "${STACK_NAME}" \
  --change-set-name "${CHANGESET_NAME}" \
  --region "${REGION}" 2>/dev/null || true

echo ""
echo "✓ ChangeSet revisado y eliminado (no se aplicó nada)"
