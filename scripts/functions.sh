#!/bin/bash

# Accept executable paths and legacy whitespace-separated commands such as
# "node /gs-upload". Hook arguments remain literal; no shell evaluation is used.
run_hook () {
    local hook=$1
    shift
    if [ -f "${hook}" ]; then
        "${hook}" "$@"
    else
        local -a hook_command
        read -r -a hook_command <<< "${hook}"
        if [ "${#hook_command[@]}" -eq 0 ]; then
            return 127
        fi
        "${hook_command[@]}" "$@"
    fi
}

get_lsn () {
    cat "$1" | grep to_lsn | cut -d ' ' -f 3
}

upload_is_configured () {
    [ -n "${UPLOAD_DESTINATION:-}${GS_BUCKET_NAME:-}" ]
}

is_builtin_upload_hook () {
    case "$1" in
        'node /gs-upload'|'node /gs-upload/index.js'|'node /scripts/gs-upload'|'node /scripts/gs-upload/index.js'|'/modules/upload.sh')
            return 0 ;;
        *) return 1 ;;
    esac
}

checkpoint_file () {
    local name
    for name in mariadb_backup_checkpoints xtrabackup_checkpoints; do
        if [ -f "$1/${name}" ]; then
            printf '%s\n' "$1/${name}"
            return 0
        fi
    done
    return 1
}

backups_by_type () {
    local dir checkpoint
    for dir in "${target_dir}"/*; do
        [ -d "${dir}" ] || continue
        checkpoint=$(checkpoint_file "${dir}") || continue
        if grep -qF "backup_type = $1" "${checkpoint}"; then
            printf '%s\n' "${checkpoint}"
        fi
    done
}

full_backups () {
    backups_by_type "full-backuped"
}

inc_backups () {
    backups_by_type "incremental"
}

count_backups () {
    echo "$1" | wc -l
}

find_newest_backup () {
    greatest_backup=
    greatest_lsn=0

    for backup in $1;
    do
        current_lsn=$(get_lsn ${backup})
        if [ "${current_lsn}" -gt "${greatest_lsn}" ]; then
            greatest_backup="${backup}"
            greatest_lsn="${current_lsn}"
        fi
    done;    
    echo ${greatest_backup}
}
