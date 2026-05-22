#!/usr/bin/env bash
# ============================================================
# iaapp — UDABOL — scripts/deploy.sh
#
# Wrapper sobre `aws cloudformation deploy` que:
#   - Aplica el naming convention iaapp-{stack}-{env}
#   - Inyecta los tags obligatorios (Project, Company, Owner, etc.)
#   - Lee parámetros de parameters/{env}/{stack}.json
#   - Captura el commit SHA y la fecha en tags
#
# Uso:
#   ./scripts/deploy.sh <env> <stack>
#
# Ejemplo:
#   ./scripts/deploy.sh dev vpc
#   ./scripts/deploy.sh qa budgets
# ============================================================

set -euo pipefail

# -- Validación de argumentos -----------------------------------
if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <env> <stack>"
  echo "  env:    dev | qa | prod"
  echo "  stack:  vpc | budgets | ..."
  exit 1
fi

ENV="$1"
STACK="$2"

# -- Constantes del proyecto ------------------------------------
PROJECT="iaapp"
COMPANY="udabol"
OWNER="ayrton.irusta@gmail.com"
SOW="SOW-001"
REGION="${AWS_REGION:-us-east-1}"

STACK_NAME="${PROJECT}-${STACK}-${ENV}"
TEMPLATE_FILE="cloudformation/modules/${STACK}/${STACK}.yaml"
PARAMS_FILE="parameters/${ENV}/${STACK}.json"

# Templates en otras ubicaciones (compatibilidad con estructura existente)
if [ ! -f "${TEMPLATE_FILE}" ]; then
  if [ "${STACK}" = "budgets" ] && [ -f "budgets/budget-setup.yaml" ]; then
    TEMPLATE_FILE="budgets/budget-setup.yaml"
  fi
fi

# -- Verificación de archivos -----------------------------------
if [ ! -f "${TEMPLATE_FILE}" ]; then
  echo "ERROR: template no encontrado: ${TEMPLATE_FILE}"
  exit 2
fi

if [ ! -f "${PARAMS_FILE}" ]; then
  echo "ERROR: parameters no encontrado: ${PARAMS_FILE}"
  exit 3
fi

# -- Capturar metadatos del despliegue --------------------------
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "manual")
DATE=$(date -u +%Y-%m-%d)
TICKET="${TICKET:-${GITHUB_RUN_ID:-manual}}"
PIPELINE="${GITHUB_ACTIONS:+github-actions}"
PIPELINE="${PIPELINE:-cli-local}"

# -- Banner -----------------------------------------------------
echo "=================================================="
echo "  iaapp — Deploy"
echo "=================================================="
echo "  Stack:        ${STACK_NAME}"
echo "  Template:     ${TEMPLATE_FILE}"
echo "  Parameters:   ${PARAMS_FILE}"
echo "  Region:       ${REGION}"
echo "  Account:      $(aws sts get-caller-identity --query Account --output text)"
echo "  Commit:       ${SHA}"
echo "  Date:         ${DATE}"
echo "  Pipeline:     ${PIPELINE}"
echo "=================================================="

# -- Convertir parameters JSON al formato --parameter-overrides
PARAMS=$(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "${PARAMS_FILE}" | tr '\n' ' ')

# -- Deploy -----------------------------------------------------
# shellcheck disable=SC2086
aws cloudformation deploy \
  --template-file "${TEMPLATE_FILE}" \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides ${PARAMS} \
  --tags \
    "Project=${PROJECT}" \
    "Company=${COMPANY}" \
    "Application=${STACK}" \
    "Environment=${ENV}" \
    "Owner=${OWNER}" \
    "ManagedBy=cloudformation" \
    "SOW=${SOW}" \
    "Pipeline=${PIPELINE}" \
    "CommitHash=${SHA}" \
    "DeployDate=${DATE}" \
    "TicketId=${TICKET}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo ""
echo "✓ Deploy completado: ${STACK_NAME}"
echo ""

# -- Imprimir outputs -------------------------------------------
echo "Outputs del stack:"
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table 2>/dev/null || echo "  (sin outputs)"
