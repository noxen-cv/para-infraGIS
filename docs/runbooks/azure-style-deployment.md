# Azure Style Deployment Runbook

This runbook publishes the Phase 3 thematic style for Para and verifies that clients can fetch it as JSON.

## Locked Parameters

- Storage Account: `paragisstorage`
- Container: `maps`
- Canonical Style Source: `src/styles/v1/para-gold.json`
- PMTiles Endpoint Used In Style: `https://paragisstorage.blob.core.windows.net/maps/philippines-260326.pmtiles`

## Theme Requirements Covered

- Deep charcoal background: `#121212`
- Water: `#1a1a1a`
- Gold-forward road hierarchy using class filters (`motorway`, `primary`, `secondary`)
- Minimal map by omission: no `poi`, `place_label`, `housenumber` layers

## Fast Path

```bash
chmod +x scripts/deploy/azure_publish_style.sh
scripts/deploy/azure_publish_style.sh all
```

This does all of the following:

1. Validates local JSON before upload.
2. Uploads immutable versioned blob (`style-vYYYYMMDD.json`).
3. Updates stable alias (`style-latest.json`) unless disabled.
4. Verifies HTTP 200 + `application/json` + valid JSON body.

## Commands

Upload only:

```bash
scripts/deploy/azure_publish_style.sh upload
```

Verify only:

```bash
scripts/deploy/azure_publish_style.sh verify
```

Use key mode if data-plane RBAC is unavailable:

```bash
STORAGE_AUTH_MODE=key scripts/deploy/azure_publish_style.sh all
```

Disable latest alias update (immutable-only release):

```bash
UPDATE_LATEST=false scripts/deploy/azure_publish_style.sh all
```

Pin a specific version date:

```bash
STYLE_DATE=20260331 scripts/deploy/azure_publish_style.sh all
```

## Manual Azure CLI Upload

If you need a direct one-liner:

```bash
az storage blob upload \
  --account-name paragisstorage \
  --container-name maps \
  --name style.json \
  --file src/styles/v1/para-gold.json \
  --content-type "application/json" \
  --auth-mode login
```

## Verification Gate

Browser check (must render raw JSON):

- `https://paragisstorage.blob.core.windows.net/maps/style-latest.json`
- `https://paragisstorage.blob.core.windows.net/maps/style-vYYYYMMDD.json`

Terminal check (must return HTTP 200 and JSON content type):

```bash
curl -I https://paragisstorage.blob.core.windows.net/maps/style-latest.json
curl -I https://paragisstorage.blob.core.windows.net/maps/style-vYYYYMMDD.json
```

If both URLs return HTTP 200 and valid JSON content, Phase 3 is complete.

## Rollback

1. Identify prior known-good versioned blob, for example `style-v20260330.json`.
2. Repoint stable alias by uploading the old local style content to `style-latest.json`.
3. Re-run verify step and client smoke-test.

## Notes

- Keep versioned styles immutable (`--overwrite false`) to preserve release history.
- Keep client integrations on `style-latest.json` for zero-code roll-forward/rollback.
- This phase only covers server-side styling and deployment, not client code integration.