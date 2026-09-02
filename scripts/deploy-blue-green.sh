#!/usr/bin/env bash
set -euo pipefail

required=(RESOURCE_GROUP CONTAINER_APP CONTAINER_APP_ENVIRONMENT IMAGE RELEASE_ID)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Required environment variable is missing: $key" >&2
    exit 2
  fi
done

if [[ ! "$RELEASE_ID" =~ ^[a-z0-9-]{1,20}$ ]]; then
  echo "RELEASE_ID must contain 1-20 lowercase letters, numbers, or hyphens." >&2
  exit 2
fi

current_prod_label=$(az containerapp ingress traffic show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --query "[?weight==\`100\`].label | [0]" \
  --output tsv)

if [[ "$current_prod_label" != "blue" && "$current_prod_label" != "green" ]]; then
  echo "Expected exactly one blue/green label at 100% traffic. Finish or roll back the current canary first." >&2
  exit 1
fi

if [[ "$current_prod_label" == "green" ]]; then
  candidate_label="blue"
  stable_label="green"
else
  candidate_label="green"
  stable_label="blue"
fi

revision_name="${CONTAINER_APP}--${RELEASE_ID}"

echo "Stable: $stable_label; candidate: $candidate_label; revision: $revision_name"

az containerapp update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --image "$IMAGE" \
  --revision-suffix "$RELEASE_ID" \
  --set-env-vars "RELEASE_ID=$RELEASE_ID" \
  --output none

az containerapp revision label add \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --revision "$revision_name" \
  --label "$candidate_label" \
  --output none

az containerapp ingress traffic set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP" \
  --label-weight "$stable_label=100" "$candidate_label=0" \
  --output none

domain=$(az containerapp env show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_APP_ENVIRONMENT" \
  --query properties.defaultDomain \
  --output tsv)
candidate_url="https://${CONTAINER_APP}---${candidate_label}.${domain}${SMOKE_PATH:-/}"

echo "Testing candidate at $candidate_url"
for attempt in {1..30}; do
  if curl --fail --silent --show-error --max-time 10 "$candidate_url" >/dev/null; then
    break
  fi
  if [[ "$attempt" -eq 30 ]]; then
    echo "Candidate smoke test failed; production remains on $stable_label." >&2
    exit 1
  fi
  sleep 10
done

if [[ "${CANARY_PERCENT:-0}" != "0" ]]; then
  canary="$CANARY_PERCENT"
  stable=$((100 - canary))
  az containerapp ingress traffic set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --label-weight "$stable_label=$stable" "$candidate_label=$canary" \
    --output none
  echo "Canary enabled: $candidate_label=$canary%, $stable_label=$stable%."
  echo "Promote later with: scripts/promote.sh $RESOURCE_GROUP $CONTAINER_APP $candidate_label $stable_label"
else
  az containerapp ingress traffic set \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP" \
    --label-weight "$stable_label=0" "$candidate_label=100" \
    --output none
  echo "Promoted $candidate_label to 100%. Roll back with: scripts/rollback.sh $RESOURCE_GROUP $CONTAINER_APP $stable_label $candidate_label"
fi
