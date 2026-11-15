FROM ubuntu:24.04

LABEL maintainer="Wolfgang Gassler"
LABEL description="XtraBackup based MySQL 9.7 backup image"

# Install the newest backup tool in the matching LTS series.
# https://docs.percona.com/percona-xtrabackup/9.7/apt-repo.html
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg2 lsb-release cron \
    && rm -rf /etc/cron.* \
    && curl -fsSLo /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb \
    && dpkg -i /tmp/percona-release.deb \
    && percona-release enable-only pxb-97-lts release \
    && apt-get update \
    && apt-get install -y --no-install-recommends percona-xtrabackup-97 zstd lz4 \
    && xtrabackup --version \
    && rm -f /tmp/percona-release.deb \
    && rm -rf /var/lib/apt/lists/*

COPY build/install-upload-tools.sh /tmp/install-upload-tools.sh
RUN bash /tmp/install-upload-tools.sh && rm /tmp/install-upload-tools.sh

COPY scripts /scripts
COPY modules /modules

VOLUME /backup /var/lib/mysql
WORKDIR /backup

CMD ["/scripts/start.sh"]
