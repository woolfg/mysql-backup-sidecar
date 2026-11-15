#!/bin/bash

get_lsn () {
    cat "$1" | grep to_lsn | cut -d ' ' -f 3
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
