<div align="center">

# para-InfraGIS

**Cloud GIS Infrastructure for Para Mobile**

[![Azure Blob Storage](https://img.shields.io/badge/Azure-Blob_Storage-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white)](#)
[![PMTiles](https://img.shields.io/badge/PMTiles-Vector_Tiles-2E7D32?style=for-the-badge)](#)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](#)
[![MapLibre](https://img.shields.io/badge/MapLibre-Style_Consumer-111827?style=for-the-badge)](#)

Managed hosting, deployment, and delivery of style and PMTiles artifacts for Para clients.

</div>

---

## Overview

`para-InfraGIS` is the infrastructure repository for serving production map assets used by Para Mobile.

It handles:

- PMTiles artifact publishing to Azure Blob Storage
- Style JSON versioning and `style-latest.json` alias updates
- Deployment runbooks and CI/CD integration for repeatable releases
- Terraform-first infrastructure lifecycle for recoverability and drift control

## Repository Scope

- GIS data pipeline artifacts and outputs
- Deployment scripts under `scripts/deploy/`
- Infrastructure runbooks under `docs/runbooks/`
- Client consumption contract under `docs/api/client-integration.md`

## Style Deployment (Phase A)

Canonical style source:

- `src/styles/v1/para-gold.json`

Deployment script:

- `scripts/deploy/azure_publish_style.sh`

Runbook:

- `docs/runbooks/azure-style-deployment.md`

Quick start:

```bash
chmod +x scripts/deploy/azure_publish_style.sh
scripts/deploy/azure_publish_style.sh all
```

## Client Integration

Canonical client guide:

- `docs/api/client-integration.md`

Style URL for mobile clients:

```text
https://paragisstorage.blob.core.windows.net/maps/style-latest.json
```

MapLibre clients should point `styleURL` to the endpoint above.

### Important Requirement: Custom Development Build

If you are integrating this map stack in React Native / Expo, you must use a **custom development build** (or production build) to continue seeing the map.

- Expo Go is not sufficient for native map/plugin combinations used in production map stacks.
- If you stay on Expo Go, the map may fail to render or render inconsistently even when style and PMTiles endpoints are healthy.
- Build and run a custom dev client before validating map rendering.

## Verification Checklist

Before client rollout:

1. Confirm style endpoint returns valid JSON.
2. Confirm PMTiles endpoint supports byte-range requests (`206 Partial Content`).
3. Confirm CORS is configured for range headers.
4. Confirm map renders on a custom dev build.

## Operational References

- `docs/runbooks/azure-style-deployment.md`
- `docs/runbooks/azure-pmtiles-cloud-provisioning.md`
- `scripts/deploy/bootstrap_tf_backend.sh`

## Open Source Contribution

If you want to contribute to this repository as an open source contributor, follow the contribution workflow in:

- `CONTRIBUTING.md`

This includes issue-first contribution flow, template usage, and optional CI style deployment automation setup.

---

Infrastructure and integration details are still actively evolving.