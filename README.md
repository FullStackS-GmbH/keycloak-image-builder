# Keycloak image build component

Build and publish an optimized Keycloak image using rootless BuildKit. The image
defaults to Keycloak 26.8.0, PostgreSQL, health endpoints and metrics. Both the
Keycloak and BuildKit defaults are pinned by digest.

## GitLab CI usage

```yaml
include:
  - component: $CI_SERVER_FQDN/fullstacks-gmbh/cicd-components/keycloak/build-keycloak@<commit-sha-or-release-tag>
    inputs:
      image_name: $CI_REGISTRY_IMAGE/keycloak
      image_tag: $CI_COMMIT_SHORT_SHA
      db: postgres
      themes_path: keycloak/themes
      providers_path: keycloak/providers
      features: scripts

stages: [build]
```

The component contains its Dockerfile. The calling repository only needs its
optional themes and provider JARs; it does not need to clone this repository.
Omit the two asset paths when no custom assets are required. A theme directory
must contain theme names as subdirectories (for example `themes/acme/login/`).
Provider JARs are copied before `kc.sh build`; their timestamps are normalized
to prevent provider-change errors during optimized startup.

See [component inputs](templates/build-keycloak/docs.md) for all parameters.
No release tag exists yet; use a real commit SHA after publishing this repository.

## Local image build

```sh
docker build -t keycloak:local .
docker build -t keycloak:custom \
  --build-arg KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.8.0 \
  --build-arg KC_DB=postgres \
  --build-arg KC_FEATURES=scripts \
  --build-arg KC_METRICS_ENABLED=false .
```

Put local assets in `themes/` and `providers/`. The default command is
`start --optimized`. Configure `KC_DB_URL`, database credentials, `KC_HOSTNAME`,
TLS and any bootstrap administrator at runtime. Secrets and realm imports are
not built into the image. Build-time options such as the database vendor and
features require a new image when changed.

## Architectures and runners

`platforms` defaults to `linux/amd64`; use `linux/arm64` on a native ARM runner,
or `linux/amd64,linux/arm64` on a runner with the necessary binfmt/QEMU support.
The component does not install emulators or enable privileged runner mode.
Rootless BuildKit requires a runner that permits user namespaces. The job uses
`--oci-worker-no-process-sandbox`, following the GitLab rootless BuildKit recipe.

## Registry authentication

The default destination is the caller's GitLab Container Registry. For another
registry, supply `registry`, `image_name`, and references to masked CI variables
in `registry_user`/`registry_password`. Alternatively, provide a complete Docker
authentication JSON object through a masked `DOCKER_AUTH_CONFIG` variable and
set both credential inputs to empty strings. Explicit credential inputs take
precedence over inherited Docker authentication configuration.
Credentials are stored in a temporary Docker config directory and removed after
the job. They are never passed as Docker build arguments.

## Development

`Dockerfile` and `ci/component.yml` are the editable sources. Generate the
self-contained component with `bash scripts/render-component.sh`.

```sh
bash tests/component-test.sh  # requires Bash, yq v4, jq and ripgrep
bash tests/integration-test.sh  # requires Docker, Bash, curl, jq, ripgrep and zip
KEYCLOAK_URL=http://localhost:8080 \
MANAGEMENT_URL=http://localhost:9000 bash scripts/smoke-test.sh
```

The component tests check asset isolation, argument forwarding, authentication
and generated-file consistency. The CI pipeline builds the component against
itself and starts the image with PostgreSQL to check readiness, OIDC and metrics.

References: [Keycloak container builds](https://www.keycloak.org/server/containers),
[GitLab components](https://docs.gitlab.com/ci/components/),
[rootless BuildKit in GitLab](https://docs.gitlab.com/ci/docker/using_buildkit/).
