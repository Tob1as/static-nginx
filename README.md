| **[GitHub](https://github.com/Tob1as/static-nginx)** | **[DockerHub](https://hub.docker.com/r/tobi312/static-nginx)** | **[Quay.io](https://quay.io/repository/tobi312/static-nginx)** |

# Static NGINX

This is a static build/binary of NGINX.

* https://nginx.org/
* https://github.com/nginx/nginx

# What is nginx?

Nginx (pronounced "engine-x") is an open source reverse proxy server for HTTP, HTTPS, SMTP, POP3, and IMAP protocols, as well as a load balancer, HTTP cache, and a web server (origin server). The nginx project started with a strong focus on high concurrency, high performance and low memory usage. It is licensed under the 2-clause BSD-like license.

> [wikipedia.org/wiki/Nginx](https://en.wikipedia.org/wiki/Nginx)

![logo](https://github.com/user-attachments/assets/3a7eeb08-1133-47f5-859c-fad4f5a6a013)

## Container Images

These container images can be used almost in the same way as the official images `nginx/nginx-unprivileged:mainline-alpine` (`nginx:mainline-alpine`):
* [Docker Hub: nginx/nginx-unprivileged](https://hub.docker.com/r/nginx/nginx-unprivileged/) | [GitHub: nginx/docker-nginx-unprivileged](https://github.com/nginx/docker-nginx-unprivileged)
* ([Docker Hub: library/nginx](https://hub.docker.com/_/nginx) | [GitHub: nginx/docker-nginx](https://github.com/nginx/docker-nginx))  

However, they do not contain a shell and therefore no envsubst (for templates).

### Registries, tags and platforms

Images: `ghcr.io/tob1as/static-nginx`, `docker.io/tobi312/static-nginx`, `quay.io/tobi312/static-nginx`

| Tags | Description | Registries | Platforms |
|---|---|---|---|
| `latest`, `<version>`, `privileged`, `<version>-privileged` | privileged (root, port `80`) | all | `linux/amd64`, `linux/arm64`, `linux/arm/v7` |
| `latest-unprivileged`, `<version>-unprivileged`, `unprivileged` | unprivileged (user `101`, port `8080`) | all | `linux/amd64`, `linux/arm64`, `linux/arm/v7` |
| `<version>-privileged-<date>.<commit>`, `<version>-unprivileged-<date>.<commit>` | unique (immutable) tag of a build | ghcr.io | `linux/amd64`, `linux/arm64`, `linux/arm/v7` |
| `base-alpine`, `base-alpine-<version>`, `base-alpine-<version>-<date>.<commit>` | base image (only `/nginx`, see "Use in own image"), built on Alpine (musl) | ghcr.io | `linux/amd64`, `linux/arm64`, `linux/arm/v7` |
| `base-debian`, `base-debian-<version>`, `base-debian-<version>-<date>.<commit>` | base image, built on Debian (glibc) | ghcr.io | `linux/amd64`, `linux/arm64` |

`<version>` = nginx version, e.g. `1.31.9`; `<date>.<commit>` e.g. `20261123101500.1a2b3c4`

### How to use this image

Run NGINX container:
```console
# privileged / root user
$ docker run --name some-nginx -p 8080:80 -v ${PWD}/html:/usr/share/nginx/html:ro -d docker.io/tobi312/static-nginx:latest

# unprivileged / nginx user
$ docker run --name some-nginx -p 8080:8080 -v ${PWD}/html:/usr/share/nginx/html:ro -d docker.io/tobi312/static-nginx:latest-unprivileged
```

Own configuration (server blocks in `/etc/nginx/conf.d/`, main config `/etc/nginx/nginx.conf`):
```console
$ docker run --name some-nginx -p 8080:8080 -v ${PWD}/conf.d:/etc/nginx/conf.d:ro -d docker.io/tobi312/static-nginx:latest-unprivileged
```

Useful commands:
```console
# test configuration
$ docker run --rm -v ${PWD}/conf.d:/etc/nginx/conf.d:ro docker.io/tobi312/static-nginx:latest-unprivileged nginx -t
# reload configuration
$ docker exec some-nginx nginx -s reload
# show version and build options
$ docker run --rm docker.io/tobi312/static-nginx:latest nginx -V
```

Use in own image:
```Dockerfile
# build on alpine:
COPY --from=ghcr.io/tob1as/static-nginx:base-alpine /nginx /
# build on debian:
COPY --from=ghcr.io/tob1as/static-nginx:base-debian /nginx /
```

Notes for the base images:
* `/nginx` contains nginx incl. configs, html and log symlinks, but no `/run` (exists in Alpine/Debian) and no user: the default `nginx.conf` uses `user nginx;`, so create the user (UID/GID `101` like the official images), e.g.:
  * Alpine: `addgroup -g 101 -S nginx && adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx`
  * Debian: `groupadd --system --gid 101 nginx && useradd --system --gid nginx --no-create-home --home /nonexistent --shell /bin/false --uid 101 nginx`
* CA certificates (`/etc/ssl/certs/ca-certificates.crt`) are not part of `/nginx`, install them in your image if needed (package `ca-certificates`).
* `base-debian`: the static glibc binary also works without the glibc NSS libraries (e.g. in `scratch`, tested on amd64 and arm64): user lookups (`/etc/passwd`, `/etc/group`) and host name resolution (`/etc/hosts`, DNS) are part of libc since glibc 2.34. Only other NSS sources in `/etc/nsswitch.conf` (e.g. LDAP, systemd) need the NSS libraries, i.e. a Debian (glibc) based image.

### Differences to the official images

* **No `load_module` needed:** the dynamic modules of `nginx:mainline-alpine` are compiled in statically:
  `ngx_http_acme_module`, `ngx_http_geoip_module` / `ngx_stream_geoip_module`, `ngx_http_image_filter_module`, `ngx_http_xslt_filter_module`, `ngx_http_js_module` / `ngx_stream_js_module` (njs).
  Existing configs with `load_module` directives must be adjusted (remove the directives), otherwise nginx does not start.
* **GeoIP:** supports legacy (`.dat`) and GeoIP2/MMDB (`.mmdb`) databases.
* **njs:** QuickJS engine available (`js_engine qjs;`).
* **No shell and no entrypoint script** (base image `scratch`):
  * no `/docker-entrypoint.d/` scripts, no templates in `/etc/nginx/templates` (envsubst), `NGINX_ENTRYPOINT_*` variables have no effect
  * `docker exec ... sh` is not possible
  * no `curl`/`wget` for container healthchecks (use e.g. a TCP check or an external check)
* **Unprivileged** images (like `nginx/nginx-unprivileged`):
  * run as user `101` (group `0`), listen on port `8080` (HTTPS example in `default.conf`: `8443`)
  * PID file `/tmp/nginx.pid`, temp paths (`proxy_temp`, `client_temp`, ...) in `/tmp`
* **CA certificates:** `/etc/ssl/certs/ca-certificates.crt` (from Alpine), also used as OpenSSL default (`/etc/ssl/cert.pem`), e.g. for `acme_issuer` or `proxy_ssl_verify`.

### Kubernetes / OpenShift

Use the unprivileged image:
* Arbitrary UIDs with GID `0` are supported (`/etc/nginx`, `/var/cache/nginx` and `/run` are group-writable).
* With `readOnlyRootFilesystem: true` mount an `emptyDir` to `/tmp` (PID file, temp paths) and - if ACME is used - to `/var/cache/nginx` (default ACME `state_path`).

```yaml
    securityContext:
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
    volumeMounts:
      - name: tmp
        mountPath: /tmp
  volumes:
    - name: tmp
      emptyDir: {}
```

### Build

Local build (versions: see `ARG` in the [base Dockerfiles](https://github.com/Tob1as/static-nginx/blob/main/static-nginx.base-alpine.Dockerfile), can be overridden with `--build-arg`).
The privileged/unprivileged images use the base image `ghcr.io/tob1as/static-nginx:base-alpine[-<NGINX_VERSION>]` (pulled from ghcr.io, if not available locally):
```console
# base image
$ docker build --progress=plain --target binary --build-arg NGINX_VERSION=1.31.9 -t ghcr.io/tob1as/static-nginx:base-alpine-1.31.9 -f static-nginx.base-alpine.Dockerfile .
# privileged / unprivileged image
$ docker build --progress=plain --target binary --build-arg NGINX_VERSION=1.31.9 -t local/static-nginx:latest -f static-nginx.privileged.Dockerfile .
$ docker build --progress=plain --target binary --build-arg NGINX_VERSION=1.31.9 -t local/static-nginx:latest-unprivileged -f static-nginx.unprivileged.Dockerfile .
```

CI ([GitHub Actions](https://github.com/Tob1as/static-nginx/tree/main/.github/workflows)):
* runs on push if a Dockerfile or the workflow changed, or manually ("Run workflow")
* the latest versions of nginx and all dependencies are determined at workflow start and passed as build args
* Alpine: base image, privileged and unprivileged images; Debian: only base image
