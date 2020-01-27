#!/bin/bash

CRON_PATTERN=${CRON_SCHEDULE:-"0 0 * * *"}

CRON_FILE=/etc/crontab

echo -e "${CRON_SCHEDULE} root /scripts/backup.sh && /scripts/rotate.sh\n" > ${CRON_FILE}

echo "starting cron to execute xtrabackup periodically (${CRON_SCHEDULE})"

cron -f