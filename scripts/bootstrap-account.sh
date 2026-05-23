#!/usr/bin/env bash
# ============================================================
# iaapp — UDABOL — scripts/bootstrap-account.sh
#
# Configura una cuenta AWS NUEVA para integrarla al pipeline.
# Despliega el OIDC Provider + IAM Role para GitHub Actions.
#
# Pre-requisitos:
#   1. SSO activo apuntando a la cuenta destino
#   2. Permisos para crear IAM Role + OIDC Provider en esa cuenta
#
# Uso:
#   ./scripts/bootstrap-account.sh <env>
#
# Ejemplo:
#   ./scripts/bootstrap-account.sh dev
#   ./scripts/bootstrap-account.sh qa
#   ./scripts/bootstrap-account.sh prod
# ============================================================

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 <env>"
  exit 1
fi

ENV="$1"
REGION="${AWS_REGION:-us-east-1}"
GITHUB_ORG="${GITHUB_ORG:-airusta}"
GITHUB_REPO="${GITHUB_REPO:-iaapp}"

ROLE_NAME="GithubActionsDeployRole-iaapp-${ENV}"
STACK_NAME="github-oidc-iaapp-${ENV}"

# -- Banner -----------------------------------------------------
echo "=================================================="
echo "  iaapp — Bootstrap cuenta AWS para OIDC"
echo "=================================================="
echo "  Environment:   ${ENV}"
echo "  Region:        ${REGION}"
echo "  Account:       $(aws sts get-caller-identity --query Account --output text)"
echo "  GitHub Repo:   ${GITHUB_ORG}/${GITHUB_REPO}"
echo "  Role:          ${ROLE_NAME}"
echo "  Stack:         ${STACK_NAME}"
echo "=================================================="
echo ""

read -p "¿Continuar? (yes/no) " confirm
if [ "${confirm}" != "yes" ]; then
  echo "Cancelado."
  exit 0
fi

# -- Despliegue del stack OIDC ----------------------------------
aws cloudformation deploy \
  --template-file .github/oidc/iam-role.yaml \
  --stack-name "${STACK_NAME}" \
  --parameter-overrides \
    "GitHubOrg=${GITHUB_ORG}" \
    "GitHubRepo=${GITHUB_REPO}" \
    "GitHubBranch=*" \
    "RoleName=${ROLE_NAME}" \
  --tags \
    "Project=iaapp" \
    "Company=udabol" \
    "Environment=${ENV}" \
    "Owner=ayrton.irusta@gmail.com" \
    "ManagedBy=cloudformation" \
    "SOW=SOW-001" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "${REGION}" \
  --no-fail-on-empty-changeset

# -- Imprimir el ARN del rol creado -----------------------------
ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" \
  --output text 2>/dev/null || echo "")

if [ -z "${ROLE_ARN}" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
fi

echo ""
echo "✓ Bootstrap completado para ambiente '${ENV}'"
echo ""
echo "  IAM Role ARN:  ${ROLE_ARN}"
echo ""
echo "  Próximo paso:"
echo "    Verifica que los workflows en .github/workflows/*.yml usan este ARN."
echo "    Actualiza si es necesario y haz commit."
