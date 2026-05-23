# Guía de Transferencia — iaapp (UDABOL)

> **Proyecto:** `iaapp` · **Empresa:** UDABOL (Universidad de Aquino Bolivia) · **SOW:** SOW-001
> **Owner:** ayrton.irusta@gmail.com
> **Última actualización:** 2026-05-05

---

## Tabla de contenidos

1. [Para qué sirve este documento](#1-para-qué-sirve-este-documento)
2. [Visión general de la plataforma](#2-visión-general-de-la-plataforma)
3. [Cuentas AWS y accesos](#3-cuentas-aws-y-accesos)
4. [Estructura del repositorio](#4-estructura-del-repositorio)
5. [Pipelines CI/CD — qué hace cada workflow](#5-pipelines-cicd--qué-hace-cada-workflow)
6. [Modelo de seguridad — OIDC sin credenciales](#6-modelo-de-seguridad--oidc-sin-credenciales)
7. [Bootstrap inicial (one-time setup)](#7-bootstrap-inicial-one-time-setup)
8. [Operación diaria — flujos de trabajo](#8-operación-diaria--flujos-de-trabajo)
9. [Cómo agregar un nuevo stack](#9-cómo-agregar-un-nuevo-stack)
10. [Cómo agregar un nuevo ambiente](#10-cómo-agregar-un-nuevo-ambiente)
11. [Tags obligatorios y trazabilidad](#11-tags-obligatorios-y-trazabilidad)
12. [Despliegue a producción — proceso paso a paso](#12-despliegue-a-producción--proceso-paso-a-paso)
13. [Estados ocultos y troubleshooting](#13-estados-ocultos-y-troubleshooting)
14. [FinOps — gobierno de costos](#14-finops--gobierno-de-costos)
15. [Glosario](#15-glosario)
16. [Referencias y enlaces](#16-referencias-y-enlaces)

---

## 1. Para qué sirve este documento

Este documento es el **handoff completo** de la infraestructura `iaapp`. Sirve para tres audiencias:

- **Nuevo miembro del equipo:** lee §3 (accesos), §7 (bootstrap), §8 (operación diaria) y §15 (glosario). En una hora puedes desplegar tu primer stack a `dev`.
- **DevOps que recibe el proyecto:** lee de principio a fin. Especial atención a §6 (seguridad), §11 (tags) y §13 (troubleshooting).
- **Stakeholder técnico de UDABOL:** lee §2 (visión general), §3 (cuentas) y §14 (FinOps).

El proyecto está optimizado para un equipo pequeño (3 personas) que despliega con frecuencia. La complejidad está acotada deliberadamente: lo que falta (cuenta de seguridad dedicada, DAST automático, Permission Boundaries elaboradas) está documentado en §13 como deuda diferida.

---

## 2. Visión general de la plataforma

`iaapp` es la plataforma cloud de UDABOL en AWS. Hoy provisiona la **red base** (VPC en 3 capas) y el **gobierno de costos** (AWS Budgets). El roadmap futuro contempla cómputo (ECS/Lambda), datos (RDS) y edge (ALB/CloudFront).

### Arquitectura de red

Cada VPC se despliega con **3 capas** y **1 o 2 AZs** según el ambiente:

| Capa        | Tipo               | Propósito                                     |
|-------------|--------------------|-----------------------------------------------|
| Exposición  | Pública            | Internet Gateway · ALB · Bastion              |
| Servicios   | Privada            | EC2 · ECS · Lambda · EKS                      |
| Datos       | Privada aislada    | RDS · ElastiCache · VPC endpoints             |

### Esquema de CIDRs

| Ambiente | VPC CIDR        | Subnets exposición | Subnets servicios | Subnets datos    | AZ     |
|----------|-----------------|--------------------|-------------------|------------------|--------|
| dev      | `10.10.0.0/16`  | `10.10.1-2.0/24`   | `10.10.11-12.0/24`| `10.10.21-22.0/24`| 1 (a) |
| qa       | `10.20.0.0/16`  | `10.20.1-2.0/24`   | `10.20.11-12.0/24`| `10.20.21-22.0/24`| 1 (a) |
| prod     | `10.30.0.0/16`  | `10.30.1-2.0/24`   | `10.30.11-12.0/24`| `10.30.21-22.0/24`| 2 (a,b) |

**Por qué Single-AZ en dev/qa:** ahorra ~50% de NAT GW y EIP. Multi-AZ se reserva para prod por requisitos de alta disponibilidad.

### Stack tecnológico

| Componente   | Decisión        | Razón |
|--------------|-----------------|---|
| IaC          | CloudFormation  | Equipo pequeño, sin overhead de Terraform/CDK, soporta StackSets nativos |
| CI/CD        | GitHub Actions  | Ya en uso por el equipo, OIDC nativo con AWS |
| Auth         | OIDC            | Cero credenciales estáticas en CI |
| Lint/Scan    | cfn-lint, cfn-nag, checkov, cfn-guard | Cubre estructura, patrones inseguros y policy-as-code |
| Versionado   | Git + GitHub Flow | 3 personas, no requiere GitFlow |

---

## 3. Cuentas AWS y accesos

### Cuentas

| Cuenta | Account ID    | Propósito                              | Estado    |
|--------|---------------|----------------------------------------|-----------|
| dev    | `245650696072`| Desarrollo, integración continua       | ✅ Activa |
| qa     | `493735739951`| Testing, validación pre-prod           | ✅ Activa |
| prod   | (pendiente)   | Producción                             | ⏳ Diferida (SOW-002) |

### Acceso humano (consola y CLI)

- **SSO Portal:** https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/
- **Usuario:** `cloudadmin`
- **CLI local:** `aws sso login --profile iaapp-dev` (ver §7)

### Acceso de pipelines (GitHub Actions)

GitHub Actions asume el rol IAM por OIDC. **No hay credenciales estáticas** en GitHub Secrets.

| Cuenta | IAM Role                                  | Asumido desde                       |
|--------|-------------------------------------------|-------------------------------------|
| dev    | `GithubActionsDeployRole-iaapp-dev`       | repo `airusta/iaapp`, env `dev`     |
| qa     | `GithubActionsDeployRole-iaapp-qa`        | repo `airusta/iaapp`, env `qa`      |
| prod   | `GithubActionsDeployRole-iaapp-prod` (futuro) | repo `airusta/iaapp`, env `production` (2 reviewers) |

---

## 4. Estructura del repositorio

```
iaapp/
├── .github/
│   ├── workflows/                       Pipelines CI/CD
│   │   ├── pr-validate.yml              Lint + ChangeSet preview en cada PR
│   │   ├── deploy-nonprod.yml           Auto-deploy a dev / manual a qa
│   │   ├── deploy-prod.yml              Manual a prod, 2 reviewers + 10min wait
│   │   └── drift-detection.yml          Schedule diario
│   └── oidc/
│       └── iam-role.yaml                Plantilla OIDC Provider + IAM Role (1x por cuenta)
│
├── cloudformation/
│   ├── modules/                         Bloques reutilizables
│   │   └── vpc/vpc.yaml                 ⭐ VPC 3 capas, single/multi-AZ
│   └── stacks/                          Stacks legacy por ambiente (en migración a parameters/)
│       ├── dev-vpc.yaml
│       ├── qa-vpc.yaml
│       └── prod-vpc.yaml
│
├── parameters/                          ⭐ Lo que cambia entre ambientes
│   ├── dev/
│   │   ├── vpc.json
│   │   └── budgets.json
│   ├── qa/
│   │   └── ...
│   └── prod/
│       └── ...
│
├── policies/                            Policy as Code
│   ├── checkov-baseline.yaml            Config checkov + exclusiones justificadas
│   └── cfn-guard/rules.guard            Reglas custom (tags obligatorios, IMDSv2, etc.)
│
├── scripts/                             Wrappers
│   ├── deploy.sh                        `aws cloudformation deploy` con tags inyectados
│   ├── diff-changeset.sh                ChangeSet preview (no aplica)
│   ├── bootstrap-account.sh             Setup OIDC en una cuenta nueva
│   └── smoke-test.sh                    Verificación post-deploy
│
├── budgets/budget-setup.yaml            AWS Budgets — alertas por ambiente
│
├── docs/
│   ├── GUIA-TRANSFERENCIA.md            ⭐ Este documento
│   ├── context.md                       Contexto del proyecto
│   ├── vpc-design.md                    Diseño VPC 3 capas
│   ├── vpn-s2s-design.md                Diseño VPN Site-to-Site
│   ├── runbook-rollback.md              Procedimiento ante deploy fallido
│   ├── onboarding.md                    Setup local del desarrollador
│   └── html/                            Portal HTML de documentación
│
├── SOW/                                 Trabajo del Statement of Work 001
├── CODEOWNERS                           Aprobaciones requeridas por carpeta
├── Makefile                             `make help` para ver todos los comandos
├── .pre-commit-config.yaml              Hooks: cfn-lint, checkov, formato
├── .cfnlintrc.yaml                      Config cfn-lint
└── .gitignore
```

### Regla de oro

> El **código** vive en `cloudformation/`. La **diferencia entre ambientes** vive en `parameters/`. Si te encuentras copiando un template y cambiando 2 líneas, parametrízalo.

---

## 5. Pipelines CI/CD — qué hace cada workflow

| Workflow                  | Trigger                                | Qué hace                                              | Aprobación      |
|---------------------------|----------------------------------------|-------------------------------------------------------|-----------------|
| `pr-validate.yml`         | PR a `main` (paths cloudformation/parameters)| `cfn-lint` + `cfn-nag` + `checkov` + ChangeSet preview en dev | —               |
| `deploy-nonprod.yml`      | Push a `main` (auto) · `workflow_dispatch` | Despliega a dev (auto) o qa (manual) con OIDC         | 1 reviewer (qa) |
| `deploy-prod.yml`         | `workflow_dispatch` solamente          | ChangeSet → revisión humana → execute en prod         | 2 reviewers + 10 min wait |
| `drift-detection.yml`     | Schedule diario 07:00 UTC              | `detect-stack-drift` en todos los stacks; abre Issue si DRIFTED | — |

### Convención de identificadores `[FASE-ETAPA-NNN]`

Cada step de los workflows lleva un ID único en el campo `name:` para facilitar trazabilidad en logs:

```
[CI-LNT-002]  cfn-lint
[CD-DEP-105]  Deploy VPC
[PRD-GATE-102] Pre-deploy context (producción)
[OPS-IAC-003]  Detect drift
```

Cuando un job falla, el ID en el log permite encontrar inmediatamente la fase y etapa exacta del problema.

---

## 6. Modelo de seguridad — OIDC sin credenciales

### Por qué OIDC

GitHub Actions intercambia un token JWT (firmado por GitHub) por credenciales temporales de AWS. Beneficios:

- **Cero secretos** en GitHub Secrets para acceso a AWS
- **Auditable** — cada `assume-role` queda en CloudTrail con el contexto del workflow
- **Granular** — la `trust policy` del rol filtra por repo, branch o environment

### Trust policy del rol (resumen)

```yaml
Principal:
  Federated: arn:aws:iam::{ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com
Condition:
  StringEquals:
    token.actions.githubusercontent.com:aud: sts.amazonaws.com
  StringLike:
    token.actions.githubusercontent.com:sub:
      - repo:airusta/iaapp:ref:refs/heads/main
      - repo:airusta/iaapp:environment:production    # solo desde el environment 'production'
```

Esto significa: **un atacante con un token de OTRO repo o branch NO puede asumir nuestro rol**. La condición `:sub:` es la que cierra la puerta.

### Jerarquía de secretos

| Capa                          | Para qué                                   | Ejemplo                                     |
|-------------------------------|--------------------------------------------|---------------------------------------------|
| GitHub Environment variables  | Account IDs (no sensitivos), región        | `PROD_ACCOUNT_ID=000000000000`              |
| SSM Parameter Store           | Configuración por ambiente                 | `/iaapp/prod/api-endpoint`                  |
| AWS Secrets Manager           | Credenciales reales                        | `iaapp/prod/db/password` (KMS-encrypted)    |
| KMS                           | Llave de cifrado                           | `alias/iaapp-prod`                          |

**Regla:** los secretos nunca se imprimen en logs. Los workflows usan `::add-mask::` antes de exportar valores recuperados de SSM o Secrets Manager.

---

## 7. Bootstrap inicial (one-time setup)

### 7.1 Setup local del desarrollador

```bash
# 1. Clonar el repo
git clone https://github.com/airusta/iaapp.git
cd iaapp

# 2. Instalar dependencias
pip install pre-commit cfn-lint==1.20.0 checkov==3.2.71 detect-secrets==1.5.0
brew install awscli jq        # macOS — para Linux/Windows usar instalador oficial

# 3. Activar pre-commit hooks
pre-commit install

# 4. Configurar AWS SSO (perfil por cuenta)
aws configure sso              # seguir el wizard
# Crear 2 perfiles: iaapp-dev (245650696072) y iaapp-qa (493735739951)

# 5. Verificar
aws sso login --profile iaapp-dev
aws sts get-caller-identity --profile iaapp-dev

# 6. Ver comandos disponibles
make help
```

### 7.2 Bootstrap de una cuenta AWS (solo la primera vez por cuenta)

Despliega el OIDC Provider + IAM Role en cada cuenta. **Hacer esto manualmente desde SSO** (no se puede via pipeline porque aún no existe el rol que el pipeline necesita).

```bash
# 1. Login SSO a la cuenta destino
aws sso login --profile iaapp-dev

# 2. Despliega el stack OIDC
./scripts/bootstrap-account.sh dev    # repetir para qa y prod

# 3. Anota el ARN del rol que imprime el script
# Output: arn:aws:iam::245650696072:role/GithubActionsDeployRole-iaapp-dev

# 4. Verifica que coincide con lo configurado en .github/workflows/deploy-nonprod.yml
grep role-to-assume .github/workflows/*.yml
```

### 7.3 Configurar GitHub Environments

En GitHub → Settings → Environments:

**Environment `dev`:**
- Sin restricciones — auto-deploy desde `main`

**Environment `qa`:**
- Required reviewers: 1 (cualquier miembro del equipo)
- Deployment branches: solo `main`

**Environment `production`:**
- Required reviewers: 2 (autor del PR no puede auto-aprobar)
- Wait timer: 10 minutos
- Deployment branches: solo `main`

### 7.4 Configurar Branch Protection

En GitHub → Settings → Branches → Add rule para `main`:

- ✅ Require pull request before merging (1 approval mínimo)
- ✅ Require review from Code Owners
- ✅ Require status checks: `pr-validate / lint-and-scan` y `pr-validate / changeset-preview-dev`
- ✅ Require linear history
- ✅ Restrict pushes (nadie puede hacer push directo, ni admins)

---

## 8. Operación diaria — flujos de trabajo

### 8.1 Modificar infraestructura existente

```bash
# 1. Crear branch
git checkout main && git pull
git checkout -b feat/agregar-vpc-endpoint-s3

# 2. Editar el template
$EDITOR cloudformation/modules/vpc/vpc.yaml

# 3. Validar localmente
make lint

# 4. Preview del cambio en dev
make plan ENV=dev STACK=vpc

# 5. Si el plan se ve bien → commit + push + PR
git add . && git commit -m "feat(vpc): agregar VPC endpoint para S3"
git push -u origin feat/agregar-vpc-endpoint-s3
gh pr create --base main

# 6. Esperar pr-validate.yml (lint + ChangeSet preview en dev)
# 7. Pedir review a un colega
# 8. Squash merge a main → dispara deploy-nonprod.yml automáticamente a dev
```

### 8.2 Promover a QA tras validación en dev

```bash
# Desde GitHub UI: Actions → deploy-nonprod → Run workflow
#   environment: qa
#   stack: vpc

# O desde la CLI:
gh workflow run deploy-nonprod.yml -f environment=qa -f stack=vpc
```

### 8.3 Modificar parámetros sin tocar código

```bash
# Cambiar el CIDR de qa? Solo edita el JSON.
$EDITOR parameters/qa/vpc.json
make plan ENV=qa STACK=vpc       # verifica el ChangeSet
git add parameters/qa/vpc.json && git commit -m "fix(qa): ajustar CIDR de VPC"
git push && gh pr create
```

### 8.4 Eliminar un stack (con cuidado)

```bash
# Solo desde local con SSO activo
make delete ENV=dev STACK=vpc
# Pide confirmación interactiva — escribir 'eliminar' para confirmar
```

---

## 9. Cómo agregar un nuevo stack

Ejemplo: agregar un stack para ECS Cluster.

### 9.1 Crear el módulo

```bash
mkdir -p cloudformation/modules/ecs-cluster
$EDITOR cloudformation/modules/ecs-cluster/ecs-cluster.yaml
```

Estructura del template — debe tener al menos estos parámetros:

```yaml
Parameters:
  Environment:        # dev | qa | prod
  ProjectName:        # default: iaapp
  Company:            # default: udabol
  Owner:              # default: ayrton.irusta@gmail.com
  # ... parámetros específicos del stack
```

Y los tags estándar en cada recurso (ver §11).

### 9.2 Crear los archivos de parameters

```bash
$EDITOR parameters/dev/ecs-cluster.json
$EDITOR parameters/qa/ecs-cluster.json
$EDITOR parameters/prod/ecs-cluster.json
```

Formato (copiar de `parameters/dev/vpc.json` y adaptar):

```json
[
  { "ParameterKey": "Environment",  "ParameterValue": "dev" },
  { "ParameterKey": "ProjectName",  "ParameterValue": "iaapp" }
]
```

### 9.3 Actualizar el `Makefile` y workflow

El `Makefile` y `deploy-nonprod.yml` ya usan `${STACK}` como variable, así que no requieren cambios — basta con que los archivos sigan la convención.

Pero sí debes:
1. Agregar la opción en el `choice` del `workflow_dispatch.inputs.stack` en ambos `deploy-nonprod.yml` y `deploy-prod.yml`.
2. Si el stack tiene smoke test específico, agregarlo a `scripts/smoke-test.sh`.

### 9.4 Probar

```bash
make lint
make plan ENV=dev STACK=ecs-cluster
make deploy ENV=dev STACK=ecs-cluster   # local, requiere SSO
```

Si todo funciona, commit + PR + merge → auto-deploy en CI.

---

## 10. Cómo agregar un nuevo ambiente

Ejemplo: agregar `staging` entre qa y prod.

### 10.1 Aprovisionar la cuenta AWS (si es nueva)

Desde la cuenta `management` de AWS Organizations, crear una cuenta nueva en la OU correspondiente.

### 10.2 Bootstrap OIDC

```bash
aws sso login --profile iaapp-staging
./scripts/bootstrap-account.sh staging
```

### 10.3 Agregar parameters

```bash
mkdir -p parameters/staging
cp parameters/qa/*.json parameters/staging/
# Editar staging/*.json — cambiar CIDRs (10.25.x.x), Environment, etc.
```

### 10.4 Actualizar workflows

En `.github/workflows/deploy-nonprod.yml`:
- Agregar `staging` al `choice` del input `environment`
- Agregar el case `staging) ACCOUNT=...` en el job `context`

### 10.5 Configurar GitHub Environment

GitHub → Settings → Environments → New environment `staging`:
- Required reviewers: 1
- Deployment branches: `main` y `release/*`

---

## 11. Tags obligatorios y trazabilidad

**Toda creación de recurso AWS debe llevar este bloque mínimo de tags:**

```yaml
Project:            iaapp
Company:            udabol
Application:        vpc | ecs | rds | ...      # módulo del que proviene
Environment:        dev | qa | prod
Owner:              ayrton.irusta@gmail.com
ManagedBy:          cloudformation
SOW:                SOW-001
DataClassification: public | internal | confidential | restricted
```

**Trazabilidad CI/CD — agregar siempre que el deploy lo haga el pipeline:**

```yaml
Pipeline:           github-actions
CommitHash:         a1b2c3d                         # primeros 7 chars del SHA
DeployDate:         2026-05-05                      # YYYY-MM-DD UTC
TicketId:           JIRA-123 | GH-456 | manual      # ticket origen del cambio
```

### Por qué importa

- **Cost Allocation:** AWS Cost Explorer permite filtrar por tag → costo exacto por proyecto/ambiente
- **Búsqueda:** `aws resourcegroupstaggingapi get-resources --tag-filters Key=CommitHash,Values=a1b2c3d` te encuentra todo lo desplegado en un commit específico
- **Compliance:** auditorías necesitan saber el dueño y la fecha de cada recurso
- **FinOps:** budgets reactivos por tag (ver §14)

### Reglas

- `kebab-case` en minúsculas para todos los **valores** (no para las **keys**)
- `ManagedBy=manual` es una señal de alarma — migrar a IaC en el siguiente sprint
- El tag `CommitHash` es el nexo entre el recurso AWS y el commit exacto del deploy

---

## 12. Despliegue a producción — proceso paso a paso

### 12.1 Pre-requisitos del cambio

- ✅ El cambio fue desplegado y validado en `qa` por al menos 24 horas
- ✅ El smoke test de qa pasó
- ✅ Existe un ticket asociado (JIRA-XXX o GH-XXX)
- ✅ Hay 2 personas disponibles para revisar (no contar al autor)
- ✅ No estamos en ventana de freeze (revisar calendario del equipo)

### 12.2 Disparar el deploy

```
GitHub UI → Actions → deploy-prod → Run workflow
  stack:    vpc
  confirm:  IAAPP-PROD          ← debe ser exactamente esto
  ticket:   JIRA-123
```

### 12.3 Lo que pasa después

1. **`validate-input`** verifica el string de confirmación y el formato del ticket
2. GitHub bloquea el job `deploy` esperando 2 reviewers
3. Cuando ambos aprueban, **arranca un timer de 10 minutos** (ventana de cancelación)
4. Tras los 10 min, el job continúa:
   - Asume el rol IAM por OIDC en la cuenta prod
   - Verifica que el caller identity coincide con la cuenta esperada
   - Crea un ChangeSet (no lo ejecuta aún)
   - Imprime el ChangeSet completo en el log
   - Ejecuta el ChangeSet
   - Espera a `stack-update-complete`
   - Imprime los outputs
   - Corre el smoke test

### 12.4 Si algo sale mal

- Si el job falla **antes** del execute → no hay cambio en AWS, no hace falta rollback
- Si falla **durante** el execute → CloudFormation hace rollback automático al estado anterior
- Si el rollback falla → ver `docs/runbook-rollback.md`

### 12.5 Notificación

El `summary` final imprime un bloque con: stack, operador, ticket, commit, fecha. Capturar ese bloque en el sistema de tickets para cierre del cambio.

---

## 13. Estados ocultos y troubleshooting

Los **estados ocultos** son condiciones que no generan error explícito pero causan fallos posteriores. Antes de buscar bugs en el código, revisar estas causas.

| Síntoma                                    | Causa probable                                        | Verificación / mitigación                                           |
|--------------------------------------------|-------------------------------------------------------|--------------------------------------------------------------------|
| Deploy a qa falla con `AccessDenied`       | Rol IAM en qa no creado (falta bootstrap)             | `./scripts/bootstrap-account.sh qa`                                |
| `validate-template` ok pero deploy falla   | Permission Boundary del rol bloquea acción específica | Revisar `policies/cfn-guard/rules.guard` y trust policy            |
| ChangeSet sale vacío en dev pero hay cambios | Los parámetros no cambiaron — solo se editó el template y el resource no se ve afectado | Inspeccionar el ChangeSet línea por línea |
| Stack en `UPDATE_ROLLBACK_FAILED`          | Rollback no pudo restaurar (común con DBs)            | `aws cloudformation continue-update-rollback`; ver runbook-rollback |
| Smoke test pasa pero la app falla          | Status 200 con cuerpo degradado                       | Smoke test debe validar estructura del body, no solo el código HTTP |
| Drift detectado tras día tranquilo         | Cambio manual en consola por alguien del equipo       | Hablar con el equipo; si fue intencional → reflejarlo en el template |
| `Resource handler returned message: ... already exists` | Stack eliminado pero recurso huérfano (NAT/EIP) | `aws ec2 release-address` manualmente; revisar tags `ManagedBy` |
| `npm install` o builds inestables          | Pinning de versiones falta                            | Usar `npm ci` (no `install`); congelar versiones en pre-commit-config |
| `cfn-lint` pasa local pero falla en CI     | Versión distinta de cfn-lint                          | Ambas usan `cfn-lint==1.20.0` (ver `.pre-commit-config.yaml`)      |
| OIDC token rejected por AWS                | Trust policy del rol no acepta este `:sub:`           | Revisar la condición `StringLike` en `.github/oidc/iam-role.yaml`  |
| GitHub Environment espera aprobación que nunca llega | Reviewer es el autor del PR                  | Otro miembro del equipo aprueba (autor no puede auto-aprobar)      |

### Comandos útiles para diagnóstico

```bash
# Ver el último deploy de un stack
aws cloudformation describe-stack-events \
  --stack-name iaapp-vpc-dev \
  --region us-east-1 \
  --max-items 20

# Ver drift de todos los stacks de iaapp
for STACK in $(aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?starts_with(StackName, `iaapp-`)].StackName' --output text); do
    echo "=== $STACK ==="
    aws cloudformation detect-stack-drift --stack-name $STACK
done

# Ver qué desplegó tal commit
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=CommitHash,Values=a1b2c3d \
  --region us-east-1
```

---

## 14. FinOps — gobierno de costos

### Budgets configurados

| Ambiente | Límite mensual | Alertas a                | Configurado en                 |
|----------|----------------|--------------------------|-------------------------------|
| dev      | $100 USD       | ayrton.irusta@gmail.com  | `parameters/dev/budgets.json` |
| qa       | $150 USD       | ayrton.irusta@gmail.com  | `parameters/qa/budgets.json`  |
| prod     | $500 USD       | ayrton.irusta@gmail.com  | `parameters/prod/budgets.json`|

Los budgets envían email cuando el gasto **proyectado** alcanza el 80% (alerta) y cuando el gasto **real** alcanza el 100% (crítico).

### Optimizaciones ya implementadas

- **Single-AZ en dev/qa** — ahorra ~50% en NAT Gateway y EIPs
- **NAT Gateway opcional** — el workflow lo permite desactivar como input
- **Flow Logs con retención de 30 días** en dev/qa, 365 en prod
- **`concurrency` cancel-in-progress** en `pr-validate.yml` — no corre 2 lints del mismo PR
- **`paths` filter** en workflows — no corren si el cambio no toca infra

### Reportes recomendados

```bash
# Costo mensual por ambiente
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-05-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=Environment

# Costo por proyecto (para distinguir si UDABOL tiene varios)
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-05-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=Project
```

---

## 15. Glosario

| Término                  | Definición                                                                                          |
|--------------------------|----------------------------------------------------------------------------------------------------|
| **OIDC**                 | OpenID Connect — protocolo que permite a GitHub firmar tokens que AWS verifica para emitir credenciales temporales. |
| **ChangeSet**            | Plan de cambios de CloudFormation. Calcula qué se va a crear/modificar/eliminar **sin aplicar nada**. |
| **Drift**                | Cuando el estado real en AWS difiere del template versionado (alguien tocó la consola).            |
| **Stack**                | Conjunto de recursos AWS desplegados juntos por una plantilla CloudFormation.                       |
| **Trust Policy**         | Política IAM que define **quién** puede asumir un rol (vs. la `Permissions Policy` que define **qué** puede hacer). |
| **GitHub Environment**   | Entorno con reglas de protección (reviewers, wait timer) — distinto de un AWS environment.          |
| **NAT Gateway**          | Permite a recursos en subnets privadas alcanzar Internet sin exponerse. ~$32/mes c/u.              |
| **NACL**                 | Network ACL — firewall a nivel de subnet, complementa Security Groups (que son a nivel ENI).        |
| **VPC Flow Logs**        | Logs de tráfico IP en la VPC. Útiles para forensics y troubleshooting.                              |
| **Multi-AZ**             | Recursos replicados en 2+ Availability Zones para alta disponibilidad.                              |
| **SSO Portal**           | AWS IAM Identity Center — el portal único de login para humanos.                                    |
| **Permission Boundary**  | Política IAM que **limita** lo que un rol puede hacer, incluso si su política base es más permisiva. |
| **Policy as Code**       | Reglas de seguridad declarativas (cfn-guard, checkov) ejecutadas en CI.                             |
| **SAST / SCA / DAST**    | Static App Security Testing / Software Composition Analysis / Dynamic AST.                          |
| **FinOps**               | Disciplina que combina ingeniería + finanzas para optimizar el gasto cloud.                         |

---

## 16. Referencias y enlaces

### Documentación interna

- [README del repo](../README.md)
- [Diseño VPC 3 capas](vpc-design.md)
- [Diseño VPN Site-to-Site](vpn-s2s-design.md)
- [Runbook rollback](runbook-rollback.md)
- [Onboarding desarrollador](onboarding.md)

### Documentación externa

- [GitHub OIDC + AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)
- [cfn-lint rules](https://github.com/aws-cloudformation/cfn-lint/blob/main/docs/rules.md)
- [checkov CloudFormation checks](https://www.checkov.io/5.Policy%20Index/cloudformation.html)
- [cfn-guard syntax](https://docs.aws.amazon.com/cfn-guard/latest/ug/writing-rules.html)

### Herramientas

| Herramienta     | Versión usada | Para qué                          |
|-----------------|---------------|-----------------------------------|
| AWS CLI         | v2            | CLI base                          |
| cfn-lint        | 1.20.0        | Lint de templates                 |
| checkov         | 3.2.71        | Policy as code                    |
| cfn-guard       | 3.x           | Reglas custom                     |
| pre-commit      | 4.6.0         | Hooks locales                     |
| detect-secrets  | 1.5.0         | Bloqueo de secretos en commits    |
| jq              | 1.6+          | Parsing de JSON en scripts        |

### Contactos

- **Owner técnico:** ayrton.irusta@gmail.com
- **Repo:** https://github.com/airusta/iaapp
- **Cuentas AWS:**
  - dev: `245650696072`
  - qa: `493735739951`
  - prod: pendiente de aprovisionamiento

---

**Fin de la guía.** Si encuentras algo que está desactualizado o incorrecto, abre un PR contra este archivo — la documentación es código.

*UDABOL · iaapp · SOW-001 · 2026*
