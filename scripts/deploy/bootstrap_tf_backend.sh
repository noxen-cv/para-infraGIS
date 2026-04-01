#!/usr/bin/env bash
set -euo pipefail

# Bootstrap dedicated Azure backend infrastructure for Terraform state.

TFSTATE_RESOURCE_GROUP="${TFSTATE_RESOURCE_GROUP:-tfstate-rg}"
TFSTATE_LOCATION="${TFSTATE_LOCATION:-southeastasia}"
TFSTATE_STORAGE_ACCOUNT="${TFSTATE_STORAGE_ACCOUNT:-tfstateparainfragis}"
TFSTATE_CONTAINER="${TFSTATE_CONTAINER:-tfstate}"
AZ_SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}"
STORAGE_AUTH_MODE="${STORAGE_AUTH_MODE:-login}"
AZURE_STORAGE_KEY="${AZURE_STORAGE_KEY:-}"

log() {
  printf "[%s] %s\n" "$(date +"%Y-%m-%d %H:%M:%S")" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

verify_azure_login() {
  if ! az account show >/dev/null 2>&1; then
    log "Azure CLI is not logged in. Run: az login"
    exit 1
  fi
}

set_subscription_context() {
  local sub

  if [[ -n "$AZ_SUBSCRIPTION_ID" ]]; then
    sub="$AZ_SUBSCRIPTION_ID"
  else
    sub="$(az account show --query id -o tsv)"
  fi

  if [[ -z "$sub" ]]; then
    log "Could not determine Azure subscription id. Set AZ_SUBSCRIPTION_ID and retry."
    exit 1
  fi

  log "Using subscription: $sub"
  az account set --subscription "$sub" --output none
}

validate_storage_account_name() {
  if [[ ! "$TFSTATE_STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
    log "Invalid TFSTATE_STORAGE_ACCOUNT '$TFSTATE_STORAGE_ACCOUNT'."
    log "Storage account name must be 3-24 chars, lowercase letters and numbers only."
    exit 1
  fi
}

ensure_resource_group() {
  if [[ "$(az group exists --name "$TFSTATE_RESOURCE_GROUP" -o tsv)" == "true" ]]; then
    log "Resource group already exists: $TFSTATE_RESOURCE_GROUP"
    return 0
  fi

  log "Creating resource group: $TFSTATE_RESOURCE_GROUP ($TFSTATE_LOCATION)"
  az group create \
    --name "$TFSTATE_RESOURCE_GROUP" \
    --location "$TFSTATE_LOCATION" \
    --output none
}

ensure_storage_account() {
  if az storage account show \
    --resource-group "$TFSTATE_RESOURCE_GROUP" \
    --name "$TFSTATE_STORAGE_ACCOUNT" \
    --output none >/dev/null 2>&1; then
    log "Storage account already exists: $TFSTATE_STORAGE_ACCOUNT"
    return 0
  fi

  log "Creating storage account: $TFSTATE_STORAGE_ACCOUNT"
  az storage account create \
    --resource-group "$TFSTATE_RESOURCE_GROUP" \
    --name "$TFSTATE_STORAGE_ACCOUNT" \
    --location "$TFSTATE_LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    --https-only true \
    --output none
}

resolve_storage_auth_args() {
  if [[ "$STORAGE_AUTH_MODE" == "login" ]]; then
    printf -- "--auth-mode login"
    return 0
  fi

  if [[ "$STORAGE_AUTH_MODE" != "key" ]]; then
    log "Unsupported STORAGE_AUTH_MODE: $STORAGE_AUTH_MODE (use login or key)"
    exit 1
  fi

  if [[ -z "$AZURE_STORAGE_KEY" ]]; then
    AZURE_STORAGE_KEY="$(az storage account keys list \
      --resource-group "$TFSTATE_RESOURCE_GROUP" \
      --account-name "$TFSTATE_STORAGE_ACCOUNT" \
      --query '[0].value' \
      -o tsv)"
  fi

  if [[ -z "$AZURE_STORAGE_KEY" ]]; then
    log "Could not resolve storage account key. Set AZURE_STORAGE_KEY and retry."
    exit 1
  fi

  printf -- "--auth-mode key --account-key %s" "$AZURE_STORAGE_KEY"
}

ensure_container() {
  local auth_args
  local exists

  auth_args="$(resolve_storage_auth_args)"
  # shellcheck disable=SC2086
  exists="$(az storage container exists \
    --name "$TFSTATE_CONTAINER" \
    --account-name "$TFSTATE_STORAGE_ACCOUNT" \
    $auth_args \
    --query exists \
    -o tsv)"

  if [[ "$exists" == "true" ]]; then
    log "Container already exists: $TFSTATE_CONTAINER"
    return 0
  fi

  log "Creating private tfstate container: $TFSTATE_CONTAINER"
  # shellcheck disable=SC2086
  az storage container create \
    --name "$TFSTATE_CONTAINER" \
    --account-name "$TFSTATE_STORAGE_ACCOUNT" \
    --public-access off \
    $auth_args \
    --output none
}

print_backend_init_hint() {
  cat <<EOF

Bootstrap complete.

Use these backend settings with terraform init:
  resource_group_name  = "$TFSTATE_RESOURCE_GROUP"
  storage_account_name = "$TFSTATE_STORAGE_ACCOUNT"
  container_name       = "$TFSTATE_CONTAINER"
  key                  = "<environment>.tfstate"

Example:
  terraform init \
    -backend-config="resource_group_name=$TFSTATE_RESOURCE_GROUP" \
    -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
    -backend-config="container_name=$TFSTATE_CONTAINER" \
    -backend-config="key=dev.tfstate"
EOF
}

main() {
  require_cmd az
  verify_azure_login
  set_subscription_context
  validate_storage_account_name
  ensure_resource_group
  ensure_storage_account
  ensure_container
  print_backend_init_hint
}

main "$@"
