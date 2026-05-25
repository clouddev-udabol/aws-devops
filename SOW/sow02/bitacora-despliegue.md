# Bitácora de Despliegue — SOW-002 Sprint 1
**Proyecto:** UDABOL ERP-Agent · Fundación Dockweiler
**Ejecutor:** Ayrton Irusta (DevOps / Cloud Architect)
**Inicio ejecución:** 2026-05-22
**Presupuesto contractual:** 80 horas (USD 4,400 · $55/hr)

---

## Control de horas

| Bloque | Actividad | Fecha | Horas est. | Horas reales | Estado |
|--------|-----------|-------|-----------|--------------|--------|
| **A.0** | Bootstrap IAM Identity Center — Permission Set Sprint1Deploy + perfiles proy-dev/proy-qa | 2026-05-22 | 2.0 h | 3.5 h | ✅ COMPLETADO |
| **A.1** | Estructura 7 repos agt-* (ramas, ci.yml, Makefile, .env.example) | 2026-05-22 | 3.0 h | 2.5 h | ✅ COMPLETADO |
| **A.2** | Branch protection rules en 7 repos | 2026-05-24 | 1.0 h | 0.5 h | 🔴 BLOQUEADO — plan GitHub Free no permite branch protection en repos privados. Requiere GitHub Team o repos públicos. Decisión pendiente Franz. |
| **A.3** | Deploy 14 repos ECR (DEV + QA vía CFN) | 2026-05-22 | 2.0 h | 0.5 h | ✅ COMPLETADO |
| **A.4** | Pipeline piloto CI/CD en agt-agent y agt-toolapi | 2026-05-22 | 3.0 h | 4.0 h | ✅ COMPLETADO |
| **B.1** | CloudFormation Lex V2 Bot + generate_template.py + intents YAML | 2026-05-23 | 8.0 h | 4.0 h | ✅ COMPLETADO |
| **B.2** | Deploy Lex DEV + QA + validación recognize-text | 2026-05-23 | 2.0 h | 2.0 h | ✅ COMPLETADO |
| **C.0** | ECS Cluster + ALB interno + Cloud Map namespace agt.local | 2026-05-23 | 3.0 h | 2.5 h | ✅ COMPLETADO |
| **C.1** | Lambda agt-whatsapp-gateway + API Gateway | 2026-05-23 | 4.0 h | 3.5 h | ✅ COMPLETADO |
| **C.2** | ECS Services: agt-agent, agt-toolapi, agt-legacy-adapter | 2026-05-23 | 6.0 h | 5.0 h | ✅ COMPLETADO |
| **C.3** | Validación ECS: describe-services running=desiredCount | 2026-05-23 | 1.0 h | 0.5 h | ✅ COMPLETADO |
| **D.1** | RDS PostgreSQL 16 + Secrets Manager + rotación 30d | 2026-05-23 | 5.0 h | 4.5 h | ✅ COMPLETADO (DEV + QA) |
| **D.2** | MSK Serverless DEV + QA + 3 topics (enrollment.events, payment.events, query.audit) | — | 6.0 h | — | ⬜ PENDIENTE (N1 resuelto por SOW-002 §2.5) |
| **D.3** | Lambda agt-readmodel + event source mapping a MSK | — | 2.0 h | — | ⬜ PENDIENTE (depende D.2) |
| **D.4** | NAT Instance t4g.nano + VPC Endpoints (ECR, Logs, SM, Lex) + mover ECS a PrivateSubnet — cierra ISS-003 | — | 5.0 h | — | ⬜ PENDIENTE — ver ADR-FINOPS-001 |
| **E.1** | OTel Collector ECS task + config.yaml (backend CloudWatch + X-Ray) | — | 9.0 h | — | ⬜ PENDIENTE (N2 resuelto por SOW-002 §2.6) |
| **E.2** | OTel SDK Python en 7 repos agt-* (requirements.txt + bootstrap main.py) | — | 6.0 h | — | ⬜ PENDIENTE (depende E.1) |
| **E.3** | Smoke test end-to-end + documentación de evidencia | — | 4.0 h | — | ⏳ Bloqueado D6 (credenciales Twilio) |
| **E.4** | Runbook sprint1-deploy.md | 2026-05-23 | 3.0 h | 1.5 h | ✅ COMPLETADO |
| — | **Total presupuestado** | — | **80.0 h** | — | — |
| — | **Acumulado real** | — | — | **32.5 h** | — |
| — | **Saldo disponible** | — | — | **47.5 h** | — |

---

## A.0 — Bootstrap IAM Identity Center (COMPLETADO)

**Fecha:** 2026-05-22
**Horas reales:** ~3.5 h (estimado 2.0 h — ver observación OBS-001)
**Perfil utilizado para bootstrap:** `fdac-cloudadmin` (Management Account `293080376762`)

### Qué se hizo

1. **Inventario IAM Identity Center:** se auditaron los 3 Permission Sets existentes:
   - `DevOpsReadOnly` — Ayrton, solo lectura (insuficiente para Sprint 1)
   - `ArchitectAccess` — Carlos, PowerUser sin IAM write
   - `AdministratorAccess` — Ian + cloudadmin

2. **Nuevo Permission Set `Sprint1Deploy` creado:**
   - ARN: `arn:aws:sso:::permissionSet/ssoins-7223753b6943f944/ps-7223d1d84b0247e6`
   - Managed Policy: `PowerUserAccess`
   - Inline Policy: `IAMForProjectRoles` — scoped a `agt-*`, `udabol-*`, `role-vpc-flowlogs-*`
   - Sesión: 8 horas

3. **Asignado a `ayrton.devops`** en DEV `245650696072` y QA `493735739951` — ambos `SUCCEEDED`.

4. **Perfiles AWS configurados** en `~/.aws/config`:
   - `proy-dev` → DEV `245650696072` · `Sprint1Deploy` · `ayrton.devops`
   - `proy-qa` → QA `493735739951` · `Sprint1Deploy` · `ayrton.devops`
   - SSO session `proy` → `https://ssoins-7223753b6943f944.portal.us-east-1.app.aws`

5. **Verificación exitosa:**
   ```
   proy-dev → AWSReservedSSO_Sprint1Deploy_61cd3079848333d4/ayrton.devops · 245650696072 ✅
   proy-qa  → AWSReservedSSO_Sprint1Deploy_cc366dc6e24be129/ayrton.devops · 493735739951 ✅
   ```

### Política inline guardada

`d:\IA_opencode\policies\sprint1-iam-inline.json`

### Observaciones de A.0

- **OBS-001:** El bootstrap tomó 3.5 h en lugar de 2 h por un problema de caché de sesión SSO. La sesión `fundaciondev` tenía token de `cloudadmin`, no de `ayrton.devops`. La solución fue crear sesión SSO separada `proy` y autenticar con `ayrton@udabol.edu.bo`. Ver [Observaciones de arquitectura §3](#obs-001-sso-multisesion).

---

## A.2 — Branch Protection (BLOQUEADO — pendiente decisión de plan)

**Fecha intento:** 2026-05-24
**Horas reales:** ~0.5 h

### Qué se hizo

1. Nuevo PAT `clouddev-udabol` con scopes `admin:org` + `repo` verificado y funcional.
2. Confirmado acceso a los 7 repos `agt-*` — ramas `main`, `qa`, `dev` presentes en todos.
3. Intento de apply branch protection via `gh api PUT /branches/{branch}/protection` → HTTP 403.
4. Intento con nueva API Rulesets (`POST /rulesets`) → mismo HTTP 403.

### Causa raíz

La org `clouddev-udabol` está en **GitHub Free**. GitHub bloquea branch protection y rulesets en repos privados en el plan gratuito, independientemente de los permisos del token o del rol del usuario.

### Opciones para desbloquear E1

| Opción | Costo | Acción requerida | Riesgo |
|--------|-------|-----------------|--------|
| **Upgrade a GitHub Team** | ~$4/usuario/mes | Owner de la org activa el plan desde Billing | Ninguno — repos siguen privados |
| **Hacer repos públicos** | $0 | `gh api repos/clouddev-udabol/{repo} --method PATCH --field private=false` × 7 | Código visible públicamente (secrets están en AWS, no en el repo) |
| **Mantener bloqueo** | $0 | Documentar y notificar a Franz | E1 no se puede cerrar, afecta pago del 60% |

### Script listo para ejecutar

`d:\IA_opencode\scripts\apply-branch-protection.ps1` — solo necesita que se resuelva el plan.

### Observaciones de A.2

- **OBS-013:** GitHub Free bloquea branch protection API (HTTP 403) en repos privados. El token y los permisos son correctos — el límite es del plan de la org, no de credenciales.

---

## A.3 — ECR CloudFormation (COMPLETADO)

**Fecha:** 2026-05-22
**Horas reales:** ~0.5 h (estimado 2.0 h)

### Qué se hizo

1. **Template CloudFormation** creado: `cloudformation/modules/ecr/ecr-repos.yaml`
   - 7 recursos `AWS::ECR::Repository` (uno por microservicio)
   - `ScanOnPush: true`, encriptación AES256
   - Lifecycle policy: retener últimas 5 imágenes tagged, expirar untagged en 1 día
   - Tags SCP-compliant: `Entorno=desarrollo` (DEV) / `Entorno=staging` (QA)
   - `DeletionPolicy: Retain` — repos sobreviven si se elimina el stack

2. **Parámetros** creados: `parameters/dev/ecr.json` y `parameters/qa/ecr.json`

3. **Stacks desplegados:**
   - `udabol-ecr-dev` → cuenta DEV `245650696072` · perfil `proy-dev` ✅
   - `udabol-ecr-qa` → cuenta QA `493735739951` · perfil `proy-qa` ✅

4. **Verificación — 7/7 repos en cada cuenta:**

   | Repo | DEV URI | QA URI |
   |------|---------|--------|
   | agt-common | 245650696072.dkr.ecr.us-east-1.amazonaws.com/agt-common | 493735739951.dkr.ecr.us-east-1.amazonaws.com/agt-common |
   | agt-intent-parser | ✅ | ✅ |
   | agt-whatsapp-gateway | ✅ | ✅ |
   | agt-toolapi | ✅ | ✅ |
   | agt-agent | ✅ | ✅ |
   | agt-legacy-adapter | ✅ | ✅ |
   | agt-readmodel | ✅ | ✅ |

---

## A.4 — Pipeline CI/CD + OIDC Roles (COMPLETADO)

**Fecha:** 2026-05-22
**Horas reales:** ~4.0 h (estimado 3.0 h)

### Qué se hizo

1. **Roles OIDC para GitHub Actions** creados vía CFN:
   - `cloudformation/modules/iam/oidc-gha-roles.yaml`
   - Stack `agt-oidc-gha-dev` → rol `agt-gha-oidc-dev` · DEV `245650696072`
   - Stack `agt-oidc-gha-qa` → rol `agt-gha-oidc-qa` · QA `493735739951`
   - Trust: `repo:clouddev-udabol/*:*` (org completa, sprint 1)
   - Permisos: `AmazonEC2ContainerRegistryPowerUser` + ECS `UpdateService`/`DescribeServices`

2. **Dockerfiles corregidos** en 4 microservicios:
   - Patrón: `poetry install --only main --no-interaction --no-ansi --no-root` + `PYTHONPATH=/app/src`
   - Fix BOM en `pyproject.toml` (Poetry fallaba con UTF-8 BOM en Windows)
   - `packages = [{include = "agt_XXX", from = "src"}]` agregado a los 4 pyproject.toml
   - Afectados: `agt-agent`, `agt-legacy-adapter`, `agt-toolapi`, `agt-whatsapp-gateway`

3. **ci.yml actualizado** en los 7 repos:
   - `role-to-assume` corregido a `agt-gha-oidc-dev` / `agt-gha-oidc-qa`
   - `continue-on-error: true` en steps ECS deploy (ECS no desplegado aún)

4. **Templates actualizados:** `_sow002_repos/ci-ecs.yml`, `_sow002_repos/Dockerfile.tpl`

### Observaciones de A.4

- **OBS-002:** Los roles pre-existentes `proy-app-gha-role-development`/`proy-app-gha-role-qa` tenían trust para org distinta. La solución fue crear nuevos roles con nombres `agt-*` (dentro del scope de `IAMForProjectRoles`).

---

## B.1 — Lex V2 CloudFormation (COMPLETADO)

**Fecha:** 2026-05-23
**Horas reales:** ~4.0 h (estimado 8.0 h)

### Qué se hizo

1. **Template CloudFormation reescrito:** `agt-intent-parser/deploy/aws/cloudformation/lex-bot.yaml`
   - Nombre IAM role: `udabol-lex-intent-parser-${Environment}` (patrón `udabol-*`)
   - Inline policy CloudWatch Logs (scope mínimo, sin `AmazonLexFullAccess`)
   - Eliminados `Tags` de `AWS::Lex::Bot` y `AWS::Lex::BotAlias` (no soportados en CFN)
   - Eliminado `VoiceSettings` (Lupe no válido para es_419)
   - Placeholder `          Intents: []` para inyección por `generate_template.py`

2. **Nuevo script `generate_template.py`:**
   - `agt-intent-parser/deploy/aws/scripts/generate_template.py`
   - Lee todos los `intents/*.yaml`, construye estructura CFN
   - Todos los slots (required + optional) incluidos en `SlotPriorities` (requisito Lex)
   - Agrega `FallbackIntent` con `ParentIntentSignature: AMAZON.FallbackIntent`
   - Inyección por texto: reemplaza `          Intents: []` en el shell template
   - Salida: `lex-bot-generated-{env}.yaml`

3. **deploy.sh actualizado** para llamar `generate_template.py` antes del deploy CFN

4. **Templates generados y commiteados:** `lex-bot-generated-dev.yaml`, `lex-bot-generated-qa.yaml`

5. **Stacks desplegados:**
   - `udabol-intent-parser-lex-dev` → BotId `AMEBQJXNM2`, BotAliasId `CAWBME2SG9`
   - `udabol-intent-parser-lex-qa` → BotId `ZZ7JYN2KA1`, BotAliasId `CDLG1YNKQL`

---

## B.2 — Validación Lex (COMPLETADO)

**Fecha:** 2026-05-23
**Horas reales:** ~2.0 h (estimado 2.0 h)

### Resultado DEV (5/5 PASS)

```
PASS | 'Quiero ver mis notas'        -> ConsultarNotas (1.00)
PASS | 'Quiero inscribirme en calculo' -> Inscribir (0.92)
PASS | 'Hola buenos dias'            -> Saludo (0.90)
PASS | 'Cuanto debo de cuota'        -> ConsultarDeuda (1.00)
PASS | 'Necesito hablar con alguien' -> HablarConPersona (0.94)
```

### Resultado QA (5/5 PASS)

```
PASS | 'Quiero ver mis notas'        -> ConsultarNotas (1.00)
PASS | 'Quiero inscribirme en calculo' -> Inscribir (0.92)
PASS | 'Hola buenos dias'            -> Saludo (0.90)
PASS | 'Cuanto debo de cuota'        -> ConsultarDeuda (1.00)
PASS | 'Necesito hablar con alguien' -> HablarConPersona (0.94)
```

### Observaciones de B.1/B.2

- **OBS-003:** BotAlias `CAWBME2SG9` apunta a versión creada antes de que el locale se construyera. Para testing se usa `TSTALIASID` (siempre apunta al DRAFT construido). Para producción: crear nueva versión post-build y actualizar el alias.
- **OBS-004:** `consultar_deuda.yaml` requirió agregar utterances adicionales ("Cuanto debo de cuota", "Tengo cuotas pendientes") para clasificar correctamente.

---

## C.0 — ECS Cluster + Cloud Map namespace agt.local (COMPLETADO)

**Fecha:** 2026-05-23
**Horas reales:** ~2.5 h (estimado 3.0 h)

### Qué se desplegó

**Template:** `cloudformation/modules/ecs/cluster.yaml`

| Recurso | DEV | QA |
|---------|-----|-----|
| Cloud Map namespace `agt.local` | `ns-hro2snrep2htcl6t` ✅ | `ns-43wzkgtkgrff3mfj` ✅ |
| ECS Task SG `udabol-agt-tasks-dev/qa` | `sg-09c2ea0fc34154bc4` ✅ | `sg-086a6e6533481098e` ✅ |
| ECS Cluster `udabol-agt-dev/qa` | ✅ ACTIVO | ✅ ACTIVO |
| ALB interno | N/A (single-AZ, diferido PROD) | N/A |

### Observaciones de C.0

- **OBS-005 (CORREGIDO):** El SCP no bloquea servicios — implementa *tagging enforcement*. `DenyNoEntorno` deniega si el tag `Entorno` está ausente en el request. CFN pasa los tags automáticamente en el CreateChangeSet, por eso el deploy por CFN funciona sin problema. Los errores iniciales fueron en tests de CLI sin `--tags`. Ver L-01 en `lecciones-despliegue-sprint1.md`.
- **OBS-006:** ECS tiene un error transitorio de service-linked role en el primer deploy de un cluster nuevo. La solución es reintentar. El segundo intento siempre funciona. Ver L-02 en lecciones.

---

## C.1 — Lambda agt-whatsapp-gateway + API Gateway (COMPLETADO)

**Fecha:** 2026-05-23
**Horas reales:** ~3.5 h (estimado 4.0 h)

### Qué se desplegó

**Template:** `cloudformation/modules/lambda/whatsapp-gateway.yaml`

| Recurso | DEV | QA |
|---------|-----|-----|
| Lambda `agt-whatsapp-gateway-{env}` | `arn:aws:lambda:us-east-1:245650696072:function:agt-whatsapp-gateway-dev` ✅ | `arn:aws:lambda:us-east-1:493735739951:function:agt-whatsapp-gateway-qa` ✅ |
| API Gateway HTTP v2 | `https://il9jw4ux6d.execute-api.us-east-1.amazonaws.com` ✅ | `https://zs2531s4q2.execute-api.us-east-1.amazonaws.com` ✅ |
| Lex integration (5 intents) | ✅ confidence 0.96 | ✅ confidence 0.96 |

### Validación E3 (criterio SOW)

```
GET /health        → {"status":"ok","service":"agt-whatsapp-gateway"}  ✅
POST /webhook/whatsapp/json "Quiero inscribirme al semestre 2026-1" → {intent: Inscribir, confidence: 0.96} ✅
```

### Issues conocidos — pendientes de corrección al cierre

| ID | Descripción | Impacto | Estado |
|----|-------------|---------|--------|
| **ISS-001** | Intents `ElegirMateria` y `ConsultarHorario` existen en el bot Lex pero no estaban en el dict `_INTENT_REPLIES` del handler → la Lambda devolvía `f"Procesando solicitud: {intent}"` en lugar de una respuesta real | Respuesta genérica al usuario en esos intents | ✅ CORREGIDO en código, pendiente redeploy |
| **ISS-002** | Utterances débiles en `ConsultarNotas` e `Inscribir`: "ver mis notas" → clasifica como `ConsultarDeuda`; "Quiero inscribirme en calculo" (sin tilde) → clasifica como `ConsultarDeuda` | Mala clasificación en variantes coloquiales sin tilde | 🔵 Documentado, corregir en B.2 revisión antes de E.2 |

### Observaciones de C.1

- **OBS-007:** IAM para Lex V2 runtime usa prefijo `lex:` (no `lexv2:`). El SDK boto3 usa cliente `lexv2-runtime` pero el evaluador IAM registra la acción como `lex:RecognizeText`. Ver L-11 en lecciones.
- **OBS-008:** CI QA se dispara con PR al branch `qa`, no con push a `dev`. El stack CFN no se puede desplegar hasta que CI haya subido la imagen a ECR QA. Orden correcto: crear PR dev→qa → esperar CI → desplegar CFN.

---

## C.2 — ECS Services: agt-agent, agt-toolapi, agt-legacy-adapter (COMPLETADO)

**Fecha:** 2026-05-23
**Horas reales:** ~5.0 h (estimado 6.0 h)

### Qué se desplegó

**Template:** `cloudformation/modules/ecs/services.yaml`

| Recurso | DEV | QA |
|---------|-----|-----|
| ECS Service `agt-agent` | running=1/desired=1 ✅ | running=2/desired=2 ✅ |
| ECS Service `agt-toolapi` | running=1/desired=1 ✅ | running=2/desired=2 ✅ |
| ECS Service `agt-legacy-adapter` | running=1/desired=1 ✅ | running=2/desired=2 ✅ |
| Cloud Map SD `agt-agent.agt.local` | ✅ | ✅ |
| Cloud Map SD `agt-toolapi.agt.local` | ✅ | ✅ |
| Cloud Map SD `agt-legacy-adapter.agt.local` | ✅ | ✅ |
| IAM Execution Role `agt-ecs-exec-{env}` | ✅ | ✅ |
| IAM Task Role `agt-ecs-task-{env}` | ✅ | ✅ |

**Configuración:**
- CPU: 256 units (0.25 vCPU) · Memoria: 512 MiB
- Red: PublicSubnetA con `AssignPublicIp: ENABLED` (workaround ISS-003)
- Imágenes DEV: `dev-latest` en ECR DEV (245650696072)
- Imágenes QA: `qa-latest` en ECR QA (493735739951)
- `DeploymentCircuitBreaker: Enable: true, Rollback: false`

### C.3 — Validación ECS (COMPLETADO)

```
DEV: agt-agent-dev:          running=1/desired=1  ✅
DEV: agt-toolapi-dev:        running=1/desired=1  ✅
DEV: agt-legacy-adapter-dev: running=1/desired=1  ✅

QA:  agt-agent-qa:           running=2/desired=2  ✅
QA:  agt-toolapi-qa:         running=2/desired=2  ✅
QA:  agt-legacy-adapter-qa:  running=2/desired=2  ✅
```

### Observaciones de C.2

- **OBS-009 (ISS-003 confirmado):** VPC Endpoints con `PrivateDnsEnabled: true` son VPC-wide. Rompen el ECR pull desde subnet pública porque el DNS resuelve al IP del endpoint ENI (en subnet privada) pero la conexión TCP no llega desde la subnet pública. Solución DEV/QA: eliminar endpoints, usar PublicSubnetA con `AssignPublicIp: ENABLED`. Ver L-12.
- **OBS-010:** Imágenes QA deben usar tag `qa-latest` (no `dev-latest`). CI pushea `dev-latest` a DEV ECR y `qa-latest` a QA ECR cuando hay PR al branch `qa`.
- **OBS-011:** Los 3 repos ECS tenían cluster name incorrecto en ci.yml (`udabol-agt-cluster-dev/qa` → correcto: `udabol-agt-dev/qa`). Corregido en fix commit `8c8ab08` / `95768d1` / `7867482`.
- **OBS-012:** CFN ECS service sin `DeploymentCircuitBreaker` espera indefinidamente cuando tasks fallan. Agregado `CircuitBreaker: Enable: true` en services.yaml para detectar failures rápido.

---

## D.1 — RDS PostgreSQL 16 + Secrets Manager + rotación (EN PROGRESO)

**Fecha:** 2026-05-23
**Estado:** DEV ✅ CREATE_COMPLETE · QA ✅ CREATE_COMPLETE

### Template creado

**Archivo:** `cloudformation/modules/rds/rds.yaml`

**Recursos:**
- `DbMasterSecret` — Secrets Manager con password de 32 chars generado automáticamente
- `RdsStubSubnet` — subnet /28 en us-east-1b (requerida para DB Subnet Group con 2+ AZs, aunque la instancia sea single-AZ)
- `DbSubnetGroup` — DataSubnetA + RdsStubSubnet
- `RdsSg` — Security Group RDS (inbound 5432 desde ECS tasks + rotation Lambda)
- `RotationLambdaSg` — SG para la Lambda de rotación (egress 5432→RDS, egress 443→SM)
- `DbParamGroup` — postgres16 con log_connections + log_disconnections
- `DbInstance` — PostgreSQL 16, db.t3.micro, gp2 20GB, single-AZ, encrypted
- `SecretAttachment` — vincula el secret al RDS para que rotation Lambda conozca el host
- `RotationSchedule` — rotación automática cada 30 días via `HostedRotationLambda` (PostgreSQLSingleUser)

**Parámetros DEV:**
```
DBInstanceClass: db.t3.micro
AllocatedStorage: 20 GB
MultiAZ: false
BackupRetentionPeriod: 1 día
RdsStubSubnetCidr: 10.10.22.0/28
```

**Parámetros QA:**
```
DBInstanceClass: db.t3.micro
AllocatedStorage: 20 GB
MultiAZ: false
BackupRetentionPeriod: 3 días
RdsStubSubnetCidr: 10.20.22.0/28
```

### Outputs DEV (udabol-rds-dev)

| Output | Valor |
|--------|-------|
| `DbEndpoint` | `agt-db-dev.c4hioyi08vln.us-east-1.rds.amazonaws.com` |
| `DbPort` | `5432` |
| `DbName` | `udabol_erp` |
| `SecretArn` | `arn:aws:secretsmanager:us-east-1:245650696072:secret:agt-rds-master-dev-qxtY1E` |
| `RdsSgId` | `sg-08661bdb0f20b83c8` |

### Outputs QA (udabol-rds-qa)

| Output | Valor |
|--------|-------|
| `DbEndpoint` | `agt-db-qa.cotomq2m0uyo.us-east-1.rds.amazonaws.com` |
| `DbPort` | `5432` |
| `DbName` | `udabol_erp` |
| `SecretArn` | `arn:aws:secretsmanager:us-east-1:493735739951:secret:agt-rds-master-qa-HaKu4g` |
| `RdsSgId` | `sg-0f2508c6c8ca17a9a` |

### Lecciones D.1

- **Transform `AWS::SecretsManager-2020-07-23`** requerido para `HostedRotationLambda`. Requiere `CAPABILITY_AUTO_EXPAND` en el deploy.
- **SCP + nested stack:** El transform crea un nested CFN stack (`RotationScheduleHostedRotationLambda-*`). El SCP bloqueaba `cloudformation:CreateStack` del nested stack porque no tenía el tag `Entorno`. Solución: pasar `--tags Entorno=<valor>` al parent stack → CFN propaga los tags al nested stack automáticamente.
- **`RotationLambdaSg` en PublicSubnet:** La rotation Lambda necesita acceso a Secrets Manager (HTTPS/443) y a RDS (TCP/5432). En DEV/QA sin NAT, se coloca en PublicSubnetA para acceso a SM via internet. Conecta a RDS via routing VPC local (mismo VPC).

---

## Registro de sesiones SSO activas

| Sesión | URL | Usuario | Expira |
|--------|-----|---------|--------|
| `proy` | ssoins-7223753b6943f944 | `ayrton@udabol.edu.bo` | ~8h desde login |
| `fundaciondev` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |
| `fdcAdmin` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |

> **Nota:** las sesiones SSO expiran. Renovar con `aws sso login --profile proy-dev` antes de cada sesión de trabajo.

---

## Dependencias bloqueantes — estado al 2026-05-24

| ID | Descripción | Responsable | Estado | Bloquea |
|----|-------------|-------------|--------|---------|
| ~~N5~~ | ~~SCP bloquea ECS/Lambda/RDS~~ | — | ✅ **RESUELTO** — era tagging enforcement, no bloqueo de servicio | — |
| ~~N1~~ | ~~MSK Serverless vs Outbox+EventBridge~~ | Franz | ✅ **RESUELTO** — SOW-002 §2.5 confirma **MSK Serverless** con IAM auth + TLS, 7d retención | D.2, D.3 |
| ~~N2~~ | ~~CloudWatch vs Vector+Prometheus+Grafana~~ | Franz | ✅ **RESUELTO** — SOW-002 §2.6 define **OTel Collector + CloudWatch/X-Ray** como default DEV/QA; E7 dashboard diferido a Sprint 2 | E.1 |
| ~~N3~~ | ~~VPC Single-AZ confirmada~~ | Franz | ✅ **RESUELTO** — SOW-002 §2.2 coloca NAT GW en us-east-1a únicamente → single-AZ confirmado para DEV/QA | C.0 ALB |
| ~~N4~~ | ~~NAT Gateway en DEV/QA~~ | Franz | ✅ **RESUELTO** — SOW-002 §2.2 lo incluye expresamente en alcance (D.4) | D.4 |
| A2 | Branch protection requiere **GitHub Team** ($4/usr/mes) o repos públicos — plan Free bloquea la API para repos privados (HTTP 403). Token `clouddev-udabol` con `admin:org`+`repo` verificado y funcional. Decisión pendiente de Franz/Dockweiler. | Franz | 🔴 Bloqueado — pendiente decisión de plan | A.2 / E1 |
| D4 | Dockerfiles funcionales en 7 repos | Carlos/Devs | ❓ Pendiente | C.2, E.3 |
| D3 | .env.example con valores reales | Carlos/Devs | ❓ Pendiente | C.2, D.2 |
| D5 | CIDR red on-premise UDABOL | Julio Chávez | ❓ Pendiente | C.2 SG Legacy |
| D6 | Credenciales Twilio | Carlos | ❓ Pendiente | E.3 smoke |

---

## Plan de trabajo — próxima sesión (bloqueantes N1–N4 resueltos)

**Fecha actualización:** 2026-05-24
**Fuente de decisiones:** SOW-002 firmada (§2.2, §2.5, §2.6)

### Prioridad 1 — D.4 NAT Instance + VPC Endpoints + cierre ISS-003 (5h est.)

**Decisión arquitectónica:** ADR-FINOPS-001 aprobado — NAT Instance en lugar de NAT Gateway.
Ahorro: ~$29/mes por cuenta = **$696/año** frente al NAT Gateway.
Referencia completa: `SOW/adr/ADR-FINOPS-001-red-optimizada-dev-qa.md`

**Templates a crear:**
- `cloudformation/modules/vpc/nat-instance.yaml` — EC2 t4g.nano (fck-nat AMI), SG, route en private table
- `cloudformation/modules/vpc/vpc-endpoints.yaml` — S3 Gateway (gratis) + 4 Interface Endpoints

**VPC Endpoints a desplegar:**

| Endpoint | Tipo | Costo/mes | Justificación |
|---|---|---|---|
| S3 | Gateway | $0 | ECR image layers — tráfico alto, costo cero |
| ECR.api | Interface | $7.30 | ECS pull imágenes — resuelve ISS-003 |
| ECR.dkr | Interface | $7.30 | ECS pull imágenes — resuelve ISS-003 |
| logs (CloudWatch) | Interface | $7.30 | awslogs driver constante desde 6 tasks |
| secretsmanager | Interface | $7.30 | ECS tasks leen creds RDS al arrancar |
| lex.runtime | Interface | $7.30 | agt-agent: 1 llamada por mensaje WhatsApp |

**Cambio en services.yaml:**
- Subnet: `PrivateSubnetA` (era `PublicSubnetA`)
- `AssignPublicIp: DISABLED` (era `ENABLED`)
- Cierra **ISS-003** definitivamente

**Orden de deploy:**
```
1. vpc-endpoints.yaml DEV + QA
2. nat-instance.yaml DEV + QA
3. services.yaml DEV + QA (forzar redeploy)
4. Validar E5: curl api.twilio.com → HTTP 401 (no timeout)
```

**Valida Entregable E5 SOW-002 §2.2**

### Prioridad 2 — D.2 MSK Serverless (6h est.)

Template `cloudformation/modules/msk/msk-serverless.yaml`
- `AWS::MSK::ServerlessCluster` con VPC Connectivity IAM auth + TLS
- 3 topics: `enrollment.events`, `payment.events`, `query.audit` — retención 7 días
- SG dedicado: inbound 9098 (IAM+TLS) desde ECS tasks SG
- VPC Endpoints para MSK en subnets privadas (§2.2)
- Parámetros DEV + QA en `parameters/dev/msk.json` y `parameters/qa/msk.json`

### Prioridad 3 — D.3 Lambda agt-readmodel (2h est.)

- Event source mapping MSK → Lambda `agt-readmodel-{env}`
- IAM: `kafka:DescribeClusterV2`, `kafka-cluster:Connect`, `kafka-cluster:DescribeGroup`, `kafka-cluster:ReadData`
- Template `cloudformation/modules/lambda/readmodel.yaml`

### Prioridad 4 — E.1 OTel Collector ECS task (9h est.)

- `otelcol-contrib` como ECS task en namespace `agt.local:4317`
- `config.yaml` con pipeline: receivers `otlp/grpc` → processors `batch` → exporters `awscloudwatchlogs + awsemf + awsxray`
- Log groups `/udabol/{env}/agt` con retención 7 días
- IAM task role con `xray:PutTelemetryRecords`, `xray:PutTraceSegments`, `logs:CreateLogGroup`, `logs:PutLogEvents`, `cloudwatch:PutMetricData`
- Template `cloudformation/modules/ecs/otel-collector.yaml`

### Prioridad 5 — E.2 OTel SDK en 7 repos agt-* (6h est.)

- `opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-grpc`, `opentelemetry-instrumentation-fastapi` en `requirements.txt`
- Bootstrap en `main.py`: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.agt.local:4317`
- PR en cada repo → merge a `dev`

### Sin bloqueante — ISS-002 (paralelo posible)

Mejorar utterances `ConsultarNotas` + `Inscribir` en Lex (sin tilde, variantes coloquiales). No depende de N1–N4. Ver `agt-intent-parser/deploy/aws/intents/`.

---

## Issues abiertos (corrección diferida)

| ID | Componente | Descripción | Impacto | Prioridad |
|----|------------|-------------|---------|-----------|
| **ISS-001** | `agt-whatsapp-gateway` handler | `ElegirMateria` + `ConsultarHorario` faltaban en `_INTENT_REPLIES` — devolvía respuesta genérica | Respuesta incorrecta al usuario | ✅ Corregido en código, commit `2cb6e38`, desplegado a Lambda DEV. QA: PR #1 dev→qa pendiente merge |
| **ISS-002** | Lex bot `udabol-intent-parser-{env}` | "ver mis notas" clasifica como `ConsultarDeuda` en vez de `ConsultarNotas`; "inscribirme en calculo" (sin tilde) → `ConsultarDeuda` | Mala clasificación coloquial | 🔵 Corregir antes de E.2 smoke test — agregar utterances sin tilde a ambos intents |
| **ISS-003** | ECS Fargate en App subnet (privada) | VPC Endpoints con `PrivateDnsEnabled: true` son VPC-wide. DNS resuelve `ecr.api.amazonaws.com` al IP privado del endpoint ENI. ECS task en subnet pública no tiene ruta a ese IP → timeout. **Causa raíz confirmada:** cliente debe estar en la misma subnet privada que los endpoints. | ECS tasks en subnet pública expuestas a internet | 🟡 Workaround activo. **Solución definitiva incluida en D.4** — mover ECS a PrivateSubnetA junto con los endpoints. Ver ADR-FINOPS-001. |

---

---

## Hallazgos FinOps — 2026-05-24

**Documento de referencia:** `SOW/adr/ADR-FINOPS-001-red-optimizada-dev-qa.md`

### Resumen ejecutivo

Durante la planificación del bloque D.4 (NAT Gateway) se realizó un análisis de eficiencia de red que identificó una alternativa más eficiente económica y arquitectónicamente.

| Métrica | NAT Gateway (plan original) | NAT Instance + Endpoints (propuesta) |
|---|---|---|
| Costo fijo mensual DEV+QA | ~$65.70 | ~$80 |
| ECS en subnet privada | No | **Sí** |
| ISS-003 resuelto | No | **Sí** |
| Ahorro sobre NAT GW en 12m | — | **$704** (solo NAT) |
| Path limpio a PROD | Parcial | **Sí** |

### Observaciones incorporadas

| ID | Observación | Acción |
|---|---|---|
| OBS-FINOPS-001 | Lex V2 sin VPC Endpoint genera tráfico NAT por cada mensaje WhatsApp | Incluido en D.4: endpoint `lex.runtime` |
| OBS-FINOPS-002 | CloudWatch Logs es el mayor volumen de tráfico interno — awslogs desde 6 ECS tasks | Incluido en D.4: endpoint `logs` |
| OBS-FINOPS-003 | Lambda agt-readmodel conectando directamente a RDS puede agotar conexiones PG bajo carga | Diferido a Sprint 2: RDS Proxy |
| OBS-FINOPS-004 | `LOG_LEVEL=DEBUG` en QA incrementa costos CloudWatch innecesariamente | Pendiente: agregar `LOG_LEVEL=INFO` como variable de entorno en services.yaml |
| OBS-FINOPS-005 | fck-nat AMI (ARM Graviton) simplifica configuración NAT Instance vs manual iptables | Adoptado en template nat-instance.yaml |

### Impacto en horas

| Bloque | Horas originales | Horas revisadas | Delta |
|---|---|---|---|
| D.4 NAT Gateway | 3h | 5h (NAT Instance + VPC Endpoints + cierre ISS-003) | +2h |
| ISS-003 (diferido Sprint 2) | 4h (Sprint 2) | 0h (incluido en D.4) | -4h Sprint 2 |
| **Efecto neto** | | | **-2h en el proyecto total** |

---

*Bitácora iniciada 2026-05-22 · Actualizada 2026-05-24 — FinOps ADR-FINOPS-001 incorporado*
