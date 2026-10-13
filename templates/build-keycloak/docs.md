# Build Keycloak inputs

| Input | Default | Purpose |
| --- | --- | --- |
| `keycloak_image` | Keycloak 26.8.0 with digest | Full base image reference; replace it to change Keycloak version. |
| `db` | `postgres` | Build-time database vendor. |
| `health_enabled` | `true` | Build health endpoints into the image. |
| `metrics_enabled` | `true` | Build metrics support into the image. |
| `features` | empty | Comma-separated features supported by the selected Keycloak version. |
| `features_disabled` | empty | Comma-separated features to disable. |
| `themes_path` | empty | Caller repository directory containing theme directories. |
| `providers_path` | empty | Caller repository directory containing provider JARs. |
| `platforms` | `linux/amd64` | One architecture or comma-separated AMD64/ARM64 platforms. |
| `image_name` | `$CI_REGISTRY_IMAGE` | Full destination image name without a tag. |
| `image_tag` | `$CI_COMMIT_SHORT_SHA` | Single destination tag. |
| `registry` | `$CI_REGISTRY` | Registry host, optionally including a port. |
| `registry_user` | `$CI_REGISTRY_USER` | Reference to a masked CI credential variable. |
| `registry_password` | `$CI_REGISTRY_PASSWORD` | Reference to a masked CI credential variable. |
| `job_name` | `build-keycloak` | Use distinct names when including the component more than once. |
| `stage` | `build` | Must exist in the caller's stage list. |
| `rules` | Branch and tag pipelines | Array of GitLab job rules. |
| `tags` | `[fullstacks]` | Runner tags; adapt for native ARM runners. |
| `buildkit_image` | BuildKit v0.34.0 rootless with digest | Builder image override. |

The job publishes a `keycloak-build-metadata.json` artifact containing the
BuildKit result, including the image digest. Authentication is read from
the credential inputs first. `DOCKER_AUTH_CONFIG` is used when the credential
inputs are empty.
