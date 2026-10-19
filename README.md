# Keycloak image build component

Build and publish an optimized Keycloak image using rootless BuildKit. The image
uses the Keycloak image pinned in `Dockerfile`, PostgreSQL, health endpoints and metrics. Both the
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
make build
make build IMAGE=keycloak:custom DB=postgres FEATURES=scripts METRICS_ENABLED=false
make build-arm64 IMAGE=keycloak:arm64
make build THEMES_PATH=/path/to/caller/themes IMAGE=keycloak:branded
```

Put local assets in `themes/` and `providers/`, or set `THEMES_PATH` and
`PROVIDERS_PATH` to existing directories. `make build` uses the host architecture
by default; override `PLATFORM=linux/amd64` or `PLATFORM=linux/arm64` as needed.
`KEYCLOAK_IMAGE` overrides the base image and `FEATURES_DISABLED` disables features.
The default command is
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
self-contained component with `make generate`.

```sh
make help
make test              # requires Bash, yq v4, jq and ripgrep
make test-integration  # also requires Docker, curl and zip; tests the native architecture
make ci-lint           # requires authenticated glab access to GitLab
KEYCLOAK_URL=http://localhost:8080 \
MANAGEMENT_URL=http://localhost:9000 bash scripts/smoke-test.sh
```

The component tests check asset isolation, argument forwarding, authentication
and generated-file consistency. The CI pipeline builds the component against
itself and starts the image with PostgreSQL to check readiness, OIDC and metrics.

## Central dependency updates

`Dockerfile` owns the default Keycloak version and digest. The generator derives
the component input default from it and embeds the Dockerfile into the template.
Renovate updates the Dockerfile and runs `bash scripts/render-component.sh` in the
same update branch, keeping the generated template consistent. Only Dockerfile
dependencies are managed initially; Keycloak stays on stable 26.x.

Set up a project access token with Developer role and `api` scope in this project.
Store it as masked, protected `RENOVATE_TOKEN` without variable expansion. Create a
schedule on protected `main` with `MAINTENANCE_TASK=renovate`, for example `0 7 * * *`
in `Europe/Vienna`. Test with `RENOVATE_DRY_RUN=full`, then remove that variable.
The bot is restricted to this project and only the generator command is allowed
as a post-upgrade task. No consumer project access is required.

Consumers can follow `build-keycloak@main` and omit `keycloak_image` to adopt
central updates in their next build. A central merge does not automatically start
consumer builds. A fixed component commit is an alternative for reproducible
component selection. Each build publishes `keycloak-builds/<job-id>/keycloak-base-image.txt` alongside its
BuildKit metadata to record the actual base image, including explicit overrides.

See [Renovate post-upgrade tasks](https://docs.renovatebot.com/configuration-options/#postupgradetasks)
and [GitLab authentication](https://docs.renovatebot.com/modules/platform/gitlab/#authentication).

| Target | Purpose |
| --- | --- |
| `help` | List targets and build parameters. |
| `generate` | Regenerate the component after source changes. |
| `check` | Fail when the generated component is stale. |
| `lint` | Check generated consistency and shell/YAML syntax. |
| `test` | Run component tests without Docker. |
| `test-integration` | Build native images and check isolated PostgreSQL startup and customization. |
| `build` | Build and load a parameterized image locally. |
| `build-amd64`, `build-arm64` | Build and load one explicit architecture. |
| `ci-lint` | Validate the current combined pipeline through GitLab's API. |
| `clean` | Remove local build metadata; preserves generated source and Docker resources. |

References: [Keycloak container builds](https://www.keycloak.org/server/containers),
[GitLab components](https://docs.gitlab.com/ci/components/),
[rootless BuildKit in GitLab](https://docs.gitlab.com/ci/docker/using_buildkit/).
