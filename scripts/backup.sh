#!/bin/bash

source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/functions.sh"

echo "$(${log_prefix}) INFO: *********** starting backup";

current_dir="${target_dir}/$(date +${dir_date_pattern})"
run_incremental=false

# Never overwrite an existing backup or reuse a partially written directory.
if [ -d "${current_dir}" ] && [ -n "$(ls -A "${current_dir}")" ]; then
    >&2 echo "$(${log_prefix}) ERROR: Backup target is not empty: ${current_dir}"
    exit 1
fi

if [ ! -z "${before_backup_script}" ]; then
    echo "$(${log_prefix}) INFO: call before backup script"
    run_hook "${before_backup_script}" "${current_dir}" || exit $?
fi

# output version information of xtrabackup
"${xtrabackup}" --version || exit $?

if [ "${incremental}" = true ]; then
    #check if a full backup has to be done again
    if [ "$(date +${full_backup_date_format})" = "${full_backup_date_result}" ]; then
        echo "$(${log_prefix}) INFO: Full backup condition true, so let's do a full backup"
    else
        #find directory of previous backup
        full_backups=$(full_backups)
        newest_backup=$(find_newest_backup "${full_backups}")
        current_base_dir=$(dirname "${newest_backup}")
        if [ -d "${current_base_dir}" ] && [ -f "${newest_backup}" ]; then
            echo "$(${log_prefix}) INFO: using ${current_base_dir} as a base for the incremental backup"
            run_incremental=true
        else
            >&2 echo "$(${log_prefix}) ERROR: ${current_base_dir} can't be used as a base dir for an incremental backup, doing a full backup"
        fi
    fi
fi

mkdir -p "${current_dir}" || exit 1
printf "$(${log_prefix}) INFO: starting";

if [ "${run_incremental}" = true ]; then
    OPT=("--incremental-basedir=${current_base_dir}" "--target-dir=${current_dir}")
    printf " incremental backup"
else
    OPT=("--target-dir=${current_dir}")
    printf " full backup"
fi

if [ ${compress_threads} -gt 0 ]; then
    OPT+=(--compress "--compress-threads=${compress_threads}")
    echo " with compression enabled"
fi

if [ ! -z "${databases_exclude}" ]; then
    OPT+=("--databases-exclude=${databases_exclude}")
    echo " with databases exclude"
fi

tmp_output=$(mktemp) || exit 1
trap 'rm -f "${tmp_output}"' EXIT
"${xtrabackup}" --backup \
    "--user=${db_user}" \
    "--password=${db_password}" \
    "--host=${db_host}" \
    "--port=${db_port}" \
    "${OPT[@]}" 2>&1 | tee "${tmp_output}"
pipeline_status=("${PIPESTATUS[@]}")
backup_status=${pipeline_status[0]}
if [ "${backup_status}" -eq 0 ]; then
    backup_status=${pipeline_status[1]}
fi

# Failed backups must not become incremental bases or trigger deletion by rotation.
if [ "${backup_status}" -ne 0 ]; then
    for checkpoint in xtrabackup_checkpoints mariadb_backup_checkpoints; do
        if [ -f "${current_dir}/${checkpoint}" ]; then
            mv "${current_dir}/${checkpoint}" "${current_dir}/${checkpoint}.failed" || exit 1
        fi
    done
fi

if [ ! -z "${after_backup_script}" ]; then
    echo "$(${log_prefix}) INFO: call after backup script"
    output=$(cat "${tmp_output}")
    if [ "${backup_status}" -eq 0 ]
    then
        status="succeed"
    else
        status="failed"
    fi
    if upload_is_configured && is_builtin_upload_hook "${after_backup_script}"; then
        # The built-in module replaces the old Node.js hook and runs once below.
        hook_status=0
    else
        run_hook "${after_backup_script}" "${status}" "${output}" "${current_dir}"
        hook_status=$?
    fi
    if [ "${backup_status}" -eq 0 ]; then
        backup_status=${hook_status}
    fi
fi

if [ "${backup_status}" -eq 0 ] && upload_is_configured; then
    bash "$(dirname "$0")/../modules/upload.sh" succeed "" "${current_dir}"
    backup_status=$?
fi

if [ "${backup_status}" -ne 0 ]; then
    >&2 echo "$(${log_prefix}) ERROR: backup process failed (exit ${backup_status})"
else
    echo "$(${log_prefix}) INFO: backup process finished"
fi
exit "${backup_status}"
