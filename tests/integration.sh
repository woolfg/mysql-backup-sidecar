#!/bin/bash
# Usage: bash tests/integration.sh mysql|mariadb VERSION [BUILT_SIDECAR_IMAGE]
# Uses only newly created containers, networks and named volumes; no host backups.
set -euo pipefail

family=${1:?Specify mysql or mariadb}
version=${2:?Specify the database series}
case "${family}" in
    mysql) client=mysql; tool=xtrabackup ;;
    mariadb) client=mariadb; tool=mariadb-backup ;;
    *) echo "Unknown database family: ${family}" >&2; exit 1 ;;
esac
db_image="${family}:${version}"
sidecar=${3:-sidecar-test:${family}-${version}}
root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -lt 3 ]; then
    docker build -t "${sidecar}" -f "${root}/${family}/${version}/Dockerfile" "${root}"
fi

prefix="sidecar-test-$(date +%s)-$$-${RANDOM}"
password="sidecar-integration-only"
containers=()
volumes=()
cleanup() {
    result=$?
    trap - EXIT
    if [ "${result}" -ne 0 ]; then
        for container in "${containers[@]}"; do docker logs "${container}" 2>&1 || true; done
    fi
    for container in "${containers[@]}"; do docker rm -f "${container}" >/dev/null 2>&1 || true; done
    for volume in "${volumes[@]}"; do docker volume rm "${volume}" >/dev/null 2>&1 || true; done
    docker network rm "${prefix}" >/dev/null 2>&1 || true
    exit "${result}"
}
trap cleanup EXIT
docker network create "${prefix}" >/dev/null

sql() {
    docker exec -e MYSQL_PWD="${password}" "$1" "${client}" -h127.0.0.1 -uroot -Nse "$2"
}
wait_ready() {
    local container=$1
    for ((attempt=0; attempt<90; attempt++)); do
        if sql "${container}" 'SELECT 1' >/dev/null 2>&1; then return; fi
        sleep 2
    done
    echo "Database did not become ready: ${container}" >&2
    return 1
}

for compression in 0 1; do
    source_db="${prefix}-${compression}-source"
    source_data="${source_db}-data"
    backup_data="${source_db}-backups"
    for volume in "${source_data}" "${backup_data}"; do
        volumes+=("${volume}")
        docker volume create "${volume}" >/dev/null
    done
    containers+=("${source_db}")
    docker run -d --name "${source_db}" --network "${prefix}" \
        -e MYSQL_ROOT_PASSWORD="${password}" -e MYSQL_ROOT_HOST=% \
        -v "${source_data}:/var/lib/mysql" "${db_image}" >/dev/null
    wait_ready "${source_db}"
    sql "${source_db}" "CREATE DATABASE restore_test;
        CREATE TABLE restore_test.records (id INT PRIMARY KEY, value VARCHAR(32)) ENGINE=InnoDB;
        INSERT INTO restore_test.records VALUES (1, 'full');"
    if [ "${family}" = mariadb ]; then
        sql "${source_db}" "CREATE TABLE restore_test.aria_records (id INT PRIMARY KEY) ENGINE=Aria;
            INSERT INTO restore_test.aria_records VALUES (42);"
    fi

    backup() {
        docker run --rm --network "${prefix}" \
            -v "${source_data}:/var/lib/mysql:ro" -v "${backup_data}:/backup" \
            -e MYSQL_HOST="${source_db}" -e MYSQL_USER=root -e MYSQL_PASSWORD="${password}" \
            -e COMPRESS_THREADS="${compression}" -e INCREMENTAL="$1" \
            -e DIR_DATE_PATTERN="$2" -e FULL_BACKUP_DATE_RESULT=never \
            "${sidecar}" /scripts/backup.sh
    }
    backup false full
    sql "${source_db}" "UPDATE restore_test.records SET value='updated' WHERE id=1;
        INSERT INTO restore_test.records VALUES (2, 'incremental');"
    backup true incremental

    docker run --rm -v "${backup_data}:/backup" "${sidecar}" bash -ec '
        source /scripts/functions.sh
        grep -q "backup_type = incremental" "$(checkpoint_file /backup/current/incremental)"
    '
    if [ "${compression}" -gt 0 ]; then
        docker run --rm -v "${backup_data}:/backup:ro" "${sidecar}" bash -ec '
            for dir in full incremental; do
                [ -n "$(find "/backup/current/$dir" -type f \( -name "*.qp" -o -name "*.zst" -o -name "*.lz4" \) -print -quit)" ]
            done
        '
    fi

    for restore in full incremental; do
        restore_data="${source_db}-${restore}-restored"
        volumes+=("${restore_data}")
        docker volume create "${restore_data}" >/dev/null
        # Prepare independent copies, because preparation modifies the backup.
        docker run --rm -v "${backup_data}:/backup:ro" -v "${restore_data}:/restore" \
            -e BACKUP_TOOL="${tool}" -e RESTORE_KIND="${restore}" -e COMPRESSION="${compression}" \
            "${sidecar}" bash -euc '
                mkdir -p /tmp/full /tmp/incremental
                cp -a /backup/current/full/. /tmp/full/
                cp -a /backup/current/incremental/. /tmp/incremental/
                if [ "$COMPRESSION" -gt 0 ]; then
                    "$BACKUP_TOOL" --decompress --remove-original --target-dir=/tmp/full
                    "$BACKUP_TOOL" --decompress --remove-original --target-dir=/tmp/incremental
                fi
                if [ "$BACKUP_TOOL" = xtrabackup ] && [ "$RESTORE_KIND" = incremental ]; then
                    "$BACKUP_TOOL" --prepare --apply-log-only --target-dir=/tmp/full
                    "$BACKUP_TOOL" --prepare --target-dir=/tmp/full --incremental-dir=/tmp/incremental
                else
                    "$BACKUP_TOOL" --prepare --target-dir=/tmp/full
                    if [ "$RESTORE_KIND" = incremental ]; then
                        "$BACKUP_TOOL" --prepare --target-dir=/tmp/full --incremental-dir=/tmp/incremental
                    fi
                fi
                "$BACKUP_TOOL" --copy-back --target-dir=/tmp/full --datadir=/restore
            '
        docker run --rm --user root --entrypoint bash -v "${restore_data}:/restore" \
            "${db_image}" -ec 'chown -R mysql:mysql /restore'
        restored_db="${restore_data}-db"
        containers+=("${restored_db}")
        docker run -d --name "${restored_db}" --network "${prefix}" \
            -v "${restore_data}:/var/lib/mysql" "${db_image}" >/dev/null
        wait_ready "${restored_db}"
        actual=$(sql "${restored_db}" "SELECT GROUP_CONCAT(CONCAT(id, ':', value) ORDER BY id) FROM restore_test.records")
        expected=1:full
        if [ "${restore}" = incremental ]; then expected=1:updated,2:incremental; fi
        if [ "${actual}" != "${expected}" ]; then
            echo "Restore mismatch: expected ${expected}, got ${actual}" >&2
            exit 1
        fi
        if [ "${family}" = mariadb ]; then
            [ "$(sql "${restored_db}" 'SELECT id FROM restore_test.aria_records')" = 42 ]
        fi
        docker stop "${restored_db}" >/dev/null
        echo "PASS: ${family} ${version}, compression=${compression}, restore=${restore}"
    done
    # A newer full backup must archive the old full and retire its incrementals.
    sql "${source_db}" "INSERT INTO restore_test.records VALUES (3, 'new-full');"
    if [ "${family}" = mariadb ]; then
        # Tiny MariaDB datasets can keep the same checkpoint across online backups.
        # A clean restart advances it deterministically for the rotation fixture.
        docker restart "${source_db}" >/dev/null
        wait_ready "${source_db}"
    fi
    backup false replacement
    docker run --rm -v "${backup_data}:/backup" "${sidecar}" /scripts/rotate.sh
    docker run --rm -v "${backup_data}:/backup:ro" "${sidecar}" bash -ec '
        source /scripts/functions.sh
        checkpoint_file /backup/archive/full >/dev/null
        checkpoint_file /backup/current/replacement >/dev/null
        [ ! -e /backup/current/full ]
        [ ! -e /backup/current/incremental ]
    '
    echo "PASS: ${family} ${version}, compression=${compression}, rotation"
    docker stop "${source_db}" >/dev/null
done
