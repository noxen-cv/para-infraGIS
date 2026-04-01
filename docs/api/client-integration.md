# Client Integration Guide

This guide explains how to consume the deployed Para InfraGIS map stack from a mobile client.

## Locked Parameters

- Canonical Style URL: `https://paragisstorage.blob.core.windows.net/maps/v1/style.json`
- Map Renderer: MapLibre

## Client Implementation

Set your MapLibre `styleURL` to:

`https://paragisstorage.blob.core.windows.net/maps/v1/style.json`

No local map data needs to be bundled with the APK/IPA.

## Why No Local Bundle Is Needed

- The style JSON is hosted in Azure Blob Storage.
- The style references cloud-hosted PMTiles endpoints.
- Clients stream map data over HTTPS at runtime.

## Preconditions

Before client rollout, confirm the infrastructure checks in these runbooks are complete:

- `docs/runbooks/azure-style-deployment.md`
- `docs/runbooks/azure-pmtiles-cloud-provisioning.md`

The PMTiles provisioning runbook includes the required CORS and byte-range validation needed for runtime map tile access.

## Verification

1. Open the style URL in a browser and confirm JSON is returned.
2. Launch the mobile app and confirm tiles render without shipping local map assets.
3. If the map is blank, validate PMTiles endpoint CORS and range support using the PMTiles runbook.

## Scope Note

This document covers client consumption of already-deployed infrastructure only. Deployment, rollback, and storage operations stay in the runbooks.
