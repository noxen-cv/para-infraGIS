# Azure PMTiles Cloud Provisioning Runbook

This runbook provisions Azure Blob infrastructure, uploads the PMTiles archive, configures CORS for PMTiles range traffic, and verifies endpoint behavior.

## Locked Parameters

- Resource Group: `paraInfraGIS-rg`
- Region: `southeastasia`
- Storage Account: `paragisstorage`
- Container: `maps`
- Local Artifact: `data/pmtiles/philippines-260326.pmtiles`
- Publish Strategy: immutable file name per artifact version

## Prerequisites

1. Azure CLI installed and authenticated.
2. Permission to create resource group, storage account, and blob container.
3. Permission to upload blobs and configure Blob service CORS.
4. PMTiles artifact present locally.

```bash
az login
az account show --output table
ls -lh data/pmtiles/philippines-260326.pmtiles
```

## Fast Path (Recommended)

Use the deployment script that executes all four steps:

```bash
chmod +x scripts/deploy/azure_publish_pmtiles.sh
scripts/deploy/azure_publish_pmtiles.sh all
```

If your CLI has multiple tenants/subscriptions, pin the target explicitly:

```bash
AZ_SUBSCRIPTION_ID="<subscription-id>" scripts/deploy/azure_publish_pmtiles.sh all
```

If blob operations fail with role errors (missing `Storage Blob Data Contributor`), use key mode:

```bash
STORAGE_AUTH_MODE=key scripts/deploy/azure_publish_pmtiles.sh all
```

Optional immutable publish with a custom blob name:

```bash
BLOB_NAME=philippines-260326.pmtiles scripts/deploy/azure_publish_pmtiles.sh all
```

## Step-by-Step Commands (Manual Fallback)

### Step 1: Provision Storage Infrastructure

```bash
az group create \
  --name paraInfraGIS-rg \
  --location southeastasia

az storage account create \
  --resource-group paraInfraGIS-rg \
  --name paragisstorage \
  --location southeastasia \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access true \
  --min-tls-version TLS1_2 \
  --https-only true

az storage container create \
  --name maps \
  --public-access blob \
  --account-name paragisstorage \
  --auth-mode login
```

### Step 2: Upload PMTiles Archive

```bash
az storage blob upload \
  --account-name paragisstorage \
  --container-name maps \
  --name philippines-260326.pmtiles \
  --file data/pmtiles/philippines-260326.pmtiles \
  --overwrite false \
  --auth-mode login
```

Public URL format:

```text
https://paragisstorage.blob.core.windows.net/maps/philippines-260326.pmtiles
```

### Step 3: Configure CORS (Critical)

Clear then apply one deterministic rule:

```bash
az storage cors clear \
  --services b \
  --account-name paragisstorage

az storage cors add \
  --services b \
  --methods GET HEAD OPTIONS \
  --origins '*' \
  --allowed-headers 'Range,Content-Type,Origin,Accept,If-Modified-Since,If-None-Match,Cache-Control,x-ms-*' \
  --exposed-headers 'Content-Range,Accept-Ranges,Content-Length,Content-Type,ETag,Last-Modified' \
  --max-age 3600 \
  --account-name paragisstorage
```

If your storage data-plane access is key-based:

```bash
KEY="$(az storage account keys list --resource-group paraInfraGIS-rg --account-name paragisstorage --query '[0].value' -o tsv)"

az storage cors clear --services b --account-name paragisstorage --account-key "$KEY"

az storage cors add \
  --services b \
  --methods GET HEAD OPTIONS \
  --origins '*' \
  --allowed-headers 'Range,Content-Type,Origin,Accept,If-Modified-Since,If-None-Match,Cache-Control,x-ms-*' \
  --exposed-headers 'Content-Range,Accept-Ranges,Content-Length,Content-Type,ETag,Last-Modified' \
  --max-age 3600 \
  --account-name paragisstorage \
  --account-key "$KEY"
```

Why this matters:

- PMTiles requires byte-range reads.
- If `Range` is not allowed in preflight, map requests fail.
- If `Content-Range` is not exposed, clients cannot interpret partial responses safely.

### Step 4: Verify Cloud Endpoint

Run script verification:

```bash
scripts/deploy/azure_publish_pmtiles.sh verify
```

Or run manual checks:

```bash
URL="https://paragisstorage.blob.core.windows.net/maps/philippines-260326.pmtiles"

curl -i -H "Range: bytes=0-255" "$URL"

curl -i -X OPTIONS "$URL" \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: range"
```

## Success Criteria

The range check must include all of the following:

1. `HTTP/1.1 206 Partial Content`
2. `Content-Range: bytes 0-255/<total-size>`
3. Binary output for the requested byte range

If all three are present, the cloud data layer is ready for styling integration.

## Troubleshooting

### 1) Endpoint returns 200 instead of 206

- Confirm the request includes `Range: bytes=0-255` exactly.
- Confirm blob URL points directly to the `.pmtiles` object.

### 2) Preflight fails or map stays blank

- Recheck CORS rule includes:
  - methods: `GET,HEAD,OPTIONS`
  - allowed headers include `Range`
  - exposed headers include `Content-Range`
- Clear existing CORS rules and reapply the single rule to avoid conflicts.

### 3) Upload denied with authorization error

- Ensure RBAC includes blob data permissions for your principal.
- Confirm CLI session target subscription:

```bash
az account show --output table
```

### 4) Blob not publicly readable

- Confirm account allows public blob access.
- Confirm container access level is `blob`.

## Hand-off

Record the final published endpoint used by mobile clients:

```text
https://paragisstorage.blob.core.windows.net/maps/<published-file>.pmtiles
```

Use this endpoint in the next map styling phase.