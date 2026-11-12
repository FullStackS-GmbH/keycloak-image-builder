#!/usr/bin/env bash
# Prepares the isolated build context for the GitHub Action (action.yml).
# Inputs arrive as KEYCLOAK_* environment variables, never through expression
# interpolation, so caller-controlled values cannot inject shell code.
# Writes step outputs to $GITHUB_OUTPUT and the resolved parameters to
# $GITHUB_STEP_SUMMARY.
set -euo pipefail
action_dir=$(cd "$(dirname "$0")/.." && pwd -P)
workspace=$(cd "${GITHUB_WORKSPACE:?}" && pwd -P)

fail() {
  echo "::error::$1" >&2
  exit 1
}

base_image=${KEYCLOAK_BASE_IMAGE:-}
[[ -n $base_image ]] || base_image=$(sed -n 's/^ARG KEYCLOAK_IMAGE=//p' "$action_dir/Dockerfile")
image_name=$(printf '%s' "${KEYCLOAK_IMAGE_NAME:?}" | tr '[:upper:]' '[:lower:]')
image_tag=${KEYCLOAK_IMAGE_TAG:?}
platforms=${KEYCLOAK_PLATFORMS:?}
db=${KEYCLOAK_DB:?}
health=${KEYCLOAK_HEALTH:?}
metrics=${KEYCLOAK_METRICS:?}
features=${KEYCLOAK_FEATURES:-}
features_disabled=${KEYCLOAK_FEATURES_DISABLED:-}
themes_path=${KEYCLOAK_THEMES_PATH:-}
providers_path=${KEYCLOAK_PROVIDERS_PATH:-}

[[ $base_image =~ ^[a-z0-9][a-z0-9._:/@-]+$ ]] || fail 'Invalid keycloak-image'
[[ $platforms =~ ^linux/(amd64|arm64)(,linux/(amd64|arm64))*$ ]] || fail 'Invalid platforms'
[[ $image_tag =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail 'Invalid image tag'
[[ $image_name =~ ^[a-z0-9][a-z0-9._:/-]+$ ]] || fail 'Invalid image name'
[[ $db =~ ^(postgres|mysql|mariadb|oracle|mssql|dev-file|dev-mem)$ ]] || fail 'Invalid db'
[[ $health =~ ^(true|false)$ ]] || fail 'health-enabled must be true or false'
[[ $metrics =~ ^(true|false)$ ]] || fail 'metrics-enabled must be true or false'
[[ $features =~ ^[a-z0-9:_,-]*$ ]] || fail 'Invalid features'
[[ $features_disabled =~ ^[a-z0-9:_,-]*$ ]] || fail 'Invalid features-disabled'

context=$(mktemp -d "${RUNNER_TEMP:-/tmp}/keycloak-context.XXXXXX")
mkdir -p "$context/themes" "$context/providers"
touch "$context/themes/.gitkeep" "$context/providers/.gitkeep"
cp "$action_dir/Dockerfile" "$context/Dockerfile"

copy_assets() {
  [[ -n $1 ]] || return 0
  case $1 in /*) fail 'Asset paths must be relative to GITHUB_WORKSPACE' ;; esac
  [[ -d "$workspace/$1" ]] || fail "Asset path does not exist: $1"
  local source
  source=$(cd "$workspace/$1" && pwd -P)
  case $source in "$workspace"/*) ;; *) fail 'Asset path must remain inside GITHUB_WORKSPACE' ;; esac
  cp -R "$source/." "$context/$2/"
}
copy_assets "$themes_path" themes
copy_assets "$providers_path" providers

summary=$(printf '%s\n' \
  "Database: $db" \
  "Health: $health" \
  "Metrics: $metrics" \
  "Platforms: $platforms" \
  "Themes: ${themes_path:-none}" \
  "Providers: ${providers_path:-none}" \
  "Features: ${features:-none}" \
  "Disabled features: ${features_disabled:-none}" \
  "Base image: $base_image" \
  "Image: $image_name:$image_tag")
printf '%s\n' "$summary"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  # shellcheck disable=SC2016 # backticks are Markdown, not command substitution
  printf '### Keycloak build parameters\n\n```text\n%s\n```\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi

delimiter="EOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
{
  printf 'context=%s\n' "$context"
  printf 'base-image=%s\n' "$base_image"
  printf 'image=%s:%s\n' "$image_name" "$image_tag"
  printf 'multi-platform=%s\n' "$([[ $platforms == *,* ]] && echo true || echo false)"
  printf 'build-args<<%s\n' "$delimiter"
  printf '%s\n' \
    "KEYCLOAK_IMAGE=$base_image" \
    "KC_DB=$db" \
    "KC_HEALTH_ENABLED=$health" \
    "KC_METRICS_ENABLED=$metrics" \
    "KC_FEATURES=$features" \
    "KC_FEATURES_DISABLED=$features_disabled" \
    "VCS_REF=${GITHUB_SHA:-local}" \
    "IMAGE_VERSION=$image_tag" \
    "SOURCE_URL=${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"
  printf '%s\n' "$delimiter"
} >> "${GITHUB_OUTPUT:?}"
