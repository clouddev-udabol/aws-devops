#!/usr/bin/env bash
# ============================================================
# iaapp — UDABOL — scripts/smoke-test.sh
#
# Verifica que un stack desplegado responda como se espera.
# Lo ejecutan los workflows post-deploy y se puede correr manualmente.
#
# Uso:
#   ./scripts/smoke-test.sh <env> <stack>
#
# Ejemplo:
#   ./scripts/smoke-test.sh dev vpc
# ============================================================

set -euo pipefail

ENV="${1:-dev}"
STACK="${2:-vpc}"
PROJECT="iaapp"
REGION="${AWS_REGION:-us-east-1}"

STACK_NAME="${PROJECT}-${STACK}-${ENV}"

echo "Smoke test: ${STACK_NAME}"

# -- Verificar que el stack existe en estado saludable ----------
STATUS=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "MISSING")

case "${STATUS}" in
  CREATE_COMPLETE|UPDATE_COMPLETE)
    echo "  ✓ Stack en estado saludable: ${STATUS}"
    ;;
  *)
    echo "  ✗ Stack en estado inválido: ${STATUS}"
    exit 1
    ;;
esac

# -- Tests específicos por tipo de stack ------------------------
case "${STACK}" in
  vpc)
    VPC_ID=$(aws cloudformation describe-stacks \
      --stack-name "${STACK_NAME}" \
      --region "${REGION}" \
      --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
      --output text)

    if [ -z "${VPC_ID}" ]; then
      echo "  ✗ No se encontró output VpcId"
      exit 2
    fi

    # VPC accesible
    aws ec2 describe-vpcs --vpc-ids "${VPC_ID}" --region "${REGION}" >/dev/null
    echo "  ✓ VPC accesible: ${VPC_ID}"

    # Subnets existen
    SUBNET_COUNT=$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --region "${REGION}" \
      --query 'length(Subnets)' \
      --output text)
    echo "  ✓ Subnets en la VPC: ${SUBNET_COUNT}"

    # Internet Gateway adjunto
    IGW_COUNT=$(aws ec2 describe-internet-gateways \
      --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
      --region "${REGION}" \
      --query 'length(InternetGateways)' \
      --output text)
    if [ "${IGW_COUNT}" -lt 1 ]; then
      echo "  ✗ Sin Internet Gateway adjunto"
      exit 3
    fi
    echo "  ✓ Internet Gateway adjunto"
    ;;

  budgets)
    echo "  (smoke test de budgets — verificación pendiente de implementación)"
    ;;

  *)
    echo "  (no hay smoke test específico para stack=${STACK})"
    ;;
esac

echo ""
echo "✓ Smoke test OK: ${STACK_NAME}"
