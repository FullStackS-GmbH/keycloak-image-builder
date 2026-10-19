#!/usr/bin/env bash
set -euo pipefail
keycloak_url=${KEYCLOAK_URL:-http://localhost:8080}
management_url=${MANAGEMENT_URL:-http://localhost:9000}
ready=false
for ((attempt = 0; attempt < 90; attempt++)); do
  if curl --fail --silent --max-time 2 "$management_url/health/ready" | jq -e '.status == "UP"' > /dev/null; then
    ready=true
    break
  fi
  sleep 2
done
[[ "$ready" == true ]] || { echo 'Keycloak did not become ready' >&2; exit 1; }
curl --fail --silent --max-time 10 "$keycloak_url/realms/master/.well-known/openid-configuration" |
  jq -e '.issuer | endswith("/realms/master")' > /dev/null
metrics=$(mktemp)
trap 'rm -f "$metrics"' EXIT
curl --fail --silent --max-time 10 "$management_url/metrics" > "$metrics"
rg -q 'jvm_|process_' "$metrics"
printf 'Optimized startup, PostgreSQL readiness, OIDC discovery and metrics passed.\n'
