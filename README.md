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

## Client Implementation

To use this infrastructure in the mobile app, point the MapLibre `styleURL` to:

`https://paragisstorage.blob.core.windows.net/maps/v1/style.json`

No local map data needs to be bundled with the APK/IPA.

Detailed guide: `docs/api/client-integration.md`

--

More details comming soon!