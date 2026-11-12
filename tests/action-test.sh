#!/usr/bin/env bash
# Tests the GitHub Action's context preparation without Docker or GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
script=scripts/prepare-github-build.sh
bash -n "$script"

# action.yml must run the script and pin every action by commit SHA.
yq -e '.runs.using == "composite"' action.yml > /dev/null
yq -e '.runs.steps[0].run | test("prepare-github-build\.sh")' action.yml > /dev/null
if yq '.runs.steps[].run // ""' action.yml | rg -q '\$\{\{'; then
  echo 'Expression interpolated into a run script' >&2; exit 1
fi
yq '.runs.steps[].uses // ""' action.yml | while IFS= read -r uses; do
  [[ -z $uses ]] || [[ $uses =~ @[0-9a-f]{40}$ ]] || { echo "Unpinned action: $uses" >&2; exit 1; }
done

workspace=$(mktemp -d)
runner=$(mktemp -d)
trap 'rm -rf "$workspace" "$runner"' EXIT
mkdir -p "$workspace/project/tests" "$workspace/project/jars"
cp -R tests/fixtures "$workspace/project/tests/"
printf 'jar' > "$workspace/project/jars/test-resource.jar"

defaults() {
  export GITHUB_WORKSPACE="$workspace/project" RUNNER_TEMP="$runner"
  export GITHUB_OUTPUT="$workspace/output" GITHUB_STEP_SUMMARY="$workspace/summary"
  export GITHUB_SHA=0123456789 GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=Example/Keycloak
  export KEYCLOAK_BASE_IMAGE='' KEYCLOAK_DB=postgres KEYCLOAK_HEALTH=true KEYCLOAK_METRICS=true
  export KEYCLOAK_FEATURES='' KEYCLOAK_FEATURES_DISABLED=''
  export KEYCLOAK_THEMES_PATH='' KEYCLOAK_PROVIDERS_PATH=''
  export KEYCLOAK_PLATFORMS=linux/amd64
  export KEYCLOAK_IMAGE_NAME=ghcr.io/Example/Keycloak KEYCLOAK_IMAGE_TAG=test-1
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
}
output() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }
build_arg() { rg -x "$1=.*" "$GITHUB_OUTPUT" | head -1; }
# rejects <case> <expected error>: the script must fail with that message.
rejects() {
  if bash "$script" > "$runner/invalid.log" 2>&1; then
    echo "Accepted invalid input: $1" >&2
    exit 1
  fi
  rg -Fq -- "$2" "$runner/invalid.log" || {
    echo "Rejected $1 for the wrong reason:" >&2
    cat "$runner/invalid.log" >&2
    exit 1
  }
}

# Defaults: Dockerfile pin, lowercased name, no assets.
defaults
bash "$script" > "$workspace/log"
pinned=$(sed -n 's/^ARG KEYCLOAK_IMAGE=//p' Dockerfile)
[[ $(output base-image) == "$pinned" ]]
[[ $(output image) == ghcr.io/example/keycloak:test-1 ]]
[[ $(output multi-platform) == false ]]
context=$(output context)
[[ $context == "$RUNNER_TEMP"/* ]]
cmp -s Dockerfile "$context/Dockerfile"
[[ $(find "$context/themes" "$context/providers" -type f ! -name .gitkeep | wc -l) -eq 0 ]]
[[ $(build_arg KEYCLOAK_IMAGE) == "KEYCLOAK_IMAGE=$pinned" ]]
[[ $(build_arg SOURCE_URL) == SOURCE_URL=https://github.com/Example/Keycloak ]]
rg -q '^Base image: ' "$GITHUB_STEP_SUMMARY"
delimiter=$(sed -n 's/^build-args<<//p' "$GITHUB_OUTPUT")
[[ $delimiter =~ ^EOF_[0-9a-f]{16}$ ]]
rg -qx "$delimiter" "$GITHUB_OUTPUT"

# Custom options and assets.
defaults
export KEYCLOAK_BASE_IMAGE=quay.io/keycloak/keycloak:26.8.0 KEYCLOAK_DB=dev-file
export KEYCLOAK_HEALTH=false KEYCLOAK_METRICS=false
export KEYCLOAK_FEATURES=scripts,token-exchange:v2 KEYCLOAK_FEATURES_DISABLED=impersonation
export KEYCLOAK_THEMES_PATH=tests/fixtures/themes KEYCLOAK_PROVIDERS_PATH=jars
export KEYCLOAK_PLATFORMS=linux/amd64,linux/arm64
bash "$script" > "$workspace/log"
context=$(output context)
[[ -f $context/themes/example/login/theme.properties ]]
[[ -f $context/providers/test-resource.jar ]]
[[ $(output multi-platform) == true ]]
[[ $(build_arg KC_DB) == KC_DB=dev-file ]]
[[ $(build_arg KC_FEATURES) == KC_FEATURES=scripts,token-exchange:v2 ]]
[[ $(build_arg KC_FEATURES_DISABLED) == KC_FEATURES_DISABLED=impersonation ]]
[[ $(build_arg KC_HEALTH_ENABLED) == KC_HEALTH_ENABLED=false ]]
[[ $(build_arg KEYCLOAK_IMAGE) == KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.8.0 ]]
rg -qx 'Providers: jars' "$workspace/log"

# Input validation.
defaults; export KEYCLOAK_IMAGE_TAG='bad,tag'; rejects 'image tag' 'Invalid image tag'
defaults; export KEYCLOAK_PLATFORMS=linux/s390x; rejects platforms 'Invalid platforms'
defaults; export KEYCLOAK_DB=sqlite; rejects db 'Invalid db'
defaults; export KEYCLOAK_HEALTH=yes; rejects health 'health-enabled must be'
defaults; export KEYCLOAK_FEATURES=$'scripts\nKC_DB=dev-mem'; rejects 'newline in features' 'Invalid features'
defaults
# shellcheck disable=SC2016 # the literal $(id) is the injection attempt under test
export KEYCLOAK_BASE_IMAGE='quay.io/keycloak/keycloak:26 $(id)'
rejects 'base image' 'Invalid keycloak-image'
defaults; export KEYCLOAK_THEMES_PATH=../; rejects 'path outside workspace' 'must remain inside'
defaults; export KEYCLOAK_THEMES_PATH=/etc; rejects 'absolute path' 'must be relative'
defaults; export KEYCLOAK_PROVIDERS_PATH=missing; rejects 'missing path' 'does not exist'
ln -s "$workspace" "$workspace/project/escape"
defaults; export KEYCLOAK_THEMES_PATH=escape; rejects 'symlink outside workspace' 'must remain inside'

printf 'GitHub Action context, build arguments and input validation passed.\n'
