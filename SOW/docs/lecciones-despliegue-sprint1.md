# Lecciones Aprendidas — Despliegue Sprint 1 SOW-002

**Proyecto:** UDABOL ERP-Agent
**Sprint:** 1 — Fundación + Infraestructura base AWS
**Autor:** Ayrton Irusta
**Fecha:** 2026-05-23

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

## Checklist para nuevos templates CFN

Antes de deployar un nuevo template CFN, verificar:

- [ ] El parámetro `Entorno` está definido con `AllowedValues: [desarrollo, staging, produccion]`
- [ ] Todos los recursos sujetos al SCP tienen `Tags: [{Key: Entorno, Value: !Ref Entorno}]`
- [ ] No hay caracteres no-ASCII en `GroupDescription` de Security Groups (EC2 API los rechaza)
- [ ] Si el template tiene `AWS::Lex::Bot` o `AWS::Lex::BotAlias`: sin `Tags`, sin `VoiceSettings`
- [ ] Los nombres de recursos IAM siguen los patrones `agt-*`, `udabol-*` o `role-vpc-flowlogs-*`
- [ ] El `--profile` corresponde al entorno correcto (`proy-dev` / `proy-qa`)
- [ ] Si es primera vez que se usa ECS en la cuenta: anticipar el error de service-linked role y reintentar
