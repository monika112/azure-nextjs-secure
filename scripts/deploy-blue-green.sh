#!/usr/bin/env bash
set -Eeuo pipefail

# Required:
#   RESOURCE_GROUP
#   CONTAINER_APP
#   IMAGE
#   RELEASE_ID
#
# Optional:
#   CANARY_PERCENT (default: 0)
#   REVISION_WAIT_ATTEMPTS (default: 30)
#   REVISION_WAIT_SECONDS (default: 10)

required=(RESOURCE_GROUP CONTAINER_APP IMAGE RELEASE_ID)

for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "::error::Required environment variable is missing: $key" >&2
    exit 2
  fi
done

if [[ ! "$RELEASE_ID" =~ ^[a-z0-9-]{1,20}$ ]]; then
  echo "::error::RELEASE_ID must contain 1-20 lowercase letters, numbers, or hyphens." >&2
  exit 2
fi

CANARY_PERCENT="${CANARY_PERCENT:-0}"
REVISION_WAIT_ATTEMPTS="${REVISION_WAIT_ATTEMPTS:-30}"
REVISION_WAIT_SECONDS="${REVISION_WAIT_SECONDS:-10}"

if [[ ! "$CANARY_PERCENT" =~ ^[0-9]+$ ]] || (( CANARY_PERCENT < 0 || CANARY_PERCENT > 100 )); then
  echo "::error::CANARY_PERCENT must be an integer from 0 to 100." >&2
  exit 2
fi

az_args=(--only-show-errors)

echo "Reading current production traffic..."
current_prod_label="$(
  az containerapp ingress traffic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --query "[?weight==\`100\`].label | [0]" \
    --output tsv \
    "${az_args[@]}"
)"

if [[ "$current_prod_label" != "blue" && "$current_prod_label" != "green" ]]; then
  echo "::error::Expected blue or green to own 100% traffic, but found '${current_prod_label:-<none>}'." >&2
  echo "Finish or roll back any existing canary before starting a new deployment." >&2
  exit 1
fi

if [[ "$current_prod_label" == "green" ]]; then
  stable_label="green"
  candidate_label="blue"
else
  stable_label="blue"
  candidate_label="green"
fi

revision_name="${CONTAINER_APP}--${RELEASE_ID}"

echo "Stable: $stable_label"
echo "Candidate: $candidate_label"
echo "Revision: $revision_name"
echo "Image: $IMAGE"

echo "Creating/updating candidate revision..."
az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --image "$IMAGE" \
  --revision-suffix "$RELEASE_ID" \
  --set-env-vars "RELEASE_ID=$RELEASE_ID" \
  --output none \
  "${az_args[@]}"

echo "Waiting for revision '$revision_name' to appear..."
revision_found=false
for ((attempt=1; attempt<=REVISION_WAIT_ATTEMPTS; attempt++)); do
  if az containerapp revision show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CONTAINER_APP" \
      --revision "$revision_name" \
      --output none \
      "${az_args[@]}" 2>/dev/null; then
    revision_found=true
    break
  fi
  echo "Revision not visible yet ($attempt/$REVISION_WAIT_ATTEMPTS)."
  sleep "$REVISION_WAIT_SECONDS"
done

if [[ "$revision_found" != "true" ]]; then
  echo "::error::Revision '$revision_name' was not found after waiting." >&2
  exit 1
fi

echo "Moving '$candidate_label' label to candidate revision '$revision_name' non-interactively..."
az containerapp revision label add \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --revision "$revision_name" \
  --label "$candidate_label" \
  --yes \
  --output none \
  "${az_args[@]}"

echo "Keeping production traffic on '$stable_label' while validating candidate..."
az containerapp ingress traffic set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --label-weight "$stable_label=100" "$candidate_label=0" \
  --output none \
  "${az_args[@]}"

echo "Waiting for Azure Container Apps to report the candidate revision healthy..."
candidate_ready=false

for ((attempt=1; attempt<=REVISION_WAIT_ATTEMPTS; attempt++)); do
  revision_state="$(
    az containerapp revision show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CONTAINER_APP" \
      --revision "$revision_name" \
      --query "[properties.provisioningState, properties.runningState, properties.healthState, properties.replicas, properties.provisioningError]" \
      --output tsv \
      "${az_args[@]}" 2>/dev/null || true
  )"

  provisioning_state="$(awk -F '\t' '{print $1}' <<< "$revision_state")"
  running_state="$(awk -F '\t' '{print $2}' <<< "$revision_state")"
  health_state="$(awk -F '\t' '{print $3}' <<< "$revision_state")"
  replicas="$(awk -F '\t' '{print $4}' <<< "$revision_state")"
  provisioning_error="$(awk -F '\t' '{print $5}' <<< "$revision_state")"

  replicas="${replicas:-0}"

  echo "Candidate state ($attempt/$REVISION_WAIT_ATTEMPTS): provisioning=${provisioning_state:-unknown}, running=${running_state:-unknown}, health=${health_state:-unknown}, replicas=$replicas"

  if [[ "$provisioning_state" == "Failed" ]] || \
     [[ "$running_state" == "Failed" ]] || \
     [[ "$running_state" == "Degraded" ]] || \
     [[ "$health_state" == "Unhealthy" ]]; then
    echo "::error::Candidate revision failed validation." >&2
    if [[ -n "$provisioning_error" && "$provisioning_error" != "None" ]]; then
      echo "Provisioning error: $provisioning_error" >&2
    fi

    az containerapp revision show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$CONTAINER_APP" \
      --revision "$revision_name" \
      --output table \
      "${az_args[@]}" || true

    echo "Production remains on '$stable_label' at 100%." >&2
    exit 1
  fi

  # Prefer explicit health. Running + at least one replica is accepted as a
  # fallback because healthState can temporarily be None while ARM catches up.
  if [[ "$provisioning_state" == "Provisioned" ]] && \
     { [[ "$health_state" == "Healthy" ]] || \
       { [[ "$running_state" == "Running" ]] && (( replicas > 0 )); }; }; then
    candidate_ready=true
    break
  fi

  sleep "$REVISION_WAIT_SECONDS"
done

if [[ "$candidate_ready" != "true" ]]; then
  echo "::error::Candidate '$revision_name' did not become healthy in time." >&2
  echo "Production remains on '$stable_label' at 100%." >&2

  az containerapp revision show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --revision "$revision_name" \
    --output table \
    "${az_args[@]}" || true

  exit 1
fi

echo "Candidate revision is healthy."

if (( CANARY_PERCENT > 0 )); then
  stable_percent=$((100 - CANARY_PERCENT))

  echo "Enabling canary: $candidate_label=$CANARY_PERCENT%, $stable_label=$stable_percent%..."
  az containerapp ingress traffic set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --label-weight "$stable_label=$stable_percent" "$candidate_label=$CANARY_PERCENT" \
    --output none \
    "${az_args[@]}"

  echo "Canary enabled."
  echo "Promote with:"
  echo "  ./scripts/promote.sh '$RESOURCE_GROUP' '$CONTAINER_APP' '$candidate_label' '$stable_label'"
else
  echo "Promoting '$candidate_label' to 100%..."
  az containerapp ingress traffic set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --label-weight "$stable_label=0" "$candidate_label=100" \
    --output none \
    "${az_args[@]}"

  echo "Promotion complete."
  echo "Rollback with:"
  echo "  ./scripts/rollback.sh '$RESOURCE_GROUP' '$CONTAINER_APP' '$stable_label' '$candidate_label'"
fi

echo "Final traffic:"
az containerapp ingress traffic show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --output table \
  "${az_args[@]}"
