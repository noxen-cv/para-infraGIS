# para-InfraGIS

Azure-hosted GIS infrastructure supporting Para Mobile.

## Scope

- Hosting and processing heavy GIS datasets
- Managing `.pmtiles` vector tile artifacts in Azure Blob Storage
- Serving custom map styles through CDN-backed delivery

## Phase 3 Thematic Styling

- Canonical style source: `src/styles/v1/para-gold.json`
- Deployment script: `scripts/deploy/azure_publish_style.sh`
- Runbook: `docs/runbooks/azure-style-deployment.md`

Quick start:

```bash
chmod +x scripts/deploy/azure_publish_style.sh
scripts/deploy/azure_publish_style.sh all
```

--

More details comming soon!