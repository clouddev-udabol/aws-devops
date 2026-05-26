# GUIA — Security Groups UDABOL ERP-Agent

**Proyecto:** UDABOL ERP-Agent · Fundación Dockweiler  
**Autor:** Ayrton Irusta  
**Fecha:** 2026-05-26  
**Alcance:** Cuentas DEV (`245650696072`) y QA (`493735739951`) · Región `us-east-1`  
**Fuente:** Estado real AWS al 2026-05-26 + IaC `clouddev-udabol/aws-devops`

---

## 1. Resumen ejecutivo

El proyecto tiene **6 Security Groups funcionales por ambiente** (DEV y QA), más los SGs `default` que no se utilizan. Todos los SGs funcionales son gestionados via CloudFormation y siguen el principio de menor privilegio: ingress explícito solo en los puertos necesarios, egress irrestricto salvo en la Lambda de rotación RDS.

| # | Componente | SG Name | Propósito |
|---|------------|---------|-----------|
| 1 | ECS Fargate tasks | `udabol-agt-tasks-{env}` | Tráfico intra-cluster (8080) + OTel gRPC (4317) |
| 2 | NAT Instance | `udabol-nat-instance-{env}` | Egress internet para subnets privadas |
| 3 | RDS PostgreSQL | `agt-rds-sg-{env}` | PostgreSQL 5432 desde ECS + Lambda rotación |
| 4 | Lambda rotación RDS | `agt-rds-rotation-sg-{env}` | Egress a RDS 5432 + Secrets Manager 443 |
| 5 | MSK Serverless | `udabol-msk-{env}-MskSecurityGroup-*` | Kafka IAM 9098 desde ECS tasks |
| 6 | VPC Interface Endpoints | `udabol-vpc-endpoints-{env}` | HTTPS 443 desde VPC hacia endpoints privados |

---

## 2. VPCs de referencia

| Ambiente | Account ID | VPC ID | CIDR |
|----------|-----------|--------|------|
| DEV | `245650696072` | `vpc-02979c7bc684e62ba` | `10.10.0.0/16` |
| QA | `493735739951` | `vpc-08a2880e02f167aa8` | `10.20.0.0/16` |

---

## 3. Detalle por Security Group

### 3.1 ECS Fargate Tasks — `udabol-agt-tasks-{env}`

**Propósito:** SG compartido por los 7 servicios ECS Fargate (`agt-agent`, `agt-toolapi`, `agt-legacy-adapter`, `agt-readmodel`, `agt-otel-collector`) y la Lambda `agt-whatsapp-gateway`. Controla el tráfico intra-cluster y hacia el OTel Collector.

**IaC:** `cloudformation/modules/ecs/cluster.yaml` (recurso `EcsTaskSg`)  
Regla 4317: `cloudformation/modules/ecs/otel-collector.yaml` (recurso `EcsTaskSgOtelIngress`)  
**Stack:** `udabol-ecs-cluster-{env}`

| Ambiente | SG ID |
|---------|-------|
| DEV | `sg-09c2ea0fc34154bc4` |
| QA | `sg-086a6e6533481098e` |

#### Reglas de Ingress

| Puerto | Protocolo | Origen | Descripción |
|--------|-----------|--------|-------------|
| `8080` | TCP | Self (`udabol-agt-tasks-{env}`) | Intra-cluster task-to-task via Cloud Map |
| `4317` | TCP | Self (`udabol-agt-tasks-{env}`) | OTel Collector gRPC OTLP desde ECS tasks |

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| Todo | Todos | `0.0.0.0/0` | Egress irrestricto (tráfico sale vía NAT Instance o VPC Endpoints) |

---

### 3.2 NAT Instance — `udabol-nat-instance-{env}`

**Propósito:** Asociado a la instancia EC2 `t4g.nano` (fck-nat AMI, ARM Graviton) en PublicSubnetA. Permite que las subnets privadas hagan egress a internet (ECR public, Twilio, etc.) a través de la NAT Instance.

**IaC:** `cloudformation/modules/vpc/nat-instance.yaml`  
**Stack:** `udabol-nat-instance-{env}`

| Ambiente | SG ID | EC2 Instance ID |
|---------|-------|----------------|
| DEV | `sg-041ee1e351b2c9760` | `i-00b970c329cab457f` (10.10.1.246) |
| QA | `sg-027edbccf416f1e3b` | — |

#### Reglas de Ingress

| Puerto | Protocolo | Origen | Descripción |
|--------|-----------|--------|-------------|
| Todo | Todos | `10.10.0.0/16` (DEV) / `10.20.0.0/16` (QA) | Todo tráfico desde la VPC hacia la NAT |

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| Todo | Todos | `0.0.0.0/0` | Egress irrestricto hacia internet |

---

### 3.3 RDS PostgreSQL — `agt-rds-sg-{env}`

**Propósito:** Protege la instancia RDS PostgreSQL 16. Acepta conexiones solo desde los ECS tasks y desde la Lambda de rotación de credenciales.

**IaC:** `cloudformation/modules/rds/rds.yaml`  
**Stack:** `udabol-rds-{env}`

| Ambiente | SG ID | RDS Endpoint |
|---------|-------|-------------|
| DEV | `sg-08661bdb0f20b83c8` | via Secrets Manager |
| QA | `sg-0f2508c6c8ca17a9a` | via Secrets Manager |

#### Reglas de Ingress

| Puerto | Protocolo | Origen | Descripción |
|--------|-----------|--------|-------------|
| `5432` | TCP | `udabol-agt-tasks-{env}` | ECS Fargate tasks → PostgreSQL |
| `5432` | TCP | `agt-rds-rotation-sg-{env}` | Lambda rotación → PostgreSQL |

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| Todo | Todos | `0.0.0.0/0` | Default egress irrestricto |

---

### 3.4 Lambda Rotación RDS — `agt-rds-rotation-sg-{env}`

**Propósito:** Asociado a la Lambda de rotación automática de credenciales RDS (Secrets Manager). SG con **ingress vacío** — solo define egress explícito hacia RDS y Secrets Manager. No puede recibir tráfico entrante.

**IaC:** `cloudformation/modules/rds/rds.yaml`  
**Stack:** `udabol-rds-{env}`

| Ambiente | SG ID |
|---------|-------|
| DEV | `sg-0823d91b4b792eb46` |
| QA | `sg-01189d694b842753e` |

#### Reglas de Ingress

*Ninguna — SG sin reglas de ingress (principio de menor privilegio para Lambda interna).*

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| `5432` | TCP | `agt-rds-sg-{env}` | Lambda → PostgreSQL para rotación |
| `443` | TCP | `0.0.0.0/0` | Lambda → Secrets Manager API (HTTPS) |

---

### 3.5 MSK Serverless — `udabol-msk-{env}-MskSecurityGroup-*`

**Propósito:** Protege el cluster MSK Serverless. Acepta conexiones Kafka IAM en puerto 9098 (TLS + SASL/IAM). Nombre contiene sufijo random generado por CFN.

**IaC:** `cloudformation/modules/msk/msk-serverless.yaml`  
**Stack:** `udabol-msk-{env}`

| Ambiente | SG ID | SG Name completo |
|---------|-------|-----------------|
| DEV | `sg-0cf7634fd07553c66` | `udabol-msk-dev-MskSecurityGroup-gDXM0s55vx1N` |
| QA | `sg-06756e394fa997989` | `udabol-msk-qa-MskSecurityGroup-4Juhi3Ptj3iJ` |

> **Nota:** El sufijo aleatorio en el nombre es generado por CloudFormation al crear el recurso `AWS::MSK::ServerlessCluster`. No es controlable. Usar el SG ID para referencias programáticas.

#### Reglas de Ingress

| Puerto | Protocolo | Origen | Descripción |
|--------|-----------|--------|-------------|
| `9098` | TCP | `udabol-agt-tasks-{env}` | ECS tasks → Kafka SASL/IAM TLS |
| `9098` | TCP | `10.10.0.0/16` / `10.20.0.0/16` | CIDR VPC → MSK (Lambda readmodel) |

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| Todo | Todos | `0.0.0.0/0` | Egress irrestricto |

---

### 3.6 VPC Interface Endpoints — `udabol-vpc-endpoints-{env}`

**Propósito:** Asociado a los 5 Interface Endpoints (ECR API, ECR DKR, CloudWatch Logs, Secrets Manager, Lex V2 Runtime). Acepta HTTPS 443 desde cualquier recurso de la VPC. Permite que los servicios ECS accedan a las APIs AWS sin salir a internet.

**IaC:** `cloudformation/modules/vpc/endpoints.yaml`  
**Stack:** `udabol-vpc-endpoints-{env}`

| Ambiente | SG ID | CIDR VPC |
|---------|-------|---------|
| DEV | `sg-055a462c60cc29e37` | `10.10.0.0/16` |
| QA | `sg-0442e51ab52b76f71` | `10.20.0.0/16` |

#### Endpoints cubiertos

| Servicio | Tipo | Endpoint ID (DEV) |
|---------|------|-------------------|
| ECR API (`ecr.api`) | Interface | — |
| ECR DKR (`ecr.dkr`) | Interface | — |
| CloudWatch Logs (`logs`) | Interface | — |
| Secrets Manager (`secretsmanager`) | Interface | — |
| Lex V2 Runtime (`runtime-v2-lex`) | Interface | — |
| S3 | Gateway | Sin SG (gateway endpoint, gratis) |

#### Reglas de Ingress

| Puerto | Protocolo | Origen | Descripción |
|--------|-----------|--------|-------------|
| `443` | TCP | `10.10.0.0/16` (DEV) / `10.20.0.0/16` (QA) | HTTPS desde VPC → Interface Endpoints |

#### Reglas de Egress

| Puerto | Protocolo | Destino | Descripción |
|--------|-----------|---------|-------------|
| Todo | Todos | `0.0.0.0/0` | Default egress irrestricto |

---

## 4. Mapa de relaciones entre SGs

```
Internet
    │
    │ 443/80 (HTTPS/HTTP)
    ▼
┌─────────────────────────────┐
│  udabol-nat-instance-{env}  │  sg-041ee1e351b2c9760 (DEV)
│  PublicSubnetA 10.x.1.0/24  │  sg-027edbccf416f1e3b (QA)
└──────────┬──────────────────┘
           │ All traffic ← desde 10.x.0.0/16
           ▼
┌─────────────────────────────────────────────┐
│          udabol-agt-tasks-{env}             │  sg-09c2ea0fc34154bc4 (DEV)
│   ECS: agt-agent · agt-toolapi              │  sg-086a6e6533481098e (QA)
│         agt-legacy-adapter                  │
│         agt-readmodel · agt-otel-collector  │
│  AppSubnetA 10.x.11.0/24                   │
└────┬──────────┬──────────────┬──────────────┘
     │          │              │
     │ 8080     │ 4317 (self)  │ 9098
     │ (self)   │              │
     ▼          ▼              ▼
  Cloud Map  otel-collector  ┌────────────────────┐
  (internal)  (OTLP gRPC)   │  udabol-msk-{env}  │
                             │  MSK Serverless     │
                             │  Kafka SASL/IAM     │
                             └────────────────────┘
     │
     │ 5432
     ▼
┌─────────────────────────────┐
│     agt-rds-sg-{env}        │  sg-08661bdb0f20b83c8 (DEV)
│   RDS PostgreSQL 16         │  sg-0f2508c6c8ca17a9a (QA)
│   DbSubnetA 10.x.21.0/28   │
└──────────────┬──────────────┘
               │ 5432 (ingress desde rotation-sg)
               │
┌──────────────┴──────────────┐
│  agt-rds-rotation-sg-{env}  │  sg-0823d91b4b792eb46 (DEV)
│  Lambda rotación 90d        │  sg-01189d694b842753e (QA)
│  Egress-only: 5432 + 443    │
└─────────────────────────────┘

┌─────────────────────────────┐
│  udabol-vpc-endpoints-{env} │  sg-055a462c60cc29e37 (DEV)
│  ECR API/DKR · Logs · SM    │  sg-0442e51ab52b76f71 (QA)
│  Lex V2 · (S3=Gateway)      │
│  Ingress: 443 desde VPC     │
└─────────────────────────────┘
     ▲
     │ 443 HTTPS (sin pasar por NAT)
     └── desde udabol-agt-tasks-{env}
```

---

## 5. IaC — origen de cada SG

| SG | Template CFN | Stack CFN | Recurso lógico |
|----|-------------|-----------|---------------|
| `udabol-agt-tasks-{env}` | `cloudformation/modules/ecs/cluster.yaml` | `udabol-ecs-cluster-{env}` | `EcsTaskSg` |
| Regla 8080 self | ídem | ídem | `EcsTaskSgSelfIngress` |
| Regla 4317 self | `cloudformation/modules/ecs/otel-collector.yaml` | `udabol-otel-collector-{env}` | `EcsTaskSgOtelIngress` |
| `udabol-nat-instance-{env}` | `cloudformation/modules/vpc/nat-instance.yaml` | `udabol-nat-instance-{env}` | `NatInstanceSg` |
| `agt-rds-sg-{env}` | `cloudformation/modules/rds/rds.yaml` | `udabol-rds-{env}` | `RdsSecurityGroup` |
| `agt-rds-rotation-sg-{env}` | `cloudformation/modules/rds/rds.yaml` | `udabol-rds-{env}` | `RotationLambdaSg` |
| `udabol-msk-{env}-MskSecurityGroup-*` | `cloudformation/modules/msk/msk-serverless.yaml` | `udabol-msk-{env}` | `MskSecurityGroup` |
| `udabol-vpc-endpoints-{env}` | `cloudformation/modules/vpc/endpoints.yaml` | `udabol-vpc-endpoints-{env}` | `EndpointsSg` |

---

## 6. Reglas de operación

### Agregar un nuevo puerto entre servicios ECS

1. Agregar `AWS::EC2::SecurityGroupIngress` en el template del nuevo servicio (no en `cluster.yaml`).
2. Usar `!ImportValue "${ClusterStackName}-EcsTaskSgId"` como `GroupId` y `SourceSecurityGroupId`.
3. Al eliminar el stack del servicio, la regla se elimina automáticamente.

Ejemplo (ver `otel-collector.yaml` recurso `EcsTaskSgOtelIngress`):
```yaml
Type: AWS::EC2::SecurityGroupIngress
Properties:
  GroupId: !ImportValue "udabol-ecs-cluster-dev-EcsTaskSgId"
  IpProtocol: tcp
  FromPort: NNNN
  ToPort: NNNN
  SourceSecurityGroupId: !ImportValue "udabol-ecs-cluster-dev-EcsTaskSgId"
  Description: "Descripción del puerto"
```

### Agregar acceso desde un nuevo servicio a RDS

Agregar una entrada en `Ingress` de `RdsSecurityGroup` en `rds.yaml`:
```yaml
- IpProtocol: tcp
  FromPort: 5432
  ToPort: 5432
  SourceSecurityGroupId: !ImportValue "udabol-ecs-cluster-{env}-EcsTaskSgId"
  Description: "Nuevo servicio → PostgreSQL"
```

### Consultar reglas vigentes en AWS

```powershell
# Reglas de un SG por nombre
aws ec2 describe-security-groups `
  --filters "Name=group-name,Values=udabol-agt-tasks-dev" `
  --region us-east-1 --profile proy-dev `
  --query 'SecurityGroups[0].{Ingress:IpPermissions,Egress:IpPermissionsEgress}'

# Todos los SGs de la VPC DEV
aws ec2 describe-security-groups `
  --filters "Name=vpc-id,Values=vpc-02979c7bc684e62ba" `
  --region us-east-1 --profile proy-dev `
  --query 'SecurityGroups[*].{Name:GroupName,ID:GroupId}' --output table
```

### Identificar a qué recurso está asociado un SG

```powershell
# Interfaces de red que usan un SG
aws ec2 describe-network-interfaces `
  --filters "Name=group-id,Values=sg-09c2ea0fc34154bc4" `
  --region us-east-1 --profile proy-dev `
  --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Desc:Description,IP:PrivateIpAddress}'
```

---

## 7. SGs no funcionales (ignorar)

| SG ID | Nombre | VPC | Motivo |
|-------|--------|-----|--------|
| `sg-0d9fd25d288f43857` | `default` | `vpc-02979c7bc684e62ba` (DEV) | SG por defecto de la VPC — no asignado a ningún recurso del proyecto |
| `sg-081a2fe334bb1cde7` | `default` | `vpc-0e8410db951126097` (DEV, VPC secundaria) | VPC legacy sin uso |
| `sg-0ad7bff5a9ccfffec` | `default` | `vpc-06679f2a6f41252a9` (QA, VPC secundaria) | VPC legacy sin uso |
| `sg-09c98d852892fd7f3` | `default` | `vpc-08a2880e02f167aa8` (QA) | SG por defecto de la VPC — no asignado a ningún recurso del proyecto |

---

*Documento generado 2026-05-26 · Estado real AWS verificado con `aws ec2 describe-security-groups` en perfiles `proy-dev` y `proy-qa`*
