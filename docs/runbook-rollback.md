# Runbook — Rollback de despliegue fallido

> **Cuándo usar:** un deploy a `prod` (o `qa`) falló y hay que volver al estado anterior.
> **Audiencia:** cualquier persona oncall del equipo iaapp.
> **Tiempo objetivo:** 15 minutos para detectar + decidir; 30 minutos para ejecutar.

---

## Árbol de decisión rápido

```
Deploy falla
  │
  ├─ ¿Stack Status?
  │     │
  │     ├─ UPDATE_ROLLBACK_COMPLETE        → ✅ AWS rolloback automático ya restauró. Investigar causa.
  │     │
  │     ├─ UPDATE_ROLLBACK_FAILED          → 🔴 Rollback automático también falló. Ir a §3.
  │     │
  │     ├─ UPDATE_IN_PROGRESS              → ⏳ Aún corriendo. Esperar 10 min y revaluar.
  │     │
  │     ├─ UPDATE_ROLLBACK_IN_PROGRESS     → ⏳ AWS rolling back. Esperar.
  │     │
  │     └─ CREATE_FAILED + DELETE_FAILED   → 🔴 Stack medio creado, no puede borrarse. Ir a §4.
  │
  └─ ¿La aplicación responde?
        ├─ Sí, pero degradada               → Considerar rollback voluntario (§2)
        └─ No                               → Comunicar incidente + rollback (§2)
```

---

## §1. Verificar estado del stack

```bash
aws cloudformation describe-stacks \
  --stack-name iaapp-vpc-prod \
  --region us-east-1 \
  --query 'Stacks[0].[StackStatus,StackStatusReason]' \
  --output table
```

Estados posibles y significado:

| Estado                          | Significado                                              | Acción                          |
|---------------------------------|----------------------------------------------------------|---------------------------------|
| `UPDATE_COMPLETE`               | Deploy exitoso                                           | No requiere acción              |
| `UPDATE_ROLLBACK_COMPLETE`      | Deploy falló, rollback automático funcionó               | Investigar causa, no urgente    |
| `UPDATE_IN_PROGRESS`            | Deploy aún corriendo                                     | Esperar (timeout: 60 min default)|
| `UPDATE_ROLLBACK_IN_PROGRESS`   | Rolling back                                             | Esperar                         |
| `UPDATE_ROLLBACK_FAILED`        | Rollback no pudo completarse                             | **§3** — intervención manual    |
| `CREATE_FAILED`                 | Primer despliegue falló                                  | **§4** — limpiar + redesplegar  |

---

## §2. Rollback voluntario (la app desplegada está degradada)

Si el deploy fue exitoso técnicamente pero la aplicación se está comportando mal, podemos volver al estado anterior haciendo un nuevo deploy con el commit previo.

### Identificar el commit estable previo

```bash
# Buscar deploys recientes a prod por tag CommitHash
aws resourcegroupstaggingapi get-resources \
  --tag-filters \
    Key=Project,Values=iaapp \
    Key=Environment,Values=prod \
  --resource-type-filters cloudformation:stack \
  --query 'ResourceTagMappingList[*].[Tags[?Key==`CommitHash`].Value | [0],ResourceARN]' \
  --output table
```

Cruzar con `git log` para encontrar el SHA estable previo (típicamente el deploy anterior al que rompió).

### Ejecutar el rollback

```bash
# 1. Hacer checkout del commit estable
git checkout <sha-estable>

# 2. Disparar deploy-prod con ese commit
gh workflow run deploy-prod.yml \
  --ref <sha-estable> \
  -f stack=vpc \
  -f confirm=IAAPP-PROD \
  -f ticket=ROLLBACK-$(date +%Y%m%d)
```

Esto requiere los 2 reviewers normales — **no hay atajo**. La razón es deliberada: incluso un rollback puede empeorar las cosas si no se piensa.

### Si la urgencia justifica saltar la espera de 10 min

1. Avisar al equipo en el canal de incidentes
2. Un admin de GitHub puede temporalmente bajar el wait timer del environment `production`
3. Hacer el deploy
4. **Restaurar el wait timer a 10 minutos inmediatamente después**

---

## §3. UPDATE_ROLLBACK_FAILED — recuperación manual

Esto pasa cuando CloudFormation no puede restaurar el estado anterior. Causas típicas:

- Recurso fue modificado fuera de CloudFormation (drift)
- Recurso depende de algo que ya no existe
- Falta de permisos para revertir cierta acción
- Database con cambios irreversibles (RDS cluster, datos en buckets)

### Procedimiento

```bash
# 1. Ver qué recursos fallaron en el rollback
aws cloudformation describe-stack-events \
  --stack-name iaapp-vpc-prod \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`UPDATE_ROLLBACK_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table

# 2. Para cada recurso problemático, decidir si:
#    a) Se puede arreglar manualmente (re-crear el recurso faltante, etc.)
#    b) Hay que saltar el recurso del rollback

# 3. Si hay que saltar (caso b):
aws cloudformation continue-update-rollback \
  --stack-name iaapp-vpc-prod \
  --resources-to-skip <LogicalResourceId1> <LogicalResourceId2> \
  --region us-east-1

# 4. Esperar a que termine
aws cloudformation wait stack-rollback-complete \
  --stack-name iaapp-vpc-prod \
  --region us-east-1
```

⚠️ **Saltar recursos en el rollback los deja en estado inconsistente.** Después del rollback, hay que arreglarlos manualmente y aplicar un nuevo deploy que los re-incorpore al stack.

---

## §4. CREATE_FAILED + DELETE_FAILED

Pasa cuando el primer deploy de un stack falló y luego el delete también falla. Recursos huérfanos quedan facturando.

```bash
# 1. Ver recursos huérfanos
aws cloudformation describe-stack-events \
  --stack-name iaapp-<stack>-<env> \
  --region us-east-1 \
  --query 'StackEvents[?starts_with(ResourceStatus, `CREATE`) || starts_with(ResourceStatus, `DELETE`)]' \
  --output table

# 2. Para cada recurso huérfano, eliminarlo manualmente
# Ejemplos típicos:
aws ec2 release-address --allocation-id eipalloc-xxx                       # EIP
aws ec2 delete-nat-gateway --nat-gateway-id nat-xxx                        # NAT GW
aws ec2 delete-vpc --vpc-id vpc-xxx                                        # VPC (último)

# 3. Una vez limpio:
aws cloudformation delete-stack --stack-name iaapp-<stack>-<env>

# 4. Verificar que el stack ya no aparece
aws cloudformation list-stacks \
  --stack-status-filter DELETE_COMPLETE \
  --query 'StackSummaries[?StackName==`iaapp-<stack>-<env>`]'
```

---

## §5. Post-incidente

Después de cualquier rollback:

1. **Comunicación:** mensaje en canal del equipo con: qué falló, qué se hizo, estado actual
2. **Postmortem corto** (incluso para incidentes pequeños):
   - Timeline (descubrimiento, decisión, acción, resolución)
   - Causa raíz
   - Acciones para evitar recurrencia
3. **Actualizar este runbook** si descubrimos un caso no contemplado
4. **Crear issue** para fix preventivo en el código

### Plantilla de postmortem

```markdown
## Incidente — iaapp prod — YYYY-MM-DD

**Severidad:** SEV-2
**Duración:** XX minutos
**Resuelto por:** @nombre

### Timeline (UTC)
- HH:MM Deploy inicia
- HH:MM Deploy reporta UPDATE_ROLLBACK_FAILED
- HH:MM Equipo notificado
- HH:MM Decisión: continue-update-rollback con skip de XYZ
- HH:MM Stack en UPDATE_ROLLBACK_COMPLETE
- HH:MM App verificada estable

### Causa raíz
(Qué pasó técnicamente)

### Acciones preventivas
- [ ] PR #XX — agregar smoke test que detecte ABC
- [ ] Actualizar runbook con caso DEF
```

---

## §6. Contactos en orden de escalamiento

1. Tú (el oncall, lee este runbook)
2. Otro miembro del equipo iaapp
3. ayrton.irusta@gmail.com (owner técnico)
4. AWS Support (si tienes plan Business o superior)

---

*Mantenido por el equipo iaapp · UDABOL · Última revisión: 2026-05-05*
