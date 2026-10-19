SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

IMAGE ?= fullstacks-keycloak:local
PLATFORM ?= linux/$(shell uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
KEYCLOAK_IMAGE ?= $(shell sed -n 's/^ARG KEYCLOAK_IMAGE=//p' Dockerfile)
DB ?= postgres
HEALTH_ENABLED ?= true
METRICS_ENABLED ?= true
FEATURES ?=
FEATURES_DISABLED ?=
THEMES_PATH ?= $(CURDIR)/themes
PROVIDERS_PATH ?= $(CURDIR)/providers

.PHONY: help generate check lint test test-integration build build-amd64 build-arm64 ci-lint clean
help: ## Show targets and build parameters
	@awk 'BEGIN {FS = ":.*## "} /^[a-z0-9-]+:.*## / {printf "%-20s %s\n", $$1, $$2}' Makefile
	@printf '\nBuild parameters: IMAGE PLATFORM KEYCLOAK_IMAGE DB HEALTH_ENABLED METRICS_ENABLED\n                 FEATURES FEATURES_DISABLED THEMES_PATH PROVIDERS_PATH\n'

generate: ## Generate the self-contained CI component
	bash scripts/render-component.sh

check: ## Check that the generated component matches its sources
	bash scripts/render-component.sh --check

lint: check ## Check shell and YAML syntax
	@set -euo pipefail; for script in scripts/*.sh tests/*.sh; do bash -n "$$script"; done
	yq eval-all '.' ci/component.yml ci/renovate.yaml templates/build-keycloak/template.yml .gitlab-ci.yml > /dev/null

test: lint ## Test component inputs, build context and authentication without Docker
	bash tests/component-test.sh

test-integration: check ## Build native images and test isolated PostgreSQL startup and custom options
	bash tests/integration-test.sh

build: ## Build and load a local image with configurable options and assets
	@set -euo pipefail; context=$$(mktemp -d); trap 'rm -rf "$$context"' EXIT; \
	  mkdir -p "$$context/themes" "$$context/providers"; \
	  cp Dockerfile "$$context/Dockerfile"; \
	  cp -R "$(THEMES_PATH)/." "$$context/themes/"; \
	  cp -R "$(PROVIDERS_PATH)/." "$$context/providers/"; \
	  docker buildx build --load --platform "$(PLATFORM)" --tag "$(IMAGE)" \
	    --build-arg "KEYCLOAK_IMAGE=$(KEYCLOAK_IMAGE)" \
	    --build-arg "KC_DB=$(DB)" \
	    --build-arg "KC_HEALTH_ENABLED=$(HEALTH_ENABLED)" \
	    --build-arg "KC_METRICS_ENABLED=$(METRICS_ENABLED)" \
	    --build-arg "KC_FEATURES=$(FEATURES)" \
	    --build-arg "KC_FEATURES_DISABLED=$(FEATURES_DISABLED)" "$$context"

build-amd64: ## Build and load the AMD64 image (emulation required on ARM)
	$(MAKE) build PLATFORM=linux/amd64

build-arm64: ## Build and load the ARM64 image (emulation required on AMD64)
	$(MAKE) build PLATFORM=linux/arm64

ci-lint: check ## Validate the current pipeline using authenticated GitLab CI Lint
	@set -euo pipefail; workspace=$$(mktemp -d); trap 'rm -rf "$$workspace"' EXIT; \
	  yq eval-all 'select(documentIndex == 0) | .spec.inputs.image_name.default = "$$CI_REGISTRY_IMAGE/test" | .spec.inputs.image_tag.default = "$$CI_COMMIT_SHA" | .spec.inputs.themes_path.default = "tests/fixtures/themes"' templates/build-keycloak/template.yml > "$$workspace/ci.yml"; \
	  printf '\n---\n' >> "$$workspace/ci.yml"; \
	  yq eval-all 'select(fileIndex == 0 and documentIndex == 1) * (select(fileIndex == 1) | del(.include)) * select(fileIndex == 2)' templates/build-keycloak/template.yml .gitlab-ci.yml ci/renovate.yaml >> "$$workspace/ci.yml"; \
	  jq -n --rawfile content "$$workspace/ci.yml" '{content: $$content}' > "$$workspace/request.json"; \
	  glab api 'projects/fullstacks-gmbh%2Fcicd-components%2Fkeycloak/ci/lint' \
	    --method POST --header 'Content-Type: application/json' --input "$$workspace/request.json" > "$$workspace/result.json"; \
	  jq '{valid, errors, warnings}' "$$workspace/result.json"; \
	  jq -e '.valid == true' "$$workspace/result.json" > /dev/null

clean: ## Remove local BuildKit metadata (keeps images, containers and generated source)
	rm -f keycloak-build-metadata.json
	rm -rf keycloak-builds
