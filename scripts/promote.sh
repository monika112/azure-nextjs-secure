#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <resource-group> <container-app> <candidate-label> <stable-label>" >&2
  exit 2
fi

az containerapp ingress traffic set \
  --resource-group "$1" \
  --name "$2" \
  --label-weight "$3=100" "$4=0" \
  --output none

echo "Promoted $3 to 100%."
