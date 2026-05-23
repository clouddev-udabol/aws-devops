# Onboarding — iaapp (UDABOL)

> **Audiencia:** desarrollador nuevo en el equipo iaapp.
> **Tiempo estimado:** 60–90 minutos para completar todo.
> **Resultado:** podrás clonar el repo, hacer un cambio trivial y verlo desplegado en `dev`.

---

## Día 1 — Setup local

### 1. Acceso al repositorio (5 min)

- Pide invitación al repo `airusta/iaapp` en GitHub
- Al recibirla, acepta y clona:

```bash
git clone https://github.com/airusta/iaapp.git
cd iaapp
```

### 2. Acceso a AWS (10 min)

- Pide al owner que cree tu usuario en AWS IAM Identity Center (SSO)
- Recibirás una invitación al portal: https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/
- Cambia tu contraseña inicial y configura MFA (obligatorio)
- Verifica que tienes acceso a las cuentas:
  - `iaapp-dev` (245650696072)
  - `iaapp-qa` (493735739951)

### 3. Instalar herramientas (15 min)

#### macOS

```bash
brew install awscli git jq
brew install --cask docker
pip install --user pre-commit cfn-lint==1.20.0 checkov==3.2.71 detect-secrets==1.5.0
```

#### Linux (Ubuntu/Debian)

```bash
sudo apt-get update && sudo apt-get install -y git jq unzip python3-pip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
pip install --user pre-commit cfn-lint==1.20.0 checkov==3.2.71 detect-secrets==1.5.0
```

#### Windows (con WSL2 — recomendado)

Usar las instrucciones de Linux dentro de WSL2 Ubuntu.

### 4. Configurar AWS CLI con SSO (10 min)

```bash
aws configure sso
```

Responde el wizard:

```
SSO session name (Recommended): iaapp
SSO start URL: https://ssoins-7223753b6943f944.portal.us-east-1.app.aws/start
SSO region: us-east-1
SSO registration scopes: sso:account:access
```

El navegador se abrirá para que confirmes. Después, selecciona la cuenta `dev`:

```
Account: 245650696072 (iaapp-dev)
Role: AdministratorAccess (o el que te haya asignado el owner)
CLI default region: us-east-1
CLI default output format: json
CLI profile name: iaapp-dev
```

Repite para `iaapp-qa` con la cuenta 493735739951.

Verifica:

```bash
aws sso login --profile iaapp-dev
aws sts get-caller-identity --profile iaapp-dev
```

### 5. Activar pre-commit hooks (5 min)

```bash
cd iaapp
pre-commit install
pre-commit run --all-files   # primera ejecución, valida que todo funciona
```

Esto activa la validación local automática en cada commit:
- `cfn-lint` (estructura CloudFormation)
- `checkov` (policy as code)
- `detect-secrets` (no commitear credenciales)

### 6. Validar con `make` (5 min)

```bash
make help          # debe imprimir la lista de comandos
make lint          # cfn-lint + checkov sobre todos los templates
```

Si todo pasa, estás listo.

---

## Día 1 — Tu primer cambio

### 7. Hacer un cambio trivial (15 min)

Cambia algo inocuo, por ejemplo el `RetentionInDays` de Flow Logs en `dev` de 30 a 14.

```bash
git checkout main && git pull
git checkout -b chore/onboarding-test
```

Edita `parameters/dev/vpc.json`:

```diff
- { "ParameterKey": "FlowLogsRetentionDays",  "ParameterValue": "30" }
+ { "ParameterKey": "FlowLogsRetentionDays",  "ParameterValue": "14" }
```

### 8. Validar localmente

```bash
make lint                              # debe pasar
make plan ENV=dev STACK=vpc            # ChangeSet preview, requiere SSO activo
```

El plan debe mostrar UN cambio: el `FlowLogsLogGroup.RetentionInDays`.

### 9. Hacer el PR

```bash
git add parameters/dev/vpc.json
git commit -m "chore(dev): reducir retención de flow logs a 14 días [onboarding]"
git push -u origin chore/onboarding-test
gh pr create --base main --title "[Onboarding] Test PR — reducir retención flow logs dev"
```

### 10. Ver el pipeline

- Ve a GitHub → Actions → busca tu PR
- Verás `pr-validate.yml` corriendo con 3 jobs:
  - `lint-and-scan` — cfn-lint + checkov
  - `changeset-preview-dev` — preview del ChangeSet en la cuenta de dev
  - `summary` — resumen final
- Cuando todo pasa (verde), pide review a un colega
- Tras la aprobación, hacer **squash merge** a `main`

### 11. Ver el deploy automático

- Al mergear, GitHub dispara `deploy-nonprod.yml` automáticamente
- Espera 2-3 minutos
- Verifica:

```bash
aws sso login --profile iaapp-dev
aws logs describe-log-groups \
  --log-group-name-prefix /vpc/flowlogs/iaapp/dev \
  --profile iaapp-dev \
  --query 'logGroups[0].retentionInDays'
# Debe imprimir: 14
```

🎉 ¡Hiciste tu primer cambio en producción de iaapp!

### 12. Limpiar

Después del onboarding test, abre un nuevo PR para revertir el cambio (`14` → `30`).

---

## Día 2+ — Lecturas obligatorias

Ahora que tienes el setup, dedica tiempo a leer:

| Tiempo | Documento                                | Por qué |
|--------|------------------------------------------|---|
| 30 min | [`docs/GUIA-TRANSFERENCIA.md`](GUIA-TRANSFERENCIA.md) | Modelo mental completo del proyecto |
| 15 min | [`docs/vpc-design.md`](vpc-design.md)    | Por qué la red está armada así |
| 10 min | [`docs/runbook-rollback.md`](runbook-rollback.md) | Qué hacer si algo se rompe |
| 10 min | [`policies/README.md`](../policies/README.md) | Reglas de seguridad |
| 5 min  | [`CODEOWNERS`](../CODEOWNERS)            | Quién aprueba qué |

---

## Comandos de referencia rápida

```bash
# SSO login (sesiones expiran en 8h)
aws sso login --profile iaapp-dev
aws sso login --profile iaapp-qa

# Validación local
make lint

# Preview cambios
make plan ENV=dev STACK=vpc

# Deploy local (no usar para prod)
make deploy ENV=dev STACK=vpc

# Diff entre AWS y local
make diff ENV=dev STACK=vpc

# Outputs de un stack
make outputs ENV=dev STACK=vpc

# Eliminar un stack (con confirmación)
make delete ENV=dev STACK=vpc

# Lanzar deploy desde GitHub CLI
gh workflow run deploy-nonprod.yml -f environment=qa -f stack=vpc
gh workflow run deploy-prod.yml -f stack=vpc -f confirm=IAAPP-PROD -f ticket=GH-123
```

---

## Convenciones que debes seguir

1. **Branch naming:** `feat/<corto>`, `fix/<corto>`, `chore/<corto>`, `docs/<corto>`
2. **Commit messages:** [Conventional Commits](https://www.conventionalcommits.org/) — `feat(vpc): agregar VPC endpoint S3`
3. **PR title:** mismo formato del commit principal
4. **PR description:** qué cambia, por qué, cómo se probó
5. **Tags AWS:** `Project=iaapp`, `Owner=ayrton.irusta@gmail.com`, etc. (ver §11 de la guía)
6. **Nunca commitear secretos:** `detect-secrets` debería bloquearte; si pasa algo igual, [rotar inmediatamente](https://docs.github.com/en/code-security/secret-scanning)

---

## Cuando algo no funciona

1. **Antes de preguntar:** intenta `make lint`, mira la sección "Estados ocultos" de la GUIA, busca en GitHub Issues
2. **Si tienes que preguntar:** abre un thread en el canal del equipo con:
   - Qué intentaste hacer
   - Qué pasó (paste del error)
   - Qué probaste

---

## Bienvenido al equipo

Cualquier mejora a este onboarding se agradece — abre un PR contra este archivo.

*UDABOL · iaapp · Owner: ayrton.irusta@gmail.com*
