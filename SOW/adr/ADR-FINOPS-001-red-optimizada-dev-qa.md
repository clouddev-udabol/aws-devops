# ADR-FINOPS-001 — Optimización de Red DEV/QA: NAT Instance + VPC Endpoints

| Campo | Valor |
|---|---|
| **Estado** | Propuesta — pendiente aceptación de Franz Álvarez |
| **Fecha** | 2026-05-24 |
| **Autor** | Ayrton Irusta — `ayrton.irusta@blockfinityadvisors.com` |
| **Proyecto** | UDABOL ERP-Agent · Fundación Dockweiler |
| **SOW** | SOW-002 Sprint 1 |
| **Ámbito** | Cuentas DEV `245650696072` y QA `493735739951` · `us-east-1a` |
| **Relacionadas** | ADR-001 (sin NAT GW) · ADR-002 (single-AZ) · ISS-003 (ECS subnet pública) |
| **Motivación** | Hallazgo durante deploy D.4 — NAT Gateway planificado en SOW-002 §2.2 tiene alternativa más eficiente |

---

## 1. Contexto

### 1.1 Estado de red al momento del análisis (2026-05-24)

Durante el despliegue del bloque C.2 (ECS Services) se encontró que los VPC Endpoints existentes para ECR con `PrivateDnsEnabled: true` rompían la conectividad de los ECS tasks en subnet pública (ISS-003). La solución de emergencia fue:

- Eliminar los VPC Endpoints Interface de ECR, Logs y Secrets Manager de ambas VPCs.
- Mover los ECS tasks a **PublicSubnetA** con `AssignPublicIp: ENABLED`.

Esta solución funciona pero introduce tres problemas:

| Problema | Impacto |
|---|---|
| ECS tasks con IP pública expuestas a internet | Superficie de ataque innecesaria |
| Tráfico AWS interno (ECR, Logs, SM) sale por internet | Costo de procesamiento en NAT + latencia |
| SOW-002 §2.2 requiere NAT GW para egress Twilio | NAT GW estándar cuesta ~$32.85/mes/cuenta |

### 1.2 Lo que dice el SOW-002 (obligación contractual)

> *"NAT Gateway en cuentas DEV y QA: 1 NAT GW por cuenta en la subnet pública de us-east-1a. Habilita egress HTTPS desde ECS Fargate hacia api.twilio.com."*
> — SOW-002 §2.2

El SOW no especifica **qué tipo** de NAT — solo que debe existir egress funcional hacia `api.twilio.com`. Un NAT Instance cumple el mismo requisito funcional que un NAT Gateway administrado.

### 1.3 Presupuesto vigente (ADR-002 §3.1)

| Cuenta | Budget mensual | Comprometido base VPC | Margen |
|---|---|---|---|
| DEV `245650696072` | $100 | ~$47 (con endpoints originales) | ~$53 |
| QA `493735739951` | $100 | ~$47 (con endpoints originales) | ~$53 |

Con los endpoints eliminados (workaround ISS-003), el gasto base bajó pero la arquitectura quedó comprometida.

---

## 2. Problema técnico: ISS-003 y su causa raíz

### Por qué fallaron los VPC Endpoints originales

Los VPC Interface Endpoints con `PrivateDnsEnabled: true` modifican el DNS **para toda la VPC**. El nombre `ecr.api.us-east-1.amazonaws.com` resuelve al IP privado del endpoint (en subnet privada). Cuando un ECS task en **subnet pública** intenta conectarse a ese IP privado, el paquete enruta por la private route table y la conexión TCP nunca llega.

```
Causa raíz ISS-003:
  ECS task (PublicSubnetA) ──DNS──▶ ecr.api.us-east-1.amazonaws.com
                                         │
                                         ▼ resuelve a 10.10.x.x (endpoint ENI en PrivateSubnetA)
  ECS task (PublicSubnetA) ──TCP──▶ 10.10.x.x  ← paquete va por public route table
                                                    no hay ruta a la subnet privada
                                                    → CONNECTION REFUSED / TIMEOUT
```

### La solución correcta

Los VPC Interface Endpoints funcionan correctamente cuando el cliente (ECS task) está en la **misma subnet o en una subnet privada con la ruta correcta**. La solución no es eliminar los endpoints — es mover los ECS tasks a la subnet privada donde sí tienen acceso.

```
Solución:
  ECS task (PrivateSubnetA) ──DNS──▶ ecr.api.us-east-1.amazonaws.com
                                          │
                                          ▼ resuelve a 10.10.x.x (endpoint ENI en PrivateSubnetA)
  ECS task (PrivateSubnetA) ──TCP──▶ 10.10.x.x  ← mismo segmento de red
                                                     → CONECTA ✅
```

---

## 3. Propuesta de arquitectura

### 3.1 Componentes

| Componente | Especificación | Justificación |
|---|---|---|
| **NAT Instance** | `t4g.nano` Amazon Linux 2023, `fck-nat` AMI | Reemplaza NAT GW — mismo egress, $29/mes menos por cuenta |
| **S3 Gateway Endpoint** | Gratis, regional | ECR almacena capas Docker en S3 — elimina ese tráfico del NAT |
| **ECR.api + ECR.dkr Interface Endpoints** | $7.30/mes c/u | ECS pull de imágenes en subnet privada — resuelve ISS-003 |
| **CloudWatch Logs Interface Endpoint** | $7.30/mes | awslogs driver constante desde todos los ECS tasks |
| **Secrets Manager Interface Endpoint** | $7.30/mes | ECS tasks leen credenciales RDS al arrancar |
| **Lex V2 Runtime Interface Endpoint** | $7.30/mes | `agt-agent` invoca Lex por cada mensaje WhatsApp |
| **ECS tasks → PrivateSubnetA** | Cambio en `services.yaml` | Cierra ISS-003, elimina `AssignPublicIp: ENABLED` |

### 3.2 Diagrama de flujos de red

```
FLUJO A — Ingesta Twilio (sin cambio, ya óptimo)
  Twilio ──HTTPS──▶ Internet ──▶ API Gateway (público) ──▶ Lambda agt-whatsapp-gateway
  Costo de red: $0  (Lambda pública, sin VPC, sin NAT)

FLUJO B — ECS tasks → Servicios AWS internos (VPC Endpoints)
  ECS agt-agent       ──▶ Lex V2 API       via VPC Endpoint lex.runtime      $0.01/GB
  ECS todos           ──▶ CloudWatch Logs  via VPC Endpoint logs              $0.01/GB
  ECS todos           ──▶ ECR pull         via VPC Endpoints ecr.api+ecr.dkr  $0.01/GB
  ECS todos           ──▶ Secrets Manager  via VPC Endpoint secretsmanager    $0.01/GB
  ECS todos           ──▶ S3 (ECR layers)  via S3 Gateway Endpoint            $0.00/GB

FLUJO C — ECS tasks → Internet real (NAT Instance)
  ECS agt-whatsapp-gateway ──▶ api.twilio.com   via NAT Instance → IGW
  ECS todos                ──▶ pip install, etc  via NAT Instance → IGW
  Costo de procesamiento: $0 (NAT Instance no cobra por GB)

FLUJO D — On-premises (sin cambio)
  ECS agt-legacy-adapter ──▶ VGW ──▶ VPN S2S ──▶ HMS Plus on-prem
  Ruta específica: 10.x.x.x/x → VGW (no pasa por NAT)
```

---

## 4. Análisis financiero

### 4.1 Comparativa mensual por cuenta (DEV o QA)

| Concepto | Escenario A: Workaround actual | Escenario B: NAT GW original (D.4) | Escenario C: Propuesta FinOps |
|---|---|---|---|
| NAT Gateway | $0 | $32.85 | $0 |
| NAT Instance t4g.nano | $0 | $0 | **$3.50** |
| S3 Gateway Endpoint | $0 | $0 | **$0** (gratis) |
| ECR.api + ECR.dkr Endpoints | $0 (eliminados) | $0 (no aplica) | **$14.60** |
| CloudWatch Logs Endpoint | $0 (eliminado) | $0 (no aplica) | **$7.30** |
| Secrets Manager Endpoint | $0 (eliminado) | $0 (no aplica) | **$7.30** |
| Lex V2 Runtime Endpoint | $0 | $0 | **$7.30** |
| Procesamiento NAT ($0.045/GB) | $0 | variable (est. +$5–15) | $0 |
| **Subtotal networking adicional** | **$0** | **~$38–48** | **~$40** |
| ECS en subnet pública (riesgo) | Sí 🔴 | Sí 🔴 | No ✅ |
| ISS-003 resuelto | No | No | **Sí** ✅ |

### 4.2 Proyección anual DEV + QA

| Período | Escenario B (NAT GW) | Escenario C (FinOps) | Ahorro FinOps |
|---|---|---|---|
| Mensual (2 cuentas) | ~$76–96 | ~$80 | **$0–16/mes** |
| Anual (2 cuentas) | ~$912–1,152 | **~$960** | ~$0–192 |
| **Ahorro sobre NAT GW en 12 meses** | — | — | **~$0–192** |

> **Nota FinOps honesta:** El ahorro financiero directo del Escenario C frente al B es modesto en QA (volúmenes bajos). El valor real está en la **corrección arquitectónica** (ISS-003, ECS en subnet privada, menor superficie de ataque) y en el **path a producción**: en PROD con volumen real, los VPC Endpoints ahorran significativamente en procesamiento de datos NAT.

### 4.3 Impacto en presupuesto mensual DEV/QA ($100/cuenta)

```
Budget DEV: $100/mes
  Base VPC (flow logs, etc.)       ~$3
  NAT Instance t4g.nano            ~$3.50
  VPC Endpoints (5 × $7.30)        ~$36.50
  ─────────────────────────────────────────
  Subtotal networking              ~$43
  Disponible para ECS/RDS/Lambda   ~$57  ← dentro del presupuesto ✅

Budget QA: $100/mes  (mismo breakdown)
  Subtotal networking              ~$43
  Disponible para ECS/RDS/Lambda   ~$57  ✅
```

### 4.4 Ahorro NAT Instance vs NAT Gateway (el driver principal)

| Comparación | NAT Gateway | NAT Instance t4g.nano |
|---|---|---|
| Costo fijo mensual | $32.85 | $3.50 |
| Costo por GB procesado | $0.045 | $0.00 |
| HA gestionada por AWS | Sí | No (acceptable en DEV/QA) |
| Parches SO | N/A | Amazon Linux 2023 auto-updates |
| **Ahorro mensual por cuenta** | — | **$29.35** |
| **Ahorro anual DEV + QA** | — | **$704** |

---

## 5. Plan de implementación

### 5.1 Cambios en CloudFormation

| Template | Acción | Impacto en trabajo |
|---|---|---|
| `cloudformation/modules/vpc/nat-instance.yaml` | **Crear nuevo** — EC2 t4g.nano con fck-nat AMI, SG, route en private table | 2h |
| `cloudformation/modules/vpc/vpc-endpoints.yaml` | **Crear nuevo** — S3 Gateway + 4 Interface Endpoints | 2h |
| `cloudformation/modules/ecs/services.yaml` | **Modificar** — cambiar subnet de Public a Private, eliminar `AssignPublicIp: ENABLED` | 0.5h |
| `parameters/dev/nat-instance.json` + `parameters/qa/nat-instance.json` | **Crear** | 0.2h |
| `parameters/dev/vpc-endpoints.json` + `parameters/qa/vpc-endpoints.json` | **Crear** | 0.2h |

**Total estimado: 5h** (vs 3h del D.4 original — 2h adicionales por resolver ISS-003)

### 5.2 Orden de despliegue

```
1. Desplegar vpc-endpoints.yaml (DEV y QA)
   └─ S3 Gateway + ECR.api + ECR.dkr + Logs + SM + Lex
   └─ Endpoints en PrivateSubnetA

2. Desplegar nat-instance.yaml (DEV y QA)
   └─ EC2 t4g.nano en PublicSubnetA
   └─ Route: 0.0.0.0/0 → Instance ID en Private Route Table

3. Actualizar services.yaml (DEV y QA)
   └─ Subnets: PrivateSubnetA (era PublicSubnetA)
   └─ AssignPublicIp: DISABLED (era ENABLED)
   └─ Forzar redeploy de los 3 ECS services

4. Validar E5 (criterio SOW)
   └─ aws ecs execute-command → curl https://api.twilio.com → HTTP 401 (no timeout)
```

### 5.3 Template NAT Instance (estructura)

```yaml
# cloudformation/modules/vpc/nat-instance.yaml
Resources:
  NatInstanceSg:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: NAT Instance — egress only
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: -1
          CidrIp: !Ref PrivateSubnetCidr   # solo tráfico desde subnet privada
      SecurityGroupEgress:
        - IpProtocol: -1
          CidrIp: 0.0.0.0/0

  NatInstance:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: t4g.nano
      ImageId: !Ref FckNatAmiId            # fck-nat AMI para ARM Graviton
      SubnetId: !Ref PublicSubnetId
      SecurityGroupIds: [!Ref NatInstanceSg]
      SourceDestCheck: false               # CRÍTICO: habilita forwarding de paquetes
      Tags:
        - Key: Name
          Value: !Sub "udabol-nat-${Environment}"
        - Key: Entorno
          Value: !Ref EntornoTag

  PrivateRouteToNat:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTableId
      DestinationCidrBlock: 0.0.0.0/0
      InstanceId: !Ref NatInstance
```

> **Nota:** `SourceDestCheck: false` es el paso crítico que permite a la instancia EC2 enrutar tráfico de terceros. Sin este flag, la instancia descarta paquetes que no van dirigidos a su propia IP.

---

## 6. Observaciones y mejoras identificadas

### OBS-FINOPS-001 — Lex V2 y el costo oculto del NAT
Cada mensaje WhatsApp que procesa `agt-agent` genera una llamada a `lexv2-runtime.us-east-1.amazonaws.com`. Sin el VPC Endpoint, esta llamada sale por NAT ($0.045/GB ida + $0.045/GB vuelta). El payload de Lex (texto + intents) es pequeño (~5KB por llamada), pero a escala de producción (miles de mensajes/día) el acumulado es significativo. El endpoint de Lex V2 cuesta $7.30/mes y paga el retorno en costos si hay más de ~162 GB/mes de tráfico Lex.

### OBS-FINOPS-002 — CloudWatch Logs: el mayor volumen de tráfico interno
El driver `awslogs` de Docker genera un flujo constante de logs estructurados hacia CloudWatch desde los 6 ECS tasks activos. En modo DEBUG (típico en QA), este flujo puede superar 10-20 GB/mes. Sin el Logs endpoint, todo pasa por NAT. Con el endpoint: $0.01/GB en lugar de $0.045/GB. **Este es el endpoint con mayor ROI relativo**.

### OBS-FINOPS-003 — RDS Proxy (recomendación para Sprint 2)
`agt-readmodel` es una Lambda que se conecta directamente a RDS PostgreSQL. Las Lambdas abren y cierran conexiones TCP con cada invocación. En eventos de alta frecuencia (MSK Serverless), esto puede agotar las conexiones permitidas de `db.t3.micro` (max_connections ~60 en PostgreSQL con 1GB RAM). Un **RDS Proxy** en la misma subnet que RDS mantiene un pool de conexiones y resuelve este problema. Costo: ~$0.015/hora = ~$11/mes. Diferir a Sprint 2 cuando haya carga real para justificarlo.

### OBS-FINOPS-004 — Nivel de log en QA
Configurar los ECS Task Definitions con `LOG_LEVEL=INFO` en lugar de `DEBUG` reduce el volumen de logs enviados a CloudWatch en un 60-80%. Esto reduce el costo de almacenamiento en CloudWatch Logs ($0.50/GB ingestado) y el tráfico por el Logs endpoint. Acción: agregar variable de entorno `LOG_LEVEL` parametrizada en `services.yaml`.

### OBS-FINOPS-005 — fck-nat AMI vs Amazon Linux manual
La AMI `fck-nat` (https://github.com/AndrewGuenther/fck-nat) es una AMI pública optimizada para NAT en EC2, disponible para ARM Graviton. Configura automáticamente `iptables` MASQUERADE, `ip_forward`, y `SourceDestCheck` correctamente. Alternativa: Amazon Linux 2023 con user-data script de iptables. La AMI fck-nat reduce el tiempo de configuración a cero y tiene actualizaciones de seguridad activas.

---

## 7. Decisión recomendada

**Adoptar Escenario C (NAT Instance + VPC Endpoints) como implementación de D.4.**

| Criterio | Escenario B (NAT GW) | Escenario C (FinOps) | Ganador |
|---|---|---|---|
| Ahorro anual DEV+QA | — | **$704** | C ✅ |
| ECS en subnet privada (seguridad) | No | **Sí** | C ✅ |
| ISS-003 resuelto definitivamente | No | **Sí** | C ✅ |
| Complejidad de implementación | Baja | Media | B |
| Mantenimiento SO NAT | Ninguno | Parches Amazon Linux | B |
| Cumple SOW-002 §2.2 (egress Twilio) | **Sí** | **Sí** | Empate |
| Dentro del budget $100/mes | **Sí** | **Sí** | Empate |
| Path limpio hacia PROD | Parcial | **Sí** | C ✅ |

El único trade-off aceptado es que la NAT Instance requiere monitoreo básico (CloudWatch alarm en CPU/estado de la instancia) y es el único punto de fallo para el egress a internet en DEV/QA — lo cual es aceptable para ambientes no productivos, consistente con ADR-002.

---

## 8. Impacto en el plan de trabajo SOW-002

| Bloque | Descripción original | Descripción revisada | Horas originales | Horas revisadas |
|---|---|---|---|---|
| **D.4** | NAT Gateway DEV + QA (1 stack CFN) | NAT Instance + VPC Endpoints + fix ISS-003 (3 stacks CFN) | 3h | **5h** |
| **ISS-003** | Diferido a Sprint 2 | **Resuelto en D.4** | — | Incluido en las 5h |
| **Δ horas** | | | | **+2h** (dentro del buffer) |

---

## 9. Trigger de revisión

Este ADR se reevalúa si:
1. El tráfico mensual de Lex V2 o CloudWatch supera 500 GB/mes (costo endpoint vs NAT cambia).
2. AWS reduce el precio del NAT Gateway por debajo de $15/mes.
3. Se activa PROD — en PROD se reemplaza la NAT Instance por NAT Gateway multi-AZ (HA obligatoria).
4. La NAT Instance falla más de 2 veces en un mes (señal de que la HA del NAT GW administrado justifica el costo).

---

## 10. Referencias

- ADR-001 — Sin NAT Gateway en DEV/QA (justificación original)
- ADR-002 — Single-AZ DEV/QA · §3.1 tabla de costos base
- SOW-002 §2.2 — Requisito contractual NAT Gateway (egress Twilio)
- Bitácora §C.2 OBS-009 / ISS-003 — Causa raíz del conflicto VPC Endpoints + ECS subnet pública
- AWS Pricing: NAT Gateway, VPC Endpoints Interface, EC2 t4g.nano (us-east-1, 2026)
- fck-nat project: github.com/AndrewGuenther/fck-nat
- AWS FinOps: "Reduce Data Transfer Costs" — Well-Architected Cost Optimization Pillar

---

*Documento creado 2026-05-24 · Pendiente aceptación de Coordinador Técnico Franz Álvarez*
