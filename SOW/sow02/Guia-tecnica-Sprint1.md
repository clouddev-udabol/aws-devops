**Fundacion Dockweiler | UDABOL ERP-Agent**

**GUIA TECNICA DE IMPLEMENTACION**

**Sprint 1 - Release 1 | SOW-002**

Para: Ayrton Rodolfo Irusta Guzman | Arquitecto DevOps

| **Documento:**           | Guia Tecnica Sprint 1 - UDABOL ERP-Agent                  |
| ------------------------ | --------------------------------------------------------- |
| **Destinatario:**        | Ayrton Rodolfo Irusta Guzman (DevOps / Cloud Architect)   |
| **Coordinador Tecnico:** | Franz Carlos Alvarez Flores (Asesor Tecnologico)          |
| **Referencia:**          | SOW-002 Sprint 1 \| MSA Cloud DevOps Fundacion Dockweiler |
| **Repositorios:**        | github.com/clouddev-udabol \| 7 repos agt-\* + aws-devops |
| **Fecha:**               | Mayo 2026                                                 |
| **Diagramas:**           | UDABOL-ERP-Agent-Architecture.drawio (4 tabs adjuntos)    |

**AUDIENCIA:** Este documento es exclusivamente tecnico, orientado a infraestructura AWS y DevOps. No incluye logica de aplicacion ni codigo de negocio. El scope es la plataforma operativa sobre la que corren los microservicios.

> **Actualizado 2026-05-26 — correcciones post-despliegue Sprint 1:** tipo de agt-readmodel (ECS, no Lambda), puertos reales (todos 8080), SGs sin ALB, observabilidad via OTel Collector. Estado live: `SOW/sow02/bitacora-despliegue.md`.

# **1\. CONTEXTO Y OBJETIVO DEL SPRINT**

El Sprint 1 construye sobre la infraestructura base entregada en el Sprint 0: tres VPCs (DEV/QA/PROD), VPC Peering, GitHub OIDC, AWS Budgets, Site-to-Site VPN y documentacion arquitectonica (E1-E6 SOW-001). El objetivo del Sprint 1 es desplegar la primera capa funcional del sistema conversacional de inscripcion academica.

## **1.1 Cuentas AWS de Trabajo**

| **Entorno** | **Account ID**         | **Email root**            | **VPC CIDR** | **Region** |
| ----------- | ---------------------- | ------------------------- | ------------ | ---------- |
| **DEV**     | 245650696072           | <clouddev@udabol.edu.bo>  | 10.10.0.0/16 | us-east-1  |
| **QA**      | 493735739951           | <cloudqa@udabol.edu.bo>   | 10.20.0.0/16 | us-east-1  |
| **PROD**    | (pendiente - Sprint 2) | <cloudprod@udabol.edu.bo> | 10.30.0.0/16 | us-east-1  |

## **1.2 Repositorios Oficiales**

Todos los repositorios estan bajo la organizacion GitHub clouddev-udabol. El repositorio aws-devops es la capa de plataforma transversal; los repositorios agt-\* son los servicios de aplicacion.

| **Repositorio**          | **URL**                            | **Tipo**       | **Responsabilidad principal**                                        | **Owner**      |
| ------------------------ | ---------------------------------- | -------------- | -------------------------------------------------------------------- | -------------- |
| **aws-devops**           | clouddev-udabol/aws-devops         | IaC / Platform | CFN stacks: VPCs, Lex, RDS, MSK, ECS. Runbooks. ADRs de infra.       | Ayrton         |
| **agt-common**           | clouddev-udabol/agt-common         | Python Library | DTOs, contratos de eventos, validadores compartidos entre servicios. | Devs           |
| **agt-intent-parser**    | clouddev-udabol/agt-intent-parser  | IaC + Script   | CFN Lex V2 bot. YAML intents. build_bot.py. deploy/aws/.             | Ayrton         |
| **agt-whatsapp-gateway** | clouddev-udabol/agt-whatsapp-gw    | Lambda App     | Webhook normalizer. SAM template o CFN Lambda + API GW.              | Ayrton (infra) |
| **agt-agent**            | clouddev-udabol/agt-agent          | ECS App        | Orquestador FastAPI. ECS Task Definition. Dockerfile.                | Ayrton (infra) |
| **agt-toolapi**          | clouddev-udabol/agt-toolapi        | ECS App        | Tool layer FastAPI. ECS Task Definition. Dockerfile.                 | Ayrton (infra) |
| **agt-legacy-adapter**   | clouddev-udabol/agt-legacy-adapter | ECS App        | ACL hacia HMS Plus. ECS Task Definition. Dockerfile.                 | Ayrton (infra) |
| **agt-readmodel**        | clouddev-udabol/agt-readmodel      | ECS App        | Proyecciones lectura. ECS Fargate port 8085, DesiredCount=0 (activa cuando dev team entregue imagen). Dockerfile.   | Ayrton (infra) |

## **1.3 Diagramas de Referencia**

El archivo UDABOL-ERP-Agent-Architecture.drawio contiene 4 tabs que debes consultar durante la implementacion:

| **#** | **Tab**                     | **Contenido**                                                                 | **Cuando consultarlo**                                            |
| ----- | --------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1     | **C4-L2 Containers**        | Todos los contenedores, sus tecnologias, repos y conexiones entre ellos.      | Durante toda la implementacion. Vision global de la arquitectura. |
| 2     | **AWS Multi-Account Infra** | Cuentas DEV/QA/PROD, VPCs, peering, OIDC, VPN. Jerarquia de Organizations.    | Bloque A (setup) y Bloque C (networking ECS).                     |
| 3     | **CI/CD Pipeline**          | Flujo GitHub Actions: dev branch → ECR → ECS DEV → PR → ECS QA.               | Bloque A (pipelines) y validacion E1 y E6.                        |
| 4     | **Flujo Request R1**        | Secuencia completa: estudiante → WhatsApp → Twilio → Lex → Orquestador → ERP. | Bloque E (prueba de humo). Entregable E7.                         |

# **2\. BLOQUE A: REPOSITORIOS agt-\* Y CI/CD PIPELINES**

## **2.1 Modelo de Ramas**

Cada repositorio agt-\* usa tres ramas permanentes mapeadas 1:1 a los ambientes AWS:

| **Rama** | **Ambiente** | **AWS Account** | **Trigger CI/CD**  | **Politica de proteccion**                                            |
| -------- | ------------ | --------------- | ------------------ | --------------------------------------------------------------------- |
| **dev**  | DEV          | 245650696072    | push directo       | Status checks CI obligatorio. Push directo permitido para arquitecto. |
| **qa**   | QA           | 493735739951    | PR merge desde dev | Require PR. 1 reviewer. Status checks. No direct push.                |
| **main** | PROD         | (Sprint 2)      | Tag v\*.\*.\*      | Require PR. 2 reviewers. Status checks. No direct push.               |

## **2.2 Estructura de Directorios por Repositorio**

Cada repositorio agt-\* debe tener la siguiente estructura base:

agt-{service}/

.github/

workflows/

ci.yml # Pipeline principal (lint + test + build + push + deploy)

deploy/

aws/

cloudformation/ # Stacks CFN del servicio (task definition, service, etc.)

scripts/ # Scripts de despliegue (deploy.sh, build_bot.py en intent-parser)

src/ # Codigo fuente de aplicacion (no es scope Ayrton)

tests/ # Tests unitarios (no es scope Ayrton)

Dockerfile # Build de la imagen Docker

Makefile # Targets: build, test, push, deploy-dev, deploy-qa, check

.env.example # Variables de entorno requeridas (valores de ejemplo, no reales)

README.md # Descripcion del servicio

## **2.3 GitHub Actions Workflow: ci.yml**

El siguiente es el workflow estandar para todos los repos agt-\*. Adaptar los valores de {SERVICE_NAME} y las variables de entorno especificas de cada repo:

name: CI/CD Pipeline

on:

push:

branches: \[dev, qa\]

pull_request:

branches: \[qa, main\]

env:

AWS_REGION: us-east-1

SERVICE_NAME: agt-{service} # Reemplazar con el nombre real

ECR_REPO_DEV: 245650696072.dkr.ecr.us-east-1.amazonaws.com/agt-{service}

ECR_REPO_QA: 493735739951.dkr.ecr.us-east-1.amazonaws.com/agt-{service}

jobs:

ci:

runs-on: ubuntu-latest

permissions:

id-token: write # OIDC required

contents: read

steps:

\- uses: actions/checkout@v4

\- name: Setup Python

uses: actions/setup-python@v5

with:

python-version: "3.11"

\- name: Install dependencies

run: pip install -r requirements.txt -r requirements-dev.txt

\- name: Lint + Type Check

run: make check

\- name: Unit Tests

run: make test

\- name: Build Docker Image

run: |

IMAGE_TAG=\${GITHUB_REF_NAME}-\${GITHUB_SHA::8}

docker build -t \$SERVICE_NAME:\$IMAGE_TAG .

\- name: Configure AWS Credentials (OIDC)

uses: aws-actions/configure-aws-credentials@v4

with:

role-to-assume: arn:aws:iam::\${{ env.ACCOUNT_ID }}:role/github-oidc-deployer

aws-region: \${{ env.AWS_REGION }}

\- name: Push to ECR

run: |

aws ecr get-login-password | docker login --username AWS --password-stdin \$ECR_REPO

docker tag \$SERVICE_NAME:\$IMAGE_TAG \$ECR_REPO:\$IMAGE_TAG

docker push \$ECR_REPO:\$IMAGE_TAG

\- name: Deploy to ECS

run: |

aws ecs update-service \\

\--cluster agt-cluster-\${ENV} \\

\--service \$SERVICE_NAME-\${ENV} \\

\--force-new-deployment \\

\--region \$AWS_REGION

**IMPORTANTE:** OIDC Role ARN: el role github-oidc-deployer ya existe en DEV y QA (entregable E3 SOW-001). Verificar el ARN exacto en IAM antes de configurar el workflow. Account ID es variable de entorno de GitHub Secrets: ACCOUNT_ID_DEV y ACCOUNT_ID_QA.

## **2.4 Repositorios ECR a Crear**

Crear un repositorio ECR por servicio en cada cuenta (DEV y QA). Total: 14 repos ECR (7 repos x 2 cuentas).

| **ECR Repo Name**        | **Cuenta**                           | **Lifecycle Policy**                                      | **scan-on-push** |
| ------------------------ | ------------------------------------ | --------------------------------------------------------- | ---------------- |
| **agt-agent**            | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-toolapi**          | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-legacy-adapter**   | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-readmodel**        | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-whatsapp-gateway** | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-intent-parser**    | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |
| **agt-common**           | DEV (245650696072) QA (493735739951) | Retener max 5 imgs por rama (expire untagged after 1 day) | **HABILITADO**   |

# **3\. BLOQUE B: AMAZON LEX V2 (agt-intent-parser)**

## **3.1 Descripcion del Componente**

El bot Amazon Lex V2 es el motor de NLU (Natural Language Understanding) de la plataforma. Recibe texto libre en espanol (locale es_419) y devuelve un intent clasificado con sus slots extraidos. Esta disenado para ser definido en CloudFormation e inicializado desde archivos YAML de intencion.

**Arquitectura del componente:** El repositorio agt-intent-parser contiene: (a) archivos YAML de intenciones en intents/\*.yaml, (b) script build_bot.py que genera el CFN con intents inyectados, (c) template CloudFormation base lex-bot.yaml, (d) script de despliegue deploy.sh.

## **3.2 CloudFormation Stack: udabol-intent-parser-{env}**

El stack debe desplegarse en ambas cuentas (DEV y QA). La diferencia entre ambientes es el parametro Environment:

\# Estructura del stack CFN (agt-intent-parser/deploy/aws/cloudformation/lex-bot.yaml)

AWSTemplateFormatVersion: "2010-09-09"

Parameters:

Environment:

Type: String

AllowedValues: \[dev, qa, prod\]

Default: dev

BotName:

Type: String

Default: UdabolEnrollmentBot

IdleSessionTTLInSeconds:

Type: Number

Default: 600

Resources:

LexBotRole:

Type: AWS::IAM::Role

Properties:

RoleName: !Sub "\${BotName}-\${Environment}-role"

AssumeRolePolicyDocument:

Statement:

\- Effect: Allow

Principal:

Service: lexv2.amazonaws.com

Action: sts:AssumeRole

ManagedPolicyArns:

\- arn:aws:iam::aws:policy/AmazonLexFullAccess

UdabolBot:

Type: AWS::Lex::Bot

Properties:

Name: !Sub "\${BotName}-\${Environment}"

RoleArn: !GetAtt LexBotRole.Arn

DataPrivacy:

ChildDirected: false

IdleSessionTTLInSeconds: !Ref IdleSessionTTLInSeconds

AutoBuildBotLocales: true

BotLocales:

\- LocaleId: es_419

NluConfidenceThreshold: 0.40

VoiceSettings:

VoiceId: Lupe

\# Intents inyectados por build_bot.py en deploy-time

**IMPORTANTE:** El CFN base (lex-bot.yaml) es un SHELL. Los intents reales se inyectan mediante el script build_bot.py que lee los archivos intents/\*.yaml. NUNCA hardcodear intents directamente en el CFN.

## **3.3 Script de Despliegue (build_bot.py + deploy.sh)**

\# deploy/aws/scripts/build_bot.py

\# Lectura de intents/\*.yaml → generacion de CFN con intents embebidos

\# Uso: python build_bot.py --env dev --output lex-bot-generated.yaml

\# deploy/aws/scripts/deploy.sh

# !/bin/bash

ENV=\${1:-dev}

STACK_NAME="udabol-intent-parser-\${ENV}"

REGION="us-east-1"

\# 1. Generar CFN con intents

python deploy/aws/scripts/build_bot.py --env \${ENV} \\

\--output /tmp/lex-bot-generated.yaml

\# 2. Deploy o update stack

aws cloudformation deploy \\

\--template-file /tmp/lex-bot-generated.yaml \\

\--stack-name \${STACK_NAME} \\

\--parameter-overrides Environment=\${ENV} \\

\--capabilities CAPABILITY_NAMED_IAM \\

\--region \${REGION}

## **3.4 Criterio de Aceptacion Bloque B**

**CRITERIO DE ACEPTACION:** Stack udabol-intent-parser-dev y udabol-intent-parser-qa en estado CREATE_COMPLETE. Bot responde a la utterance "Quiero inscribirme al semestre 2026-1" con intent=Inscribir, confidence >= 0.70, slot term=2026-1. Verificar con: aws lexv2-runtime recognize-text --bot-id {BOT_ID} --bot-alias-id {ALIAS_ID} --locale-id es_419 --session-id test-001 --text "Quiero inscribirme al semestre 2026-1" --region us-east-1

# **4\. BLOQUE C: MICROSERVICIOS EN ECS FARGATE**

## **4.1 Arquitectura ECS para el Sprint 1**

Se despliegan 4 servicios ECS Fargate en AppSubnetA (subred privada, via NAT Instance): agt-agent (Orquestador), agt-toolapi (Tool Layer), agt-legacy-adapter (ACL hacia HMS Plus), agt-readmodel (DesiredCount=0, activa cuando dev team entregue imagen). El agt-whatsapp-gateway es Lambda (no Fargate). Todos los servicios ECS usan puerto 8080 excepto agt-readmodel que usa 8085.

## **4.2 Parametros por Servicio y Ambiente**

| **Servicio**           | **Puerto App** | **CPU DEV** | **Mem DEV** | **desired_count DEV** | **desired_count QA** |
| ---------------------- | -------------- | ----------- | ----------- | --------------------- | -------------------- |
| **agt-agent**          | 8080           | 256         | 512 MB      | 1                     | 2                    |
| **agt-toolapi**        | 8080           | 256         | 512 MB      | 1                     | 2                    |
| **agt-legacy-adapter** | 8080           | 256         | 512 MB      | 1                     | 2                    |
| **agt-readmodel**      | 8085           | 256         | 512 MB      | 0 (sin imagen aún)    | 0 (sin imagen aún)   |

## **4.3 Task Definition CloudFormation (patron base)**

Usar el siguiente patron en aws-devops/cloudformation/ecs-services.yaml. Replicar por servicio con los parametros correspondientes:

AgentTaskDefinition:

Type: AWS::ECS::TaskDefinition

Properties:

Family: !Sub "agt-agent-\${Environment}"

Cpu: "256"

Memory: "512"

NetworkMode: awsvpc

RequiresCompatibilities: \[FARGATE\]

ExecutionRoleArn: !GetAtt ECSExecutionRole.Arn

TaskRoleArn: !GetAtt ECSTaskRole.Arn

ContainerDefinitions:

\- Name: agt-agent

Image: !Sub "245650696072.dkr.ecr.us-east-1.amazonaws.com/agt-agent:latest"

PortMappings:

\- ContainerPort: 8080

Protocol: tcp

Environment: \[\] # Variables no sensibles aqui

Secrets: # Variables sensibles desde Secrets Manager

\- Name: DB_PASSWORD

ValueFrom: !Sub "arn:aws:secretsmanager:us-east-1:\${AWS::AccountId}:secret:agt/db-creds"

HealthCheck:

Command: \["CMD-SHELL", "curl -f <http://localhost:8080/health> || exit 1"\]

Interval: 30

Timeout: 5

Retries: 3

StartPeriod: 60

LogConfiguration:

LogDriver: awslogs

Options:

awslogs-group: !Sub "/agt/agent/\${Environment}"

awslogs-region: !Ref AWS::Region

awslogs-stream-prefix: ecs

## **4.4 Security Groups**

Reglas minimas de ingreso. Principio de menor privilegio:

> **Nota DEV/QA (single-AZ):** No se desplegó ALB en Sprint 1. Los servicios se comunican directamente via Cloud Map (`agt-agent.agt.local:8080`, etc.). Para detalle completo de IDs y reglas reales, ver `SOW/docs/GUIA-security-groups.md`.

| **SG Nombre**    | **Protocolo** | **Puerto** | **Origen**                   | **Proposito**                              |
| ---------------- | ------------- | ---------- | ---------------------------- | ------------------------------------------ |
| **sg-ecs-tasks** | TCP           | 8080/8085  | sg-ecs-tasks (self)          | Trafico inter-servicio ECS via Cloud Map   |
| **sg-ecs-tasks** | TCP           | 4317       | sg-ecs-tasks (self)          | OTel gRPC hacia otel-collector.agt.local   |
| **sg-ecs-tasks** | TCP           | 5432       | → sg-rds                     | Fargate a RDS PostgreSQL                   |
| **sg-ecs-tasks** | TCP           | 9098       | → sg-msk                     | Fargate a MSK Serverless (SASL/IAM)        |
| **sg-rds**       | TCP           | 5432       | sg-ecs-tasks + sg-rotation   | RDS acepta de Fargate y Lambda rotacion    |
| **sg-msk**       | TCP           | 9098       | sg-ecs-tasks + VPC CIDR      | MSK acepta de Fargate                      |
| **sg-nat**       | ALL           | -          | VPC CIDR → internet          | NAT Instance trafico de salida             |
| **sg-endpoints** | TCP           | 443        | VPC CIDR                     | VPC Endpoints ECR/SM/Logs/Lex              |

**CRITERIO DE ACEPTACION:** Criterio E4: Tasks agt-agent y agt-toolapi en estado RUNNING. GET /health retorna HTTP 200. CloudWatch Logs grupo /agt/agent/dev y /agt/toolapi/dev con entradas.

# **5\. BLOQUE D: PERSISTENCIA Y BUS DE EVENTOS**

## **5.1 RDS PostgreSQL 16**

| **Parametro**        | **DEV**                                  | **QA**                         |
| -------------------- | ---------------------------------------- | ------------------------------ |
| **Engine**           | postgres 16                              | postgres 16                    |
| **Instance Class**   | db.t4g.medium                            | db.t4g.medium                  |
| **Multi-AZ**         | No (Single-AZ)                           | No (Single-AZ)                 |
| **Storage**          | 20 GB gp3                                | 30 GB gp3                      |
| **Backup Retention** | 7 dias                                   | 14 dias                        |
| **Encryption**       | AES-256 (default KMS)                    | AES-256 (default KMS)          |
| **Subnet Group**     | rds-subnet-group-dev (subnets aisladas)  | rds-subnet-group-qa            |
| **SG**               | sg-rds (ingreso solo desde sg-ecs-tasks) | sg-rds                         |
| **DB Name**          | udabol_dev                               | udabol_qa                      |
| **Secret (SM)**      | agt/db-creds-dev (rotacion 90d)          | agt/db-creds-qa (rotacion 90d) |

## **5.2 Amazon MSK Serverless**

Un cluster MSK Serverless por ambiente (DEV y QA). Autenticacion IAM (sin SASL/SCRAM). Topics a crear:

| **Topic**             | **Retencion** | **Partitions** | **Productores / Consumidores**                   |
| --------------------- | ------------- | -------------- | ------------------------------------------------ |
| **enrollment.events** | 7 dias        | 3              | Producer: agt-toolapi \| Consumer: agt-readmodel |
| **payment.events**    | 7 dias        | 3              | Producer: agt-toolapi \| Consumer: agt-readmodel |
| **query.audit**       | 7 dias        | 1              | Producer: agt-agent \| Consumer: (futuro)        |

## **5.3 Secrets Manager: Variables Sensibles por Servicio**

Todas las variables sensibles van en Secrets Manager. Las variables no sensibles (URLs, timeouts) van como Environment en el Task Definition. NUNCA en el CFN ni en el codigo.

| **Secret ARN (patron)** | **Servicios que lo usan**             | **Variables incluidas**                                   | **Rotacion**                |
| ----------------------- | ------------------------------------- | --------------------------------------------------------- | --------------------------- |
| agt/db-creds-{env}      | agt-agent, agt-toolapi, agt-readmodel | DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME           | 90 dias auto (RDS rotation) |
| agt/twilio-{env}        | agt-whatsapp-gateway                  | TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_FROM  | Manual                      |
| agt/hms-plus-{env}      | agt-legacy-adapter                    | HMS_PLUS_BASE_URL, HMS_PLUS_API_KEY, HMS_PLUS_TIMEOUT_SEC | Manual                      |
| agt/anthropic-{env}     | agt-agent (Sprint 3)                  | ANTHROPIC_API_KEY, CLAUDE_MODEL                           | Manual (Sprint 3)           |

**CRITERIO DE ACEPTACION:** Criterio E5: RDS disponible (DescribeDBInstances Status=available). MSK cluster activo, 3 topics existentes verificables en consola MSK. Conexion desde tarea Fargate exitosa (log de startup del servicio muestra DB connected y MSK producer ready).

# **6\. VARIABLES DE ENTORNO POR REPOSITORIO (.env.example)**

El archivo .env.example en cada repositorio debe documentar todas las variables requeridas con valores de ejemplo (no reales). Las reales van en Secrets Manager o en GitHub Secrets. A continuacion el detalle por servicio:

## **6.1 agt-intent-parser**

NLU_ENGINE=lex # "lex" | "claude" (R2) | "llm" (R3)

FALLBACK_THRESHOLD=0.70 # Confianza minima; si score < threshold → FallbackIntent

AWS_REGION=us-east-1

LEX_BOT_ID=&lt;bot-id-desde-cloudformation&gt; # Extraer del stack output

LEX_BOT_ALIAS_ID=&lt;alias-id&gt; # Alias del bot Lex

LEX_LOCALE_ID=es_419

LOG_LEVEL=INFO

PORT=8083 # Puerto del servicio (si es API)

INTENTS_DIR=/app/intents # Directorio de YAML de intenciones

## **6.2 agt-whatsapp-gateway (Lambda)**

\# Estas variables se configuran en Lambda Environment Variables via CFN/SAM

TWILIO_AUTH_TOKEN=&lt;secreto-SM&gt; # Desde Secrets Manager: agt/twilio-{env}

ORCHESTRATOR_URL=http://agt-agent.agt.local:8080/v1/converse

LOG_LEVEL=INFO

## **6.3 agt-agent**

DB_HOST=&lt;rds-endpoint-dev&gt; # RDS endpoint (desde CFN output)

DB_PORT=5432

DB_NAME=udabol_dev

DB_USER=&lt;secreto-SM&gt; # Desde agt/db-creds-dev

DB_PASSWORD=&lt;secreto-SM&gt;

TOOLAPI_URL=http://agt-toolapi.agt.local:8080 # URL interna via Cloud Map service discovery

SESSION_TTL_SECONDS=600

LOG_LEVEL=INFO

PORT=8080

## **6.4 agt-toolapi**

LEGACY_ADAPTER_URL=http://agt-legacy-adapter.agt.local:8080

MSK_BOOTSTRAP_SERVERS=&lt;msk-endpoint&gt;:9098 # Desde CFN output — SASL/IAM puerto 9098 (no 9092)

MSK_TOPIC_ENROLLMENT=enrollment.events

MSK_TOPIC_PAYMENT=payment.events

DB_HOST=&lt;rds-endpoint-dev&gt;

DB_PORT=5432

DB_NAME=udabol_dev

DB_USER=&lt;secreto-SM&gt;

DB_PASSWORD=&lt;secreto-SM&gt;

LOG_LEVEL=INFO

PORT=8080

## **6.5 agt-legacy-adapter**

HMS_PLUS_BASE_URL=<http://hms-plus.udabol.edu.bo/api> # Via Site-to-Site VPN

HMS_PLUS_API_KEY=&lt;secreto-SM&gt; # Desde agt/hms-plus-{env}

HMS_PLUS_TIMEOUT_SEC=10

HMS_PLUS_MAX_RETRIES=3

HMS_PLUS_RETRY_BACKOFF_MS=500

LOG_LEVEL=INFO

PORT=8080

## **6.6 agt-readmodel (Lambda)**

DB_HOST=&lt;rds-endpoint-dev&gt;

DB_PORT=5432

DB_NAME=udabol_dev

DB_USER=&lt;secreto-SM&gt;

DB_PASSWORD=&lt;secreto-SM&gt;

MSK_TOPIC_ENROLLMENT=enrollment.events

LOG_LEVEL=INFO

# **7\. BLOQUE E: OBSERVABILIDAD Y VALIDACION END-TO-END**

## **7.1 Observabilidad — OTel Collector ADOT (COMPLETADO)**

> **N2 resuelto:** SOW-002 §2.6 define OTel Collector (ADOT) + CloudWatch/X-Ray como stack de observabilidad para DEV/QA. El dashboard CloudWatch con 6 widgets (criterio E7 original) queda **diferido a Sprint 2**.

### Stack desplegado: udabol-otel-collector-{env}

| Componente | Descripcion |
| ---------- | ----------- |
| Imagen | `public.ecr.aws/aws-observability/aws-otel-collector:latest` (v0.48.0) |
| Template CFN | `cloudformation/modules/ecs/otel-collector.yaml` |
| Log group | `/udabol/{env}/agt` (retencion 7 dias) |
| Cloud Map | `otel-collector.agt.local:4317` |
| Protocolo | gRPC OTLP — puerto 4317 |
| Exporters | `traces → awsxray` · `metrics → awsemf` (namespace `udabol/agt`) |
| IAM Task Role | `agt-ecs-otel-task-{env}` — X-Ray + CloudWatch EMF |
| Estado DEV | `udabol-otel-collector-dev` CREATE_COMPLETE · running=1/desired=1 |
| Estado QA | `udabol-otel-collector-qa` CREATE_COMPLETE · running=1/desired=1 |

### Config AOT_CONFIG_CONTENT

La config ADOT se inyecta via variable de entorno `AOT_CONFIG_CONTENT` (no requiere S3 ni SSM). Incluye extension `health_check` en puerto 13133 (requerido por CMD `/healthcheck`).

### Integracion desde servicios agt-* (E.2 — pendiente)

Variables de entorno a agregar en cada repo:

OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.agt.local:4317
OTEL_SERVICE_NAME=agt-{service}

Dependencias Python (E.2 — ~6 horas estimadas):

opentelemetry-sdk
opentelemetry-exporter-otlp-proto-grpc
opentelemetry-instrumentation-fastapi

### Dashboard CloudWatch con 6 widgets — DIFERIDO Sprint 2

El criterio E7 original ("Dashboard udabol-erp-agent-{env} con 6 widgets activos") queda diferido a Sprint 2. Las metricas `udabol/agt` emitidas por CloudWatch EMF desde el OTel Collector alimentaran ese dashboard en Sprint 2 sin necesidad de reconfigurar la telemetria.

Los widgets planeados (referencia para Sprint 2):

| **#** | **Widget Title**                | **Metrica(s)**                        | **Fuente**                                  |
| ----- | ------------------------------- | ------------------------------------- | ------------------------------------------- |
| **1** | **ECS CPU Utilization**         | ECS/ContainerInsights CPUUtilization  | Cluster `udabol-agt-dev/qa`                 |
| **2** | **ECS Memory Utilization**      | ECS/ContainerInsights MemoryUtilization | Cluster `udabol-agt-dev/qa`               |
| **3** | **OTel Traces Count**           | `udabol/agt` SpanCount (via EMF)      | OTel Collector CloudWatch EMF               |
| **4** | **RDS Connections + Storage**   | AWS/RDS DatabaseConnections, FreeStorageSpace | `udabol-rds-dev/qa`               |
| **5** | **MSK Incoming Bytes**          | AWS/Kafka BytesInPerSec               | `udabol-msk-dev/qa` topics                  |
| **6** | **Lambda WG Errors + Duration** | AWS/Lambda Errors, Duration           | `agt-whatsapp-gateway-{env}`                |

## **7.2 Prueba de Humo End-to-End (Entregable E7)**

Simular el flujo completo en DEV sin Twilio real. El endpoint de API Gateway acepta un JSON con el mismo formato que Twilio firma. Documentar el resultado con capturas de pantalla.

**Paso 1: Obtener URL de API Gateway**

aws apigateway get-rest-apis --region us-east-1

\# Buscar la API "udabol-whatsapp-gw-dev" y copiar el invoke URL

**Paso 2: Simular webhook Twilio**

curl -X POST \

https://il9jw4ux6d.execute-api.us-east-1.amazonaws.com/webhook/whatsapp/json \

\-H "Content-Type: application/x-www-form-urlencoded" \\

\-d "From=whatsapp:+59170000000" \\

\-d "Body=Quiero inscribirme al semestre 2026-1" \\

\-d "AccountSid=TEST_ACCOUNT" \\

\-d "MessageSid=SM_TEST_001"

\# Respuesta esperada: HTTP 200 con TwiML o JSON

\# {"status": "accepted", "session_id": "...", "intent": "Inscribir"}

**Paso 3: Verificar propagacion en CloudWatch Logs**

\# Grupo: /aws/lambda/agt-whatsapp-gateway-dev

aws logs tail /aws/lambda/agt-whatsapp-gateway-dev --follow

\# Debe mostrar: "Request received", "Forwarding to orchestrator", "Response: 200"

\# Grupo: /agt/agent/dev

aws logs tail /agt/agent/dev --follow

\# Debe mostrar: "Session created", "Intent: Inscribir", "Calling ToolAPI"

**CRITERIO DE ACEPTACION:** Criterio E7: (a) Dashboard con 6 widgets activos y mostrando datos reales. (b) Prueba de humo documentada con captura de curl request, response HTTP 200, y log entries en CloudWatch para Lambda WG y agt-agent. (c) aws-devops/runbooks/sprint1-deploy.md actualizado con comandos reales.

## **7.3 Runbook: aws-devops/runbooks/sprint1-deploy.md**

El runbook debe cubrir los siguientes puntos con comandos reales (no pseudocodigo):

- Prerequisitos: cuentas, herramientas (aws cli v2, docker, python 3.11, node 18+).
- Paso 1: Deploy stack VPC (referencia SOW-001, ya existente, verificar estado).
- Paso 2: Deploy udabol-intent-parser-dev (Lex V2).
- Paso 3: Create ECR repos (7 repos DEV + 7 repos QA).
- Paso 4: Configure Secrets Manager (crear secretos con valores de DEV).
- Paso 5: Deploy RDS PostgreSQL DEV.
- Paso 6: Deploy MSK Serverless DEV + crear topics.
- Paso 7: Build y push imagen Docker de cada servicio a ECR DEV.
- Paso 8: Deploy ECS cluster + Task Definitions + Services.
- Paso 9: Verificar health checks y CloudWatch logs.
- Paso 10: Prueba de humo end-to-end (curl + log verification).
- Rollback: como hacer rollback de cada stack.

# **8\. CHECKLIST DE ENTREGA Y ACEPTACION**

Antes de comunicar la entrega al Coordinador Tecnico, verificar que cada item esta completo. El Coordinador verificara de forma independiente usando los mismos criterios.

| **Entg.** | **Bloque** | **Item a verificar**                                                     | **Evidencia**      | **Estado** |
| --------- | ---------- | ------------------------------------------------------------------------ | ------------------ | ---------- |
| **E1**    | A          | 7 repos agt-\* con ramas dev/qa/main y branch protection configurada     | GitHub repos       | ✅ COMPLETADO — A.1+A.2: ramas y branch protection (GitHub Team) en main+qa los 7 repos |
| **E1**    | A          | GitHub Actions CI corre en push a dev sin errores (lint+test+build+push) | GH Actions runs    | ✅ COMPLETADO — A.4: ci.yml en 7 repos con OIDC roles agt-gha-oidc-dev/qa |
| **E1**    | A          | ECR repos creados en DEV y QA (14 repos total) con scan-on-push ON       | Consola ECR        | ✅ COMPLETADO — A.3: udabol-ecr-dev/qa, 7×2 repos, ScanOnPush:true |
| **E2**    | B          | Stack udabol-intent-parser-dev en CREATE_COMPLETE                        | Consola CFN        | ✅ COMPLETADO — B.1: `udabol-intent-parser-lex-dev` CREATE_COMPLETE. BotId AMEBQJXNM2 |
| **E2**    | B          | Stack udabol-intent-parser-qa en CREATE_COMPLETE                         | Consola CFN        | ✅ COMPLETADO — B.2: `udabol-intent-parser-lex-qa` CREATE_COMPLETE. BotId ZZ7JYN2KA1 |
| **E2**    | B          | recognize_text "Quiero inscribirme" retorna intent=Inscribir, conf>=0.70 | CLI Lex test       | ✅ COMPLETADO — B.2: conf=0.92 verificado DEV y QA. 5/5 intents PASS |
| **E3**    | C          | Lambda agt-whatsapp-gateway-dev desplegada y activa                      | Consola Lambda     | ✅ COMPLETADO — C.1: `arn:aws:lambda:...:agt-whatsapp-gateway-dev` activa |
| **E3**    | C          | API Gateway endpoint responde HTTP 200 a POST test                       | curl output        | ✅ COMPLETADO — C.1: `https://il9jw4ux6d.execute-api.us-east-1.amazonaws.com` |
| **E3**    | C          | Logs en /aws/lambda/agt-whatsapp-gateway-dev                             | CloudWatch Logs    | ✅ COMPLETADO — C.1 verificado |
| **E4**    | C          | Task agt-agent-dev en RUNNING, /health HTTP 200                          | Consola ECS + curl | ✅ COMPLETADO — C.2+C.3: running=1/desired=1, AppSubnetA 10.10.11.23 |
| **E4**    | C          | Task agt-toolapi-dev en RUNNING, /health HTTP 200                        | Consola ECS + curl | ✅ COMPLETADO — C.2+C.3: running=1/desired=1, AppSubnetA 10.10.11.200 |
| **E4**    | C          | Logs en /agt/agent/dev y /agt/toolapi/dev                                | CloudWatch Logs    | ✅ COMPLETADO — C.2: grupos creados con entradas |
| **E5**    | C          | Task agt-legacy-adapter-dev en RUNNING                                   | Consola ECS        | ✅ COMPLETADO — C.2+C.3: running=1/desired=1, AppSubnetA 10.10.11.204 |
| **E5**    | D          | RDS DEV en status=available, QA en status=available                      | Consola RDS        | ✅ COMPLETADO — D.1: agt-db-dev.c4hioyi08vln / agt-db-qa.cotomq2m0uyo, available |
| **E5**    | D          | MSK DEV activo, 3 topics creados                                         | Consola MSK        | ✅ COMPLETADO — D.2: udabol-msk-dev/qa CREATE_COMPLETE, 9098 SASL/IAM, 3 topics |
| **E5**    | D          | Conexion DB desde Fargate exitosa (log de startup muestra DB connected)  | CloudWatch log     | ⏳ PENDIENTE — depende de valores reales en Secrets Manager (D3/D4 Carlos pendiente) |
| **E6**    | A          | Push a dev dispara build+deploy en DEV (pipeline completo)               | GH Actions         | ✅ COMPLETADO — A.4: ci.yml operativo, OIDC, ECR push verificado |
| **E6**    | A          | PR merge a qa dispara deploy en QA (al menos en 2 repos)                 | GH Actions         | ✅ COMPLETADO — A.4 verificado |
| **E6**    | A          | Sin credenciales AWS estaticas en GitHub Secrets (solo OIDC)             | GH Settings        | ✅ COMPLETADO — A.4: roles agt-gha-oidc-dev/qa, sin credenciales estaticas |
| **E7**    | E          | Dashboard udabol-erp-agent-dev con 6+ widgets con datos reales           | Consola CW         | ⏳ DIFERIDO Sprint 2 — N2 resuelto: OTel Collector (E.1) operativo; dashboard Sprint 2 |
| **E7**    | E          | Prueba de humo documentada: curl + captura response + log CW             | Documento/captura  | ⏳ BLOQUEADO — D6: credenciales Twilio pendientes (Carlos) |
| **E7**    | E          | aws-devops/runbooks/sprint1-deploy.md completo y funcional               | GitHub repo        | ✅ COMPLETADO — E.4: runbook actualizado 2026-05-23 |

# **9\. LO QUE CARLOS TE PROVEE (DEPENDENCIAS)**

Las siguientes dependencias son responsabilidad del Coordinador Tecnico. Si no las recibes en la primera semana, notificar de inmediato para evitar suspension justificada conforme al MSA:

| **#**  | **Dependencia**                                                                                                      | **Formato de entrega**           | **Cuando**          |
| ------ | -------------------------------------------------------------------------------------------------------------------- | -------------------------------- | ------------------- |
| **D1** | Acceso IAM Identity Center a DEV (245650696072) con permisos para desplegar ECS, RDS, MSK, Lex, Lambda, CFN          | Email + SSO portal URL           | **Antes de inicio** |
| **D2** | Acceso IAM Identity Center a QA (493735739951)                                                                       | Email + SSO portal               | **Semana 1**        |
| **D3** | Acceso colaborador GitHub org clouddev-udabol                                                                        | Invitacion GitHub                | **Antes de inicio** |
| **D4** | Variables de entorno .env.example con valores reales de DEV (TWILIO, HMS_PLUS, etc.) para configurar Secrets Manager | Archivo seguro / 1Password       | **Semana 1**        |
| **D5** | Dockerfiles base de cada microservicio (al menos un Dockerfile funcional que haga docker build sin errores)          | Commit en rama dev de cada repo  | **Semana 1**        |
| **D6** | CIDR de la red on-premise UDABOL para configurar Security Group del Legacy Adapter                                   | Mensaje directo                  | **Semana 1**        |
| **D7** | Credenciales Twilio (Account SID, Auth Token, numero de telefono origen) para prueba de humo                         | Secrets Manager o mensaje seguro | **Semana 2**        |

**IMPORTANTE:** Si alguna dependencia no esta disponible al inicio del Sprint, comunicar inmediatamente al Coordinador Tecnico (Carlos Alvarez Flores). El MSA (Clausula 15) permite reprogramar plazos sin penalidad cuando el bloqueo viene del Contratante.

Fundacion Dockweiler / Carlos Alvarez Flores | Mayo 2026 | Guia Tecnica Sprint 1 SOW-002 v1.0 | CONFIDENCIAL