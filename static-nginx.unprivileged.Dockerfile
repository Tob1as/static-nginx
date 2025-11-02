# build: docker build --no-cache --progress=plain --target binary --build-arg NGINX_VERSION=1.29.3 -t tobi312/static-nginx:latest-unprivileged -f static-nginx.unprivileged.Dockerfile .
ARG NGINX_VERSION
FROM ghcr.io/tob1as/static-nginx:base${NGINX_VERSION:+-${NGINX_VERSION}} AS base
# based on image from https://github.com/Tob1as/static-nginx/
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"


FROM alpine:latest AS builder-unprivileged
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"
ENV OUTPUT_DIR=/nginx
COPY --from=base /nginx /nginx
# unprivileged / non-root user (patch)
RUN sed -i -E 's/^(\s*#?\s*listen\s+)(\[::\]:)?80(\b[^0-9])/\1\28080\3/' ${OUTPUT_DIR}/etc/nginx/conf.d/default.conf && \
    sed -i -E 's/^(\s*#?\s*listen\s+)(\[::\]:)?443(\b[^0-9])/\1\28443\3/' ${OUTPUT_DIR}/etc/nginx/conf.d/default.conf && \
    chown -R 101:101 /nginx/
RUN tree ${OUTPUT_DIR}


FROM scratch AS binary

ARG VCS_REF
ARG BUILD_DATE

ARG PCRE2_VERSION
ARG ZLIB_VERSION
ARG OPENSSL_VERSION
ARG NGINX_VERSION

LABEL org.opencontainers.image.title="Static NGINX" \
      org.opencontainers.image.authors="Tobias Hargesheimer <docker@ison.ws>" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.description="Static NGINX${NGINX_VERSION:+ ${NGINX_VERSION}} (unprivileged/nginxuser) build with pcre2${PCRE2_VERSION:+-${PCRE2_VERSION}}, zlib${ZLIB_VERSION:+-${ZLIB_VERSION}} and openssl${OPENSSL_VERSION:+-${OPENSSL_VERSION}}" \
      org.opencontainers.image.documentation="https://github.com/Tob1as/static-nginx/" \
      org.opencontainers.image.base.name="scratch" \
      org.opencontainers.image.licenses="BSD-2-Clause license" \
      org.opencontainers.image.url="https://hub.docker.com/r/tobi312/static-nginx" \
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"

COPY --from=builder-unprivileged /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder-unprivileged /nginx /

COPY <<EOF /etc/passwd
nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin
EOF

COPY <<EOF /etc/group
nginx:x:101:nginx
EOF

STOPSIGNAL SIGQUIT

EXPOSE 8080
USER 101

CMD ["nginx", "-g", "daemon off;"]