# Lecciones Aprendidas — Despliegue Sprint 1 SOW-002

**Proyecto:** UDABOL ERP-Agent
**Sprint:** 1 — Fundación + Infraestructura base AWS
**Autor:** Ayrton Irusta
**Fecha:** 2026-05-23 (actualizado 2026-05-26 — L-13, L-14, L-15, L-16, L-17)

---

## L-01 — SCP de tagging no es un bloqueo de servicio

**Síntoma:** `ecs:CreateCluster`, `lambda:CreateFunction`, `rds:CreateDBInstance` retornaban `AccessDeniedException: explicit deny in service control policy p-lgafaevf`.

**Diagnóstico inicial (incorrecto):** El SCP bloquea ECS, Lambda y RDS en las cuentas DEV/QA.

**Causa real:** El SCP implementa *tagging enforcement*, no un bloqueo de servicio. Tiene dos statements:
- `DenyNoEntorno`: deniega si el tag `Entorno` está **ausente** en el request
- `DenyWrongEntorno`: deniega si `Entorno` tiene un valor distinto al del entorno (`desarrollo` en DEV, `staging` en QA)

Todos los tests de CLI que fallaron se ejecutaron sin pasar el tag `--tags Entorno=desarrollo`.

**Solución:** CloudFormation pasa automáticamente los tags definidos en `Properties.Tags:` al API call interno. Basta con incluir el tag en cada resource CFN:
```yaml
Tags:
  - Key: Entorno
    Value: !Ref Entorno
```

**Regla para futuros templates:** Todo recurso sujeto al SCP (`ec2:RunInstances`, `rds:CreateDBInstance`, `s3:CreateBucket`, `lambda:CreateFunction`, `ecs:CreateCluster`, `eks:CreateCluster`) **debe tener** `Tags: [{Key: Entorno, Value: !Ref Entorno}]` en la definición CFN. El parámetro `Entorno` (desarrollo/staging/produccion) debe incluirse en todos los templates.

**Cada entorno tiene su propio SCP:**
| Entorno | OU | SCP | Valor requerido |
|---------|-----|-----|-----------------|
| DEV | `ou-85xm-j0d6i27j` | `scp-dockweiler-development` | `Entorno=desarrollo` |
| QA | `ou-85xm-dfzuimrq` | `scp-dockweiler-quality-assurance` | `Entorno=staging` |
| PROD | `ou-85xm-cjg414jn` | `scp-dockweiler-production` | `Entorno=produccion` |

---

## L-02 — ECS service-linked role: error transitorio en primera creación

**Síntoma:** `CreateCluster Invalid Request: Unable to assume the service linked role` al intentar crear el primer ECS Cluster en una cuenta, incluso cuando `AWSServiceRoleForECS` ya existe.

**Causa:** Bug conocido de AWS — al crear el primer cluster en una cuenta, ECS intenta asumir el service-linked role y falla con un error de propagación IAM transitorio. El role existe pero AWS no lo "ve" inmediatamente.

**Solución:** Simplemente reintentar el deploy del stack CFN. El segundo intento siempre funciona (el role ya está propagado). No es necesario eliminar el role ni modificar permisos.

**Workaround en el template:** Se agregó el parámetro `EnableEcsCluster: true/false` al template `cluster.yaml` para poder deployar la capa de networking (Cloud Map + SGs) en un primer paso y agregar el cluster en un segundo deploy.

---

## L-03 — `cloudformation deploy` usa ChangeSets, no CreateStack/UpdateStack directo

**Síntoma:** El SCP incluye `cloudformation:CreateStack` y `cloudformation:UpdateStack` en los actions bloqueados (sin tag). Sin embargo, todos los deploys CFN funcionaron sin pasar `--tags` al comando `aws cloudformation deploy`.

**Causa:** El comando `aws cloudformation deploy` utiliza internamente `CreateChangeSet` + `ExecuteChangeSet`, **no** `CreateStack`/`UpdateStack` directamente. Esas dos acciones no están en el SCP bloqueado.

**Implicación:** Los stacks CFN no necesitan tags en el nivel del stack (el `--tags` del CLI) para pasar el SCP. Solo los recursos individuales dentro del stack (ECS, Lambda, RDS, etc.) necesitan el tag `Entorno`.

---

## L-04 — UTF-8 BOM rompe el parser de Poetry/TOML

**Síntoma:** `poetry install` falla con `Invalid statement (at line 1, column 1)` en Windows al leer `pyproject.toml`.

**Causa:** Algunos editores en Windows guardan archivos UTF-8 con BOM (`0xEF 0xBB 0xBF` al inicio). El parser TOML de Poetry no acepta BOM.

**Detección:**
```powershell
[System.IO.File]::ReadAllBytes("pyproject.toml")[0..2] | ForEach-Object { "{0:X2}" -f $_ }
# Si devuelve EF BB BF → tiene BOM
```

**Solución:** Reescribir el archivo con el tool `Write` de Claude (o con `Set-Content -Encoding utf8` en PowerShell, que en PS 5.1 escribe UTF-8 sin BOM al usar `-Encoding utf8NoBOM`).

**Afectados:** `agt-agent`, `agt-legacy-adapter`, `agt-toolapi`, `agt-whatsapp-gateway`.

---

## L-05 — Docker: `--no-root` + `PYTHONPATH` para src-layout con Poetry

**Síntoma:** `docker build` falla con `/app/src/agt_agent does not contain any element` al ejecutar `poetry install`.

**Causa:** Con `packages = [{include = "agt_agent", from = "src"}]` en pyproject.toml (src-layout), Poetry intenta instalar el paquete local como parte de `poetry install`. Pero en ese momento el `COPY src/` aún no se ejecutó — solo están `pyproject.toml` y `poetry.lock`.

**Solución:** Usar `--no-root` en el install (no instala el paquete local durante la fase de dependencias) y agregar `ENV PYTHONPATH=/app/src` para que Python encuentre los módulos en runtime:

```dockerfile
RUN poetry install --only main --no-interaction --no-ansi --no-root
COPY src/ ./src/
ENV PYTHONPATH=/app/src
CMD ["uvicorn", "agt_agent.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Patrón aplicado a:** todos los microservicios con src-layout.

---

## L-06 — Amazon Lex V2: limitaciones de CloudFormation

Limitaciones descubiertas al crear el bot con `AWS::Lex::Bot`:

| Limitación | Detalle | Solución |
|-----------|---------|----------|
| `Tags` no soportado en `AWS::Lex::Bot` | CFN rechaza el campo `Tags` en el recurso del bot | Eliminar el bloque Tags del Bot |
| `Tags` no soportado en `AWS::Lex::BotAlias` | Igual que el bot | Eliminar Tags del Alias |
| `VoiceId: Lupe` inválido para `es_419` | La voz Lupe no está disponible para ese locale | Eliminar `VoiceSettings` (campo opcional) |
| Todos los slots necesitan `SlotPriorities` | Lex V2 requiere que TODOS los slots (required + optional) estén listados en `SlotPriorities`, no solo los required | Incluir todos los slots al construir `SlotPriorities` en `generate_template.py` |

---

## L-07 — BotAlias de Lex V2: usar `TSTALIASID` para testing

**Síntoma:** `recognize-text` falla con "Bot alias ... isn't built" al usar el alias creado por CFN.

**Causa:** El `AWS::Lex::BotVersion` se crea **antes** de que el locale esté construido. La versión queda ligada al DRAFT pre-build. El BotAlias apunta a esa versión vacía.

**Solución para testing:** Usar `TSTALIASID` como alias ID. Este ID especial de AWS siempre apunta al DRAFT más reciente y construido:
```powershell
aws lexv2-runtime recognize-text --bot-alias-id TSTALIASID ...
```

**Solución para producción:** Después de `build-bot-locale`, crear una nueva `AWS::Lex::BotVersion` y actualizar el alias. En CFN, esto requiere actualizar el stack después del build.

---

## L-08 — ALB requiere mínimo 2 subnets en AZs distintas

**Síntoma:** `At least two subnets in two different Availability Zones must be specified` al intentar crear un Application Load Balancer.

**Causa:** Los entornos DEV y QA usan VPCs Single-AZ (costo optimizado). Solo existe `AppSubnetA` en `us-east-1a`.

**Solución:** El template `cluster.yaml` tiene el ALB condicional a `HasSecondSubnet`:
```yaml
Conditions:
  HasSecondSubnet: !Not [!Equals [!Ref AppSubnetB, ""]]
```
El ALB solo se crea cuando `AppSubnetB` tiene valor (entornos multi-AZ / PROD).

Para DEV/QA: el service discovery interno usa Cloud Map (`agt.local`) exclusivamente.

---

## L-09 — Inyección de intents en Lex: texto vs YAML parsing

**Problema de diseño original:** El script `build_bot.py` intentaba parsear el template CFN con `yaml.safe_load()` para insertar los intents, pero el template tiene tags CFN custom (`!Ref`, `!Sub`, `!ImportValue`) que no son YAML estándar — PyYAML falla con `could not determine a constructor for the tag`.

**Solución:** Inyección por texto. El template tiene un placeholder exacto:
```yaml
          Intents: []
```
El script `generate_template.py` reemplaza ese string con el bloque YAML serializado de los intents. No toca el resto del template.

```python
generated = shell_text.replace(
    "          Intents: []",
    f"          Intents:\n{intents_yaml}"
)
```

---

## L-10 — OIDC GitHub Actions: trust policy debe coincidir con la org

**Síntoma:** `Not authorized to perform sts:AssumeRoleWithWebIdentity` en los pipelines CI/CD.

**Causa:** Los roles OIDC pre-existentes (`proy-app-gha-role-development`, `proy-app-gha-role-qa`) tenían trust policy para una org de GitHub distinta a `clouddev-udabol`.

**Solución:** Crear nuevos roles IAM con nombres `agt-*` (dentro del scope del inline policy `IAMForProjectRoles`) vía CFN, con trust policy correcta:
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:clouddev-udabol/*:*"
}
```
Los roles pre-existentes se dejaron intactos; los nuevos roles se usan en todos los repos del sprint.

---

## L-11 — Lex V2 runtime: prefijo IAM es `lex:` no `lexv2:`

**Síntoma:** Lambda invocaba `lexv2-runtime.recognize_text()` pero recibía `AccessDeniedException` a pesar de tener la política IAM adjunta.

**Causa:** El prefijo de la acción IAM para Lex V2 runtime es `lex:` (igual que Lex V1), **no** `lexv2:`. El SDK de boto3 llama al cliente `lexv2-runtime`, pero el IAM evalúa la acción como `lex:RecognizeText`.

**Incorrecto:**
```yaml
Action:
  - lexv2:RecognizeText    # ← RECHAZADO por IAM
  - lexv2:RecognizeUtterance
```

**Correcto:**
```yaml
Action:
  - lex:RecognizeText      # ← IAM evalúa esto
  - lex:RecognizeUtterance
Resource: !Sub "arn:aws:lex:${AWS::Region}:${AWS::AccountId}:bot-alias/${LexBotId}/*"
```

**Referencia:** [IAM actions for Amazon Lex V2](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonlexv2.html) — todas las acciones tienen prefijo `lex:`.

---

## L-12 — VPC Endpoints con PrivateDnsEnabled=true son VPC-wide: incompatibles con tasks en subnet pública

**Síntoma (iteración 1):** Tasks ECS Fargate con `AssignPublicIp: DISABLED` en subnet privada fallan con `ResourceInitializationError: dial tcp <IP_PUBLICA>:443: i/o timeout`.

**Síntoma (iteración 2):** Tras crear VPC Endpoints (ecr.api, ecr.dkr, s3, logs, secretsmanager con `PrivateDnsEnabled: true`) y cambiar las tasks a subnet pública (`AssignPublicIp: ENABLED`), las tasks siguen fallando: `dial tcp 10.10.11.219:443: i/o timeout`.

**Causa raíz (confirmada):** `PrivateDnsEnabled: true` en un Interface VPC Endpoint sobreescribe el DNS del servicio de forma **VPC-wide** mediante Route 53 Resolver. Todas las queries DNS a `api.ecr.us-east-1.amazonaws.com` en cualquier subnet del VPC retornan la IP privada del ENI del endpoint (e.g. `10.10.11.219`). Si el ENI del endpoint está en la subnet App (privada) pero la task está en la subnet pública, la conexión TCP falla porque las rutas y SGs no están configuradas para cross-subnet.

**Solución para DEV/QA (subnet pública + internet):**
1. Eliminar el stack de VPC Endpoints completamente
2. Tasks con `AssignPublicIp: ENABLED` en subnet pública resuelven ECR a IPs públicas reales y conectan por internet
3. Costo: $0 adicional. Funcional mientras no haya ALB ni DNS externo.

**Solución correcta para PROD (subnet privada):**
- Los Interface Endpoints deben crearse con `SubnetIds` apuntando a **la misma subnet** donde corren las tasks (o al menos a una subnet de la misma AZ)
- Verificar que el Security Group del endpoint permite inbound TCP 443 desde el SG de las tasks ECS (no solo el CIDR del VPC)
- Agregar `platformVersion: LATEST` en la TaskDefinition para asegurar soporte DNS moderno de Fargate
- Orden de despliegue: crear endpoints → verificar DNS desde una instancia de prueba → luego lanzar tasks

**Parámetros afectados:**
- `SubnetId` en `parameters/dev/ecs-services.json`: usa `PublicSubnetA` (`subnet-00e7e9f0913426c64`)
- `AssignPublicIp`: `ENABLED` en DEV/QA, `DISABLED` en PROD (con endpoints correctos)

---

## L-13 — NACL subnet privada: regla de puertos efímeros debe abarcar `0.0.0.0/0`

**Síntoma:** Tasks ECS Fargate en AppSubnetA (subnet privada) fallan con `CannotPullContainerError: dial tcp 52.216.51.58:443: i/o timeout` al intentar descargar capas de imagen desde ECR. El endpoint ECR DKR existe, tiene `PrivateDnsEnabled: true` y su ENI está accesible.

**Causa raíz:** ECR DKR autentica y entrega manifests vía el Interface VPC Endpoint (IP privada). Pero los blobs de capas de imagen se sirven desde **S3 presigned URLs** — ECR redirige los GET de blobs a S3. El tráfico a S3 sale por el **S3 Gateway Endpoint** (ruta `pl-63a5400a`), que usa las IPs públicas de S3 como destino. El tráfico de **retorno de S3** llega con source IP = IP pública de S3 (`52.216.x.x`, `16.15.x.x`). Si la NACL de la subnet privada solo permite TCP 1024-65535 inbound desde el CIDR de la VPC, esos paquetes de retorno quedan bloqueados por el `deny all` por defecto.

**Solución:** La regla NACL que permite puertos efímeros inbound debe usar `CidrBlock: "0.0.0.0/0"`, no el CIDR del VPC:

```yaml
NaclAppInboundFromPublic:
  Type: AWS::EC2::NetworkAclEntry
  Properties:
    NetworkAclId: !Ref NaclApp
    RuleNumber: 100
    Protocol: 6
    RuleAction: allow
    Egress: false
    CidrBlock: "0.0.0.0/0"   # ← no !Ref VpcCidr
    PortRange: { From: 1024, To: 65535 }
```

**Seguridad:** Ampliar a `0.0.0.0/0` en una subnet privada (sin ruta a IGW) es seguro. Ningún host externo puede iniciar conexiones a esa subnet porque no existe una ruta de entrada desde internet. Solo tráfico de retorno de conexiones iniciadas dentro del VPC puede llegar con source IP externo (caso S3 Gateway Endpoint).

**Regla:** En cualquier subnet privada que use S3 Gateway Endpoint o que el tráfico de retorno pueda venir de IPs externas a la VPC, la regla NACL de puertos efímeros inbound debe ser `0.0.0.0/0`.

---

## L-14 — ECS Deployment Circuit Breaker: deadlock con CloudFormation

**Síntoma:** Stack CFN en `UPDATE_ROLLBACK_IN_PROGRESS` o `UPDATE_ROLLBACK_FAILED` permanente. Las tasks ECS fallan consecutivamente pero CFN no puede completar el rollback porque espera que el servicio ECS estabilice, y ECS no reintenta porque el circuit breaker está activo.

**Causa:** El `DeploymentCircuitBreaker` de ECS se activa tras N fallos consecutivos y establece `RolloutState: FAILED`. ECS deja de lanzar nuevas tasks. CFN interpreta esto como "servicio inestable" y espera indefinidamente para completar el rollback, creando un deadlock.

**Diagnóstico:**
```bash
aws ecs describe-services --cluster CLUSTER --services SERVICE \
  --query "services[0].deployments[*].{Status:status,Desired:desiredCount,Running:runningCount,Rollout:rolloutState}"
```
Si `RolloutState: FAILED` → circuit breaker activo.

**Secuencia de escape:**
1. `aws ecs update-service --force-new-deployment --cluster CLUSTER --service SERVICE`
   — resetea el circuit breaker, ECS lanza nuevas tasks
2. Esperar `RolloutState: COMPLETED` (verificar con describe-services)
3. Si el stack quedó en `UPDATE_ROLLBACK_FAILED`:
   `aws cloudformation continue-update-rollback --stack-name STACK_NAME`
4. Esperar `UPDATE_ROLLBACK_COMPLETE` antes de intentar el siguiente deploy

**Contexto de cuentas:** `force-new-deployment` y `continue-update-rollback` son operaciones de recuperación — se ejecutan con `cloudadmin` como excepción. Notificar al usuario antes de proceder.

**Prevención:** Asegurarse de que la causa raíz que activa el circuit breaker esté corregida antes de forzar un nuevo deploy. De lo contrario el ciclo se repite.

---

## L-15 — IAM inline policy en roles GHA pre-existentes: actualización fuera de CFN

**Síntoma:** Stack `udabol-ecs-services-dev` falla con `AccessDeniedException: User ... is not authorized to perform: iam:DeleteRolePolicy on resource: role agt-ecs-task-dev`. El rol GHA `proy-app-gha-role-development` existe pero le faltan permisos para gestionar los roles IAM del stack ECS.

**Causa:** El stack `github-oidc-iaapp-dev` que gestiona el inline policy `IAMForVPCFlowLogs` está en `ROLLBACK_COMPLETE`. CFN no permite actualizar un stack en ese estado. Los roles GHA (`proy-app-gha-role-development/qa`) fueron creados manualmente (no vía CFN), por lo que el template `iam-role.yaml` tiene el estado correcto pero el stack no puede aplicarlo.

**Acciones necesarias para el ECS services deploy:**
```
iam:GetRole, iam:CreateRole, iam:DeleteRole
iam:PutRolePolicy, iam:DeleteRolePolicy, iam:GetRolePolicy
iam:TagRole, iam:UntagRole
iam:ListRolePolicies, iam:ListAttachedRolePolicies
iam:PassRole
```
Sobre recursos `arn:aws:iam::ACCOUNT:role/agt-ecs-*`.

**Solución:** Aplicar directamente con `cloudadmin` (operación IAM/seguridad — excepción permitida):
```bash
aws iam put-role-policy \
  --role-name proy-app-gha-role-development \
  --policy-name IAMForVPCFlowLogs \
  --policy-document file://policy.json \
  --profile cloudadmin-dev
```
El template `iam-role.yaml` debe actualizarse igualmente para mantener IaC consistente, aunque el stack CFN no pueda aplicarlo.

**Regla:** Cuando un stack CFN que gestiona IAM roles/policies está en `ROLLBACK_COMPLETE`, usar `aws iam put-role-policy` como workaround. Siempre actualizar el template IaC en paralelo. El stack en `ROLLBACK_COMPLETE` debe eliminarse y redesplegarse en una ventana de mantenimiento posterior.

---

## L-16 — CFN stack-level tags actualizan IAM roles: GHA role necesita iam:TagRole/UntagRole

**Contexto:** Deploy de `ecs-services` fallaba con `iam:TagRole` / `iam:UntagRole` denegado aunque el template de IAM roles no cambió.

**Causa raíz:** `aws cloudformation deploy` pasa tags de stack-level (`CommitHash`, `DeployDate`, etc.). En cada deploy, si algún tag cambia, CFN actualiza esos tags en TODOS los recursos del stack, incluyendo IAM roles. Para taggear un rol, el deployer necesita `iam:TagRole` y `iam:UntagRole`.

**Síntoma confuso:** `EcsTaskRole` y `EcsExecutionRole` no cambiaron en el template, pero igual fallaron con AccessDenied en tagging porque `DeployDate` y `CommitHash` son diferentes en cada run.

**Fix:** Inline policy `IAMForECSRoles` en GHA role con `iam:TagRole`, `iam:UntagRole`, `iam:PutRolePolicy`, `iam:DeleteRolePolicy` scoped a `agt-ecs-*`. Aplicar via `aws iam put-role-policy` (cloudadmin) ya que el stack del GHA role está en ROLLBACK_COMPLETE.

**Regla:** Todo GHA role que despliege stacks CFN con `AWS::IAM::Role` debe tener `iam:TagRole` + `iam:UntagRole` scoped al prefijo de roles que gestiona. Si los stack-level tags son dinámicos (CommitHash, DeployDate), asumir que CFN intentará re-taggear los roles en cada deploy.

---

## L-17 — ADOT en ECS: AOT_CONFIG_CONTENT + puerto 4317 no incluido en SG del cluster

**Contexto:** Deploy del OTel Collector (E.1) con `public.ecr.aws/aws-observability/aws-otel-collector`.

**Lección 1 — AOT_CONFIG_CONTENT como env var elimina la necesidad de S3/SSM:**
ADOT lee su configuración desde la variable de entorno `AOT_CONFIG_CONTENT` si está presente. Esto permite definir el config YAML completo inline en el `ContainerDefinitions` del task definition via `!Sub |`, con sustitución de `${Environment}` y `${AWS::Region}` desde CloudFormation. No requiere S3 bucket, SSM Parameter Store ni volumen EFS para montar el config.

**Lección 2 — La extensión `health_check` es requerida para el ECS health check:**
El binario `/healthcheck` incluido en la imagen ADOT conecta al endpoint de la extensión `health_check` (por defecto `0.0.0.0:13133`). Si la extensión no está declarada en el config, el binario no encuentra el endpoint y el health check ECS falla con exit 1. Siempre incluir en `AOT_CONFIG_CONTENT`:
```yaml
extensions:
  health_check:
    endpoint: "0.0.0.0:13133"
service:
  extensions: [health_check]
```
Y en el task definition:
```yaml
HealthCheck:
  Command: ["CMD", "/healthcheck"]
```

**Lección 3 — El SG del cluster solo tiene self-referencing ingress en puerto 8080:**
El stack `udabol-ecs-cluster-{env}` define `EcsTaskSgSelfIngress` únicamente para TCP 8080 (comunicación entre servicios). El puerto 4317 (gRPC OTLP) no está incluido. La solución correcta es agregar un recurso `AWS::EC2::SecurityGroupIngress` en el stack del OTel Collector que añade la regla al SG importado:
```yaml
EcsTaskSgOtelIngress:
  Type: AWS::EC2::SecurityGroupIngress
  Properties:
    GroupId: !ImportValue "${ClusterStackName}-EcsTaskSgId"
    IpProtocol: tcp
    FromPort: 4317
    ToPort: 4317
    SourceSecurityGroupId: !ImportValue "${ClusterStackName}-EcsTaskSgId"
```
Al eliminar el stack otel-collector, la regla también se elimina.

**Lección 4 — Reutilizar el execution role del services stack evita IAM duplicado:**
El execution role `agt-ecs-exec-{env}` (creado en `udabol-ecs-services-{env}`) tiene `AmazonECSTaskExecutionRolePolicy` + `secretsmanager:GetSecretValue`. Referenciar por ARN con `!Sub "arn:aws:iam::${AWS::AccountId}:role/agt-ecs-exec-${Environment}"` evita crear un rol duplicado y no requiere ninguna operación IAM adicional en el GHA role.

**Lección 5 — Los logs del contenedor ADOT satisfacen el criterio E6:**
ADOT emite logs estructurados JSON a stdout (ej: `{"level":"info","msg":"Everything is ready...","service.name":"aws-otel-collector"}`). El driver `awslogs` los captura directamente al log group `/udabol/{env}/agt`. No es necesario configurar el exporter `awscloudwatchlogs` en el pipeline OTel para satisfacer "log group con al menos 1 entrada estructurada JSON" del criterio E6.

---

## Checklist para nuevos templates CFN

Antes de deployar un nuevo template CFN, verificar:

- [ ] El parámetro `Entorno` está definido con `AllowedValues: [desarrollo, staging, produccion]`
- [ ] Todos los recursos sujetos al SCP tienen `Tags: [{Key: Entorno, Value: !Ref Entorno}]`
- [ ] No hay caracteres no-ASCII en `GroupDescription` de Security Groups (EC2 API los rechaza)
- [ ] Si el template tiene `AWS::Lex::Bot` o `AWS::Lex::BotAlias`: sin `Tags`, sin `VoiceSettings`
- [ ] Los nombres de recursos IAM siguen los patrones `agt-*`, `udabol-*` o `role-vpc-flowlogs-*`
- [ ] El `--profile` corresponde al entorno correcto (`proy-dev` / `proy-qa`)
- [ ] Si es primera vez que se usa ECS en la cuenta: anticipar el error de service-linked role y reintentar
- [ ] Subnets privadas con S3 Gateway Endpoint: regla NACL de puertos efímeros inbound debe usar `0.0.0.0/0` (ver L-13)
- [ ] Antes de deployar ECS services: verificar que `proy-app-gha-role-*` tiene `IAMForECSRoles` con `iam:TagRole`, `iam:UntagRole`, `iam:PutRolePolicy`, `iam:DeleteRolePolicy` sobre `agt-ecs-*` (ver L-15, L-16)
- [ ] Si el ECS Deployment Circuit Breaker se activa durante un deploy: seguir la secuencia de escape de L-14 antes de reintentar
- [ ] Nuevos ECS services sin imagen en ECR: usar `DesiredCount=0` hasta que la imagen sea pusheada; evita circuit breaker
- [ ] Templates con ADOT: incluir `health_check` extension en `AOT_CONFIG_CONTENT` y usar `CMD /healthcheck` (ver L-17)
- [ ] Si el stack agrega un nuevo puerto inter-ECS: agregar `AWS::EC2::SecurityGroupIngress` en el mismo stack referenciando el SG exportado del cluster (ver L-17)
