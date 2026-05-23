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
| **A.2** | Branch protection rules en 7 repos | 2026-05-22 | 1.0 h | — | 🔴 BLOQUEADO (admin) |
| **A.3** | Deploy 14 repos ECR (DEV + QA vía CFN) | 2026-05-22 | 2.0 h | 0.5 h | ✅ COMPLETADO |
| **A.4** | Pipeline piloto CI/CD en agt-agent y agt-toolapi | — | 3.0 h | — | ⏳ Pendiente |
| **B.1** | CloudFormation Lex V2 Bot + build_bot.py + intents YAML | — | 8.0 h | — | ⏳ Pendiente |
| **B.2** | Deploy Lex DEV + QA + validación recognize-text | — | 2.0 h | — | ⏳ Pendiente |
| **C.0** | ECS Cluster + ALB interno + Cloud Map namespace | — | 3.0 h | — | ⏳ Pendiente |
| **C.1** | Lambda agt-whatsapp-gateway + API Gateway | — | 4.0 h | — | ⏳ Pendiente |
| **C.2** | ECS Services: agt-agent, agt-toolapi, agt-legacy-adapter | — | 6.0 h | — | ⏳ Pendiente |
| **C.3** | Validación ECS: describe-services + curl /health | — | 1.0 h | — | ⏳ Pendiente |
| **D.1** | RDS PostgreSQL 16 + Secrets Manager + rotación 90d | — | 5.0 h | — | ⏳ Pendiente |
| **D.2** | Bus de eventos (MSK o Outbox+EventBridge — según decisión Carlos) | — | 6.0 h | — | ⏳ Bloqueado N1 |
| **D.3** | Lambda agt-readmodel + event source mapping | — | 2.0 h | — | ⏳ Bloqueado N1 |
| **E.1** | Dashboard CloudWatch (o stack obs — según decisión Carlos) | — | 4.0 h | — | ⏳ Bloqueado N2 |
| **E.2** | Smoke test end-to-end + documentación de evidencia | — | 4.0 h | — | ⏳ Bloqueado D6 |
| **E.3** | Runbook sprint1-deploy.md + actualización .env.example | — | 3.0 h | — | ⏳ Pendiente |
| — | **Total presupuestado** | — | **80.0 h** | — | — |
| — | **Acumulado real** | — | — | **6.5 h** | — |
| — | **Saldo disponible** | — | — | **73.5 h** | — |

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
   | agt-intent-parser | ...same pattern... | ...same pattern... |
   | agt-whatsapp-gateway | ✅ | ✅ |
   | agt-toolapi | ✅ | ✅ |
   | agt-agent | ✅ | ✅ |
   | agt-legacy-adapter | ✅ | ✅ |
   | agt-readmodel | ✅ | ✅ |

---

## Registro de sesiones SSO activas

| Sesión | URL | Usuario | Expira |
|--------|-----|---------|--------|
| `proy` | ssoins-7223753b6943f944 | `ayrton@udabol.edu.bo` | ~8h desde login |
| `fundaciondev` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |
| `fdcAdmin` | ssoins-7223753b6943f944 | `cloudadmin@udabol.edu.bo` | ~8h desde login |

> **Nota:** las sesiones SSO expiran. Renovar con `aws sso login --profile proy-dev` antes de cada sesión de trabajo.

---

## Dependencias bloqueantes — estado al 2026-05-22

| ID | Descripción | Responsable | Estado | Bloquea |
|----|-------------|-------------|--------|---------|
| N1 | MSK Serverless vs Outbox+EventBridge | Franz | 🟡 Enviado WhatsApp 2026-05-22 | D.2, D.3 |
| N2 | CloudWatch vs Vector+Prometheus+Grafana | Franz | 🟡 Enviado WhatsApp 2026-05-22 | E.1 |
| N3 | VPC Single-AZ confirmada o re-deploy 3-AZ | Franz | 🟡 Enviado WhatsApp 2026-05-22 | C.0 topología |
| N4 | NAT Gateway en DEV/QA | Franz | 🟡 Enviado WhatsApp 2026-05-22 | Lambda egress |
| D4 | Dockerfiles funcionales en 7 repos | Carlos/Devs | ❓ | C.2, E.2 |
| D3 | .env.example con valores reales | Carlos/Devs | ❓ | C.2, D.2 |
| #7 | ARN cert ACM para ALB interno | Carlos | ❓ | C.0 |
| #10 | YAML de intents Lex | Carlos | ❓ | B.1 |
| D5 | CIDR red on-premise UDABOL | Julio Chávez | ❓ | C.2 SG Legacy |
| D6 | Credenciales Twilio | Carlos | ❓ | E.2 smoke |

---

*Bitácora iniciada 2026-05-22 · Actualizar al cerrar cada bloque*
