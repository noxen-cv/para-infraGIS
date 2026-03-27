# para-InfraGIS

Standard folder structure template for Azure-hosted GIS infrastructure supporting Para Mobile.

## Scope

This repository template is prepared for:
- Hosting and processing heavy GIS datasets
- Managing `.pmtiles` vector tile artifacts in Azure Blob Storage
- Serving custom map styles through CDN-backed delivery

## Directory Template

```text
.
├── infra/
│   └── terraform/
│       ├── modules/
│       └── environments/
│           ├── dev/
│           ├── staging/
│           └── prod/
├── services/
│   ├── api/
│   ├── tiles-pipeline/
│   └── style-cdn/
├── data/
│   ├── raw/
│   ├── processed/
│   ├── pmtiles/
│   └── qc/
├── scripts/
│   ├── data/
│   ├── deploy/
│   └── ops/
├── docs/
│   ├── architecture/
│   ├── runbooks/
│   └── api/
├── config/
│   └── environments/
├── tests/
│   ├── integration/
│   └── performance/
├── ops/
│   ├── monitoring/
│   ├── backup-restore/
│   └── security/
├── community/
└── .github/
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE/
```

## Community Health Files Included

- `README.md`
- `.gitignore`
- `COMMUNITY.md`
- `LICENSE`
