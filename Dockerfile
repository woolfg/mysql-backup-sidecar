FROM debian:10-slim

LABEL maintainer="Wolfgang Gassler"
LABEL description="XtraBackup based MySQL / MariaDB backup docker image to create incremental backups periodically"

# installing xtrabackup according to https://www.percona.com/doc/percona-xtrabackup/8.0/installation/apt_repo.html

RUN wget https://repo.percona.com/apt/percona-release_latest.$(lsb_release -sc)_all.deb \
    && dpkg -i percona-release_latest.$(lsb_release -sc)_all.deb \
    && percona-release enable-only tools release \
    && apt-get update \
    && apt-get install percona-xtrabackup-80 crond

COPY scripts /

VOLUME /backup /var/lib/mysql
WORKDIR /backup

CMD ["/scripts/start.sh]