# Plan de Despliegue — SOW-002 Sprint 1 (R1) · v1.1
**Proyecto:** UDABOL ERP-Agent · Fundación Dockweiler
**Framework:** OODA (Observe → Orient → Decide → Act)
**Autor:** Ayrton Irusta (DevOps / Cloud Architect)
**Coordinador Técnico:** Franz Carlos Álvarez Flores
**Fecha plan v1.1:** 2026-05-22 (revisión tras leer ADR-002 v3.0)
**Documentos base:** `SOW-002_Sprint1 v1.0` (firmado), `Guía Técnica Sprint 1`, `ADR-002 v3.0 Native` (firmado 2026-05-14)
**Cuentas:** DEV `245650696072` · QA `493735739951` · Región `us-east-1`
**Plazo contractual:** 17 días hábiles · Monto USD 4,400 (40/60)

> **Cambios v1.0 → v1.1:** (a) D1 y D2 confirmados via `cloudadmin`; (b) `ADR_002_native.md` recibido y leído — **introduce dos conflictos directos con el SOW-002** que el plan documenta y resuelve abajo; (c) email a Carlos del Día 0 reducido a 4 preguntas técnicas decisorias en lugar de 12.

---

## 0. RESUMEN EJECUTIVO

Despliegue end-to-end del Release 1 sobre la VPC base de SOW-001. **Los bloqueadores administrativos están resueltos**; quedan **decisiones técnicas que solo Carlos puede ratificar** porque hay contradicciones expresas entre el SOW firmado y el ADR-002 v3.0 firmado.

### 0.1 Estado de bloqueadores hoy (2026-05-22)

| Bloqueador | Estado v1.0 | Estado v1.1 | Evidencia |
|---|---|---|---|
| D7 Pago anticipo USD 1,760 | ✅ | ✅ | — |
| D1 Acceso DEV `245650696072` | ⚠️ Pendiente | ✅ **Resuelto** | Acceso vía `cloudadmin` (root) |
| D2 Acceso QA `493735739951` | ⚠️ Pendiente | ✅ **Resuelto** | Acceso vía `cloudadmin` (root) |
| `SOW/sow02/ADR_002_native.md` | ❓ Vacío | ✅ **Recibido** | ADR-002 v3.0 leído íntegro |
| D3 GitHub org collaborator | ✅ | ✅ | — |
| OIDC trust DEV/QA | ✅ heredado | ✅ heredado | Roles `proy-app-gha-role-development/qa` |
| D4 Dockerfiles funcionales | ❓ | ❓ Pendiente | Pedido a Carlos |
| D5 `.env` reales | ❓ | ❓ Pendiente | Pedido a Carlos |
| D6 CIDR on-prem UDABOL | ❓ | ❓ Pendiente | Pedido a Julio C. (TI) |
| D7-G Credenciales Twilio | ❓ | ❓ Pendiente | Pedido a Carlos (Semana 2) |
| ACM cert ALB interno | ❓ | ❓ Pendiente | Excluido del scope SOW; pedido a Carlos |
| **Conflicto SOW vs ADR (MSK/CW)** | **N/A** | 🟥 **NUEVO** | Ver §0.2 |

> **Nota sobre `cloudadmin` (root):** funciona para arrancar, pero **NO es buena práctica operar el Sprint con root** — el SOW E1/E6 exige "sin credenciales estáticas". Plan inmediato: usar `cloudadmin` solo para crear un usuario IAM operativo `devops-ayrton` con permission set acotado al Sprint 1 (CFN, ECS, RDS, MSK/EventBridge, Lex, Lambda, APIGW, Secrets, IAM PassRole limitado), y dejar `cloudadmin` para emergencias. Ver §11.

### 0.3 Estado real al 2026-05-26 (post-Sprint 1)

| Bloque | Estado |
|--------|--------|
| **A.0** IAM Identity Center — Permission Set Sprint1Deploy | ✅ COMPLETADO — perfiles proy-dev/proy-qa operativos |
| **A.1-A.4** Repos, CI/CD, ECR, pipelines | ✅ COMPLETADO — 7 repos, 14 ECR, OIDC roles, ci.yml en 7 repos |
| **B.1-B.2** Lex V2 DEV+QA | ✅ COMPLETADO — `udabol-intent-parser-lex-dev/qa`, 5/5 intents PASS |
| **C.0** ECS Cluster + Cloud Map | ✅ COMPLETADO — `udabol-agt-dev/qa`, namespace `agt.local` |
| **C.1** Lambda agt-whatsapp-gateway + API GW | ✅ COMPLETADO — API GW HTTP v2, Lex integrado |
| **C.2-C.3** ECS Services (agent, toolapi, legacy-adapter) | ✅ COMPLETADO — 3 DEV + 3 QA RUNNING en AppSubnetA (privada) |
| **D.1** RDS PostgreSQL 16 + Secrets Manager | ✅ COMPLETADO — `udabol-rds-dev/qa`, rotación 30d |
| **D.2** MSK Serverless + 3 topics | ✅ COMPLETADO — Plan A (SOW §2.5 confirma MSK). Puerto 9098 SASL/IAM |
| **D.3** ECS service agt-readmodel | ✅ COMPLETADO — SOW §2.3 confirma ECS (no Lambda). DesiredCount=0, pendiente imagen dev team |
| **D.4** NAT Instance + VPC Endpoints | ✅ COMPLETADO — fck-nat t4g.nano + 6 endpoints. SCP corregido via fdac-cloudadmin |
| **E.1** OTel Collector ADOT | ✅ COMPLETADO — `udabol-otel-collector-dev/qa`, RUNNING v0.48.0, `otel-collector.agt.local:4317` |
| **E.2** OTel SDK en 7 repos agt-* | ⬜ PENDIENTE ~6h |
| **E.3** Smoke test E2E | ⏳ BLOQUEADO D6 (credenciales Twilio — Carlos) |
| **E.4** Runbook sprint1-deploy.md | ✅ COMPLETADO |

**N1 (MSK):** ✅ RESUELTO — Plan A · **N2 (Observabilidad):** ✅ RESUELTO — OTel Collector · **N3 (Single-AZ):** ✅ RESUELTO · **N4 (NAT):** ✅ RESUELTO — NAT Instance t4g.nano ($3/mes vs $32/mes NAT GW)

**Acumulado real 2026-05-26:** 55.5 h / 80 h · **Saldo:** 24.5 h

---

### 0.2 Conflictos SOW-002 firmado ↔ ADR-002 v3.0 firmado

| # | Tema | SOW-002 (firmado mayo 2026) | ADR-002 v3.0 (firmado 14-may-2026) | Impacto |
|---|---|---|---|---|
| **C1** | Bus de eventos | §2.1, §3.4, E5: **Amazon MSK Serverless** con topics `enrollment.events`, `payment.events`, `query.audit` | §4.1, §4.3, §4.4: **MSK eliminado** → Outbox PG + EventBridge custom bus. _"Volumen UDABOL no justifica un broker Kafka administrado"_ | 🟥 E5 acceptance literal dice "MSK cluster activo, 3 topics creados verificables en consola" |
| **C2** | Observabilidad | §3.5, §3.3, E7: **CloudWatch Dashboard + Logs + Alarmas** | §3, §4.3: **CloudWatch eliminado** → Vector + S3/Athena + Prometheus + Grafana + Alertmanager + SNS. _"Violación de Single Responsibility"_ | 🟥 E7 acceptance literal dice "Dashboard `udabol-erp-agent-{env}` con 6 widgets activos" |
| **C3** | Topología AZ | (no especifica AZ) | §4.4: **"subnets pub/priv/db en 3 AZ"** | ⚠️ La VPC SOW-001 ya está desplegada **Single-AZ** (ADR-002 v1.x, `us-east-1a`). Inconsistencia |
| **C4** | NAT Gateway | (no especifica) | §4.4: **"NAT GW (1 en DEV/QA, 3 en PROD)"** + §4.6: \$95/mes NAT | ⚠️ ADR-001 anterior decía **sin NAT en DEV/QA** (ahorro \$32/mes/AZ). VPC actual no tiene NAT |
| C5 | Naming repos | `agt-*` (`clouddev-udabol/agt-agent`, ...) | `udabol-*` (§4.1) | 🟢 Resuelto: los repos reales en GitHub son `agt-*`. ADR v3.0 está desactualizado en naming |
| C6 | Budget DEV/QA | SOW-001 fijó USD 100/mes/cuenta | §4.4: USD 150 DEV / USD 200 QA | 🟢 ADR sube el budget — favorable, lo adoptamos |

**Cláusula contractual aplicable:** SOW §10 dice "En caso de conflicto entre la presente SOW y el MSA, prevalecen los terminos del MSA salvo disposicion expresa aceptada por ambas partes en esta SOW". El ADR-002 v3.0 está firmado pero **no es un anexo del SOW** ni una "disposición expresa aceptada en esta SOW". Por estricta literalidad, **el SOW manda**. Pero éticamente y técnicamente, hay que **levantar la ambigüedad con Carlos antes de tocar AWS** — caso contrario me gasto 13.80 h en MSK que después me piden migrar a Outbox.

**Mi recomendación profesional** (ver §3.5 y §3.6):
- **Plan A (Default — Literal SOW):** cumplir SOW al pie de la letra → desplegar MSK y CloudWatch para asegurar pago, documentar en runbook la deuda técnica "migrar a Outbox+EventBridge y stack obs desagregado en Sprint 2 (SOW-003) conforme ADR-002 v3.0".
- **Plan B (Si Carlos lo autoriza por escrito):** ejecutar ADR-002 v3.0 directamente → Outbox+EventBridge en lugar de MSK, stack desagregado en lugar de CloudWatch. Requiere **adenda al SOW** redactada y firmada antes del Día 4 para no exponerme a rechazo del entregable E5/E7.
- **Plan C (Híbrido seguro):** desplegar lo que cumple el SOW (MSK + CloudWatch) **y además** loguear con `awslogs` driver a CloudWatch (cumple E7) más Vector como segundo destino opcional a S3 (deja sembrada la migración de Sprint 2). Misma decisión sobre MSK: cumplir el SOW.

→ **Plan A es mi default** hasta tener respuesta escrita de Carlos. El email del §10 hace la pregunta directamente.

---

## 1. OBSERVE — Hechos verificados

### 1.1 Lo que ya existe (heredado SOW-001)

| Recurso | Estado | Notas |
|---|---|---|
| VPC DEV `10.10.0.0/16` **Single-AZ** `us-east-1a` (3 capas) | ✅ Desplegada | **Conflicto C3 con ADR v3.0** |
| VPC QA `10.20.0.0/16` **Single-AZ** `us-east-1a` | ✅ Desplegada | idem |
| VPC PROD `10.30.0.0/16` | 🔒 Placeholder | Sprint 2 |
| **Sin NAT Gateway DEV/QA** (ADR-001 anterior) | ✅ Sin NAT | **Conflicto C4 con ADR v3.0** |
| VPC Endpoints (S3, ECR.api, ECR.dkr, Logs, Secrets) | ✅ En DEV/QA | Heredados |
| Roles OIDC `proy-app-gha-role-development/qa` | ✅ Activos | |
| Budgets DEV/QA USD 100/mes | ✅ Activos | **ADR v3.0 sube a USD 150/200 (favorable, adoptar)** |
| SCP `p-lgafaevf` (DEV `Entorno=desarrollo`) y `p-k7ywnh7g` (QA `Entorno=staging`) | ✅ Activas | Case-sensitive |
| 8 repos GitHub bajo `clouddev-udabol` | ✅ Existen | aws-devops + 7 `agt-*` |
| Acceso root `cloudadmin` a DEV y QA | ✅ Nuevo | Para bootstrap de IAM operativo |

### 1.2 Lo que el SOW-002 obliga a entregar (E1–E7)

Sin cambios respecto a v1.0 — los criterios de aceptación siguen siendo los del SOW firmado.

| # | Entregable | Prioridad |
|---|---|---|
| **E1** | 7 repos `agt-*` con ramas/branch protection + CI/CD pasando en `dev` + 14 ECR | **CRÍTICO** |
| **E2** | Stacks Lex `udabol-intent-parser-{dev,qa}` `CREATE_COMPLETE`; bot responde confidence ≥ 0.70 a "Quiero inscribirme al semestre 2026-1" | **CRÍTICO** |
| **E3** | Lambda WhatsApp Gateway DEV + API GW respondiendo HTTP 200 | **CRÍTICO** |
| **E4** | `agt-agent` + `agt-toolapi` RUNNING en ECS Fargate DEV con `/health` 200 | **CRÍTICO** |
| **E5** | `agt-legacy-adapter` RUNNING + RDS PG `available` + **MSK 3 topics** (literal) | **CRÍTICO** |
| **E6** | Pipeline DEV→QA en ≥ 2 repos, OIDC | **REQUERIDO** |
| **E7** | **Dashboard CloudWatch** (literal) con ≥ 6 widgets + smoke + runbook | **REQUERIDO** |

### 1.3 Hechos nuevos del ADR-002 v3.0 (componentes que aparecen)

| Componente nuevo | Tecnología | Sprint |
|---|---|---|
| **Patrón Outbox transaccional** | Tabla `events_outbox` en RDS + Lambda relay worker | R1 (ADR) — diferido a R2 si vamos por Plan A |
| **Amazon EventBridge custom bus** | `udabol-events-{env}` + rules | R1 (ADR) — diferido si Plan A |
| **Stack observabilidad desagregado** | Vector → S3+Athena → Prometheus → Grafana → Alertmanager → SNS | R1 (ADR) — diferido si Plan A |
| **Tempo distributed tracing** | Self-hosted ECS Fargate Spot | R2 (Sprint 3) |
| **Arquitectura hexagonal `udabol-intent-parser`** | `NLUEnginePort` adapter para Lex (R1), Bedrock (R2), híbrido (R3) | R1 — diseño que sí adoptamos |
| **VPC Peering DEV↔QA y QA↔PROD** | network-peering stack | R1 (ADR) — **conflicto con ADR anterior "VPC isla"**, pedir aclaración |
| **Roles permission set IAM IC nombrados** | `AdministratorAccess` (Ian), `ArchitectAccess` (Carlos), `DevOpsReadOnly` (Ayrton) | Operativo |
| **AWS Budgets ajustados** | USD 150 DEV / USD 200 QA / USD 400 PROD | R1 — adoptar |

> **Punto crítico de diseño que sí cae bajo Sprint 1:** la arquitectura hexagonal de `agt-intent-parser` con `NLUEnginePort` y adapters (Lex en R1, Bedrock+Lex en R2). Esto **no** está en conflicto con el SOW y debería implementarse así desde Día 1 — es lo que permite que R2 (SOW-004 futuro) no rompa lo construido.

---

## 2. ORIENT — Análisis y restricciones (actualizado)

### 2.1 Topología objetivo R1 — Plan A (Literal SOW)

```
Twilio ──HTTPS──▶ API Gateway DEV ──▶ Lambda agt-whatsapp-gateway
                                            │
                                            ▼
                            ALB interno HTTPS/443 (ACM) en App-layer
                                            │
              ┌─────────────────────────────┼─────────────────────────────┐
              ▼                             ▼                             ▼
        agt-agent (8080)            agt-toolapi (8081)         agt-legacy-adapter (8082)
              │                             │                             │
              ▼                             ├──▶ MSK Serverless           │
            Lex V2                          │     (3 topics)              │
        (es_419 vía boto3                   │           │                 │
         adapter NLUEnginePort)             │           ▼                 │
                                            │     Lambda agt-readmodel     │
                                            │           │                 │
                                            └──────▶ RDS PG 16 ◀──────────┘
                                                  (Single-AZ DEV/QA)
                                                  │
                          CloudWatch Logs/Dashboard ←──┘ (E7)
                          (con awslogs driver en ECS + Lambda)
                          VPN S2S ──▶ HMS Plus on-prem (sólo desde Legacy Adapter)
```

### 2.2 Topología R1 — Plan B (ADR-002 v3.0 directo)

Idéntico al diagrama anterior, con dos cambios:
1. En lugar de **MSK Serverless** entre `agt-toolapi` y `agt-readmodel`: tabla `events_outbox` en RDS → Lambda relay worker → EventBridge bus `udabol-events-{env}` → Lambda `agt-readmodel` (suscriptor).
2. En lugar de **CloudWatch**: sidecar Vector en cada Task ECS → S3 buckets `raw/curated` → Athena (queries SQL); Prometheus (scrape `/metrics` de cada servicio) → Grafana (dashboards) → Alertmanager → SNS. Esto agrega **4 nuevos servicios ECS Fargate Spot** al cluster.

### 2.3 Restricciones duras (sin cambios desde v1.0)

1. SCPs case-sensitive: `Entorno=desarrollo` DEV, `Entorno=staging` QA.
2. **Single-AZ DEV/QA** (ADR-002 anterior). La VPC ya está así. ADR-002 v3.0 dice 3-AZ pero la VPC base no se re-despliega bajo este SOW.
3. **Sin NAT en DEV/QA** (ADR-001). Si Carlos pide NAT para alguna razón (Internet egress de Twilio outbound, etc.), pedirlo por escrito y agregar al costo.
4. Cero credenciales estáticas: solo OIDC.
5. Budget DEV/QA: **USD 150/USD 200** adoptado de ADR-002 v3.0 §4.4 (favorable).
6. Plazo 17 días hábiles.
7. No `Co-Authored-By` en commits.
8. Tags obligatorios + `SOW=SOW-002`.

### 2.4 Riesgos top-5 actualizados

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| **R0** | **Carlos no decide entre Plan A y Plan B antes del Día 4 → me bloqueo en Bloque D/E sin saber si despliego MSK o EventBridge** | Media | **Crítico** | Email del §10 con deadline Día 3. Si no responde, **arranco Plan A (literal SOW)** y notifico por escrito. |
| R1 | D4 (Dockerfiles) sigue pendiente al Día 7 | Alta | Crítico | Plan B: imagen `nginxdemos/hello` con `/health` para validar Task Def + ALB. |
| R2 | Lex V2 confidence < 0.70 por intents pobres | Media | Crítico (E2) | Pedir YAML de Carlos (D5) o redactar `Inscribir`, `ConsultarDeuda`, `ConsultarNotas` con 10 utterances mínimas. |
| R3 | Costos MSK Serverless erosionan budget | Alta | Medio | Adoptar Budget DEV USD 150 (ADR v3.0). Plan B elimina este riesgo. |
| R4 | Pipeline QA: rama `qa` inexistente al crear repo | Media | Medio | A.1 crea las 3 ramas con commit vacío. |
| R5 | NAT Gateway requerido por Lambda WG para llamar a Twilio outbound | Baja | Medio | Twilio sólo envía webhooks (entrante). Outbound desde Lambda WG **no es necesario** salvo confirmación de status callback. Si lo es, agregar NAT en App-layer (~USD 32/mes/AZ). |
| R6 | ACM cert para ALB interno: dominio interno (`*.dev.udabol.internal`) no resoluble sin Route 53 privado o Hosted Zone | Media | Medio | Pedir a Carlos (item 7 §5). Plan B: cert self-signed temporal o ALB HTTPS con SNI default. |

### 2.5 Decisiones de naming/arquitectura adoptadas

- **Stacks CFN:** `udabol-{component}-{env}` (ej. `udabol-ecs-cluster-dev`, `udabol-rds-dev`, `udabol-msk-dev` _o_ `udabol-events-bridge-dev` según plan elegido).
- **ECR repos:** `agt-{service}` (sin prefijo `udabol/`).
- **NLUEnginePort de `agt-intent-parser`:** adoptar arquitectura hexagonal del ADR aún en R1. Permite intercambio futuro con Bedrock sin reescribir.
- **VPC Peering DEV↔QA:** **NO desplegar** en este SOW (no está en alcance E1–E7). Diferir a aclaración con Carlos sobre cómo conviven las dos versiones del ADR.

---

## 3. DECIDE — Plan de despliegue por bloques

### 3.1 Calendario (17 días hábiles) — sin cambios estructurales

```
Día  1  2  3  │  4  5  6  7  │  8  9 10 11 12 │ 13 14 │ 15 16 17
─────────────┼──────────────┼────────────────┼───────┼──────────
Bloq.  A.1 A.2 A.0 │  A.3 A.4 B.1 B.2 │  C.1 C.2 C.3 D.1 D.2 │ E.1 E.2 │ Revisión
   (no IAM AWS) │ (IAM operativo) │  (IAM + Docker + ACM) │ (Twilio) │ Coordinador
```

Día 0 ahora incluye **A.0** = crear el usuario IAM operativo `devops-ayrton` desde `cloudadmin` (root) antes que nada.

### 3.2 Bloque A — Repositorios + CI/CD + ECR + IAM operativo (E1, E6) — sin cambios

Detalle igual a v1.0, con dos adiciones:

- **A.0 (Día 1, 2h):** Bootstrap de IAM operativo desde `cloudadmin`:
  - DEV: crear `iam-role devops-ayrton` con custom managed policy `Sprint1DeployPolicy` (CFN/ECS/ECR/RDS/MSK o EventBridge/Lex/Lambda/APIGW/Secrets/Logs/IAM PassRole acotado a roles del proyecto).
  - QA: idem.
  - Crear `~/.aws/config` con perfiles `proy-dev` y `proy-qa` que asumen este role.
  - Validar con `aws sts get-caller-identity --profile proy-dev`.
  - A partir de aquí, `cloudadmin` solo para emergencia y para crear el OIDC role si hubiera que reemplazarlo (no es el caso, ya existen los `proy-app-gha-role-*`).
- **A.4 piloto** ahora se hace contra **stacks reales** (no placeholder) en Día 7 después de B.

Resto idéntico (A.1, A.2, A.3 y la plantilla `ci.yml` consolidada de §3.2.1).

### 3.3 Bloque B — Amazon Lex V2 (E2) — sin cambios técnicos

Sin cambios; SOW y ADR están alineados en R1 = Lex V2 puro. Se adopta la abstracción `NLUEnginePort` para que la app de `agt-intent-parser` no quede acoplada a Lex (futuro R2 con Bedrock pasa transparente).

### 3.4 Bloque C — Microservicios ECS Fargate + Lambda Gateway (E3, E4, parcial E5)

#### C.0 — Pre-cómputo (Día 8)
- ECS Cluster `udabol-agt-cluster-{env}` + Cloud Map namespace `agt.local` (alineado con ADR §4.4 "Service Discovery (Cloud Map)").
- ALB interno `udabol-alb-internal-{env}`:
  - Esquema `internal`, 2 subnets App-layer DEV (con la subnet placeholder en `us-east-1b` por requisito sintáctico — ver ADR-002 v1.x).
  - Listener HTTPS 443 con cert ACM (**dato faltante #7 §5**).
  - Reglas de path: `/v1/converse` → `tg-agent:8080`, `/v1/tools/*` → `tg-toolapi:8081`, `/v1/legacy/*` → `tg-legacy:8082`.
  - Listener HTTP 80 → redirect 443 (`ListenerRule` con `Type=redirect`).

#### C.1 — Lambda `agt-whatsapp-gateway` + API Gateway (E3)
- Python 3.11, 256 MB, timeout 10s, en subnets App con SG `sg-lambda-gw`.
- API GW REST API `udabol-whatsapp-gw-{env}`, stage `dev`/`qa`.
- Validación firma Twilio (`X-Twilio-Signature`) en el handler.

#### C.2 — ECS Services (E4, E5)
- 3 Task Defs según Guía §4.2 (`256 cpu / 512 MiB`, `desired=1` DEV, `desired=2` QA).
- Service Discovery `agt.local`.
- Health checks `curl -f http://localhost:{port}/health`.
- Logs a `/agt/{service}/{env}` vía `awslogs` driver (cumple E7 Plan A; no impide Plan B futuro porque Vector puede leer de CWL).

#### C.3 — Validación
`describe-services` → `runningCount==desiredCount` y `deployments[0].rolloutState==COMPLETED`. `curl https://alb-internal/v1/converse/health` desde bastion → 200.

### 3.5 Bloque D — Persistencia y Bus de Eventos (E5) ⚠️ DECISIÓN PENDIENTE

#### D.1 — RDS PostgreSQL 16 (común a Plan A y Plan B)

`db.t4g.medium`, Single-AZ, gp3 20 GB DEV / 30 GB QA, backup 7d/14d, `StorageEncrypted=true`, `DeletionProtection=true`, `PubliclyAccessible=false`. Subnet group = Data layer. Secret `agt/db-creds-{env}` con `GenerateSecretString` + rotación 90 días. DB inicial `udabol_dev`/`udabol_qa`. Parameter group custom: `pg_stat_statements`, `log_statement=ddl`, `log_min_duration_statement=500`.

#### D.2-A — Bus de Eventos · PLAN A (Literal SOW: MSK Serverless)

- Cluster `udabol-{env}-msk` con `ClientAuthentication.Sasl.Iam.Enabled=true`.
- Crear topics vía `kafka-python` admin client post-deploy (no por CFN — el recurso `AWS::MSK::Cluster` no soporta topics):
  - `enrollment.events` (3 partitions, retention 7d)
  - `payment.events` (3 partitions, retention 7d)
  - `query.audit` (1 partition, retention 7d)
- IAM policy por producer/consumer: `agt-toolapi` produce a `enrollment.events`/`payment.events`, `agt-agent` produce a `query.audit`, `agt-readmodel` consume todo.
- **Costo estimado:** ~USD 35/mes/cuenta base + throughput (compatible con Budget USD 150 adoptado).
- **Pros:** cumple SOW al pie de la letra → pago seguro.
- **Cons:** deuda técnica para Sprint 2 (migrar a Outbox+EventBridge conforme ADR v3.0).

#### D.2-B — Bus de Eventos · PLAN B (ADR-002 v3.0: Outbox + EventBridge)

- Tabla `events_outbox(id, aggregate_type, aggregate_id, event_type, payload jsonb, created_at, published_at, retry_count)` creada por CFN (`AWS::RDS::DBProxyEndpoint` + migration Lambda con `psycopg2`).
- Lambda `udabol-outbox-relay-{env}` (Python 3.11, 256 MB, schedule cada 30s vía EventBridge rule):
  - SELECT batch ≤ 100 WHERE published_at IS NULL ORDER BY created_at.
  - PutEvents a EventBridge bus `udabol-events-{env}` con `Source=udabol.{aggregate_type}`, `DetailType=event_type`.
  - UPDATE published_at = now() en filas exitosas.
- EventBridge bus `udabol-events-{env}` + 3 rules:
  - Rule `enrollment-events` → target Lambda `agt-readmodel`
  - Rule `payment-events` → target Lambda `agt-readmodel`
  - Rule `query-audit` → target CloudWatch Logs (audit trail)
- IAM: `agt-toolapi` y `agt-agent` solo escriben a outbox (acceso DB).
- **Costo estimado:** ~USD 2/mes (EventBridge + Lambda relay) — gran ahorro vs MSK.
- **Pros:** alineado con decisión arquitectónica final, sin deuda técnica.
- **Cons:** **requiere adenda firmada al SOW** modificando E5 antes de Día 4, sino riesgo de rechazo del entregable.

#### D.3 — Read Model
- **Plan A:** Lambda `agt-readmodel` con `AWS::Lambda::EventSourceMapping` a MSK + topics.
- **Plan B:** Lambda `agt-readmodel` invocada por EventBridge rules (target).

> **Mi recomendación a Carlos:** Plan A por seguridad contractual, deuda técnica documentada en `runbooks/sprint1-deploy.md` y `SOW/sow02/deuda-tecnica.md` con jira/issue para Sprint 2.

### 3.6 Bloque E — Observabilidad + Smoke + Runbook (E7) ⚠️ DECISIÓN PENDIENTE

#### E.1-A — Observabilidad · PLAN A (Literal SOW: CloudWatch)

- Dashboard `udabol-erp-agent-{env}` con 6 widgets exactos según Guía §7.1.
- Alarmas: CPU Fargate >80%/5min, RDS FreeStorage <20%, ALB 5xx >5%.
- Log Groups `/agt/{service}/{env}` (retention 14d DEV/30d QA), `/aws/lambda/agt-whatsapp-gateway-{env}`, `/aws/lambda/agt-readmodel-{env}`.
- KMS: alias `alias/aws/logs` (deuda CKV_AWS_158, deferred to Sprint 2).

#### E.1-B — Observabilidad · PLAN B (ADR-002 v3.0: stack desagregado)

Agrega al cluster ECS:
- ECS Service `vector-aggregator` (Fargate Spot 0.25 vCPU / 0.5 GB) que recibe logs de los sidecars Vector de cada Task Def.
- ECS Service `prometheus` con storage en EBS (gp3 10 GB), retention 30d local.
- ECS Service `grafana` con datasources Prometheus + Athena + (R2: Tempo).
- ECS Service `alertmanager` con SNS destination.
- S3 buckets `udabol-logs-raw-{env}` (Parquet) y `udabol-logs-curated-{env}` con lifecycle a Glacier después de 30d.
- Glue catalog + Athena workgroup `udabol-{env}` para queries SQL on-demand.
- Costo: +USD 15/mes obs ECS + USD 6/mes S3+Athena = USD 21/mes/cuenta.

> **Mi recomendación a Carlos:** Plan A. Es lo que dice el SOW E7. Plan B cabe en Sprint 2 con margen.

### 3.7 Plan C (Híbrido — automático si Plan A se decide)

Aunque sigamos Plan A, **siembro 2 cosas baratas para facilitar la migración futura**:
1. **Log driver `awsfirelens` con Fluent Bit** en lugar de `awslogs` directo. Cumple E7 (Fluent Bit envía a CW Logs como destino primario) y a la vez permite agregar S3 como destino secundario sin tocar la Task Def. **Costo extra: 0**.
2. **Sidecar `aws-otel-collector`** apagado por default (variable `OTEL_DISABLED=true` en env). Si Sprint 2 decide activarlo, basta toggle. **Costo extra: 0**.

---

## 4. ACT — Secuencia ejecutable

### 4.1 Día 0 (hoy) — 4 acciones inmediatas

1. **Bootstrap IAM operativo (A.0)** desde `cloudadmin` en DEV: crear `devops-ayrton` user + `Sprint1DeployPolicy`. Idem QA. ~2h.
2. **Email a Carlos (§10)** con las 4 decisiones técnicas que solo él puede tomar (MSK vs Outbox / CW vs stack desagregado / NAT sí o no / 3-AZ sí o no en VPC futura). Deadline respuesta: Día 3.
3. **Branch `feature/sow-002-init`** en `clouddev-udabol/aws-devops` con `SOW/sow02/cloudformation/` + este plan.
4. **Estructura A.1** en los 7 repos (sin tocar AWS).

### 4.2 Día 1–3 (sin esperar a Carlos)

- A.1 + A.2 completos. Templates CFN locales validados con `cfn-lint`/`checkov`/`cfn-guard`.
- `build_bot.py` + YAML de 3 intents mínimos (`Inscribir`, `ConsultarDeuda`, `ConsultarNotas`) con 10 utterances cada uno.
- **Default:** trabajo asumiendo Plan A. Si Carlos responde Plan B antes del Día 4, refactor menor en los templates `persistence/` y `observability/` (no he gastado horas en MSK aún).

### 4.3 Día 4–7

- A.3 deploy 14 ECR (DEV+QA).
- A.4 pipeline piloto en `agt-agent` y `agt-toolapi`.
- B.1 + B.2 Lex bot DEV/QA + validación `recognize-text`.

### 4.4 Día 8–12

- C.1 → C.2 → D.1 → D.2-{A|B} → D.3.
- Smoke parcial con imagen placeholder hasta que llegue D4 (Dockerfiles).

### 4.5 Día 13–14

- E.1-{A|B} + smoke end-to-end + runbook.

### 4.6 Plan FinOps (actualizado con budget v3.0)

| Recurso | Mes DEV | Mes QA | Mecanismo de ahorro |
|---|---|---|---|
| RDS PG `db.t4g.medium` | ~USD 35 | ~USD 35 | Stop fuera de horario laboral via EventBridge + Lambda (RDS Stop, 7d auto-start cap). |
| ECS Fargate (3 tasks) | ~USD 30 (1×3) | ~USD 60 (2×3) | Scheduled `desired_count=0` 22:00–07:00 BO. |
| Plan A: MSK Serverless | ~USD 35 base + throughput | ~USD 35 + throughput | No apagable. **Budget DEV USD 150 cubre.** |
| Plan B: EventBridge + Lambda relay | ~USD 2 | ~USD 2 | — |
| Plan A: CloudWatch (logs+metrics+dashboard+alarms) | ~USD 8 | ~USD 8 | Retention 14d DEV. |
| Plan B: Vector+Prom+Grafana+Alertmanager (Spot) + S3+Athena | ~USD 21 | ~USD 21 | Fargate Spot. |
| **Total Plan A DEV** | **~USD 108** | — | OK con budget USD 150 |
| **Total Plan B DEV** | **~USD 88** | — | OK con budget USD 100 original |

> Plan B es **más barato a largo plazo**, pero solo paga la pena si Carlos firma la adenda.

---

## 5. VALIDACIONES — Datos faltantes actualizados

| # | Dato faltante | Estado v1.0 | Estado v1.1 | Quién | Urgencia |
|---|---|---|---|---|---|
| 1 | Permission Set IAM IC DEV | ⚠️ Pendiente | ✅ Resuelto (cloudadmin) | — | — |
| 2 | Permission Set IAM IC QA | ⚠️ Pendiente | ✅ Resuelto (cloudadmin) | — | — |
| 12 | `ADR_002_native.md` | ⚠️ Vacío | ✅ Recibido | — | — |
| 3 | **Dockerfiles funcionales** en 7 repos `agt-*` | ❓ | ❓ Pendiente | Carlos / equipo App | Día 7 |
| 4 | **`.env.example` con valores reales** (Twilio, HMS, etc.) | ❓ | ❓ Pendiente | Carlos / equipo App | Día 7 |
| 5 | **CIDR red on-premise UDABOL** | ❓ | ❓ Pendiente | Julio Chávez / Carlos | Día 10 |
| 6 | **Credenciales Twilio** | ❓ | ❓ Pendiente | Carlos | Día 13 |
| 7 | **ARN cert ACM** para ALB interno | ❓ | ❓ Pendiente | Carlos | Día 8 |
| 8 | **Estado real VPN S2S** SOW-001 | ❓ | ❓ Pendiente | Yo + Carlos | Día 10 |
| 9 | **Nombre repo WhatsApp Gateway** (SOW dice `agt-whatsapp-gateway`, Guía dice `agt-whatsapp-gw`) | ❓ | 🟢 Confirmado `agt-whatsapp-gateway` (lista del usuario) | — | — |
| 10 | **YAML de intents Lex** | ❓ | ❓ Pendiente | Carlos | Día 5 |
| 11 | **Budget DEV USD 150** | ❓ | ✅ Implícito por ADR v3.0 §4.4 | — | — |
| **N1** | **🟥 ¿Plan A (MSK) o Plan B (Outbox+EventBridge)?** | N/A | 🟥 **NUEVO** | Carlos | **Día 3** |
| **N2** | **🟥 ¿Plan A (CloudWatch) o Plan B (Vector+Prom+Grafana)?** | N/A | 🟥 **NUEVO** | Carlos | **Día 3** |
| **N3** | **¿VPC actual Single-AZ se mantiene o ADR v3.0 obliga a re-desplegar 3-AZ?** (E1 SOW-001 ya cerrado) | N/A | ⚠️ **NUEVO** | Carlos | Día 7 |
| **N4** | **¿NAT Gateway en DEV/QA (ADR v3.0 §4.4) o sin NAT (ADR-001 anterior)?** | N/A | ⚠️ **NUEVO** | Carlos | Día 8 |

→ Items 3, 4, 7, **N1, N2** son del **Día 0–3**.

---

## 6. ENTREGABLES — Mapeo con artefactos físicos (sin cambios v1.0)

Igual que v1.0; cambia internamente el contenido del stack de E5 (`persistence/11-msk-serverless.yaml` vs `persistence/11-events-outbox-bridge.yaml`) y de E7 (`observability/13-cloudwatch.yaml` vs `observability/13-obs-stack.yaml`).

---

## 7. GATES DE CALIDAD (sin cambios)

`cfn-lint` → `cfn-nag` → `checkov` → `cfn-guard` → ChangeSet preview → smoke post-deploy.

---

## 8. ROLLBACK Y CONTINGENCIA (sin cambios v1.0)

- Cada stack diseñado para `delete` limpio (RDS y Log Groups con `Retain`).
- ECS rollback: TaskDefinition revision anterior.
- Lambda rollback: alias `LIVE` apunta a versión `N-1`.
- Lex rollback: alias a `BotVersion` previo.

---

## 9. REGLAS DE TRABAJO (sin cambios)

1. Sin `Co-Authored-By` en commits.
2. Tokens AWS via `boto3` con `sts assume_role` o perfil SSO, no `aws configure set`.
3. PAT fine-grained GitHub: scope `Actions: Write`, `Contents: Write`, `Pull requests: Write`.
4. Tags case-sensitive obligatorios incluyendo `SOW=SOW-002`.
5. No `*` en IAM Action sin justificación inline.
6. `shopt -s globstar nullglob` antes de globs `**` en bash.
7. `requirements.txt` versiones fijadas si `cache: pip` está activo.

---

## 10. EMAIL A CARLOS (borrador v1.1 — 4 decisiones técnicas)

> Asunto: **SOW-002 Sprint 1 — Decisiones técnicas necesarias antes del Día 4**
>
> Carlos,
>
> Con D1/D2 ya resueltos vía `cloudadmin` y leído íntegro el ADR-002 v3.0 que enviaste, encuentro **cuatro decisiones técnicas que solo vos podés tomar** porque hay contradicción literal entre el SOW-002 firmado y el ADR-002 v3.0 firmado por vos el 14-may-2026. Necesito tu respuesta por escrito antes del **Día 3 de ejecución** para no quemar horas en una arquitectura que después haya que rehacer.
>
> **N1 · Bus de eventos:** el SOW §3.4 y E5 me obligan a desplegar **MSK Serverless con 3 topics** (`enrollment.events`, `payment.events`, `query.audit`). El ADR v3.0 §4.1 dice _"MSK retirado del stack → Outbox PG + EventBridge"_. ¿Cuál ejecuto?
> - **Opción A (default):** despliego MSK como dice el SOW para asegurar aceptación del entregable E5. Documento como deuda técnica la migración a Outbox+EventBridge en Sprint 2.
> - **Opción B:** Outbox+EventBridge directo, pero necesito **adenda al SOW** firmada antes del Día 4 modificando E5 para no exponer la aceptación del pago del 60%.
>
> **N2 · Observabilidad:** el SOW §3.5 y E7 piden **Dashboard CloudWatch con 6 widgets**. El ADR v3.0 elimina CloudWatch a favor de Vector + S3+Athena + Prometheus + Grafana + Alertmanager + SNS. ¿Cuál ejecuto?
> - **Opción A (default):** CloudWatch como dice el SOW. Adopto `awsfirelens` con Fluent Bit en los Task Defs para que la migración futura a Vector sea trivial (deuda diferida).
> - **Opción B:** stack desagregado directo, requiere adenda al SOW como en N1.
>
> **N3 · Topología AZ:** la VPC actual está Single-AZ `us-east-1a` (ADR-002 v1.x). El ADR-002 v3.0 §4.4 dice _"subnets pub/priv/db en 3 AZ"_. La VPC base ya está cerrada como E1 del SOW-001. ¿Confirmás que mantenemos Single-AZ en DEV/QA para Sprint 1 y la migración a 3-AZ queda para PROD en Sprint 2?
>
> **N4 · NAT Gateway:** el ADR v3.0 §4.4 menciona _"NAT GW (1 en DEV/QA, 3 en PROD)"_. La VPC actual no tiene NAT (ADR-001 anterior). El SOW-002 no menciona NAT. ¿Necesito NAT para alguna ruta concreta (egress de Lambda WG a Twilio status callbacks, por ejemplo) o seguimos sin NAT? Sin NAT, el outbound desde Lambda WG hacia internet no funciona; con NAT son ~USD 32/mes/AZ.
>
> **Dependencias que sigo esperando** (sin urgencia hasta Día 7–13):
> - Dockerfiles funcionales en los 7 repos `agt-*` (Día 7).
> - `.env.example` con valores reales para Secrets Manager (Día 7).
> - ARN del certificado ACM para el dominio interno del ALB (Día 8).
> - YAML de intents Lex (Día 5) — si no, redacto `Inscribir`, `ConsultarDeuda`, `ConsultarNotas` con 10 utterances mínimas.
> - CIDR red on-premise UDABOL (Día 10) — para SG del Legacy Adapter.
> - Credenciales Twilio (Día 13) — para smoke test E7.
> - Confirmación del estado real de la VPN S2S del SOW-001 (Día 10).
>
> Avanzo hoy con Bloque A.0 (bootstrap IAM operativo `devops-ayrton` desde `cloudadmin`) y A.1 (estructura repos). El template MSK vs EventBridge y CloudWatch vs Vector lo dejo en stand-by hasta tu respuesta — son ~26 h de trabajo (Bloques D y E) que no quiero quemar dos veces.
>
> Ayrton

---

## 11. APÉNDICE — Bootstrap IAM operativo desde `cloudadmin` (A.0)

Para no operar el sprint con root, plan A.0:

```bash
# Desde cloudadmin (root) en DEV
aws iam create-user --user-name devops-ayrton

aws iam create-policy \
  --policy-name Sprint1DeployPolicy \
  --policy-document file://policies/sprint1-deploy-policy.json

aws iam attach-user-policy \
  --user-name devops-ayrton \
  --policy-arn arn:aws:iam::245650696072:policy/Sprint1DeployPolicy

# Generar access key inicial — pegar a 1Password, NO commitear
aws iam create-access-key --user-name devops-ayrton

# Alternativa preferida: usar IAM Identity Center con permission set Sprint1Deploy
# Pero requiere Management Account access que no tenés todavía
```

`sprint1-deploy-policy.json` (recortado, ver `policies/` en repo):
- `cloudformation:*` sobre stacks `udabol-*`.
- `ecs:*`, `ecr:*` (los repos lo crea CFN, las imágenes las pusheás).
- `rds:*` sobre instancias `udabol-*`.
- `kafka:*` (MSK — solo si Plan A) **o** `events:*` (EventBridge — solo si Plan B).
- `lex-v2:*`.
- `lambda:*`, `apigateway:*`.
- `secretsmanager:*` sobre `agt/*`.
- `logs:*` sobre `/agt/*` y `/aws/lambda/*`.
- `iam:PassRole` solo a roles `proy-app-*` y `agt-*`.
- `iam:GetRole`, `iam:CreateRole` solo para crear roles `agt-*` (CFN los crea).

Mismo proceso en QA. Validar con:
```bash
aws sts get-caller-identity --profile proy-dev
aws sts get-caller-identity --profile proy-qa
```

---

*Plan v1.1 — 2026-05-22. Cambios v1.0 → v1.1 en §0.2 (conflictos SOW vs ADR), §3.5/§3.6 (planes A/B), §5 (validaciones), §10 (email reducido a 4 decisiones), §11 (apéndice IAM bootstrap).*
