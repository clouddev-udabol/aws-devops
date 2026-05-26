# Observaciones de Arquitectura — SOW-002 Sprint 1
**Autor:** Ayrton Irusta
**Fecha:** 2026-05-22
**Versión:** 1.0
**Propósito:** Registrar conflictos, decisiones pendientes y recomendaciones para modificar la propuesta de arquitectura antes de continuar el despliegue.

---

## 1. Conflictos SOW-002 firmado vs ADR-002 v3.0 firmado

Existen contradicciones directas entre dos documentos ambos firmados. Requieren resolución explícita de Carlos Álvarez (Coordinador Técnico) antes del Día 4.

### C1 — Bus de eventos (🟥 CRÍTICO — bloquea E5)

| | SOW-002 (firmado mayo 2026) | ADR-002 v3.0 (firmado 14-may-2026) |
|---|---|---|
| **Decisión** | Amazon MSK Serverless con 3 topics | MSK eliminado → Outbox PG + EventBridge custom bus |
| **Referencia** | §2.1, §3.4, Entregable E5 | §4.1, §4.3, §4.4 |
| **Justificación ADR** | — | "Volumen UDABOL no justifica un broker Kafka administrado" |
| **Impacto contractual** | E5 acceptance literal: "MSK cluster activo, 3 topics creados verificables en consola" | Outbox no satisface este criterio literalmente |
| **Costo estimado** | ~USD 35/mes/cuenta base + throughput | ~USD 2/mes (EventBridge + Lambda relay) |

**Recomendación:**
- **Plan A (default):** Desplegar MSK como dice el SOW → asegura aceptación E5 → **pago 60% garantizado**. Documentar migración a Outbox+EventBridge como deuda técnica en Sprint 2 (SOW-003).
- **Plan B:** Outbox+EventBridge directo → ahorro USD 33/mes/cuenta → **requiere adenda firmada al SOW modificando criterio E5 antes del Día 4**.

**Acción requerida de Carlos:** Respuesta escrita (email/WhatsApp) antes del Día 3. Sin respuesta → Plan A por default.

> ✅ **RESUELTO 2026-05-25 — Plan A ejecutado:** SOW-002 §2.5 confirmó MSK Serverless con SASL/IAM. Stacks `udabol-msk-dev` y `udabol-msk-qa` en CREATE_COMPLETE. Topics `enrollment.events`, `payment.events`, `query.audit` creados. Puerto 9098 (no 9092). Ver bitácora D.2.

---

### C2 — Observabilidad (🟥 CRÍTICO — bloquea E7)

| | SOW-002 (firmado mayo 2026) | ADR-002 v3.0 (firmado 14-may-2026) |
|---|---|---|
| **Decisión** | CloudWatch Dashboard + Logs + Alarmas | CloudWatch eliminado → Vector + S3/Athena + Prometheus + Grafana + Alertmanager + SNS |
| **Referencia** | §3.5, §3.3, Entregable E7 | §3, §4.3 |
| **Justificación ADR** | — | "Violación de Single Responsibility" |
| **Impacto contractual** | E7: "Dashboard udabol-erp-agent-{env} con 6 widgets activos" | Stack desagregado no satisface este criterio |
| **Costo estimado** | ~USD 8/mes/cuenta | ~USD 21/mes/cuenta (+13) |

**Recomendación:**
- **Plan A (default):** CloudWatch como dice el SOW → asegura aceptación E7. Siembro `awsfirelens + Fluent Bit` en los Task Defs para que la migración futura a Vector sea sin fricción. **Costo extra: $0**.
- **Plan B:** Stack desagregado directo → **requiere adenda firmada al SOW modificando criterio E7 antes del Día 4**.

**Acción requerida de Carlos:** Misma respuesta que C1.

> ✅ **RESUELTO 2026-05-26 — variante adoptada:** SOW-002 §2.6 define OTel Collector (ADOT) + CloudWatch/X-Ray como stack de observabilidad para DEV/QA. Stack `udabol-otel-collector-dev/qa` COMPLETADO. Log group `/udabol/{env}/agt` con JSON estructurado. E7 dashboard CloudWatch diferido a Sprint 2. Ver bitácora E.1.

---

### C3 — Topología AZ (⚠️ Importante)

| | Estado actual | ADR-002 v3.0 |
|---|---|---|
| **Decisión** | VPC Single-AZ `us-east-1a` (ADR-002 v1.x) | "subnets pub/priv/db en 3 AZ" |
| **Impacto** | La VPC base está cerrada (E1 SOW-001 liquidado) | Re-despliegue = costo y tiempo adicional no contratado |

**Recomendación:** Mantener Single-AZ en DEV/QA para Sprint 1. La migración a 3-AZ aplica a PROD en Sprint 2/3 donde el costo se justifica por HA real. Si Carlos confirma que 3-AZ es necesario en DEV/QA ahora, requiere **cambio de alcance y ajuste de horas**.

**Acción requerida de Carlos:** Confirmación por escrito antes del Día 7.

> ✅ **RESUELTO:** SOW-002 §2.2 confirma Single-AZ us-east-1a para DEV/QA. VPC base (iaapp-vpc-dev/qa) mantenida. Migración a 3-AZ diferida a PROD en Sprint 2.

---

### C4 — NAT Gateway (⚠️ Importante)

| | Estado actual | ADR-002 v3.0 §4.4 |
|---|---|---|
| **Decisión** | Sin NAT Gateway DEV/QA (ADR-001, ahorro ~$32/mes/AZ) | "NAT GW (1 en DEV/QA, 3 en PROD)" + $95/mes estimado |
| **Impacto funcional** | Lambda agt-whatsapp-gateway **no puede hacer egress a internet** sin NAT | Twilio callbacks de status (outbound) requieren NAT |

**Análisis:** Twilio opera principalmente en modo webhook (entrante hacia API GW). El único caso que requiere NAT desde Lambda hacia Twilio es el status callback (confirmación de envío). Si ese caso no aplica en Sprint 1, **sin NAT es suficiente**.

**Recomendación:** No agregar NAT en DEV/QA por defecto. Si aparece el caso de use concreto de egress → agregar NAT solo en App-layer (~USD 32/mes/AZ). Solicitarlo por escrito.

**Acción requerida de Carlos:** Confirmar si hay egress requerido en Sprint 1 antes del Día 8.

> ✅ **RESUELTO 2026-05-25:** SOW-002 §2.2 incluye NAT en alcance. Se implementó **NAT Instance** (EC2 fck-nat t4g.nano ARM Graviton) en lugar de NAT Gateway — misma funcionalidad, costo ~$3/mes vs $32/mes. Stack `udabol-nat-instance-dev/qa` CREATE_COMPLETE. Ver bitácora D.4 y ADR FinOps `SOW/adr/ADR-FINOPS-001-red-optimizada-dev-qa.md`.

---

### C5 — Naming repos (✅ Resuelto)

ADR-002 v3.0 menciona naming `udabol-*`. Los repos reales en GitHub son `agt-*`. Se confirma: **usar `agt-*` como naming canónico**. El ADR está desactualizado en este punto.

---

### C6 — Budget DEV/QA (✅ Adoptar)

| | SOW-001 actual | ADR-002 v3.0 |
|---|---|---|
| **Budget DEV** | USD 100/mes | USD 150/mes |
| **Budget QA** | USD 100/mes | USD 200/mes |

ADR-002 v3.0 sube los budgets — favorable. **Adoptar en Sprint 1.** Actualizar stacks `iaapp-budgets-dev` y `iaapp-budgets-qa` con los nuevos montos.

---

## 2. Decisiones de arquitectura que sí están alineadas (sin conflicto)

Estos puntos del ADR-002 v3.0 **no contradicen el SOW** y deben implementarse directamente:

| Componente | Decisión adoptada | Beneficio |
|-----------|------------------|-----------|
| `agt-intent-parser` arquitectura hexagonal | Implementar `NLUEnginePort` con adapter Lex V2 en R1 | R2 (Bedrock) pasa sin reescribir |
| Service Discovery | Cloud Map namespace `agt.local` (ADR §4.4) | Sin IPs hardcodeadas entre servicios |
| Log driver | `awsfirelens + Fluent Bit` en lugar de `awslogs` directo | Cumple E7 (CW primario) + migration path a Vector (S3 secundario, costo $0) |
| Sidecar OTEL | `aws-otel-collector` con `OTEL_DISABLED=true` por default | Toggle en Sprint 2 sin tocar Task Def |
| Naming stacks CFN | `udabol-{component}-{env}` | Consistente con ADR v3.0 |
| ECR repos | `agt-{service}` (sin prefijo `udabol/`) | Consistente con repos GitHub |

---

## 3. Observaciones operativas

### OBS-001 — SSO multisesión (impacto en todos los sprints)

**Problema encontrado en A.0:** La cuenta `cloudadmin` y la cuenta `ayrton.devops` usan el mismo SSO portal (`ssoins-7223753b6943f944`). El AWS CLI cachea el token SSO por `sso-session` name. Si la sesión `fundaciondev` tiene token de `cloudadmin`, los perfiles operativos (`proy-dev`, `proy-qa`) deben usar una sesión separada (`proy`) para que `ayrton.devops` pueda autenticarse independientemente.

**Solución implementada:** Sesión SSO `proy` separada en `~/.aws/config`. Login: `aws sso login --profile proy-dev` autenticando como `ayrton@udabol.edu.bo`.

**Regla para el futuro:** Nunca compartir `sso_session` entre perfiles que usan usuarios IAM IC distintos. Crear una sesión named por usuario o por grupo de perfiles del mismo usuario.

---

### OBS-002 — VPC Peering DEV↔QA (conflicto con ADR anterior)

El ADR-002 v3.0 §4.5 menciona VPC Peering DEV↔QA y QA↔PROD. El ADR-001 establecía "VPCs isla" (sin peering). **El Sprint 1 NO incluye peering en su alcance E1–E7.** Diferir a clarificación con Carlos en Sprint 2. Riesgo: si el Legacy Adapter necesita acceder a recursos en QA desde DEV, el peering sería necesario antes.

---

### OBS-003 — Stacks CFN: naming iaapp-* vs udabol-*

Los stacks de SOW-001 usan `iaapp-*` (ej. `iaapp-vpc-dev`, `iaapp-budgets-dev`). Los stacks de SOW-002 deben usar `udabol-*` (ej. `udabol-ecs-cluster-dev`) según ADR-002 v3.0. **No hay conflicto** — son componentes distintos. Los stacks `iaapp-*` se mantienen como base, los nuevos de Sprint 1 usan `udabol-*`.

---

### OBS-004 — ACM Certificate para ALB interno

El ALB interno requiere certificado ACM para HTTPS/443. Para dominios internos como `*.dev.udabol.internal` se necesita Route 53 Hosted Zone privada. Si no existe:
- **Opción A:** Certificado ACM para un dominio público que Carlos controla (ej. `internal.udabol.edu.bo`) con validación DNS.
- **Opción B:** ALB con listener HTTPS y SNI default (cert auto-firmado temporal para DEV/QA).
- **Opción C:** ALB solo HTTP/80 en DEV (no recomendado, viola buenas prácticas).

**Pendiente:** ARN del cert ACM o confirmación del dominio → Carlos, Día 8.

---

### OBS-005 — agt-readmodel: Lambda vs ECS

El SOW §2.1 menciona `agt-readmodel` como "Lambda + RDS PG". El SOW §3.3 (Bloque C) no lo incluye en las Task Definitions Fargate. **Decisión adoptada:** `agt-readmodel` es una función Lambda (no ECS), invocada via event source mapping (MSK en Plan A) o EventBridge rules (Plan B). Esto es coherente con "proyecciones de lectura" — no es un servicio de larga duración.

> ✅ **CORREGIDO 2026-05-25:** SOW-002 §2.3 especifica `agt-readmodel` como **ECS Fargate** (256 CPU / 512 MB), no Lambda. El `PLAN-DESPLIEGUE` interno tenía un error de diseño. Se implementó como ECS service con `DesiredCount=0` en el stack `udabol-ecs-services-dev/qa`. El service se activa (DesiredCount=1) cuando el dev team entregue la imagen Docker en ECR. Puerto: 8085, health check: `/v1/healthz`.

---

## 4. Preguntas para Carlos (email borrador)

> **Asunto:** SOW-002 Sprint 1 — Decisiones técnicas necesarias antes del Día 4
>
> Carlos, con los accesos operativos ya resueltos, hay **4 decisiones que bloquean los Bloques D y E** (~26 h de trabajo) porque existe contradicción entre el SOW-002 firmado y el ADR-002 v3.0 firmado el 14-may-2026. Necesito respuesta escrita antes del **Día 3**:
>
> **N1 · Bus de eventos** (bloquea E5, ~14 h):
> - Opción A (default): MSK Serverless como dice el SOW → criterio E5 cumplido literalmente.
> - Opción B: Outbox PG + EventBridge como dice ADR v3.0 → ahorro $33/mes pero necesita adenda al SOW modificando el criterio de E5.
>
> **N2 · Observabilidad** (bloquea E7, ~11 h):
> - Opción A (default): Dashboard CloudWatch como dice el SOW → criterio E7 cumplido literalmente.
> - Opción B: Vector + Prometheus + Grafana como dice ADR v3.0 → necesita adenda al SOW.
>
> **N3 · VPC Single-AZ:** La VPC DEV/QA está Single-AZ (SOW-001 cerrado). ADR v3.0 dice 3-AZ. ¿Confirmás Single-AZ para Sprint 1 y 3-AZ se diferiere a PROD en Sprint 2?
>
> **N4 · NAT Gateway:** ADR v3.0 menciona NAT en DEV/QA. La VPC actual no tiene NAT. ¿Hay algún flujo de egress concreto que lo requiera en Sprint 1? Sin egress confirmado, sigo sin NAT (ahorro $32/mes/AZ).
>
> Sin respuesta al Día 3 → **ejecuto Plan A en todo** (literal SOW) y documento deuda técnica.
>
> Ayrton

---

## 5. Impacto en horas si se adopta Plan B (referencia)

| Cambio | Horas adicionales | Justificación |
|--------|-------------------|---------------|
| Redactar + gestionar adenda SOW para C1 y C2 | +2 h | Redacción + revisión legal |
| Refactor templates D.2 (MSK → Outbox+EventBridge) | +1 h | Cambio menor en CFN |
| Refactor templates E.1 (CW → Vector+Prometheus+Grafana) | +8 h | Stack nuevo de 4 servicios ECS |
| **Total impacto Plan B** | **+11 h** | Dentro del buffer 15% (10.35 h) |

> Plan B supera el buffer de contingencia si se adoptan C1 y C2 juntos. Si Carlos quiere Plan B, se debe formalizar como adenda con horas adicionales o reducir alcance en otro bloque.

---

*Documento creado 2026-05-22 · Actualizado 2026-05-26 con resoluciones reales de C1–C4 y OBS-005*
