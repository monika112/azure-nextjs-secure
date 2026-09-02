#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <resource-group> <container-apps-environment>" >&2
  exit 2
fi

resource_group="$1"
environment_name="$2"
environment_id=$(az containerapp env show \
  --resource-group "$resource_group" \
  --name "$environment_name" \
  --query id \
  --output tsv)

mapfile -t pending_ids < <(az network private-endpoint-connection list \
  --id "$environment_id" \
  --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" \
  --output tsv)

if [[ ${#pending_ids[@]} -eq 0 ]]; then
  echo "No pending Private Link connections found."
  exit 0
fi

for connection_id in "${pending_ids[@]}"; do
  az network private-endpoint-connection approve \
    --id "$connection_id" \
    --description "Approved for Azure Front Door Premium" \
    --output none
  echo "Approved: $connection_id"
done
