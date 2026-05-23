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
| **A.2** | Branch protection rules en 7 repos | 2026-05-22 | 1.0 h | — | 🔴 BLOQUEADO (admin GitHub) |
| **A.3** | Deploy 14 repos ECR (DEV + QA vía CFN) | 2026-05-22 | 2.0 h | 0.5 h | ✅ COMPLETADO |
| **A.4** | Pipeline piloto CI/CD en agt-agent y agt-toolapi | 2026-05-22 | 3.0 h | 4.0 h | ✅ COMPLETADO |
| **B.1** | CloudFormation Lex V2 Bot + generate_template.py + intents YAML | 2026-05-23 | 8.0 h | 4.0 h | ✅ COMPLETADO |
| **B.2** | Deploy Lex DEV + QA + validación recognize-text | 2026-05-23 | 2.0 h | 2.0 h | ✅ COMPLETADO |
| **C.0** | ECS Cluster + ALB interno + Cloud Map namespace agt.local | 2026-05-23 | 3.0 h | 1.5 h | 🟡 PARCIAL (SCP bloquea ECS) |
| **C.1** | Lambda agt-whatsapp-gateway + API Gateway | — | 4.0 h | — | 🔴 BLOQUEADO N5 (SCP) |
| **C.2** | ECS Services: agt-agent, agt-toolapi, agt-legacy-adapter | — | 6.0 h | — | 🔴 BLOQUEADO N5 (SCP) |
| **C.3** | Validación ECS: describe-services + curl /health | — | 1.0 h | — | 🔴 BLOQUEADO N5 (SCP) |
| **D.1** | RDS PostgreSQL 16 + Secrets Manager + rotación 90d | — | 5.0 h | — | 🔴 BLOQUEADO N5 (SCP) |
| **D.2** | Bus de eventos (MSK o Outbox+EventBridge — según decisión Franz) | — | 6.0 h | — | 🔴 Bloqueado N1 + N5 |
| **D.3** | Lambda agt-readmodel + event source mapping | — | 2.0 h | — | 🔴 Bloqueado N1 + N5 |
| **E.1** | Dashboard CloudWatch (o stack obs — según decisión Franz) | — | 4.0 h | — | ⏳ Bloqueado N2 |
| **E.2** | Smoke test end-to-end + documentación de evidencia | — | 4.0 h | — | ⏳ Bloqueado D6 |
| **E.3** | Runbook sprint1-deploy.md + actualización .env.example | — | 3.0 h | — | ⏳ Pendiente |
| — | **Total presupuestado** | — | **80.0 h** | — | — |
| — | **Acumulado real** | — | — | **18.0 h** | — |
| — | **Saldo disponible** | — | — | **62.0 h** | — |

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

## C.0 — ECS Cluster + Cloud Map namespace agt.local (PARCIAL)

**Fecha:** 2026-05-23
**Horas reales:** ~1.5 h (estimado 3.0 h)
**Estado:** Cloud Map + SGs desplegados. ECS Cluster bloqueado por SCP.

### Qué se desplegó

**Template:** `cloudformation/modules/ecs/cluster.yaml`

| Recurso | DEV | QA |
|---------|-----|-----|
| Cloud Map namespace `agt.local` | `ns-hro2snrep2htcl6t` ✅ | `ns-43wzkgtkgrff3mfj` ✅ |
| ECS Task SG `udabol-agt-tasks-dev` | `sg-09c2ea0fc34154bc4` ✅ | `sg-086a6e6533481098e` ✅ |
| ECS Cluster `udabol-agt-dev` | ❌ SCP bloqueado | ❌ SCP bloqueado |
| ALB interno | N/A (single-AZ) | N/A (single-AZ) |

### Pendiente

- Cuando Franz actualice el SCP: `aws cloudformation deploy ... --parameter-overrides EnableEcsCluster=true`
- ALB: solo cuando VPC pase a multi-AZ (PROD o N3 resuelto)

### Observaciones de C.0

- **OBS-005:** SCP `p-lgafaevf` (org `o-pgxasmc8jj`) bloquea explícitamente `ecs:CreateCluster`, `lambda:CreateFunction` y `rds:CreateDBInstance`. API Gateway, Cloud Map, ALB y EC2 están permitidos. Ver N5 en tabla de bloqueantes.

---

## Registro de sesiones SSO activas

| Sesión | URL | Usuario | Expira |
|--------|-----|---------|--------|
| `proy` | ssoins-7223753b6943f944 | `ayrton@udabol.edu.bo` | ~8h desde login |
| `fundaciondev` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |
| `fdcAdmin` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |

> **Nota:** las sesiones SSO expiran. Renovar con `aws sso login --profile proy-dev` antes de cada sesión de trabajo.

---

## Dependencias bloqueantes — estado al 2026-05-23

| ID | Descripción | Responsable | Estado | Bloquea |
|----|-------------|-------------|--------|---------|
| **N5** | **SCP `p-lgafaevf` bloquea ECS, Lambda, RDS** | **Franz (Org Admin)** | 🔴 **CRÍTICO — descubierto 2026-05-23** | **C.1, C.2, C.3, D.1, D.2, D.3** |
| N1 | MSK Serverless vs Outbox+EventBridge | Franz | 🟡 Enviado WhatsApp 2026-05-22 | D.2, D.3 |
| N2 | CloudWatch vs Vector+Prometheus+Grafana | Franz | 🟡 Enviado WhatsApp 2026-05-22 | E.1 |
| N3 | VPC Single-AZ confirmada o re-deploy 3-AZ | Franz | 🟡 Enviado WhatsApp 2026-05-22 | C.0 ALB |
| N4 | NAT Gateway en DEV/QA | Franz | 🟡 Enviado WhatsApp 2026-05-22 | Lambda egress |
| A2 | Derechos admin GitHub repos (branch protection) | Franz | 🔴 Bloqueado | A.2 |
| D4 | Dockerfiles funcionales en 7 repos | Carlos/Devs | ❓ | C.2, E.2 |
| D3 | .env.example con valores reales | Carlos/Devs | ❓ | C.2, D.2 |
| D5 | CIDR red on-premise UDABOL | Julio Chávez | ❓ | C.2 SG Legacy |
| D6 | Credenciales Twilio | Carlos | ❓ | E.2 smoke |

### Mensaje sugerido para Franz (N5)

> Franz, encontré un bloqueo de SCP en las cuentas DEV y QA que impide desplegar la capa de cómputo del sprint.
> La política `p-lgafaevf` bloquea explícitamente:
> - `ecs:CreateCluster` / `ecs:*` — necesario para C.0/C.2 (Fargate)
> - `lambda:CreateFunction` / `lambda:*` — necesario para C.1/D.3
> - `rds:CreateDBInstance` / `rds:*` — necesario para D.1 (PostgreSQL)
>
> Necesito que habilites estos servicios en las cuentas `245650696072` (DEV) y `493735739951` (QA).
> Tienen permitidos: VPC, ECR, Lex, API Gateway, Cloud Map, ALB, IAM (scoped).

---

*Bitácora iniciada 2026-05-22 · Actualizada 2026-05-23*
