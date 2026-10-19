#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
workspace=$(mktemp -d)
suffix=$(basename "$workspace" | tr '[:upper:]' '[:lower:]')
network="keycloak-component-$suffix"
postgres="keycloak-postgres-$suffix"
server="keycloak-server-$suffix"
variant="fullstacks-keycloak:test-$suffix"
cleanup() {
  docker logs "$server" > "$workspace/server.log" 2>&1 || true
  if [[ ${1:-0} != 0 ]]; then
    [[ ! -f "$workspace/config.txt" ]] || cat "$workspace/config.txt" >&2
    cat "$workspace/server.log" >&2
  fi
  docker rm -f "$server" "$postgres" > /dev/null 2>&1 || true
  docker network rm "$network" > /dev/null 2>&1 || true
  docker image rm "$variant" > /dev/null 2>&1 || true
  rm -rf "$workspace"
}
trap 'cleanup "$?"' EXIT
docker build -t fullstacks-keycloak:local .
mkdir -p "$workspace/context/providers" "$workspace/jar/META-INF"
cp Dockerfile "$workspace/context/"
cp -R tests/fixtures/themes "$workspace/context/themes"
printf 'Manifest-Version: 1.0\n\n' > "$workspace/jar/META-INF/MANIFEST.MF"
(cd "$workspace/jar" && zip -qr "$workspace/context/providers/test-resource.jar" META-INF)
docker build -t "$variant" \
  --build-arg KC_DB=dev-file \
  --build-arg KC_HEALTH_ENABLED=false \
  --build-arg KC_METRICS_ENABLED=false \
  --build-arg KC_FEATURES=scripts \
  --build-arg KC_FEATURES_DISABLED=impersonation "$workspace/context"
docker run --rm -i --entrypoint /bin/sh "$variant" < scripts/check-customization.sh
docker network create "$network" > /dev/null
docker run -d --name "$postgres" --network "$network" --network-alias postgres \
  -e POSTGRES_DB=keycloak -e POSTGRES_USER=keycloak -e POSTGRES_PASSWORD=integration-only \
  postgres:17.7-alpine > /dev/null
docker run -d --name "$server" --network "$network" \
  -p 127.0.0.1::8080 -p 127.0.0.1::9000 \
  -e KC_DB_URL=jdbc:postgresql://postgres:5432/keycloak \
  -e KC_DB_USERNAME=keycloak -e KC_DB_PASSWORD=integration-only \
  -e KC_HTTP_ENABLED=true -e KC_HTTP_MANAGEMENT_SCHEME=http \
  -e KC_HOSTNAME=http://localhost:8080 fullstacks-keycloak:local > /dev/null
export KEYCLOAK_URL="http://$(docker port "$server" 8080/tcp)"
export MANAGEMENT_URL="http://$(docker port "$server" 9000/tcp)"
bash scripts/smoke-test.sh
printf 'Default image startup and customized image configuration/assets passed.\n'
