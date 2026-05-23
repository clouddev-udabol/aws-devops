# Git Workflow — Multi-Remote (fork + upstream)

> Cómo trabajar con dos remotes: el repo personal (`airusta`) y el institucional (`clouddev-udabol`).

---

## Estructura de remotes

```
origin    → https://github.com/airusta/aws-devops.git
upstream  → https://github.com/clouddev-udabol/aws-devops.git
```

- **`origin`** es el fork personal. Aquí se hace push de las ramas de trabajo.
- **`upstream`** es el repositorio institucional. Es la fuente de verdad. Los PRs se abren hacia él.

```bash
# Verificar que los remotes estén configurados
git remote -v

# Si falta upstream, agregarlo
git remote add upstream https://github.com/clouddev-udabol/aws-devops.git
```

---

## Flujo completo para un cambio

### 1. Sincronizar con upstream antes de empezar

```bash
git fetch upstream
git fetch origin
```

### 2. Crear rama desde upstream/main

```bash
# Siempre partir desde upstream/main, no desde tu origin/main
git checkout -b feature/sow-001-descripcion-corta upstream/main
```

### 3. Hacer los cambios y commitear

```bash
# Editar archivos...

# Agregar solo los archivos relevantes (no git add .)
git add cloudformation/modules/vpc/vpc.yaml
git add parameters/dev/vpc.json

# Commit con Conventional Commits
git commit -m "feat(vpc): agregar tag Entorno via Mappings para SCP compliance"
```

### 4. Lint local antes de push

```bash
# Verificar que no haya errores antes de empujar
pre-commit run --all-files

# O manualmente:
cfn-lint
checkov --directory cloudformation --framework cloudformation --quiet --compact
```

### 5. Push a origin

```bash
git push origin feature/sow-001-descripcion-corta
```

### 6. Abrir PR

El PR se abre **desde** `airusta/aws-devops:feature/sow-001-*` **hacia** `clouddev-udabol/aws-devops:main`.

En GitHub UI: ir a `clouddev-udabol/aws-devops` → "Pull requests" → "New pull request" → "compare across forks".

O si tienes acceso de push directo a upstream (como en este proyecto):
```bash
# Push directo a la rama en upstream y abrir PR desde allí
git push upstream feature/sow-001-descripcion-corta
# Luego abrir PR en GitHub: upstream/feature → upstream/main
```

---

## Sincronizar tu fork con upstream/main

Hacer esto al inicio de cada sesión de trabajo para evitar divergencias.

```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

Si tu `main` local divergió (no debería):
```bash
git fetch upstream
git checkout main
git reset --hard upstream/main   # ⚠️ borra cambios locales en main
git push origin main --force-with-lease
```

---

## Mantener una rama feature actualizada con upstream

Si `upstream/main` avanzó mientras trabajabas en tu rama:

```bash
git fetch upstream
git checkout feature/sow-001-mi-cambio
git rebase upstream/main
# Resolver conflictos si los hay
git push origin feature/sow-001-mi-cambio --force-with-lease
```

---

## Hacer cambios a un PR ya abierto

Una vez abierto el PR, los nuevos commits en la misma rama se suman automáticamente.

```bash
# En la rama del PR
git checkout feature/sow-001-mi-cambio

# Hacer el fix
git add .github/workflows/pr-validate.yml
git commit -m "fix(ci): agregar shopt globstar nullglob en validate step"

# Push a la misma rama (origin o upstream, según donde esté el PR)
git push upstream feature/sow-001-mi-cambio
```

GitHub re-ejecuta los checks automáticamente con el nuevo commit.

---

## Comandos útiles de diagnóstico

```bash
# Ver historial de la rama respecto a upstream/main
git log --oneline upstream/main..HEAD

# Ver diferencias entre tu rama y upstream/main
git diff upstream/main...HEAD

# Ver en qué rama estás y si hay cambios sin commitear
git status

# Ver todos los commits en la rama del PR
git log --oneline feature/sow-001-mi-cambio

# Ver archivos que difieren respecto a upstream/main
git diff --name-only upstream/main
```

---

## Stash — guardar cambios temporalmente

Necesario cuando querés cambiar de rama sin commitear cambios pendientes.

```bash
# Guardar cambios de archivos tracked (no untracked)
git stash push -m "descripcion" -- path/al/archivo otro/archivo

# Guardar TODO (tracked + untracked)
git stash push --include-untracked -m "descripcion"

# Ver lista de stashes
git stash list

# Restaurar el último stash
git stash pop

# Restaurar un stash específico
git stash pop stash@{1}
```

> **Precaución:** `--include-untracked` guarda TODOS los archivos no trackeados en el directorio, incluyendo archivos que no son del repo. Preferir pasar rutas específicas cuando sea posible.

---

## Convenciones de nombres de ramas

```
feature/sow-001-descripcion-corta    ← nueva funcionalidad SOW-001
feature/sow-002-descripcion-corta    ← nueva funcionalidad SOW-002
fix/ci-descripcion-del-fix           ← corrección en CI
fix/cfn-descripcion-del-fix          ← corrección en template CFN
docs/descripcion-del-doc             ← solo documentación
```

---

## Problemas comunes

### "Your branch has diverged"

Ocurre cuando hay commits en upstream/main que tu rama no tiene. Solución:
```bash
git fetch upstream
git rebase upstream/main
```

### "fatal: refusing to merge unrelated histories"

Ocurre al intentar mergear dos repos con historiales distintos (situación del PR inicial). Solución histórica de este proyecto: crear rama nueva desde upstream/main y cherry-pick de los archivos específicos.

### "Permission denied (publickey)"

Revisar que tu SSH key esté cargada o usar HTTPS con token:
```bash
git remote set-url origin https://github.com/airusta/aws-devops.git
```

### Checkout bloqueado por archivos modificados no commiteados

```bash
# Guardar cambios primero
git stash push -m "wip" -- archivos/modificados/

# Cambiar de rama
git checkout feature/otra-rama

# Restaurar cambios cuando vuelvas
git stash pop
```
