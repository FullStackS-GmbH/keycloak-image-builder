ARG KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.8.2@sha256:c68e286cacd87b942ac1939a0a1481461109d6acd3a57dc496969a319a76bbf0
FROM ${KEYCLOAK_IMAGE} AS builder
ARG KC_DB=postgres
ARG KC_HEALTH_ENABLED=true
ARG KC_METRICS_ENABLED=true
ARG KC_FEATURES=
ARG KC_FEATURES_DISABLED=
ENV KC_DB=${KC_DB} \
    KC_HEALTH_ENABLED=${KC_HEALTH_ENABLED} \
    KC_METRICS_ENABLED=${KC_METRICS_ENABLED}
COPY --chown=keycloak:keycloak themes/ /opt/keycloak/themes/
COPY --chown=keycloak:keycloak providers/ /opt/keycloak/providers/
# Stable JAR timestamps prevent false provider-change detection at optimized startup.
RUN for provider in /opt/keycloak/providers/*.jar; do \
      [ ! -f "$provider" ] || touch -m --date=@1743465600 "$provider"; \
    done && \
    set -- build && \
    if [ -n "$KC_FEATURES" ]; then set -- "$@" "--features=$KC_FEATURES"; fi && \
    if [ -n "$KC_FEATURES_DISABLED" ]; then set -- "$@" "--features-disabled=$KC_FEATURES_DISABLED"; fi && \
    unset KC_FEATURES KC_FEATURES_DISABLED && \
    /opt/keycloak/bin/kc.sh "$@"

FROM ${KEYCLOAK_IMAGE}
ARG KC_DB=postgres
ARG KC_HEALTH_ENABLED=true
ARG KC_METRICS_ENABLED=true
ARG VCS_REF=local
ARG IMAGE_VERSION=dev
ARG SOURCE_URL=
LABEL org.opencontainers.image.title="FULLSTACKS Parameterized Keycloak IMAGE" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${IMAGE_VERSION}"
ENV KC_DB=${KC_DB} \
    KC_HEALTH_ENABLED=${KC_HEALTH_ENABLED} \
    KC_METRICS_ENABLED=${KC_METRICS_ENABLED}
COPY --from=builder --chown=keycloak:keycloak /opt/keycloak/ /opt/keycloak/
USER 1000
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized"]
