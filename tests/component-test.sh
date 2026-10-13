#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/render-component.sh --check
job='.["$[[ inputs.job_name ]]"]'
[[ $(yq eval-all "select(documentIndex == 1) | $job.variables.KEYCLOAK_DOCKERFILE.expand" templates/build-keycloak/template.yml) == false ]]
dockerfile=$(yq eval-all "select(documentIndex == 1) | $job.variables.KEYCLOAK_DOCKERFILE.value" templates/build-keycloak/template.yml)
[[ "$dockerfile" == "$(cat Dockerfile)" ]]
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/bin" "$workspace/capture"
export CAPTURE_DIR="$workspace/capture"
yq eval-all "select(documentIndex == 1) | $job.script[0]" templates/build-keycloak/template.yml > "$workspace/job.sh"
sh -n "$workspace/job.sh"
cat > "$workspace/bin/buildctl-daemonless.sh" <<'STUB'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$CAPTURE_DIR/args"
for argument in "$@"; do
  case "$argument" in context=*) cp -R "${argument#context=}/." "$CAPTURE_DIR/context";; esac
done
cp "$DOCKER_CONFIG/config.json" "$CAPTURE_DIR/auth.json"
STUB
chmod +x "$workspace/bin/buildctl-daemonless.sh"
export PATH="$workspace/bin:$PATH"
export CI_PROJECT_DIR="$PWD" CI_COMMIT_SHA=0123456789 CI_PROJECT_URL=https://gitlab.com/example/keycloak
export KEYCLOAK_DOCKERFILE="$dockerfile" KEYCLOAK_BASE_IMAGE=quay.io/keycloak/keycloak:26.8.0
export KEYCLOAK_DB=mysql KEYCLOAK_HEALTH=false KEYCLOAK_METRICS=false
export KEYCLOAK_FEATURES=scripts KEYCLOAK_FEATURES_DISABLED=''
export KEYCLOAK_THEMES_PATH=tests/fixtures/themes KEYCLOAK_PROVIDERS_PATH=''
export KEYCLOAK_PLATFORMS=linux/amd64,linux/arm64
export KEYCLOAK_IMAGE_NAME=registry.example.test/team/keycloak KEYCLOAK_IMAGE_TAG=test-1
export KEYCLOAK_REGISTRY=registry.example.test KEYCLOAK_REGISTRY_USER=ci-user
export KEYCLOAK_REGISTRY_PASSWORD='test-password-"-with-special-characters'
unset DOCKER_AUTH_CONFIG
sh "$workspace/job.sh" > "$workspace/job.log" 2>&1
[[ -f "$CAPTURE_DIR/context/themes/example/login/theme.properties" ]]
[[ "$(cat "$CAPTURE_DIR/context/Dockerfile")" == "$dockerfile" ]]
rg -q '^platform=linux/amd64,linux/arm64$' "$CAPTURE_DIR/args"
rg -q '^build-arg:KC_DB=mysql$' "$CAPTURE_DIR/args"
rg -q '^build-arg:KC_FEATURES=scripts$' "$CAPTURE_DIR/args"
rg -q '^build-arg:KC_HEALTH_ENABLED=false$' "$CAPTURE_DIR/args"
[[ $(jq -r '.auths["registry.example.test"].auth' "$CAPTURE_DIR/auth.json" | base64 -d) == "$KEYCLOAK_REGISTRY_USER:$KEYCLOAK_REGISTRY_PASSWORD" ]]
! rg -Fq "$KEYCLOAK_REGISTRY_PASSWORD" "$workspace/job.log"
export KEYCLOAK_IMAGE_TAG='bad,tag'
if sh "$workspace/job.sh" > "$workspace/invalid.log" 2>&1; then
  echo 'Invalid image tag was accepted' >&2; exit 1
fi
export KEYCLOAK_IMAGE_TAG=test-2 KEYCLOAK_THEMES_PATH=../
if sh "$workspace/job.sh" > "$workspace/invalid.log" 2>&1; then
  echo 'Asset path outside the repository was accepted' >&2; exit 1
fi
export KEYCLOAK_THEMES_PATH=''
export DOCKER_AUTH_CONFIG='{"auths":{"registry.example.test":{"auth":"dGVzdDp0ZXN0"}}}'
sh "$workspace/job.sh" > "$workspace/job.log" 2>&1
[[ $(jq -r '.auths["registry.example.test"].auth' "$CAPTURE_DIR/auth.json") == dGVzdDp0ZXN0 ]]
printf 'Component context, build arguments, auth handling and input validation passed.\n'
