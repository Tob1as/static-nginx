# build: docker build --no-cache --progress=plain --target binary --build-arg NGINX_VERSION=1.29.3 -t ghcr.io/tob1as/static-nginx:latest -f static-nginx.Dockerfile .
ARG NGINX_VERSION
ARG OS=alpine
FROM ghcr.io/tob1as/static-nginx:base-${OS}${NGINX_VERSION:+-${NGINX_VERSION}} AS base
# based on image from https://github.com/Tob1as/static-nginx/
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"


FROM alpine:latest AS builder-privileged
LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"
ENV OUTPUT_DIR=/nginx
# nginx user
RUN echo 'nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin' >> /etc/passwd ; \
    echo 'nginx:x:101:nginx' >> /etc/group
# copy static nginx
COPY --from=base /nginx /nginx
RUN mkdir -p ${OUTPUT_DIR}/var/run && \
    rm -f ${OUTPUT_DIR}/etc/nginx/nginx.conf.default
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
      org.opencontainers.image.description="Static NGINX${NGINX_VERSION:+ ${NGINX_VERSION}} build with pcre2${PCRE2_VERSION:+-${PCRE2_VERSION}}, zlib${ZLIB_VERSION:+-${ZLIB_VERSION}} and openssl${OPENSSL_VERSION:+-${OPENSSL_VERSION}}" \
      org.opencontainers.image.documentation="https://github.com/Tob1as/static-nginx/" \
      org.opencontainers.image.base.name="scratch" \
      org.opencontainers.image.licenses="BSD-2-Clause license" \
      org.opencontainers.image.url="https://hub.docker.com/r/tobi312/static-nginx" \
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"

COPY --from=builder-privileged /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder-privileged /nginx /

COPY <<EOF /etc/passwd
root:x:0:0:root:/root:/sbin/nologin
nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin
EOF

COPY <<EOF /etc/group
root:x:0:root
nginx:x:101:nginx
EOF

STOPSIGNAL SIGQUIT

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]