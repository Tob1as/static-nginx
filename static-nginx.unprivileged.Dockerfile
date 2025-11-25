# build: docker build --no-cache --progress=plain --target binary --build-arg NGINX_VERSION=1.29.3 -t ghcr.io/tob1as/static-nginx:latest-unprivileged -f static-nginx.unprivileged.Dockerfile .
ARG NGINX_VERSION
ARG OS=alpine
FROM ghcr.io/tob1as/static-nginx:base-${OS}${NGINX_VERSION:+-${NGINX_VERSION}} AS base
# based on image from https://github.com/Tob1as/static-nginx/
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"


FROM alpine:latest AS builder-unprivileged
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"
ENV OUTPUT_DIR=/nginx
# nginx user
RUN echo 'nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin' >> /etc/passwd ; \
    echo 'nginx:x:101:nginx' >> /etc/group
# copy static nginx
COPY --from=base /nginx /nginx
RUN rm -f ${OUTPUT_DIR}/etc/nginx/nginx.conf.default
# unprivileged / non-root user (patch)
RUN sed -i -E 's/^(\s*#?\s*listen\s+)(\[::\]:)?80(\b[^0-9])/\1\28080\3/' ${OUTPUT_DIR}/etc/nginx/conf.d/default.conf && \
    sed -i -E 's/^(\s*#?\s*listen\s+)(\[::\]:)?443(\b[^0-9])/\1\28443\3/' ${OUTPUT_DIR}/etc/nginx/conf.d/default.conf && \
    sed -i '/user  nginx;/d' ${OUTPUT_DIR}/etc/nginx/nginx.conf && \
    sed -i 's,\(/var\)\{0\,1\}/run/nginx.pid,/tmp/nginx.pid,' ${OUTPUT_DIR}/etc/nginx/nginx.conf && \
    sed -i "/^http {/a \    proxy_temp_path /tmp/proxy_temp;\n    client_body_temp_path /tmp/client_temp;\n    fastcgi_temp_path /tmp/fastcgi_temp;\n    uwsgi_temp_path /tmp/uwsgi_temp;\n    scgi_temp_path /tmp/scgi_temp;\n" ${OUTPUT_DIR}/etc/nginx/nginx.conf && \
    chown -R 101:0 ${OUTPUT_DIR}/var/cache/nginx && \
    chmod -R g+w ${OUTPUT_DIR}/var/cache/nginx && \
    chown -R 101:0 ${OUTPUT_DIR}/etc/nginx && \
    chmod -R g+w ${OUTPUT_DIR}/etc/nginx && \
    mkdir -p ${OUTPUT_DIR}/tmp && chmod -R 1777 ${OUTPUT_DIR}/tmp
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