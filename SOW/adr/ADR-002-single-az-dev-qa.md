# ADR-002 — Single-AZ en ambientes DEV y QA

| Campo | Valor |
|---|---|
| **Estado** | Aceptada |
| **Fecha** | 2026-05-06 |
| **Autor** | Ayrton Irusta — `ayrton.irusta@gmail.com` |
| **Proyecto** | IAAPP-app · UDABOL |
| **SOW** | SOW-001 |
| **Ámbito** | Cuentas Development (`245650696072`) y Quality (`493735739951`) |
| **Region** | `us-east-1` · AZ única: `us-east-1a` |
| **Decisores** | Cloud Architect (Owner) — pendiente ratificación del Coordinador |
| **Sustituye / actualiza** | Resumen ADR-002 en `SOW/contexto-dev-qa.md` §2 |
| **Relacionadas** | ADR-001 (sin NAT Gateway) · ADR-003 (3 capas, sin peering/TGW) · ADR-004 (OIDC CI/CD) |

---

## 1. Contexto

UDABOL inicia su plataforma cloud bajo el SOW-001 con un presupuesto explícito de **USD 100/mes por cuenta** para los ambientes no productivos (Dev y QA), monitoreado por AWS Budgets con tres alertas (50 %, 80 %, 100 %).

Los ambientes Dev y QA son entornos de **desarrollo iterativo y validación funcional**, no productivos. No prestan servicio a usuarios finales, no tienen SLA, no mueven datos sensibles (`DataClassification: internal`) y se apagan/reciclan con frecuencia. La pérdida total de cualquiera de los dos por un incidente de zona implica únicamente **pérdida de tiempo del equipo (3 personas)** durante el redeploy desde IaC, no impacto a negocio.

La práctica recomendada de AWS Well-Architected (Pilar de Confiabilidad) sugiere desplegar en al menos 2 AZ. Sin embargo, esa recomendación apunta principalmente a cargas con SLA y a la disponibilidad continua del plano de datos, criterios que **no aplican a Dev/QA** en este SOW.

El driver fuerza de esta decisión es **costo operativo**: con USD 100/mes por cuenta y los componentes ya comprometidos (VPC Endpoints Interface en SSM, Logs, ECR.api, ECR.dkr), duplicar la huella en una segunda AZ erosiona >40 % del presupuesto sin aportar valor de disponibilidad real al ciclo de desarrollo.

### Restricciones que enmarcan la decisión

- Presupuesto duro: USD 100/mes por cuenta no productiva.
- ADR-001 ya elimina NAT Gateway (≈ USD 32/mes/AZ + tráfico).
- ADR-003 aísla cada VPC: no hay TGW ni peering que exija simetría multi-AZ.
- IaC en CloudFormation puro: redeploy reproducible end-to-end < 30 min.
- Equipo de 3 personas — operación lean, sin guardia 24/7 en Dev/QA.

---

## 2. Decisión

**Todas las subredes y recursos zonales de DEV y QA se despliegan en una única AZ: `us-east-1a`.**

Esto aplica a:

| Recurso | Comportamiento single-AZ |
|---|---|
| Subnets (Public, App, Data) | Una por capa, en `us-east-1a` |
| VPC Endpoints Interface (SSM, SSMMessages, EC2Messages, Logs, ECR.api, ECR.dkr) | ENI única en `us-east-1a` |
| RDS / Aurora (cuando aplique) | `MultiAZ: false` en Dev/QA |
| ALB / NLB (cuando aplique) | Asociado a una sola subnet pública |
| EC2 / ECS / EKS workers (cuando aplique) | Lanzados solo en `us-east-1a` |
| EBS volumes | Creados en `us-east-1a` (zonal por naturaleza) |

**Recursos NO afectados** (siguen siendo regionales o globales, sin cambio):
- VPC, IGW, Route Tables, NACLs, Security Groups (regionales).
- VPC Endpoints Gateway de S3 y DynamoDB (regionales, sin costo).
- IAM, Budgets, CloudFormation, CloudTrail, Config (globales/regionales).
- VPC Flow Logs → CloudWatch Logs (servicio regional).

### Excepciones explícitas

- **Producción (cuando se active)** se despliega obligatoriamente Multi-AZ. Los templates CloudFormation parametrizan el número de AZ: `AzCount: 1` en Dev/QA, `AzCount: 2` (mínimo) en Prod. Esta ADR **no aplica** al ambiente Prod.
- Cualquier prueba de carga/HA que requiera multi-AZ se ejecuta en un stack temporal con sufijo `-haprobe`, fuera de los stacks base, y se elimina al término de la prueba.

---

## 3. Análisis de costo (justificación cuantitativa)

Cifras estimadas mensuales en `us-east-1`, precios on-demand 2026 redondeados. Asumen actividad ligera de desarrollo.

### 3.1 Costo del modelo elegido (single-AZ por cuenta)

| Componente | Cantidad | USD/mes |
|---|---|---|
| VPC + IGW + Route Tables + NACLs + SGs | 1 set | 0 |
| VPC Endpoint Gateway S3 | 1 | 0 |
| VPC Endpoint Gateway DynamoDB | 1 | 0 |
| VPC Endpoint Interface SSM | 1 ENI | 7.30 |
| VPC Endpoint Interface SSMMessages | 1 ENI | 7.30 |
| VPC Endpoint Interface EC2Messages | 1 ENI | 7.30 |
| VPC Endpoint Interface Logs | 1 ENI | 7.30 |
| VPC Endpoint Interface ECR.api | 1 ENI | 7.30 |
| VPC Endpoint Interface ECR.dkr | 1 ENI | 7.30 |
| VPC Flow Logs (retención 14 días, tráfico bajo) | — | ~3.00 |
| Tráfico inter-AZ | 0 | 0 |
| **Subtotal infraestructura base/mes** | | **~46.80** |
| Margen para EC2/RDS/ALB de pruebas | | ~53.20 |
| **Total objetivo** | | **≤ 100.00** |

### 3.2 Costo del modelo descartado (2 AZ por cuenta)

| Componente adicional al pasar a 2 AZ | Cantidad | USD/mes |
|---|---|---|
| Segunda ENI por cada Endpoint Interface (×6) | 6 ENIs adicionales | +43.80 |
| Tráfico inter-AZ (estimado conservador, 50 GB/mes) | 50 GB × USD 0.01 × 2 sentidos | +1.00 |
| Si se habilita NAT GW (no es el caso, ver ADR-001) | 2 NAT GW | (+64.00) |
| Si RDS Multi-AZ (no es el caso en Dev/QA) | factor ×2 | (variable) |
| **Sobrecosto neto multi-AZ (sin NAT, sin RDS)** | | **+44.80** |

**Conclusión cuantitativa:** Pasar Dev y QA a 2 AZ añade ~USD 45/mes por cuenta, ~USD 90/mes en total para el SOW. Esto representa el **45 % del presupuesto combinado** consumido en redundancia que no aporta valor en ambientes no productivos. La única alternativa viable bajo el límite de USD 100 sería sacrificar VPC Endpoints e introducir NAT Gateway o tráfico por Internet — peor en costo, peor en seguridad y contradice ADR-001.

### 3.3 Costo de la "no decisión" (impacto si la AZ falla)

- Probabilidad de degradación severa de una AZ en `us-east-1`: histórico < 1 evento/año con duración > 1 h.
- Impacto: 3 ingenieros bloqueados durante el incidente + redeploy en otra AZ vía CloudFormation parametrizado (`AzCount: 1`, `PrimaryAz: us-east-1b`) en < 30 min.
- Costo esperado anual: 3 personas × 2 h × USD ~25/h ≈ **USD 150/año**, materialmente menor que USD 90 × 12 = USD 1 080/año del modelo multi-AZ.

---

## 4. Alternativas consideradas

| Alternativa | Costo/mes (2 cuentas) | Disponibilidad | Decisión |
|---|---|---|---|
| **A. Single-AZ Dev/QA, Multi-AZ Prod** *(elegida)* | ~93 | AZ-única en Dev/QA, Multi-AZ en Prod | ✅ Acepta |
| B. Multi-AZ uniforme en todos los ambientes | ~183 + tráfico | Multi-AZ en todos | ❌ Excede presupuesto, sin valor en no-prod |
| C. Single-AZ con NAT en lugar de Endpoints | ~74 + tráfico | AZ-única + Internet egress | ❌ Contradice ADR-001, peor seguridad |
| D. Compartir una VPC central entre Dev y QA | ~50 | AZ-única, mezcla de cuentas | ❌ Rompe aislamiento por cuenta (ADR-003) |
| E. Spot AZ rotativo (`us-east-1a` lunes, `us-east-1b` martes…) | ~46 | AZ-única, rotada por cron | ❌ Complejidad operativa alta para un equipo de 3 |

---

## 5. Consecuencias

### Positivas

- Costo de infra base por cuenta ≤ USD 47/mes → margen real ≥ USD 53/mes para EC2/RDS/ALB de pruebas dentro del presupuesto.
- Templates CloudFormation más simples: un único bloque de subnets por capa, sin loop por AZ en Dev/QA.
- Tiempo de despliegue de la VPC base reducido (~3 min vs ~6 min en multi-AZ).
- Cero costo de tráfico inter-AZ por diseño.
- Coherencia con ADR-001 (sin NAT) y ADR-003 (VPC isla).

### Negativas / Aceptadas

- **Sin alta disponibilidad zonal en Dev/QA.** Una falla de `us-east-1a` deja ambos ambientes inoperativos hasta el redeploy.
- RDS/Aurora en Dev/QA serán Single-AZ → snapshots manuales/automáticos como única estrategia de recuperación.
- ALB/NLB en Dev/QA (cuando se introduzcan) requerirán al menos 2 subnets por requerimiento del servicio: este es el único caso donde se permitirá una segunda subnet pública mínima en `us-east-1b` **sin recursos asociados** (subnet "vacía") como excepción técnica.
- Tests de comportamiento HA del software no pueden ejecutarse en Dev/QA con la infra base — requieren stack `-haprobe` temporal.

---

## 6. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| Falla parcial o total de `us-east-1a` | Baja | Bloqueo de Dev/QA | Templates parametrizan `PrimaryAz`. Pivot a `us-east-1b` por redeploy < 30 min. |
| Equipo se acostumbra al patrón single-AZ y lo replica en Prod | Media | Alto si llega a Prod | Templates Prod imponen `AzCount >= 2` por validación `cfn-guard` / `checkov`. CI bloquea merge a `release/prod-*` si Prod queda single-AZ. |
| Datos relevantes en RDS Dev/QA se pierden por falla zonal | Media | Bajo (no son datos productivos) | Snapshots automáticos diarios, retención 7 días, en S3 (regional). Cualquier dato productivo que aparezca en Dev/QA es violación de política y se trata por separado. |
| ALB exige multi-subnet y se interpreta como contradicción | Alta | Nulo | Documentado: subnet pública secundaria en `us-east-1b` queda vacía y solo cumple el requisito sintáctico del servicio. |
| Costo real supera estimado (Endpoints Interface por dataprocesado) | Media | Bajo | AWS Budgets a 50 / 80 / 100 % ya configurado en SOW E4. Alerta vía SNS al Owner. Revisión mensual del cost explorer. |

---

## 7. Implementación

### En el template CloudFormation `iaapp-vpc-{env}`

```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues: [development, qa, production]
  AzCount:
    Type: Number
    AllowedValues: [1, 2, 3]
    Default: 1   # Override a 2 mínimo en Prod via stack parameter
  PrimaryAz:
    Type: String
    Default: us-east-1a

Conditions:
  IsMultiAz: !Not [!Equals [!Ref AzCount, 1]]
  IsProd:    !Equals [!Ref Environment, production]

Rules:
  ProdMustBeMultiAz:
    RuleCondition: !Equals [!Ref Environment, production]
    Assertions:
      - Assert: !Not [!Equals [!Ref AzCount, 1]]
        AssertDescription: "Producción requiere AzCount >= 2 (ADR-002 §5)."
```

### En CI (validación)

- `cfn-lint` con regla custom: `Environment=production` → `AzCount >= 2`.
- `checkov` regla `CKV_AWS_157` (RDS Multi-AZ): suprimida en Dev/QA con justificación inline `# checkov:skip=CKV_AWS_157: ADR-002`.

### En tags

Recursos zonales llevan adicionalmente:

```yaml
AvailabilityZone: us-east-1a
ResiliencyTier:   single-az-dev-qa     # documentado en references/tags-catalog
```

---

## 8. Trigger de revisión

Esta ADR se reabre y reevalúa si ocurre **cualquiera** de estos eventos:

1. El presupuesto Dev/QA aumenta a ≥ USD 200/mes por cuenta.
2. Se firma SLA interno con UDABOL para Dev o QA (cualquier % de uptime comprometido).
3. Una falla de AZ provoca pérdida de productividad acumulada > 8 h en un trimestre.
4. AWS publica precios o modelos que reduzcan el delta multi-AZ a < USD 15/mes por cuenta.
5. Se introduce en Dev/QA un workload con `DataClassification != internal`.
6. El equipo crece a > 8 personas y la coordinación de redeploy zonal deja de ser viable.

Revisión periódica obligatoria: una vez al año (próxima: 2027-05-06) o al inicio de cada SOW de plataforma, lo que ocurra antes.

---

## 9. Referencias

- SOW-001 — `SOW/contexto-dev-qa.md` §2
- ADR-001 — Sin NAT Gateway en Dev/QA
- ADR-003 — Tres capas, sin peering ni TGW
- AWS Well-Architected Framework — Reliability Pillar (REL10-BP01: Deploy the workload to multiple locations)
- AWS Pricing — VPC Endpoints, Data Transfer (consultado 2026-05-06)
- `references/tags-catalog.md` — definición del tag `ResiliencyTier`
