#!/usr/bin/env bash
# ============================================================
# iaapp — UDABOL — scripts/deploy.sh
#
# Wrapper sobre `aws cloudformation deploy` que:
#   - Aplica el naming convention del proyecto
#   - Inyecta los tags obligatorios (Project, Company, Owner, etc.)
#   - Lee parámetros de parameters/{env}/{stack}.json
#   - Captura el commit SHA y la fecha en tags
#
# Uso:
#   ./scripts/deploy.sh <env> <stack>
#
# Stacks soportados:
#   vpc | budgets | nat-instance | vpc-endpoints
#   ecs-cluster | ecs-services | ecr | rds
#   whatsapp-gateway | msk | ecs-services-update
# ============================================================

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Uso: $0 <env> <stack>"
  echo "  env:    dev | qa | prod"
  echo "  stack:  vpc | budgets | nat-instance | vpc-endpoints | ecs-cluster | ecs-services | ..."
  exit 1
fi

ENV="$1"
STACK="$2"

PROJECT="iaapp"
COMPANY="udabol"
OWNER="ayrton.irusta@gmail.com"
SOW="SOW-002"
REGION="${AWS_REGION:-us-east-1}"

# -- Mapeo de stacks con naming/template no-estandar -----------
case "${STACK}" in
  nat-instance)
    STACK_NAME="udabol-nat-instance-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/vpc/nat-instance.yaml"
    ;;
  vpc-endpoints)
    STACK_NAME="udabol-vpc-endpoints-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/vpc/endpoints.yaml"
    ;;
  ecs-cluster)
    STACK_NAME="udabol-ecs-cluster-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/ecs/cluster.yaml"
    ;;
  ecs-services)
    STACK_NAME="udabol-ecs-services-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/ecs/services.yaml"
    ;;
  ecr)
    STACK_NAME="udabol-ecr-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/ecr/ecr-repos.yaml"
    ;;
  rds)
    STACK_NAME="udabol-rds-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/rds/rds.yaml"
    ;;
  whatsapp-gateway)
    STACK_NAME="udabol-whatsapp-gateway-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/lambda/whatsapp-gateway.yaml"
    ;;
  msk)
    STACK_NAME="udabol-msk-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/msk/msk-serverless.yaml"
    ;;
  *)
    STACK_NAME="${PROJECT}-${STACK}-${ENV}"
    TEMPLATE_FILE="cloudformation/modules/${STACK}/${STACK}.yaml"
    if [ ! -f "${TEMPLATE_FILE}" ] && [ "${STACK}" = "budgets" ]; then
      TEMPLATE_FILE="budgets/budget-setup.yaml"
    fi
    ;;
esac

PARAMS_FILE="parameters/${ENV}/${STACK}.json"

if [ ! -f "${TEMPLATE_FILE}" ]; then
  echo "ERROR: template no encontrado: ${TEMPLATE_FILE}"
  exit 2
fi

if [ ! -f "${PARAMS_FILE}" ]; then
  echo "ERROR: parameters no encontrado: ${PARAMS_FILE}"
  exit 3
fi

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "manual")
DATE=$(date -u +%Y-%m-%d)
TICKET="${TICKET:-${GITHUB_RUN_ID:-manual}}"
PIPELINE="${GITHUB_ACTIONS:+github-actions}"
PIPELINE="${PIPELINE:-cli-local}"

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

PARAMS=$(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "${PARAMS_FILE}" | tr '\n' ' ')

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
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

echo ""
echo "Deploy completado: ${STACK_NAME}"
echo ""

echo "Outputs del stack:"
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table 2>/dev/null || echo "  (sin outputs)"
