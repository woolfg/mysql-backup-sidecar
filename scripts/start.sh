#!/bin/bash

CRON_PATTERN={$CRON_PATTERN:-"0 0 * * *"}

rm -rf /var/spool/cron/crontabs && mkdir -m 0644 -p /var/spool/cron/crontabs

echo -e "${CRON_PATTERN} /scripts/backup.sh\n" > /var/spool/cron/crontabs/CRON_STRINGS

chmod -R 0644 /var/spool/cron/crontabs

crond -s /var/spool/cron/crontabs