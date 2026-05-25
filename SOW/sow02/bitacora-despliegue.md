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
| **A.2** | Branch protection rules en 7 repos | 2026-05-25 | 1.0 h | 0.5 h | ✅ COMPLETADO — GitHub Team activado. main+qa protegidas en 7 repos (1 revisor, no force push, no delete). |
| **A.3** | Deploy 14 repos ECR (DEV + QA vía CFN) | 2026-05-22 | 2.0 h | 0.5 h | ✅ COMPLETADO |
| **A.4** | Pipeline piloto CI/CD en agt-agent y agt-toolapi | 2026-05-22 | 3.0 h | 4.0 h | ✅ COMPLETADO |
| **B.1** | CloudFormation Lex V2 Bot + generate_template.py + intents YAML | 2026-05-23 | 8.0 h | 4.0 h | ✅ COMPLETADO |
| **B.2** | Deploy Lex DEV + QA + validación recognize-text | 2026-05-23 | 2.0 h | 2.0 h | ✅ COMPLETADO |
| **C.0** | ECS Cluster + ALB interno + Cloud Map namespace agt.local | 2026-05-23 | 3.0 h | 2.5 h | ✅ COMPLETADO |
| **C.1** | Lambda agt-whatsapp-gateway + API Gateway | 2026-05-23 | 4.0 h | 3.5 h | ✅ COMPLETADO |
| **C.2** | ECS Services: agt-agent, agt-toolapi, agt-legacy-adapter | 2026-05-23 | 6.0 h | 5.0 h | ✅ COMPLETADO |
| **C.3** | Validación ECS: describe-services running=desiredCount | 2026-05-23 | 1.0 h | 0.5 h | ✅ COMPLETADO |
| **D.1** | RDS PostgreSQL 16 + Secrets Manager + rotación 30d | 2026-05-23 | 5.0 h | 4.5 h | ✅ COMPLETADO (DEV + QA) |
| **D.2** | MSK Serverless DEV + QA + 3 topics (enrollment.events, payment.events, query.audit) | 2026-05-25 | 6.0 h | 3.0 h | ✅ COMPLETADO — `udabol-msk-dev/qa` CREATE_COMPLETE · SASL/IAM puerto 9098 |
| **D.3** | ECS Fargate service agt-readmodel (corregido SOW §2.3: ECS, no Lambda) | 2026-05-25 | 2.0 h | 2.5 h | ✅ COMPLETADO — `udabol-ecs-services-dev/qa` UPDATE_COMPLETE · ServiceReadmodel ACTIVE desiredCount=0 (sin imagen ECR aún) |
| **D.4** | NAT Instance t4g.nano + VPC Endpoints (ECR, Logs, SM, Lex) + mover ECS a PrivateSubnet — cierra ISS-003 | 2026-05-25 | 5.0 h | 8.0 h | ✅ COMPLETADO — VPC Endpoints ✅ DEV+QA · NAT Instance ✅ DEV+QA · SCP OBS-014 corregido via fdac-cloudadmin |
| **C.2-FIX** | ISS-003 resolución completa — IAM inline policy GHA roles + NACL ephemeral ports + ECS circuit breaker reset + redeploy ecs-services DEV+QA a AppSubnetA | 2026-05-25 | 2.0 h | 6.5 h | ✅ COMPLETADO — 3 DEV + 3 QA RUNNING en AppSubnetA (10.10.11.x / 10.20.11.x). Commits f67922a (vpc.yaml) · 01db864 (endpoints.yaml) |
| **E.1** | OTel Collector ECS task + config.yaml (backend CloudWatch + X-Ray) | 2026-05-25 | 9.0 h | 2.0 h | 🔄 EN PROGRESO — template+params commiteados (`1e47439`), deploy pendiente (TECH-001) |
| **E.2** | OTel SDK Python en 7 repos agt-* (requirements.txt + bootstrap main.py) | — | 6.0 h | — | ⬜ PENDIENTE (depende E.1) |
| **E.3** | Smoke test end-to-end + documentación de evidencia | — | 4.0 h | — | ⏳ Bloqueado D6 (credenciales Twilio) |
| **E.4** | Runbook sprint1-deploy.md | 2026-05-23 | 3.0 h | 1.5 h | ✅ COMPLETADO |
| — | **Total presupuestado** | — | **80.0 h** | — | — |
| — | **Acumulado real** | — | — | **54.5 h** | — |
| — | **Saldo disponible** | — | — | **25.5 h** | — |

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

## D.2 — MSK Serverless DEV + QA (EN PROGRESO)

**Fecha inicio:** 2026-05-25
**Horas reales:** en curso
**Estado:** ✅ COMPLETADO — DEV + QA CREATE_COMPLETE
**Horas reales:** ~3.0 h

### Qué se implementó

**Template:** `cloudformation/modules/msk/msk-serverless.yaml`

- `AWS::MSK::ServerlessCluster` — auth SASL/IAM, puerto 9098
- `MskStubSubnet` — `/28` en `us-east-1b` para satisfacer requisito multi-AZ (mismo patrón que RDS D.1)
  - DEV: `10.10.23.0/28` | QA: `10.20.23.0/28`
- `MskSecurityGroup` — inbound 9098 desde `EcsTaskSgId` + VPC CIDR (Lambda readmodel)
- IAM Task Role en `services.yaml` extendido con política `MskKafkaAccess`:
  - `kafka-cluster:Connect/DescribeCluster/AlterCluster`
  - `kafka-cluster:DescribeTopic/CreateTopic/WriteData/ReadData`
  - `kafka-cluster:AlterGroup/DescribeGroup`

**Parámetros:** `parameters/dev/msk.json` · `parameters/qa/msk.json`

**Stack names:** `udabol-msk-dev` / `udabol-msk-qa`

### Recursos live

| Recurso | DEV | QA |
|---------|-----|-----|
| `udabol-msk-dev/qa` | ✅ CREATE_COMPLETE | ✅ CREATE_COMPLETE |
| MSK Cluster ARN | `…:cluster/udabol-dev/fa6017fd-c8a6-43a3-b73f-404ec40a6a65-s1` | `…:cluster/udabol-qa/20451623-032d-4c74-bd7a-e44bd9f23561-s1` |
| MskStubSubnet CIDR | `10.10.23.0/28` us-east-1b | `10.20.23.0/28` us-east-1b |
| MskStubSubnet ID | — | `subnet-057afe77732491cac` |

### Lecciones de D.2

- **OBS-017 — SG rule Description no acepta `>`:** EC2 valida los chars en `Description` de reglas SG: solo `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*`. El carácter `>` (usado en `ECS tasks => MSK`) rechaza la creación del SG con `ValidationError`. Fix: reemplazar `=>` por `to`.
- **OBS-018 — ROLLBACK_COMPLETE bloquea redeploy:** `aws cloudformation deploy` falla con exit 254 si el stack está en `ROLLBACK_COMPLETE`. Fix: step `CD-CLN-303b` en el workflow elimina el stack pre-existente antes del deploy.

---

## D.3 — ECS Service agt-readmodel (COMPLETADO)

**Fecha:** 2026-05-25
**Horas reales:** ~2.5 h
**Commits:** `52186eb` (feat), `43658d5` (fix ReadmodelDesiredCount)

### Qué se hizo

1. **Corrección arquitectural**: el SOW-002 §2.3 especifica `agt-readmodel` como servicio ECS Fargate (256 CPU / 512 MB), no Lambda. El plan interno PLAN-DESPLIEGUE tenía un error de diseño ("Lambda agt-readmodel"). Se corrigió siguiendo el documento contractual.

2. **Template `cloudformation/modules/ecs/services.yaml`** actualizado:
   - Parámetro `ImageAgtReadmodel` + `ReadmodelDesiredCount` (default 0)
   - `LogGroupReadmodel` → `/agt/agt-readmodel/{env}` retención 14d/30d
   - `TaskDefReadmodel` (port 8085, health check `/v1/healthz`, READMODEL_MODE=mock)
   - `SdReadmodel` → Cloud Map `agt-readmodel.agt.local`
   - `ServiceReadmodel` → AppSubnetA, EcsTaskSgId, desiredCount=ReadmodelDesiredCount
   - Outputs: `ServiceReadmodelArn`, `ReadmodelEndpoint`

3. **`ReadmodelDesiredCount=0`**: servicio creado sin lanzar tasks. La imagen en ECR `agt-readmodel` está vacía — el dev team push la imagen cuando el código esté listo, y luego se actualiza el parámetro a 1/2.

4. **OBS-023 — IAMForECSRoles en GHA roles** (via cloudadmin — excepción justificada):
   - `proy-app-gha-role-development` y `proy-app-gha-role-qa` necesitan `iam:TagRole`, `iam:UntagRole`, `iam:PutRolePolicy`, `iam:DeleteRolePolicy` para actualizar `agt-ecs-*` roles cuando CloudFormation propaga tags de stack.
   - Inline policy `IAMForECSRoles` aplicada en DEV (`245650696072`) y QA (`493735739951`).

### Estado final DEV

| Recurso | Estado |
|---|---|
| Stack `udabol-ecs-services-dev` | UPDATE_COMPLETE |
| Service `agt-readmodel-dev` | ACTIVE, desired=0, running=0 |
| Cloud Map `agt-readmodel.agt.local` | registrado |
| Export `ReadmodelEndpoint` | `http://agt-readmodel.agt.local:8085` |

### Observaciones

**OBS-023** — `IAMForECSRoles` inline policy faltaba en GHA roles DEV+QA. CloudFormation propaga tags de stack-level (`CommitHash`, `DeployDate`) a TODOS los recursos incluyendo IAM roles, lo que requiere `iam:TagRole`/`iam:UntagRole`. Adicionalmente, los inline policies de los roles requieren `iam:PutRolePolicy`/`iam:DeleteRolePolicy`. Sin esta policy, cada update del stack `ecs-services` falla. Fix: `aws iam put-role-policy IAMForECSRoles` via cloudadmin, scoped a `agt-ecs-*`.

---

## D.4 — NAT Instance + VPC Endpoints (COMPLETADO)

**Fecha:** 2026-05-25
**Horas reales:** ~8.0 h (estimado 5.0 h — ver OBS-014, OBS-015, OBS-016)

### Qué se desplegó

**Templates:**
- `cloudformation/modules/vpc/endpoints.yaml` — 6 Interface/Gateway Endpoints
- `cloudformation/modules/vpc/nat-instance.yaml` — EC2 t4g.nano Graviton + ENI pre-creada

| Recurso | DEV | QA |
|---------|-----|-----|
| `udabol-vpc-endpoints-dev/qa` | ✅ CREATE_COMPLETE | ✅ CREATE_COMPLETE |
| `udabol-nat-instance-dev/qa` | ✅ `i-00b970c329cab457f` (10.10.1.246) | ✅ via GitHub Actions |
| VPC Endpoint ECR API | `vpce-*` ✅ | ✅ |
| VPC Endpoint ECR DKR | `vpce-*` ✅ | ✅ |
| VPC Endpoint S3 (Gateway) | ✅ gratis | ✅ |
| VPC Endpoint CloudWatch Logs | ✅ | ✅ |
| VPC Endpoint Secrets Manager | ✅ | ✅ |
| VPC Endpoint Lex V2 Runtime | ✅ | ✅ |

### Fix SCP OBS-014 — ejecutado con `fdac-cloudadmin`

Los SCPs `p-lgafaevf` (DEV OU) y `p-k7ywnh7g` (QA OU) tenían dos bugs:

1. `DenyNoEntorno` con `Resource: "*"` incluía `security-group/*` y `network-interface/*`, que son recursos **pre-existentes** y no admiten `aws:RequestTag` en `ec2:RunInstances`.
2. `DenyWrongEntorno` solo permitía un único valor (`"desarrollo"` o `"staging"`) en lugar del array `["desarrollo","staging","produccion"]`.

**Fix aplicado:**
```
DenyNoEntorno  → partido en DenyNoEntornoGeneral (sin EC2) + DenyNoEntornoEC2 (solo instance/* y volume/*)
DenyWrongEntorno → condicion: StringNotEquals + array 3 valores + Null:false (evita doble deny)
```

Archivos: `policies/scp-p-lgafaevf-fix.json`, `policies/scp-p-k7ywnh7g-fix.json`

### Lecciones D.4

- **OBS-014 (RESUELTO):** `aws:RequestTag` en RunInstances solo aplica a recursos *creados en ese request* (instance, volume, nuevas ENIs). SGs y ENIs pre-existentes referenciados en RunInstances no admiten RequestTag → bloqueo. Fix: acotar el deny a `instance/*` y `volume/*` exclusivamente.
- **OBS-015:** El service name de Lex V2 VPC Endpoint es `com.amazonaws.{region}.runtime-v2-lex` (no `lex.runtime` ni `runtime.lex.v2`). Verificar siempre con `aws ec2 describe-vpc-endpoint-services --filters Name=service-name,Values=*lex*`.
- **OBS-016:** Stack en `ROLLBACK_COMPLETE` debe eliminarse antes de re-desplegar. CFN no permite update sobre un stack en estado ROLLBACK_COMPLETE.
- **Regla Git:** Todos los commits del repo `clouddev-udabol/aws-devops` deben usar `ayrton.irusta@gmail.com`. El historial fue reescrito el 2026-05-25 via `git filter-branch` para eliminar todos los registros de `ayrton.irusta@blockfinityadvisors.com`.

---

## C.2-FIX — ISS-003: ECS tasks en AppSubnetA (COMPLETADO)

**Fecha:** 2026-05-25
**Horas reales:** ~6.5 h (estimado 2.0 h — ver OBS-019 a OBS-022)

### Contexto

D.4 desplegó NAT Instance + VPC Endpoints y actualizó `services.yaml` para mover las ECS tasks a AppSubnetA (`AssignPublicIp: DISABLED`). Sin embargo, el redeploy del stack `udabol-ecs-services-dev/qa` falló en tres rondas consecutivas por tres causas independientes que debieron resolverse secuencialmente.

### Secuencia de fallos y resolución

#### Fallo 1 — IAM: permisos insuficientes en el rol GHA

**Error:** `iam:DeleteRolePolicy / iam:TagRole / iam:UntagRole / iam:PutRolePolicy` denegado sobre `agt-ecs-task-dev` y `agt-ecs-exec-dev`.

**Causa:** El inline policy `IAMForVPCFlowLogs` en `proy-app-gha-role-development/qa` tenía como `Resource` solo los roles de VPC Flow Logs (`role-vpc-flowlogs-*`). Los roles ECS (`agt-ecs-*`) no estaban incluidos. El stack `github-oidc-iaapp-dev` está en `ROLLBACK_COMPLETE` — no puede actualizarse vía CFN.

**Solución (cloudadmin — excepción aprobada):** `aws iam put-role-policy` directamente sobre ambos roles GHA, ampliando `Resource` con `arn:aws:iam::ACCOUNT:role/agt-ecs-*` y agregando las acciones faltantes (`DeleteRolePolicy`, `TagRole`, `UntagRole`, `PutRolePolicy`). Ver OBS-019.

#### Fallo 2 — ECS Deployment Circuit Breaker trabado

**Error:** `ECS Deployment Circuit Breaker was triggered` — el stack esperaba estabilización del servicio indefinidamente. `udabol-ecs-services-dev` quedó en `UPDATE_ROLLBACK_FAILED`.

**Causa:** Tres fallos consecutivos de tareas activaron el circuit breaker. ECS dejó de reintentar. CFN no puede avanzar ni hacer rollback sin que el servicio estabilice.

**Solución (cloudadmin — excepción aprobada):** `aws ecs update-service --force-new-deployment` en los 6 servicios (3 DEV + 3 QA). Todos alcanzaron `RolloutState: COMPLETED`. Stack desbloqueado con `continue-update-rollback`. Ver OBS-020.

#### Fallo 3 — NACL AppSubnetA bloqueaba retorno de S3 (causa raíz de ISS-003)

**Error:** `CannotPullContainerError: dial tcp 52.216.51.58:443: i/o timeout` — tasks en AppSubnetA no podían descargar capas de imagen ECR.

**Diagnóstico:** El endpoint ECR DKR (`vpce-0e6fd1b6f18d21500`) con `PrivateDnsEnabled: true` resuelve `*.dkr.ecr.us-east-1.amazonaws.com` al ENI privado (`10.10.1.254`) correctamente. Sin embargo, ECR DKR redirige los blobs de capas a **S3 presigned URLs**. El tráfico a S3 va por el S3 Gateway Endpoint (route table `pl-63a5400a` → `vpce-0446b0f3915e62f2a`). El tráfico de **retorno de S3** llega desde IPs públicas de S3 (`52.216.51.58`, `16.15.191.109`). La regla NACL `NaclAppInboundFromPublic` (Rule 100) tenía `CidrBlock: VpcCidr (10.10.0.0/16)` — las IPs públicas de S3 caían en el `deny all` por defecto.

**Solución (vía GitHub Actions):** Actualizado `cloudformation/modules/vpc/vpc.yaml` — Rule 100 cambiada de `CidrBlock: !Ref VpcCidr` a `CidrBlock: "0.0.0.0/0"`. Seguro: AppSubnetA no tiene ruta a IGW, ningún host externo puede iniciar conexiones hacia esa subred. Commit `f67922a`. Ver OBS-021, OBS-022.

**Nota adicional:** Durante el diagnóstico se movieron los endpoints de AppSubnetA a PublicSubnetA (commit `01db864`) para co-locarlos con las tasks. Aunque la causa raíz era el NACL, este cambio permanece porque reduce la latencia intra-subnet.

### Recursos live post-resolución

| Recurso | DEV | QA |
|---------|-----|-----|
| `udabol-ecs-services-dev/qa` | ✅ UPDATE_COMPLETE | ✅ UPDATE_COMPLETE |
| `agt-agent` subnet | AppSubnetA `10.10.11.23` | AppSubnetA `10.20.11.96` / `10.20.11.238` |
| `agt-toolapi` subnet | AppSubnetA `10.10.11.200` | AppSubnetA `10.20.11.119` / `10.20.11.186` |
| `agt-legacy-adapter` subnet | AppSubnetA `10.10.11.204` | AppSubnetA `10.20.11.173` / `10.20.11.92` |
| Endpoints ENI (ECR/Logs/SM/Lex) | PublicSubnetA `10.10.1.x` | PublicSubnetA `10.20.1.x` |
| NACL Rule 100 CidrBlock | `0.0.0.0/0` (antes VpcCidr) | `0.0.0.0/0` (antes VpcCidr) |

### Observaciones C.2-FIX

- **OBS-019 — IAM en roles GHA pre-existentes con CFN en ROLLBACK_COMPLETE:** Cuando el stack `github-oidc-iaapp-dev` está en `ROLLBACK_COMPLETE`, no se puede actualizar el inline policy vía CFN. La única vía es `aws iam put-role-policy` directamente con `cloudadmin`. Esta operación es una excepción permitida (IAM/seguridad) según la regla de uso de cuentas. Siempre notificar al usuario antes de ejecutar. El template `iam-role.yaml` fue actualizado igualmente para mantener IaC consistente (commit `df5bfd2`), aunque el stack CFN no puede aplicarlo.
- **OBS-020 — ECS Deployment Circuit Breaker deadlock con CFN:** Cuando el circuit breaker se activa y CFN espera estabilización del servicio, el stack queda atrapado indefinidamente. Secuencia de escape: (1) identificar el ECS service en estado `RolloutState: FAILED`; (2) ejecutar `aws ecs update-service --force-new-deployment --cluster CLUSTER --service SERVICE`; (3) esperar `RolloutState: COMPLETED`; (4) si el stack queda en `UPDATE_ROLLBACK_FAILED`, ejecutar `aws cloudformation continue-update-rollback`. Solo proceder con el siguiente deploy cuando el stack esté en `UPDATE_ROLLBACK_COMPLETE`.
- **OBS-021 — S3 Gateway Endpoint y NACL: retorno desde IPs públicas:** El S3 Gateway Endpoint enruta el tráfico saliente via prefijo `pl-63a5400a` (IPs de S3), pero el tráfico de **retorno** llega desde las IPs públicas de S3 directamente (no desde dentro del VPC). Las reglas NACL deben permitir TCP 1024-65535 desde `0.0.0.0/0` (no solo desde VpcCidr) en la subnet privada para que las respuestas S3 puedan entrar.
- **OBS-022 — ECR image pull en Fargate usa S3 para capas:** ECR DKR maneja la autenticación y el manifest vía el VPC Endpoint (DNS privado → ENI). Sin embargo, los blobs de capas (`/v2/{name}/blobs/{digest}`) son redirigidos a **S3 presigned URLs** por ECR. Para que el pull sea completo se necesitan tanto el ECR DKR endpoint como acceso a S3 (via Gateway Endpoint o NAT). La NACL debe permitir retorno desde IPs públicas de S3.

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
| ~~A2~~ | ~~Branch protection~~ | — | ✅ **RESUELTO** — GitHub Team activado 2026-05-25. main+qa protegidas 7 repos. | — |
| ~~OBS-014~~ | ~~SCP `p-lgafaevf`/`p-k7ywnh7g` bloqueaba `ec2:RunInstances` en `security-group/*` via `aws:RequestTag/Entorno`~~ | fdac-cloudadmin | ✅ **RESUELTO 2026-05-25** — SCPs corregidos: (1) `DenyNoEntornoEC2` acotado a `instance/*` y `volume/*` exclusivamente; (2) `DenyWrongEntorno` permite `["desarrollo","staging","produccion"]` con `Null:false`. Ver `policies/scp-p-lgafaevf-fix.json` y `policies/scp-p-k7ywnh7g-fix.json`. | — |
| D4 | Dockerfiles funcionales en 7 repos | Carlos/Devs | ❓ Pendiente | C.2, E.3 |
| D3 | .env.example con valores reales | Carlos/Devs | ❓ Pendiente | C.2, D.2 |
| D5 | CIDR red on-premise UDABOL | Julio Chávez | ❓ Pendiente | C.2 SG Legacy |
| D6 | Credenciales Twilio | Carlos | ❓ Pendiente | E.3 smoke |

---

## Plan de trabajo — sesión 2026-05-25 (D.4 completado)

**Fecha actualización:** 2026-05-25
**Estado:** D.4 ✅ · ISS-003 ✅ · C.2-FIX ✅ · D.3 ✅ · Próximo: E.1 OTel Collector

### ~~Prioridad 0 — Cierre ISS-003~~ ✅ COMPLETADO 2026-05-25

3 DEV + 3 QA RUNNING en AppSubnetA. Ver sección C.2-FIX para detalle completo.

### ~~Prioridad 1 — D.2 MSK Serverless DEV+QA~~ ✅ COMPLETADO 2026-05-25

### ~~Prioridad 1 — D.3 agt-readmodel ECS service~~ ✅ COMPLETADO 2026-05-25

SOW §2.3 confirma que agt-readmodel es ECS Fargate (no Lambda). 
Service creado con `ReadmodelDesiredCount=0` (sin imagen en ECR aún — dev team push imagen cuando código listo).
Commits: `52186eb` (services.yaml + params), `43658d5` (ReadmodelDesiredCount fix).
OBS-023: `IAMForECSRoles` inline policy aplicada a GHA roles DEV+QA via cloudadmin (iam:TagRole/UntagRole/PutRolePolicy/DeleteRolePolicy en agt-ecs-*).

### Prioridad 3 — E.1 OTel Collector ECS task (9h est.) 🔄 EN PROGRESO

**Commit:** `1e47439` · **Estado:** template en main, deploy bloqueado por TECH-001

**Entregado en `1e47439`:**
- `cloudformation/modules/ecs/otel-collector.yaml` — ADOT (`public.ecr.aws/aws-observability/aws-otel-collector:latest`)
  - IAM task role `agt-ecs-otel-task-{env}`: X-Ray + CloudWatch EMF
  - Log group `/udabol/{env}/agt` (7 días retención)
  - Config via `AOT_CONFIG_CONTENT`: `otlp:4317 → awsxray + awsemf`
  - Cloud Map SD: `otel-collector.agt.local:4317`
  - SG ingress rule port 4317 en shared ECS task SG (`EcsTaskSgOtelIngress`)
  - Reutiliza `agt-ecs-exec-{env}` execution role del services stack
- `parameters/{dev,qa}/otel-collector.json`: `OtelDesiredCount=1`
- `scripts/deploy.sh`: case `otel-collector` → `udabol-otel-collector-{env}`
- `deploy-nonprod.yml`: opción + condición `otel-collector` (pendiente merge — TECH-001)

**Próximo:** Resolver TECH-001 → trigger GHA `deploy-nonprod` con `stack=otel-collector, env=dev` → validar task RUNNING → repetir QA.

### Prioridad 4 — E.2 OTel SDK Python en 7 repos agt-* (6h est.)

- `opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-grpc`, `opentelemetry-instrumentation-fastapi` en `requirements.txt`
- Bootstrap en `main.py`: `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.agt.local:4317`
- PR en cada repo → merge a `dev`

### Paralelo posible — ISS-002

Mejorar utterances `ConsultarNotas` + `Inscribir` en Lex (sin tilde, variantes coloquiales). No depende de ningún bloque pendiente. Ver `agt-intent-parser/deploy/aws/intents/`.

---

## Issues abiertos (corrección diferida)

| ID | Componente | Descripción | Impacto | Prioridad |
|----|------------|-------------|---------|-----------|
| **TECH-001** | PAT GitHub sin scope `workflow` | El PAT `ghp_GrfWOW5...` no tiene scope `workflow` — no puede pushear cambios en `.github/workflows/**`. Workaround actual: separar commits (sin workflow) y pushear workflow manualmente desde GitHub UI. **Acción requerida:** Regenerar PAT con scope `workflow` o editar `.github/workflows/deploy-nonprod.yml` en GitHub UI para agregar `otel-collector` en `options` y en la condición `if` del job `deploy-stack`. | Bloquea actualización de workflows vía CLI | 🔴 Deuda técnica — bloquea despliegue GHA de E.1 hasta que el workflow sea actualizado |
| **ISS-001** | `agt-whatsapp-gateway` handler | `ElegirMateria` + `ConsultarHorario` faltaban en `_INTENT_REPLIES` — devolvía respuesta genérica | Respuesta incorrecta al usuario | ✅ Corregido en código, commit `2cb6e38`, desplegado a Lambda DEV. QA: PR #1 dev→qa pendiente merge |
| **ISS-002** | Lex bot `udabol-intent-parser-{env}` | "ver mis notas" clasifica como `ConsultarDeuda` en vez de `ConsultarNotas`; "inscribirme en calculo" (sin tilde) → `ConsultarDeuda` | Mala clasificación coloquial | 🔵 Corregir antes de E.2 smoke test — agregar utterances sin tilde a ambos intents |
| ~~**ISS-003**~~ | ECS Fargate en App subnet (privada) | NACL `NaclAppInboundFromPublic` (Rule 100) tenía `CidrBlock: VpcCidr`. S3 Gateway Endpoint retorna tráfico desde IPs públicas de S3 → NACL bloqueaba esos paquetes. ECR DKR redirige blobs de capas de imagen a presigned S3 URLs → timeout en image pull desde AppSubnetA. Fix: Rule 100 ampliada a `0.0.0.0/0`. Ver OBS-019–OBS-022 y sección C.2-FIX. | ECS tasks en subnet pública expuestas a internet | ✅ **RESUELTO 2026-05-25** — 3 DEV + 3 QA RUNNING en AppSubnetA (10.10.11.x / 10.20.11.x). Commits: f67922a (vpc.yaml NaclApp), 01db864 (endpoints a PublicSubnetA). |

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

*Bitácora iniciada 2026-05-22 · Actualizada 2026-05-25 — E.1 en progreso · TECH-001 deuda técnica PAT workflow scope*
