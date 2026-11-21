# build: docker build --no-cache --progress=plain --target binary --build-arg NGINX_VERSION=1.31.9 -t ghcr.io/tob1as/static-nginx:base-debian -f static-nginx.base-debian.Dockerfile .
#
# Static NGINX with all modules of the official images "nginx:mainline-alpine-slim" (built-in)
# and "nginx:mainline-alpine" (dynamic: acme, geoip, image_filter, njs, xslt), here compiled in statically on Debian (glibc).
# Note: a static glibc binary still needs the glibc NSS libraries at runtime for user/host lookups (getpwnam, getaddrinfo),
#       so use this base in a Debian image ("COPY --from=ghcr.io/tob1as/static-nginx:base-debian /nginx /").
#
# global build args (must be re-declared without value inside each stage to be used there)
ARG NGINX_VERSION=1.31.9
ARG PCRE2_VERSION=10.49
ARG ZLIB_VERSION=1.4
ARG OPENSSL_VERSION=3.5.9
ARG LIBMAXMINDDB_VERSION=1.14.1
ARG LIBGEOIP_VERSION=1.6.12
ARG LIBGD_VERSION=2.3.3
ARG QUICKJS_VERSION=2026-06-04
ARG NJS_VERSION=1.0.2
ARG NGINX_ACME_VERSION=0.4.2
# Debian only: built from source, because Debian's libxml2 is linked against ICU (huge when linked statically)
ARG LIBXML2_VERSION=2.13.9
ARG LIBXSLT_VERSION=1.1.43

FROM docker.io/library/debian:trixie-slim AS builder

ARG NGINX_VERSION
ARG PCRE2_VERSION
ARG ZLIB_VERSION
ARG OPENSSL_VERSION
ARG LIBMAXMINDDB_VERSION
ARG LIBGEOIP_VERSION
ARG LIBGD_VERSION
ARG QUICKJS_VERSION
ARG NJS_VERSION
ARG NGINX_ACME_VERSION
ARG LIBXML2_VERSION
ARG LIBXSLT_VERSION

ARG VCS_REF
ARG BUILD_DATE

# BUILD_DIR: sources, DEPS_DIR: self-built static libraries, WRAP_DIR: linker scripts (see below), OUTPUT_DIR: image rootfs
# RUSTUP_HOME/CARGO_HOME: Rust toolchain for nginx-acme (installed with rustup, see below)
ENV BUILD_DIR=/usr/src \
    DEPS_DIR=/opt/static \
    WRAP_DIR=/opt/static/lib-wrap \
    OUTPUT_DIR=/nginx \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:${PATH}

ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Static NGINX"\
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.description="Static NGINX${NGINX_VERSION:+ ${NGINX_VERSION}} build with pcre2${PCRE2_VERSION:+-${PCRE2_VERSION}}, zlib${ZLIB_VERSION:+-${ZLIB_VERSION}}, openssl${OPENSSL_VERSION:+-${OPENSSL_VERSION}}, libmaxminddb${LIBMAXMINDDB_VERSION:+-${LIBMAXMINDDB_VERSION}}, libgeoip${LIBGEOIP_VERSION:+-${LIBGEOIP_VERSION}}, libgd${LIBGD_VERSION:+-${LIBGD_VERSION}}, quickjs${QUICKJS_VERSION:+-${QUICKJS_VERSION}}, njs${NJS_VERSION:+-${NJS_VERSION}} and nginx-acme${NGINX_ACME_VERSION:+-${NGINX_ACME_VERSION}} on Debian" \
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

WORKDIR /usr/src

# build-only stage: package versions are intentionally not pinned (pins break on every Debian package update)
# libpng/libjpeg/libwebp (-dev incl. static libs): for libgd
# clang/libclang-dev: nginx-acme (Rust, bindgen needs libclang)
# hardening-cflags: compiler hardening for nginx and all self-built libraries (like the official Debian packages),
#   architecture specific: CET on x86_64, BTI/PAC on aarch64, nothing extra on armv7
# static-ldflag: "-static-pie" (ASLR for the static binary) if glibc provides rcrt1.o (amd64, arm64), otherwise "-static" (e.g. armhf)
# hadolint ignore=DL3008
RUN echo ">> Install build packages ..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        xz-utils \
        g++ \
        make \
        perl \
        file \
        tree \
        pkgconf \
        \
        autoconf \
        automake \
        libtool \
        \
        libpng-dev \
        libjpeg-dev \
        libwebp-dev \
        \
        clang \
        libclang-dev \
    && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p ${OUTPUT_DIR} ${DEPS_DIR}/lib ${DEPS_DIR}/include ${WRAP_DIR} && \
    case "$(uname -m)" in \
        x86_64)  ARCH_CFLAGS="-fcf-protection" ;; \
        aarch64) ARCH_CFLAGS="-mbranch-protection=standard" ;; \
        *)       ARCH_CFLAGS="" ;; \
    esac && \
    echo "-fstack-protector-strong -fstack-clash-protection -Wp,-D_FORTIFY_SOURCE=2 ${ARCH_CFLAGS}" > ${DEPS_DIR}/hardening-cflags && \
    if [ "$(gcc -print-file-name=rcrt1.o)" != "rcrt1.o" ]; then echo "-static-pie"; else echo "-static"; fi > ${DEPS_DIR}/static-ldflag && \
    cat ${DEPS_DIR}/hardening-cflags ${DEPS_DIR}/static-ldflag

# https://rustup.rs (Rust toolchain for nginx-acme; Debian's rustc can be older than the MSRV of nginx-acme)
RUN echo ">> Install Rust toolchain ..." && \
    wget -qO- https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable && \
    rustc --version && cargo --version

# === Static dependencies ===

# https://github.com/madler/zlib (prebuilt: used by nginx, libxml2, libpng, libgd -> exactly one zlib in the binary)
RUN echo ">> Download: zlib-${ZLIB_VERSION} ..." && \
    wget --progress=dot:giga https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz && \
    tar xf zlib-${ZLIB_VERSION}.tar.gz && rm zlib-${ZLIB_VERSION}.tar.gz

WORKDIR /usr/src/zlib-${ZLIB_VERSION}
RUN echo ">> Compile: zlib-${ZLIB_VERSION} ..." && \
    CFLAGS="-Os -fPIC $(cat ${DEPS_DIR}/hardening-cflags)" ./configure --static --prefix=${DEPS_DIR} && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://github.com/openssl/openssl
# prebuilt (instead of nginx --with-openssl=...) so nginx-acme (Rust openssl-sys) links against the very same library.
# --openssldir=/etc/ssl: default CA bundle /etc/ssl/cert.pem (like Alpine), no-module: providers built into libcrypto (no dlopen in static binaries)
RUN echo ">> Download: openssl-${OPENSSL_VERSION} ..." && \
    wget --progress=dot:giga https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
    tar xf openssl-${OPENSSL_VERSION}.tar.gz && rm openssl-${OPENSSL_VERSION}.tar.gz

WORKDIR /usr/src/openssl-${OPENSSL_VERSION}
# hardening-cflags must be split into separate arguments (word splitting intended)
# hadolint ignore=SC2046
RUN echo ">> Compile: openssl-${OPENSSL_VERSION} ..." && \
    ./config --prefix=${DEPS_DIR} --libdir=lib --openssldir=/etc/ssl \
        no-shared no-module no-tests no-docs \
        -Os $(cat ${DEPS_DIR}/hardening-cflags) && \
    make -j"$(nproc)" && make install_sw

WORKDIR /usr/src

# https://github.com/maxmind/libmaxminddb (MMDB/GeoIP2, supported by ngx_http_geoip_module since nginx 1.31.7)
RUN echo ">> Download: (MMDB/GeoIP2) libmaxminddb-${LIBMAXMINDDB_VERSION} ..." && \
    wget --progress=dot:giga https://github.com/maxmind/libmaxminddb/releases/download/${LIBMAXMINDDB_VERSION}/libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz && \
    tar xf libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz && rm libmaxminddb-${LIBMAXMINDDB_VERSION}.tar.gz

WORKDIR /usr/src/libmaxminddb-${LIBMAXMINDDB_VERSION}
RUN echo ">> Compile: libmaxminddb-${LIBMAXMINDDB_VERSION} ..." && \
    CFLAGS="-Os $(cat ${DEPS_DIR}/hardening-cflags)" ./configure --prefix=${DEPS_DIR} --enable-static --disable-shared && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://github.com/maxmind/geoip-api-c (libGeoIP, GeoIP legacy, .dat databases)
# the official image links ngx_http_geoip_module against both libGeoIP and libmaxminddb -> supports .dat and .mmdb
RUN echo ">> Download: (GeoIP legacy) geoip-api-c-${LIBGEOIP_VERSION} ..." && \
    wget --progress=dot:giga -O geoip-api-c-${LIBGEOIP_VERSION}.tar.gz https://github.com/maxmind/geoip-api-c/archive/refs/tags/v${LIBGEOIP_VERSION}.tar.gz && \
    tar xf geoip-api-c-${LIBGEOIP_VERSION}.tar.gz && rm geoip-api-c-${LIBGEOIP_VERSION}.tar.gz

WORKDIR /usr/src/geoip-api-c-${LIBGEOIP_VERSION}
RUN echo ">> Compile: geoip-api-c-${LIBGEOIP_VERSION} ..." && \
    ./bootstrap && \
    CFLAGS="-Os $(cat ${DEPS_DIR}/hardening-cflags)" ./configure --prefix=${DEPS_DIR} --enable-static --disable-shared && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://gitlab.gnome.org/GNOME/libxml2 (for xslt + njs; Debian only, see LIBXML2_VERSION)
RUN echo ">> Download: libxml2-${LIBXML2_VERSION} ..." && \
    wget --progress=dot:giga https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-${LIBXML2_VERSION}.tar.xz && \
    tar xf libxml2-${LIBXML2_VERSION}.tar.xz && rm libxml2-${LIBXML2_VERSION}.tar.xz

WORKDIR /usr/src/libxml2-${LIBXML2_VERSION}
RUN echo ">> Compile: libxml2-${LIBXML2_VERSION} ..." && \
    CFLAGS="-Os $(cat ${DEPS_DIR}/hardening-cflags)" ./configure --prefix=${DEPS_DIR} --enable-static --disable-shared \
        --with-zlib=${DEPS_DIR} --without-lzma --without-icu --without-python --without-modules && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://gitlab.gnome.org/GNOME/libxslt (incl. libexslt, for xslt + njs; Debian only, see LIBXML2_VERSION)
RUN echo ">> Download: libxslt-${LIBXSLT_VERSION} ..." && \
    wget --progress=dot:giga https://download.gnome.org/sources/libxslt/${LIBXSLT_VERSION%.*}/libxslt-${LIBXSLT_VERSION}.tar.xz && \
    tar xf libxslt-${LIBXSLT_VERSION}.tar.xz && rm libxslt-${LIBXSLT_VERSION}.tar.xz

WORKDIR /usr/src/libxslt-${LIBXSLT_VERSION}
RUN echo ">> Compile: libxslt-${LIBXSLT_VERSION} ..." && \
    CFLAGS="-Os $(cat ${DEPS_DIR}/hardening-cflags)" PKG_CONFIG_PATH=${DEPS_DIR}/lib/pkgconfig \
    ./configure --prefix=${DEPS_DIR} --enable-static --disable-shared \
        --with-libxml-prefix=${DEPS_DIR} --without-python --without-crypto && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://github.com/libgd/libgd (for ngx_http_image_filter_module)
# only the formats image_filter uses: JPEG, GIF (built-in), PNG, WebP
RUN echo ">> Download: libgd-${LIBGD_VERSION} ..." && \
    wget --progress=dot:giga https://github.com/libgd/libgd/releases/download/gd-${LIBGD_VERSION}/libgd-${LIBGD_VERSION}.tar.xz && \
    tar xf libgd-${LIBGD_VERSION}.tar.xz && rm libgd-${LIBGD_VERSION}.tar.xz

WORKDIR /usr/src/libgd-${LIBGD_VERSION}
RUN echo ">> Compile: libgd-${LIBGD_VERSION} ..." && \
    CFLAGS="-Os $(cat ${DEPS_DIR}/hardening-cflags)" CPPFLAGS="-I${DEPS_DIR}/include" LDFLAGS="-L${DEPS_DIR}/lib" \
    ./configure --prefix=${DEPS_DIR} --enable-static --disable-shared \
        --with-zlib=${DEPS_DIR} --with-png --with-jpeg --with-webp \
        --without-freetype --without-fontconfig --without-xpm --without-x --without-tiff \
        --without-avif --without-heif --without-raqm --without-liq && \
    make -j"$(nproc)" && make install

WORKDIR /usr/src

# https://bellard.org/quickjs/ (QuickJS engine for njs: "js_engine qjs;", like official nginx-module-njs)
RUN echo ">> Download: quickjs-${QUICKJS_VERSION} ..." && \
    wget --progress=dot:giga https://bellard.org/quickjs/quickjs-${QUICKJS_VERSION}.tar.xz && \
    tar xf quickjs-${QUICKJS_VERSION}.tar.xz && rm quickjs-${QUICKJS_VERSION}.tar.xz

WORKDIR /usr/src/quickjs-${QUICKJS_VERSION}
RUN echo ">> Compile: quickjs-${QUICKJS_VERSION} ..." && \
    CFLAGS="-fPIC $(cat ${DEPS_DIR}/hardening-cflags)" make -j"$(nproc)" libquickjs.a && \
    mkdir -p ${DEPS_DIR}/include/quickjs && \
    cp quickjs.h ${DEPS_DIR}/include/quickjs/ && \
    cp libquickjs.a ${DEPS_DIR}/lib/

WORKDIR /usr/src

# Linker scripts: nginx feature tests and the final link use "-lgd", "-lxml2", "-lxslt", "-lexslt" without the
# transitive dependencies. Statically linked archives need them (in the right order), so these wrappers
# (found first via -L${WRAP_DIR}) pull in the real archive plus its dependencies.
# Debian: system libs (png/jpeg/webp) via "-l..." -> found in the multiarch dir, independent of the architecture.
# libgcc_s: Rust std (nginx-acme) requests -lgcc_s, which only exists as shared library -> use libgcc_eh.a.
RUN echo ">> Create linker scripts for static dependencies ..." && \
    LIBS_XML="${DEPS_DIR}/lib/libxml2.a ${DEPS_DIR}/lib/libz.a -lm" && \
    echo "GROUP ( ${DEPS_DIR}/lib/libgd.a -lpng16 -ljpeg -lwebp -lsharpyuv ${DEPS_DIR}/lib/libz.a -lm )" > ${WRAP_DIR}/libgd.a && \
    echo "GROUP ( ${LIBS_XML} )" > ${WRAP_DIR}/libxml2.a && \
    echo "GROUP ( ${DEPS_DIR}/lib/libxslt.a ${LIBS_XML} )" > ${WRAP_DIR}/libxslt.a && \
    echo "GROUP ( ${DEPS_DIR}/lib/libexslt.a ${DEPS_DIR}/lib/libxslt.a ${LIBS_XML} )" > ${WRAP_DIR}/libexslt.a && \
    echo "GROUP ( $(gcc -print-file-name=libgcc_eh.a) )" > ${WRAP_DIR}/libgcc_s.a && \
    head ${WRAP_DIR}/*

# === nginx modules (third party / out of tree) ===

# https://github.com/PCRE2Project/pcre2 (built by nginx itself, --with-pcre-jit)
RUN echo ">> Download: pcre2-${PCRE2_VERSION} ..." && \
    wget --progress=dot:giga https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.gz && \
    tar xf pcre2-${PCRE2_VERSION}.tar.gz && rm pcre2-${PCRE2_VERSION}.tar.gz

# https://github.com/nginx/njs (ngx_http_js_module + ngx_stream_js_module)
RUN echo ">> Download: njs-${NJS_VERSION} ..." && \
    wget --progress=dot:giga -O njs-${NJS_VERSION}.tar.gz https://github.com/nginx/njs/archive/refs/tags/${NJS_VERSION}.tar.gz && \
    tar xf njs-${NJS_VERSION}.tar.gz && rm njs-${NJS_VERSION}.tar.gz

# https://github.com/nginx/nginx-acme (ngx_http_acme_module, Rust)
RUN echo ">> Download: nginx-acme-${NGINX_ACME_VERSION} ..." && \
    wget --progress=dot:giga -O nginx-acme-${NGINX_ACME_VERSION}.tar.gz https://github.com/nginx/nginx-acme/archive/refs/tags/v${NGINX_ACME_VERSION}.tar.gz && \
    tar xf nginx-acme-${NGINX_ACME_VERSION}.tar.gz && rm nginx-acme-${NGINX_ACME_VERSION}.tar.gz

# nginx user
RUN echo 'nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin' >> /etc/passwd ; \
    echo 'nginx:x:101:nginx' >> /etc/group

# === Build NGINX static ===
# https://github.com/nginx/nginx && https://nginx.org/
# https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-open-source/#compile-and-install-from-source
# https://nginx.org/en/docs/configure.html
# configured build like: "docker run --rm --name nginx-info --entrypoint=nginx -it nginx:mainline-alpine-slim -V"
# plus the dynamic modules of "nginx:mainline-alpine" (compiled in).
# Removed (useless for a static binary, no dlopen): --with-compat, --modules-path, --with-perl_modules_path
# nginx-acme: openssl-sys must use the same (static) OpenSSL as nginx, NGX_ACME_STATE_PREFIX: default dir for "state_path"
# cc-opt/ld-opt: hardening like the official Debian packages (see hardening-cflags, static-ldflag, full RELRO)
# "-Wl,-E" (added by nginx to export symbols for dynamic modules) is removed from objs/Makefile:
#   useless in a static binary and glibc static-pie binaries crash at startup with it (exit code 139)
RUN echo ">> Download: nginx-${NGINX_VERSION} ..." && \
    wget --progress=dot:giga https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
    tar xf nginx-${NGINX_VERSION}.tar.gz && rm nginx-${NGINX_VERSION}.tar.gz

WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN echo ">> BUILD: nginx-${NGINX_VERSION} ..." && \
    LIBCLANG_PATH="$(dirname "$(find /usr/lib -name 'libclang.so*' | head -n1)")" && \
    HARDENING_CFLAGS="$(cat ${DEPS_DIR}/hardening-cflags)" && \
    STATIC_LDFLAG="$(cat ${DEPS_DIR}/static-ldflag)" && \
    export LIBCLANG_PATH \
           OPENSSL_INCLUDE_DIR=${DEPS_DIR}/include \
           OPENSSL_LIB_DIR=${DEPS_DIR}/lib \
           OPENSSL_STATIC=1 \
           NGX_ACME_STATE_PREFIX=/var/cache/nginx \
           PKG_CONFIG_PATH=${DEPS_DIR}/lib/pkgconfig && \
    ./configure \
        --with-pcre=../pcre2-${PCRE2_VERSION} \
        --with-pcre-jit \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --user=nginx \
        --group=nginx \
        --with-control-api \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_json_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        `# dynamic modules of nginx:mainline-alpine, here built in:` \
        --with-http_geoip_module \
        --with-stream_geoip_module \
        --with-http_image_filter_module \
        --with-http_xslt_module \
        --add-module=../njs-${NJS_VERSION}/nginx \
        --add-module=../nginx-acme-${NGINX_ACME_VERSION} \
        --with-cc-opt="${STATIC_LDFLAG} -Os ${HARDENING_CFLAGS} -Wformat -Werror=format-security -I${DEPS_DIR}/include -I${DEPS_DIR}/include/quickjs -I${DEPS_DIR}/include/libxml2" \
        --with-ld-opt="${STATIC_LDFLAG} -L${WRAP_DIR} -L${DEPS_DIR}/lib -Wl,--as-needed,-O1,--sort-common,-z,relro,-z,now" \
    && \
    sed -i 's/-Wl,-E//g' objs/Makefile && \
    make -j"$(nproc)" && \
    strip objs/nginx && \
    make DESTDIR=${OUTPUT_DIR} install

WORKDIR /usr/src

RUN echo ">> do something after builds ..." && \
    rmdir ${OUTPUT_DIR}/dev 2>/dev/null || true && \
    mkdir -p ${OUTPUT_DIR}/var/cache/nginx ${OUTPUT_DIR}/var/log/nginx ${OUTPUT_DIR}/usr/share/nginx ${OUTPUT_DIR}/etc/nginx/conf.d ${OUTPUT_DIR}/etc/ssl && \
    mv ${OUTPUT_DIR}/etc/nginx/html ${OUTPUT_DIR}/usr/share/nginx/html && \
    find ${OUTPUT_DIR}/etc/nginx -name "*.default" -delete && \
    mv ${OUTPUT_DIR}/etc/nginx/nginx.conf ${OUTPUT_DIR}/etc/nginx/nginx.conf.default && \
    `# like official image: log files are symlinks to stdout/stderr` \
    ln -sf /dev/stdout ${OUTPUT_DIR}/var/log/nginx/access.log && \
    ln -sf /dev/stderr ${OUTPUT_DIR}/var/log/nginx/error.log && \
    `# OpenSSL default CA bundle (OPENSSLDIR=/etc/ssl), used e.g. by acme_issuer (default: system CA bundle)` \
    ln -sf certs/ca-certificates.crt ${OUTPUT_DIR}/etc/ssl/cert.pem && \
    file ${OUTPUT_DIR}/usr/sbin/nginx && \
    ${OUTPUT_DIR}/usr/sbin/nginx -V && \
    ${OUTPUT_DIR}/usr/sbin/nginx -help

COPY <<EOF /nginx/etc/nginx/nginx.conf

user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log notice;
pid        /run/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  65;

    #gzip  on;

    #server_tokens off;

    include /etc/nginx/conf.d/*.conf;
}

EOF

COPY <<EOF /nginx/etc/nginx/conf.d/default.conf
# HTTP server
server {
    listen       80;
    listen  [::]:80;
    server_name  localhost;

    #charset koi8-r;

    #access_log  /var/log/nginx/access.log  main;

    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }

    #error_page  404              /404.html;

    # redirect server error pages to the static page /50x.html
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }

    # proxy the PHP scripts to Apache listening on 127.0.0.1:80
    #
    #location ~ \\.php$ {
    #    proxy_pass   http://127.0.0.1;
    #}

    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
    #
    #location ~ \\.php$ {
    #    root           html;
    #    fastcgi_pass   127.0.0.1:9000;
    #    fastcgi_index  index.php;
    #    fastcgi_param  SCRIPT_FILENAME  /scripts\$fastcgi_script_name;
    #    include        fastcgi_params;
    #}

    # deny access to .htaccess files, if Apache's document root
    # concurs with nginx's one
    #
    #location ~ /\\.ht {
    #    deny  all;
    #}

    location /nginx_status {
        stub_status on;   
        access_log off;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        allow ::1;
        allow fc00::/7;
        deny all;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { log_not_found off; }
}

# HTTPS server
#server {
#    listen       443 ssl;
#    listen  [::]:443 ssl;
#    server_name  localhost;
#
#    ssl_certificate      /etc/ssl/ssl.crt;
#    ssl_certificate_key  /etc/ssl/ssl.key;
#
#    ssl_session_cache    shared:SSL:1m;
#    ssl_session_timeout  5m;
#
#    ssl_ciphers  HIGH:!aNULL:!MD5;
#    ssl_prefer_server_ciphers  on;
#
#    #charset koi8-r;
#
#    #access_log  /var/log/nginx/access.log  main;
#
#    location / {
#        root   /usr/share/nginx/html;
#        index  index.html index.htm;
#    }
#
#    #error_page  404              /404.html;
#
#    # redirect server error pages to the static page /50x.html
#    #
#    error_page   500 502 503 504  /50x.html;
#    location = /50x.html {
#        root   /usr/share/nginx/html;
#    }
#
#    # proxy the PHP scripts to Apache listening on 127.0.0.1:80
#    #
#    #location ~ \\.php$ {
#    #    proxy_pass   http://127.0.0.1;
#    #}
#
#    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
#    #
#    #location ~ \\.php$ {
#    #    root           html;
#    #    fastcgi_pass   127.0.0.1:9000;
#    #    fastcgi_index  index.php;
#    #    fastcgi_param  SCRIPT_FILENAME  /scripts\$fastcgi_script_name;
#    #    include        fastcgi_params;
#    #}
#
#    # deny access to .htaccess files, if Apache's document root
#    # concurs with nginx's one
#    #
#    #location ~ /\\.ht {
#    #    deny  all;
#    #}
#
#    location /nginx_status {
#        stub_status on;   
#        access_log off;
#        allow 127.0.0.1;
#        allow 10.0.0.0/8;
#        allow 172.16.0.0/12;
#        allow 192.168.0.0/16;
#        allow ::1;
#        allow fc00::/7;
#        deny all;
#    }
#
#    location = /favicon.ico { log_not_found off; access_log off; }
#    location = /robots.txt { log_not_found off; }
#}

EOF

COPY <<EOF /nginx/usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is working. 
Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
This is a static nginx build, for more details see:
<a href="https://github.com/Tob1as/static-nginx/">https://github.com/Tob1as/static-nginx</a>.</p>

<p><em>Have Fun!</em></p>
</body>
</html>
EOF

# no /run and /var/run in the base image (created by "make install" from --pid-path):
# - /var/run is a symlink to /run in Alpine/Debian ("COPY --from" ERROR: failed to build: failed to solve: cannot copy to non-directory: /var/run)
# - "COPY --from" would overwrite owner/mode of an existing /run in the target image
# the images based on this create /run themselves, Alpine/Debian already have it
RUN rm -rf ${OUTPUT_DIR}/run ${OUTPUT_DIR}/var/run && \
    tree ${OUTPUT_DIR} && \
    VERSION_FILE="/tmp/versions.txt" && \
    { \
      echo "NGINX_VERSION=${NGINX_VERSION}" ; \
      echo "PCRE2_VERSION=${PCRE2_VERSION}" ; \
      echo "ZLIB_VERSION=${ZLIB_VERSION}" ; \
      echo "OPENSSL_VERSION=${OPENSSL_VERSION}" ; \
      echo "LIBMAXMINDDB_VERSION=${LIBMAXMINDDB_VERSION}" ; \
      echo "LIBGEOIP_VERSION=${LIBGEOIP_VERSION}" ; \
      echo "LIBGD_VERSION=${LIBGD_VERSION}" ; \
      echo "QUICKJS_VERSION=${QUICKJS_VERSION}" ; \
      echo "NJS_VERSION=${NJS_VERSION}" ; \
      echo "NGINX_ACME_VERSION=${NGINX_ACME_VERSION}" ; \
      echo "LIBXML2_VERSION=${LIBXML2_VERSION}" ; \
      echo "LIBXSLT_VERSION=${LIBXSLT_VERSION}" ; \
    } > "${VERSION_FILE}" && \
    cat "${VERSION_FILE}"


FROM scratch AS binary

ARG VCS_REF
ARG BUILD_DATE

ARG NGINX_VERSION
ARG PCRE2_VERSION
ARG ZLIB_VERSION
ARG OPENSSL_VERSION
ARG LIBMAXMINDDB_VERSION
ARG LIBGEOIP_VERSION
ARG LIBGD_VERSION
ARG QUICKJS_VERSION
ARG NJS_VERSION
ARG NGINX_ACME_VERSION

LABEL org.opencontainers.image.title="Static NGINX" \
      org.opencontainers.image.authors="Tobias Hargesheimer <docker@ison.ws>" \
      org.opencontainers.image.version="${NGINX_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.description="Baseimage with Static NGINX${NGINX_VERSION:+ ${NGINX_VERSION}} build with pcre2${PCRE2_VERSION:+-${PCRE2_VERSION}}, zlib${ZLIB_VERSION:+-${ZLIB_VERSION}}, openssl${OPENSSL_VERSION:+-${OPENSSL_VERSION}}, libmaxminddb${LIBMAXMINDDB_VERSION:+-${LIBMAXMINDDB_VERSION}}, libgeoip${LIBGEOIP_VERSION:+-${LIBGEOIP_VERSION}}, libgd${LIBGD_VERSION:+-${LIBGD_VERSION}}, quickjs${QUICKJS_VERSION:+-${QUICKJS_VERSION}}, njs${NJS_VERSION:+-${NJS_VERSION}} and nginx-acme${NGINX_ACME_VERSION:+-${NGINX_ACME_VERSION}} on Debian" \
      org.opencontainers.image.documentation="https://github.com/Tob1as/static-nginx/" \
      org.opencontainers.image.base.name="scratch" \
      org.opencontainers.image.licenses="BSD-2-Clause license" \
      org.opencontainers.image.url="https://hub.docker.com/r/tobi312/static-nginx" \
      org.opencontainers.image.source="https://github.com/Tob1as/static-nginx/"

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /nginx /nginx
COPY --from=builder /tmp/versions.txt /tmp/versions.txt

COPY <<EOF /etc/passwd
root:x:0:0:root:/root:/sbin/nologin
nginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin
EOF

COPY <<EOF /etc/group
root:x:0:root
nginx:x:101:nginx
EOF
