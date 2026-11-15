FROM mariadb:10.11

LABEL maintainer="Wolfgang Gassler"
LABEL description="MariaDB 10.11 backup image"

# qpress is needed to restore backups made with COMPRESS_THREADS > 0.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates cron curl gnupg2 lsb-release \
    && rm -rf /etc/cron.* \
    && curl -fsSLo /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb \
    && dpkg -i /tmp/percona-release.deb \
    && percona-release enable-only original release \
    && apt-get update \
    && apt-get install -y --no-install-recommends qpress \
    && mariadb-backup --version \
    && rm -f /tmp/percona-release.deb \
    && rm -rf /var/lib/apt/lists/*

COPY scripts /scripts

VOLUME /backup /var/lib/mysql
WORKDIR /backup

ENTRYPOINT []
CMD ["/scripts/start.sh"]
