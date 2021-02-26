FROM mariadb:10.5

LABEL maintainer="Wolfgang Gassler"
LABEL description="Mariabackup based backup docker image to create incremental backups periodically of MariaDB"

RUN apt-get update \
    && apt-get -y install cron curl \
    && rm -rf /etc/cron.* 

COPY scripts /scripts

VOLUME /backup /var/lib/mysql
WORKDIR /backup

ENTRYPOINT []
CMD ["/scripts/start.sh"]