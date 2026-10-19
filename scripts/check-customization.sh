#!/bin/sh
set -eu
config=$(mktemp)
trap 'rm -f "$config"' EXIT
/opt/keycloak/bin/kc.sh show-config > "$config"
cat "$config"
grep -Eq 'kc.db =[[:space:]]+dev-file' "$config"
grep -Eq 'kc.features =[[:space:]]+scripts' "$config"
grep -Eq 'kc.features-disabled =[[:space:]]+impersonation' "$config"
grep -Eq 'kc.health-enabled =[[:space:]]+false' "$config"
grep -Eq 'kc.metrics-enabled =[[:space:]]+false' "$config"
test -f /opt/keycloak/themes/example/login/theme.properties
test "$(stat -c %Y /opt/keycloak/providers/test-resource.jar)" = 1743465600
