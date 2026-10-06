# civikitchen Standalone plus the PHP clients for every cache backend under test.
FROM ghcr.io/jfilter/civikitchen@sha256:663150544bea40b4f3d595bffe503328316f9a1803b91426bc69d3c5cc5ad68d

RUN apt-get update \
 && apt-get install -y --no-install-recommends libmemcached-dev zlib1g-dev libssl-dev iproute2 \
 && rm -rf /var/lib/apt/lists/* \
 && printf '\n' | pecl install redis memcached apcu \
 && docker-php-ext-enable redis memcached apcu \
 && rm -f /usr/local/etc/php/conf.d/docker-php-ext-pcov.ini

COPY bench.ini /usr/local/etc/php/conf.d/zz-bench.ini
COPY cache-settings.php /usr/local/share/bench/cache-settings.php
COPY runtime.php /var/www/html/bench-runtime.php
# Form for the afform-contact scenario, in the site-local afform directory ([civicrm.files]/ang).
COPY --chown=www-data:www-data afform/ /var/www/html/public/ang/

# CORE other than "stable" replaces civikitchen's site code with core/<CORE>.tar.gz (bench/fetch-core.sh).
ARG CORE=stable
COPY core/ /tmp/core/
RUN if [ "$CORE" != stable ]; then \
      rm -rf /var/www/html/core /var/www/html/ext \
      && tar -xzf "/tmp/core/$CORE.tar.gz" -C /var/www/html --strip-components=1 --exclude=civicrm-standalone/private \
      && chown -R www-data:www-data /var/www/html; \
    fi \
 && rm -rf /tmp/core

COPY patches/cache-tiers.patch /usr/local/share/bench/
RUN patch -d /var/www/html/core -p1 --forward < /usr/local/share/bench/cache-tiers.patch
