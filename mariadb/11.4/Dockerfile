FROM mariadb:11.4

LABEL maintainer="Wolfgang Gassler"
LABEL description="MariaDB 11.4 backup image"

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

COPY build/install-upload-tools.sh /tmp/install-upload-tools.sh
RUN bash /tmp/install-upload-tools.sh && rm /tmp/install-upload-tools.sh

COPY scripts /scripts
COPY modules /modules

VOLUME /backup /var/lib/mysql
WORKDIR /backup

ENTRYPOINT []
CMD ["/scripts/start.sh"]
