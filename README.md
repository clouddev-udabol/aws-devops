# iaapp — Infraestructura AWS (UDABOL)

> **Proyecto:** `iaapp`
> **Institución:** Universidad de Aquino Bolivia (UDABOL)
> **SOW:** SOW-001
> **Owner:** ayrton.irusta@gmail.com
> **Ambientes:** DEV (`245650696072`) | QA (`493735739951`) | PROD (diferido)
> **Región:** `us-east-1`
> **IaC:** CloudFormation puro
> **CI/CD:** GitHub Actions + OIDC (sin credenciales estáticas)

---

## Descripción

Repositorio único de Infrastructure as Code (IaC) para el despliegue y gestión de la plataforma `iaapp` de **UDABOL** en AWS. Implementa redes VPC en 3 capas por ambiente, gobierno de costos con AWS Budgets y autenticación segura mediante **GitHub OIDC** (sin credenciales estáticas).

**Estrategia de entrega:** GitHub Flow simplificado · 3 cuentas AWS · CloudFormation puro · pipelines con SAST/SCA/IaC scanning obligatorio.

> 📘 **Empieza por `docs/GUIA-TRANSFERENCIA.md`** — guía completa de bootstrap, operación diaria y handoff.

## Entregables SOW-001

| ID | Descripción | Estado |
|---|---|---|
| E1 | CloudFormation: 3 VPCs (DEV, QA, PROD) | Pendiente |
| E2 | Interconexión VPCs (no aplica — diseño aislado) | N/A |
| E3 | GitHub OIDC en cuenta DEV | Pendiente |
| E4 | AWS Budgets DEV y QA | Pendiente |
| E5 | Documento diseño VPN S2S | Pendiente |
| E6 | Documentación técnica + diagramas | Pendiente |

## Estructura del repositorio

```
iaapp/
├── .github/
│   ├── workflows/            # CI/CD: pr-validate, deploy-nonprod, deploy-prod, drift-detection
│   └── oidc/                 # Plantilla IAM Role + OIDC Provider (deploy 1x por cuenta AWS)
├── cloudformation/
│   ├── modules/              # Bloques reutilizables (vpc/, futuro: ecs/, rds/, kms/)
│   └── stacks/               # Stacks específicos por ambiente (legacy — migrando a parameters/)
├── parameters/               # ⭐ Parámetros por ambiente — única diferencia entre envs
│   ├── dev/
│   ├── qa/
│   └── prod/
├── policies/                 # Policy-as-code: cfn-guard rules + checkov baseline
├── scripts/                  # Wrappers: deploy.sh · diff-changeset.sh · bootstrap-account.sh
├── budgets/                  # AWS Budgets — gobierno de costos por ambiente
├── docs/
│   ├── GUIA-TRANSFERENCIA.md  ⭐ Documento principal de handoff
│   ├── context.md             Contexto del proyecto
│   ├── vpc-design.md          Diseño VPC 3 capas
│   ├── vpn-s2s-design.md      Diseño VPN Site-to-Site
│   ├── runbook-rollback.md    Procedimiento ante deploy fallido en prod
│   ├── onboarding.md          Setup local para nuevo desarrollador
│   └── html/                  Portal de documentación HTML
├── SOW/                      Trabajo asociado al Statement of Work 001
├── CODEOWNERS                Aprobaciones requeridas por carpeta
├── Makefile                  Comandos uniformes — `make help`
├── .pre-commit-config.yaml   Hooks: cfn-lint, checkov, formato
├── .cfnlintrc.yaml           Config cfn-lint
└── .gitignore
```

## Quick Start

```bash
# 1. Setup local (una vez)
pip install pre-commit cfn-lint checkov
pre-commit install

# 2. Antes de un PR
make lint                              # cfn-lint + checkov local

# 3. Ver cambios contra dev sin desplegar
make plan ENV=dev STACK=vpc

# 4. Desplegar localmente (requiere AWS CLI con SSO activo)
make deploy ENV=dev STACK=vpc

# 5. Ver todos los comandos
make help
```

## Arquitectura de red

Cada VPC se despliega en **3 capas** × **2 AZ**:

| Capa | Tipo | Propósito |
|---|---|---|
| Exposición | Pública | Internet Gateway, ALB, Bastion |
| Servicios | Privada | EC2, ECS, Lambda, EKS |
| Datos | Privada aislada | RDS, ElastiCache, endpoints |

## Esquema CIDR

| Ambiente | VPC | Exposición | Servicios | Datos |
|---|---|---|---|---|
| DEV | `10.10.0.0/16` | `10.10.1-2.0/24` | `10.10.11-12.0/24` | `10.10.21-22.0/24` |
| QA | `10.20.0.0/16` | `10.20.1-2.0/24` | `10.20.11-12.0/24` | `10.20.21-22.0/24` |
| PROD | `10.30.0.0/16` | `10.30.1-2.0/24` | `10.30.11-12.0/24` | `10.30.21-22.0/24` |

## Acceso

- **SSO Portal:** [https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/](https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/)
- **Usuario:** `cloudadmin`

## Pipelines

| Workflow | Trigger | Despliega a | Aprobación |
|---|---|---|---|
| `pr-validate.yml` | PR a `main` | — (lint + ChangeSet preview) | — |
| `deploy-nonprod.yml` | push a `main` (auto) · `workflow_dispatch` | dev (auto) · qa (manual) | 1 reviewer |
| `deploy-prod.yml` | `workflow_dispatch` | prod | 2 reviewers + 10 min wait |
| `drift-detection.yml` | schedule diario | — (genera issue si hay drift) | — |

## Convención de naming

Todo stack se nombra: `iaapp-{stack}-{env}` — ejemplos:
- `iaapp-vpc-dev`
- `iaapp-vpc-qa`
- `iaapp-budgets-dev`

## Tags obligatorios (todo recurso)

```yaml
Project:            iaapp
Company:            udabol
Environment:        dev | qa | prod
Owner:              ayrton.irusta@gmail.com
ManagedBy:          cloudformation
SOW:                SOW-001
CommitHash:         <git-sha-7-chars>
DeployDate:         <YYYY-MM-DD>
```

## Documentación

| Documento | Propósito |
|---|---|
| [`docs/GUIA-TRANSFERENCIA.md`](docs/GUIA-TRANSFERENCIA.md) | ⭐ **Empezar aquí.** Bootstrap + operación + handoff |
| [`docs/context.md`](docs/context.md) | Contexto del proyecto |
| [`docs/vpc-design.md`](docs/vpc-design.md) | Diseño de arquitectura VPC 3 capas |
| [`docs/vpn-s2s-design.md`](docs/vpn-s2s-design.md) | Diseño VPN Site-to-Site |
| [`docs/runbook-rollback.md`](docs/runbook-rollback.md) | Procedimiento ante deploy fallido en prod |
| [`docs/onboarding.md`](docs/onboarding.md) | Setup local del desarrollador |
| [`docs/html/index.html`](docs/html/index.html) | Portal HTML de documentación |

## Acceso AWS

- **SSO Portal:** https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/
- **Usuario:** `cloudadmin`

---

*Proyecto `iaapp` · UDABOL · SOW-001 · 2026*
*Owner: ayrton.irusta@gmail.com*
