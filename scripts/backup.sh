#!/bin/bash

incremental=${INCREMENTAL:-true}
compress_threads=${COMPRESS_THREADS:-0}
target_dir="${TARGET_DIR:-/backup}"
full_date_pattern=${FULL_DATE_PATTERN:-"%Y_week%W"}
full_dir="${target_dir}/$(date +${full_date_pattern})"
incremental_date_pattern=${INCREMENTAL_DATE_PATTERN:-"%Y%m%d_baseweek_%W"}
incremental_dir="${target_dir}/$(date +${incremental_date_pattern})"
db_user=${MYSQL_USER:-"root"}
db_password="${MYSQL_PASSWORD}"
debug=${DEBUG:-false}
xtrabackup=xtrabackup
log_prefix='date +%FT%T%z'

printf "$(${log_prefix}) INFO: starting";

if [ "${MYSQL_PASSWORD_FILE}" ]; then
    db_password="$(< "${MYSQL_PASSWORD_FILE}")"
fi

if [ ! -d "${full_dir}" ]; then
    OPT="--target-dir='${full_dir}'"
    printf " full backup"
elif [ ${incremental} ]; then
    OPT="--incremental-basedir='${full_dir}' \
        --target-dir='${incremental_dir}'"
    printf " incremental backup"
fi

if [ ${compress_threads} -gt 0 ]; then
    OPT="--compress --compress-threads=${compress_threads} ${OPT}"
    echo " with compression enabled"
fi

command="${xtrabackup} --backup \
     --user='${db_user}' \
     --password='${db_password}' \
     ${OPT}";

if [ "${DEBUG}" ]; then echo "$(${log_prefix}) DEBUG: $command"; fi

$command

echo "$(${log_prefix}) INFO: backup process finished";