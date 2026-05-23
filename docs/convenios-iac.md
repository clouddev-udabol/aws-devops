# Convenciones IaC — iaapp / UDABOL

> **Audiencia:** ingenieros que tocan `cloudformation/`, `parameters/`, `budgets/` o `.github/workflows/`.
> **Objetivo:** evitar que los mismos problemas de CI bloqueen PRs futuras y mantener calidad uniforme en los templates.

---

## Índice

1. [Reglas GitHub Actions CI](#1-reglas-github-actions-ci)
2. [Reglas CloudFormation](#2-reglas-cloudformation)
3. [Reglas de escaneo de seguridad](#3-reglas-de-escaneo-de-seguridad)
4. [Tagging obligatorio](#4-tagging-obligatorio)
5. [Estructura de archivos](#5-estructura-de-archivos)
6. [Checklist de PR](#6-checklist-de-pr)
7. [Lecciones aprendidas](#7-lecciones-aprendidas)

---

## 1. Reglas GitHub Actions CI

### 1.1 `cache: pip` requiere `requirements.txt`

`actions/setup-python` con `cache: 'pip'` **falla en ~1 segundo** si no existe un archivo de dependencias reconocido por pip (`requirements.txt`, `pyproject.toml`, etc.).

**Regla:** toda job que use `cache: 'pip'` DEBE tener un `requirements.txt` en la raíz del repo con las librerías exactas (versiones fijadas).

```yaml
# CORRECTO
- uses: actions/setup-python@v5
  with:
    python-version: '3.11'
    cache: 'pip'          # ← requiere requirements.txt en el repo
```

```
# requirements.txt — siempre versiones fijadas
cfn-lint==1.20.0
checkov==3.2.71
detect-secrets==1.5.0
```

Al actualizar una librería, actualizar `requirements.txt` **y** el `pip install` del workflow en el mismo commit.

---

### 1.2 Globs recursivos en bash requieren `shopt`

En bash, `**` **no es recursivo por defecto**. Sin activarlo, `cloudformation/**/*.yaml` se pasa como string literal al comando siguiente.

**Regla:** cualquier `run:` que use globs con `**` DEBE empezar con:

```bash
shopt -s globstar nullglob
```

- `globstar` → activa `**` recursivo
- `nullglob` → si el patrón no hace match (directorio inexistente), se ignora silenciosamente en lugar de pasarse como literal

```yaml
# CORRECTO
- name: Validate templates
  run: |
    shopt -s globstar nullglob
    for tpl in cloudformation/**/*.yaml budgets/*.yaml; do
      aws cloudformation validate-template --template-body file://${tpl} ...
    done
```

```yaml
# INCORRECTO — falla si budgets/ no existe
- name: Validate templates
  run: |
    for tpl in cloudformation/**/*.yaml budgets/*.yaml; do
      ...
```

---

### 1.3 Variables de repositorio vs. valores hardcodeados

Los ARNs de roles IAM y IDs de cuenta **NO** se hardcodean en los workflows. Se usan GitHub Variables del repositorio.

| Variable | Descripción |
|----------|-------------|
| `vars.AWS_ROLE_DEV` | ARN completo del rol OIDC en cuenta DEV |
| `vars.AWS_ROLE_QA`  | ARN completo del rol OIDC en cuenta QA  |

```yaml
# CORRECTO
role-to-assume: ${{ vars.AWS_ROLE_DEV }}

# INCORRECTO
role-to-assume: arn:aws:iam::245650696072:role/GithubActionsDeployRole-iaapp-dev
```

Al crear una nueva cuenta/ambiente, agregar la variable correspondiente en el repositorio GitHub antes de abrir el PR.

---

### 1.4 Versiones de actions

Usar versiones fijadas (`@v4`, no `@latest` ni `@main`) para reproducibilidad. Revisar actualizaciones de Node.js en los action runners al menos una vez por SOW.

```yaml
# CORRECTO
uses: actions/checkout@v4
uses: aws-actions/configure-aws-credentials@v4

# INCORRECTO
uses: stelligent/cfn_nag@master   # ← apunta a HEAD, no reproducible
```

> Excepción actual: `stelligent/cfn_nag@master` — pendiente migrar a versión fija cuando el proyecto publique releases estables.

---

## 2. Reglas CloudFormation

### 2.1 `DeletionPolicy` y `UpdateReplacePolicy` en recursos con estado

Los recursos con estado (LogGroups, Buckets, tablas DynamoDB, RDS) **deben** declarar explícitamente qué sucede al borrar o reemplazar el stack.

```yaml
# CORRECTO
FlowLogsLogGroup:
  Type: AWS::Logs::LogGroup
  DeletionPolicy: Retain         # ← no borrar logs al destruir stack
  UpdateReplacePolicy: Retain
  Properties:
    ...
```

Valores válidos: `Delete` | `Retain` | `Snapshot` (solo para recursos que lo soporten).
Si se omite, CloudFormation aplica `Delete` por defecto — riesgo de pérdida de datos.

---

### 2.2 VPC Flow Logs — sintaxis correcta

La propiedad `VpcId` fue deprecada en `AWS::EC2::FlowLog`. Usar siempre:

```yaml
# CORRECTO
Type: AWS::EC2::FlowLog
Properties:
  ResourceId: !Ref VPC
  ResourceType: VPC

# INCORRECTO (deprecated — produce CREATE_FAILED)
Properties:
  VpcId: !Ref VPC
```

---

### 2.3 Parámetros condicionados a ambientes — usar Mappings

Cuando un valor difiere por ambiente, usar `Mappings` en lugar de múltiples condicionales. Ejemplo del tag `Entorno` requerido por SCP:

```yaml
Mappings:
  EnvToEntorno:
    dev:  { Entorno: desarrollo }
    qa:   { Entorno: staging }
    prod: { Entorno: produccion }

# Uso en cualquier recurso
- Key: Entorno
  Value: !FindInMap [EnvToEntorno, !Ref Environment, Entorno]
```

---

### 2.4 NAT Gateway — costo por defecto desactivado

Para DEV y QA, `EnableNatGateway` debe ser `"false"` en los archivos de parámetros. Un NAT Gateway cuesta ~$32/mes por AZ.

```json
// parameters/dev/vpc.json
{ "ParameterKey": "EnableNatGateway", "ParameterValue": "false" }

// parameters/prod/vpc.json
{ "ParameterKey": "EnableNatGateway", "ParameterValue": "true" }
```

---

### 2.5 Subnets públicas — `MapPublicIpOnLaunch`

Las subnets de la capa pública (exposición) tienen `MapPublicIpOnLaunch: true` de forma intencional para soportar balanceadores de carga. Esto es conocido y documentado.

Checkov CKV_AWS_130 es suprimido en las subnets públicas con comentario explícito si lo señalara en el futuro.

---

## 3. Reglas de escaneo de seguridad

### 3.1 Jerarquía de herramientas

| Herramienta | Qué detecta | Falla el CI si... |
|-------------|-------------|-------------------|
| `cfn-lint`  | Errores de sintaxis y mejores prácticas CFN | Nivel E (error) |
| `cfn-nag`   | Patrones inseguros (IAM wildcard, SGs abiertos) | Cualquier W con `--fail-on-warnings` |
| `checkov`   | Policy-as-code (CIS, NIST, PCI) | Severidad MEDIUM o mayor |

### 3.2 Cuándo suprimir un check

Suprimir un check de seguridad es válido cuando:

1. La decisión es **intencional y documentada** (ej: subnet pública con IP pública).
2. El remedio está **deferido con ticket** (ej: KMS para CWL en SOW-002).
3. El check tiene un **falso positivo** demostrable.

**Nunca** suprimir sin comentario de justificación.

#### Formato de supresión — checkov (en el template CFN)

```yaml
ResourceLogico:
  # checkov:skip=CKV_AWS_XXX:<justificación en una línea — qué, por qué, cuándo se revisará>
  Type: AWS::...
```

#### Formato de supresión — cfn-lint (en `.cfnlintrc.yaml`)

```yaml
ignore_checks:
  - W3005  # DependsOn implícito — intencional en VPCGatewayAttachment + RouteTable
  - W2001  # Parámetros de Multi-AZ solo usados condicionalmente
```

#### Formato de supresión — cfn-nag (metadata en el recurso)

```yaml
ResourceLogico:
  Type: AWS::...
  Metadata:
    cfn_nag:
      rules_to_suppress:
        - id: W28
          reason: "Nombre explícito requerido por naming convention del proyecto"
```

### 3.3 Checks de seguridad deferred (deuda técnica conocida)

| Check | Recurso afectado | Prioridad | SOW destino |
|-------|-----------------|-----------|-------------|
| CKV_AWS_158 | `FlowLogsLogGroup` (CWL sin KMS) | MEDIUM | SOW-002 |

Al iniciar SOW-002, resolver este punto antes de nuevos recursos de logging.

### 3.4 IAM actions — nombres exactos

cfn-lint valida que las actions de IAM existan en el catálogo. Errores comunes:

| Incorrecto | Correcto |
|------------|---------|
| `cloudformation:DescribeChangeSets` | `cloudformation:DescribeChangeSet` (singular) |
| `budgets:CreateBudget` | Solo existe via API directo; usar `budgets:ModifyBudget` para CFN |

Referencia canónica: [Actions, resources, and condition keys for AWS services](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html)

---

## 4. Tagging obligatorio

Todo recurso desplegado por CloudFormation **debe** tener los siguientes tags. El SCP organizacional bloquea recursos sin el tag `Entorno`.

| Tag | Valor | Fuente |
|-----|-------|--------|
| `Name` | `<tipo>-<proyecto>-<ambiente>[-sufijo]` | `!Sub` hardcoded |
| `Environment` | `dev` / `qa` / `prod` | `!Ref Environment` |
| `Entorno` | `desarrollo` / `staging` / `produccion` | `!FindInMap [EnvToEntorno, ...]` |
| `Project` | `iaapp` | `!Ref ProjectName` |
| `Company` | `udabol` | `!Ref Company` |
| `Owner` | email del responsable | `!Ref Owner` |
| `ManagedBy` | `cloudformation` | hardcoded |
| `SOW` | `SOW-001`, `SOW-002`, etc. | hardcoded por módulo |

Al agregar un nuevo recurso al template, copiar el bloque `Tags:` de un recurso vecino y verificar que incluya todos los tags de la tabla.

---

## 5. Estructura de archivos

```
cloudformation/
  modules/
    vpc/
      vpc.yaml          ← template reutilizable multi-ambiente
    <modulo>/
      <modulo>.yaml

parameters/
  dev/
    vpc.json            ← parámetros específicos de ambiente
    budgets.json
  qa/
    vpc.json
    budgets.json
  prod/
    vpc.json
    budgets.json

budgets/
  budget-setup.yaml     ← template CFN para AWS Budgets

.github/
  workflows/
    deploy-nonprod.yml  ← deploy a dev y qa (rama main)
    deploy-prod.yml     ← deploy a prod (tag vX.Y.Z)
    pr-validate.yml     ← lint + scan + changeset preview (PR)
    drift-detection.yml ← detección de drift (schedule)
  oidc/
    iam-role.yaml       ← OIDC Provider + IAM Role para GHA

requirements.txt        ← librerías Python de CI (versiones fijadas)
.cfnlintrc.yaml         ← configuración cfn-lint
.pre-commit-config.yaml ← hooks locales
```

---

## 6. Checklist de PR

Antes de abrir un PR que toque IaC, verificar:

### Templates CloudFormation
- [ ] Todos los recursos nuevos tienen los 8 tags obligatorios
- [ ] Recursos con estado tienen `DeletionPolicy` y `UpdateReplacePolicy` explícitos
- [ ] No se usa la propiedad `VpcId` en `AWS::EC2::FlowLog`
- [ ] Los parámetros de costo (NAT Gateway) están en `"false"` para dev/qa

### GitHub Actions
- [ ] `requirements.txt` existe y está actualizado si se agregan librerías
- [ ] Cualquier `run:` con `**` en el glob tiene `shopt -s globstar nullglob`
- [ ] No hay ARNs ni IDs de cuenta hardcodeados — se usan `vars.*`

### Seguridad
- [ ] `checkov`, `cfn-lint` y `cfn-nag` corren localmente sin nuevos bloqueos
- [ ] Toda supresión nueva tiene comentario de justificación
- [ ] La tabla de deuda técnica en §3.3 está actualizada si se agrega una supresión

### Pre-commit (si está instalado localmente)
```bash
pre-commit run --all-files
```

---

## 7. Lecciones aprendidas

Registro de problemas encontrados en CI, con causa raíz y solución aplicada. Actualizar con cada PR problemático.

---

### [2026-05-22] PR #1 — feature/sow-001-vpc-3capas

**Contexto:** primera PR al repo clouddev-udabol/aws-devops desde el stack SOW-001.

| # | Síntoma | Causa raíz | Solución |
|---|---------|-----------|---------|
| 1 | `Setup Python` falla en 1 segundo | `cache: 'pip'` sin `requirements.txt` | Crear `requirements.txt` con versiones fijadas |
| 2 | `checkov` falla con CKV_AWS_158 | `FlowLogsLogGroup` sin cifrado KMS | `checkov:skip` con justificación; KMS deferido a SOW-002 |
| 3 | `validate-template` falla con "No such file `cloudformation/**/*.yaml`" | bash no expande `**` sin `shopt -s globstar` | Agregar `shopt -s globstar nullglob` antes del loop |
| 4 | `validate-template` falla con "No such file `budgets/*.yaml`" | Directorio `budgets/` no existe en la rama | `nullglob` hace que el patrón se ignore silenciosamente |

**Tiempo total bloqueado:** ~45 minutos de iteración CI/push.
**Prevención futura:** checklist §6 cubre los 4 puntos.

---

*Documento mantenido por el equipo DevOps. Actualizar en cada SOW o cuando se detecte un patrón nuevo en CI.*
