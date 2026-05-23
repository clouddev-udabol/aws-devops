# Parameters

Esta carpeta contiene los parámetros específicos de cada **(ambiente × stack)**.
La regla de oro: **el código en `cloudformation/` es único; lo que cambia entre ambientes son estos archivos JSON**.

## Estructura

```
parameters/
├── dev/
│   ├── vpc.json
│   └── budgets.json
├── qa/
│   ├── vpc.json
│   └── budgets.json
└── prod/
    ├── vpc.json
    └── budgets.json
```

## Naming convention

`parameters/{env}/{stack}.json` debe coincidir con `cloudformation/modules/{stack}/{stack}.yaml`.

## Cómo se consumen

Estos archivos son leídos por:
1. `scripts/deploy.sh` — usa `--parameters file://parameters/{env}/{stack}.json`
2. Workflows GitHub Actions — `deploy-nonprod.yml` y `deploy-prod.yml`
3. `make plan ENV=dev STACK=vpc` y `make deploy ENV=dev STACK=vpc`

## CIDRs reservados

| Ambiente | VPC CIDR       | Notas |
|---|---|---|
| dev      | `10.10.0.0/16` | Single-AZ, NAT GW único |
| qa       | `10.20.0.0/16` | Single-AZ, NAT GW único |
| prod     | `10.30.0.0/16` | Multi-AZ, alta disponibilidad |

## Reglas

1. **Nunca** commits credenciales o ARNs de Secrets Manager aquí — usar SSM/Secrets Manager y referenciar por nombre.
2. **Nunca** dejar valores hardcodeados de cuenta AWS — esos van en variables de workflow.
3. Cualquier cambio a `parameters/prod/*.json` requiere revisión (ver `CODEOWNERS`).
4. Si un parámetro es opcional, mejor poner default en el template `.yaml` y omitirlo aquí.
