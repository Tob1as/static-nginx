| **[GitHub](https://github.com/Tob1as/static-nginx)** | **[DockerHub](https://hub.docker.com/r/tobi312/static-nginx)** |

# Static NGINX

This is a static build/binary of NGINX.

* https://nginx.org/
* https://github.com/nginx/nginx

# What is nginx?

Nginx (pronounced "engine-x") is an open source reverse proxy server for HTTP, HTTPS, SMTP, POP3, and IMAP protocols, as well as a load balancer, HTTP cache, and a web server (origin server). The nginx project started with a strong focus on high concurrency, high performance and low memory usage. It is licensed under the 2-clause BSD-like license.

> [wikipedia.org/wiki/Nginx](https://en.wikipedia.org/wiki/Nginx)

![logo](https://raw.githubusercontent.com/docker-library/docs/refs/heads/master/nginx/logo.png)

## Container Images

These container images can be used almost in the same way as the official images ([library/nginx](https://hub.docker.com/_/nginx) & [nginxinc/nginx-unprivileged](https://hub.docker.com/r/nginxinc/nginx-unprivileged)).
However, they do not contain a shell and therefore no envsubst (for templates).

### Supported tags and respective `Dockerfile` links

-	[`<version>`, `latest`](https://github.com/Tob1as/static-nginx/blob/main/static-nginx.Dockerfile)
-	[`<version>-unprivileged`, `latest-unprivileged`](https://github.com/Tob1as/static-nginx/blob/main/static-nginx.unprivileged.Dockerfile)

Alternate static nginx images can be found here: https://github.com/Tob1as/docker-tools

### How to use this image

```console
# privileged / root user
$ docker run --name some-nginx -p 8080:80 -v ${PWD}/html:/usr/share/nginx/html:ro -d tobi312/static-nginx:latest

# unprivileged / nginx user
$ docker run --name some-nginx -p 8080:8080 -v ${PWD}/html:/usr/share/nginx/html:ro -d tobi312/static-nginx:latest-unprivileged
```
