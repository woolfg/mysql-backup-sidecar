#!/bin/bash

CRON_PATTERN=${CRON_PATTERN:-"0 0 * * *"}

CRON_FILE=/etc/crontab

echo -e "${CRON_PATTERN} root /scripts/backup.sh\n" > ${CRON_FILE}

echo "starting cron to execute xtrabackup periodically (${CRON_PATTERN})"

cron -f