# AWS SSO — Autenticación y Perfiles

> Cómo autenticarse en las cuentas AWS del proyecto con AWS IAM Identity Center (SSO).

---

## Cuentas del proyecto

| Cuenta | Account ID | Perfil `~/.aws/config` | Rol disponible |
|--------|-----------|----------------------|----------------|
| DEV (UDABOL) | `245650696072` | `fdac-dev` | `AdministratorAccess` |
| QA (UDABOL) | `493735739951` | `fdac-qa` | `AdministratorAccess` |
| CloudManagement | `293080376762` | `fdac-cloudadmin` | `AdministratorAccess` |

**SSO Start URL DEV/QA:** `https://d-90660851f1.awsapps.com/start`

---

## Autenticación rápida

```bash
# Iniciar sesión SSO (abre el browser)
aws sso login --profile fdac-dev

# Verificar identidad
aws sts get-caller-identity --profile fdac-dev

# Usar el perfil en todos los comandos siguientes
export AWS_PROFILE=fdac-dev
aws cloudformation describe-stacks

# Al terminar, limpiar variable de entorno
unset AWS_PROFILE
```

> **Importante:** No dejar `AWS_PROFILE` seteado en la sesión. Puede causar que todos los comandos apunten a la cuenta incorrecta y generar errores difíciles de diagnosticar.

---

## Configuración en `~/.aws/config`

Los perfiles del proyecto (extracto relevante):

```ini
[profile fdac-dev]
sso_session = fdac-dev
sso_account_id = 245650696072
sso_role_name = AdministratorAccess
region = us-east-1
output = json

[sso-session fdac-dev]
sso_start_url = https://d-90660851f1.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile fdac-qa]
sso_session = fdac-qa
sso_account_id = 493735739951
sso_role_name = AdministratorAccess
region = us-east-1
output = json

[sso-session fdac-qa]
sso_start_url = https://d-90660851f1.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

> **Nota histórica:** En versiones anteriores del config, `sso_role_name` estaba seteado como `DevOpsReadOnly`. Este rol no existe — el único disponible es `AdministratorAccess`. Si los comandos AWS fallan con "No role" o "Access Denied", verificar que `sso_role_name = AdministratorAccess` esté correcto.

---

## Cómo funciona el token SSO

Cuando ejecutás `aws sso login`, el CLI:

1. Abre el browser con la URL del SSO portal
2. Pedís autenticación (usuario + MFA si aplica)
3. El CLI recibe un **access token** efímero
4. El token se guarda en `~/.aws/sso/cache/` como archivo JSON
5. El token tiene una **expiración** (generalmente 8-12 horas)
6. Cuando el token expira, los comandos AWS fallan con "Session token not found or invalid"

### Ver cuándo expira el token

```bash
# En Windows PowerShell
Get-Content "$env:USERPROFILE\.aws\sso\cache\*.json" | ConvertFrom-Json | Select-Object expiresAt

# En bash/Git Bash
cat ~/.aws/sso/cache/*.json | python3 -c "import sys,json; [print(json.load(open(f))['expiresAt']) for f in sys.stdin.read().strip().split('\n') if f.endswith('.json')]" 2>/dev/null
```

### Renovar sesión expirada

```bash
aws sso login --profile fdac-dev
# Si también necesitás QA (sesión independiente):
aws sso login --profile fdac-qa
```

> Las sesiones de `fdac-dev` y `fdac-qa` son **independientes** aunque usen el mismo SSO start URL. Si estás trabajando en ambas cuentas en la misma sesión de trabajo, iniciar ambas sesiones antes de ejecutar comandos de larga duración.

---

## Obtener credenciales temporales (STS)

Útil para scripts que necesitan credenciales explícitas (acceso directo a la API sin el CLI wrapper de SSO).

```bash
# Obtener el access token del cache
ACCESS_TOKEN=$(cat ~/.aws/sso/cache/*.json | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line)
        if 'accessToken' in d:
            print(d['accessToken'])
            break
    except: pass
")

# Obtener credenciales STS para la cuenta DEV
aws sso get-role-credentials \
  --account-id 245650696072 \
  --role-name AdministratorAccess \
  --access-token "$ACCESS_TOKEN" \
  --region us-east-1
```

Esto devuelve `accessKeyId`, `secretAccessKey` y `sessionToken` que se pueden usar como variables de entorno:

```bash
export AWS_ACCESS_KEY_ID=<valor>
export AWS_SECRET_ACCESS_KEY=<valor>
export AWS_SESSION_TOKEN=<valor>
export AWS_DEFAULT_REGION=us-east-1

# Verificar
aws sts get-caller-identity
```

---

## Trabajar con múltiples cuentas en paralelo

Cuando necesitás operar en DEV y QA en la misma sesión, mantener variables de entorno separadas es complejo. La alternativa más segura es usar el flag `--profile` en cada comando:

```bash
# DEV
aws cloudformation describe-stacks --profile fdac-dev --region us-east-1

# QA
aws cloudformation describe-stacks --profile fdac-qa --region us-east-1
```

O usar subshells:
```bash
# DEV en una subshell
(export AWS_PROFILE=fdac-dev; aws cloudformation list-stacks)

# QA en otra
(export AWS_PROFILE=fdac-qa; aws cloudformation list-stacks)
```

---

## Troubleshooting

### Error: "Session token not found or invalid"

El token SSO expiró. Solución:
```bash
aws sso login --profile fdac-dev
```

### Error: "No role found for account/role"

El `sso_role_name` en `~/.aws/config` no existe en la cuenta. Verificar los roles disponibles:
```bash
# Listar roles disponibles en la cuenta
aws sso list-account-roles \
  --account-id 245650696072 \
  --access-token $(cat ~/.aws/sso/cache/*.json | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
```

El único rol disponible en DEV y QA es `AdministratorAccess`.

### Error: "An error occurred (ExpiredTokenException)"

Diferente a "Session token not found". Significa que las credenciales STS derivadas del SSO ya expiraron. Las credenciales STS duran 1 hora por defecto. Solución:
```bash
# Re-iniciar sesión SSO y re-obtener credenciales
aws sso login --profile fdac-dev
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### `AWS_PROFILE` seteado en el entorno causa fallos inesperados

Si hay una variable `AWS_PROFILE` seteada globalmente (ej: en `.bashrc` o heredada de otro proceso), todos los comandos AWS irán al perfil incorrecto. Verificar y limpiar:

```bash
echo $AWS_PROFILE
unset AWS_PROFILE
```

En Windows PowerShell:
```powershell
$env:AWS_PROFILE
Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
```

---

## Roles IAM en GitHub Actions (OIDC)

Los workflows de CI/CD **no usan SSO**. Usan OIDC para asumir roles IAM directamente.

| Variable GitHub | ARN del rol | Cuenta | Restricción |
|----------------|-------------|--------|-------------|
| `vars.AWS_ROLE_DEV` | `arn:aws:iam::245650696072:role/proy-app-gha-role-development` | DEV | Cualquier branch |
| `vars.AWS_ROLE_QA` | `arn:aws:iam::493735739951:role/proy-app-gha-role-qa` | QA | Solo branch `main` |

Los roles tienen `PowerUserAccess` y son asumidos automáticamente por los workflows sin intervención humana.

Para más detalles sobre la configuración OIDC: ver [SOW/docs/github-oidc-setup.md](../SOW/docs/github-oidc-setup.md).
