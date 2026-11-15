#!/bin/bash
# Also accepts the existing AFTER_BACKUP_SCRIPT interface: status, output, directory.
set -euo pipefail
source "$(dirname "$0")/../scripts/functions.sh"

if [ "${1:-}" != succeed ]; then
    echo "ERROR: upload requires a successful backup" >&2
    exit 1
fi

destination=${UPLOAD_DESTINATION:-}
if [ -z "${destination}" ] && [ -n "${GS_BUCKET_NAME:-}" ]; then
    # Use bucket IAM and avoid bucket/destination probes for existing upload-only keys.
    export RCLONE_CONFIG_SIDECAR_GCS_TYPE=googlecloudstorage
    export RCLONE_CONFIG_SIDECAR_GCS_BUCKET_POLICY_ONLY=${RCLONE_CONFIG_SIDECAR_GCS_BUCKET_POLICY_ONLY:-true}
    export RCLONE_CONFIG_SIDECAR_GCS_NO_CHECK_BUCKET=true
    if [ -n "${GS_KEY_FILE:-}" ]; then
        export RCLONE_CONFIG_SIDECAR_GCS_SERVICE_ACCOUNT_FILE="${GS_KEY_FILE}"
    else
        export RCLONE_CONFIG_SIDECAR_GCS_ENV_AUTH=true
    fi
    destination="sidecar_gcs:${GS_BUCKET_NAME}"
fi
if [ -z "${destination}" ]; then
    echo "ERROR: set UPLOAD_DESTINATION or GS_BUCKET_NAME to upload backups" >&2
    exit 1
fi

backup_path=${3:?Specify the completed backup directory as the third argument}
backup_path=$(cd -- "${backup_path}" && pwd)
full_only=${UPLOAD_FULLBACKUPS_ONLY:-${GS_FULLBACKUPS_ONLY:-false}}
case "${full_only}" in
    true)
        checkpoint=$(checkpoint_file "${backup_path}") || {
            echo "ERROR: backup checkpoint file is missing" >&2
            exit 1
        }
        if ! grep -q '^backup_type = full-backuped$' "${checkpoint}"; then
            echo "INFO: skipping upload of incremental backup (full backups only)"
            exit 0
        fi
        ;;
    false) ;;
    *) echo "ERROR: UPLOAD_FULLBACKUPS_ONLY must be true or false" >&2; exit 1 ;;
esac

project=${UPLOAD_PROJECT_NAME:-${GS_PROJECT_NAME:-${HOSTNAME:-mysql-backup}}}
timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
object_name="${project}/${timestamp}_${project}.zip"
case "${destination}" in
    *:) remote_path="${destination}${object_name}" ;;
    *) remote_path="${destination%/}/${object_name}" ;;
esac
staging_root=${UPLOAD_TMP_DIR:-${TMPDIR:-/tmp}}
mkdir -p -- "${staging_root}"
staging_root=$(cd -- "${staging_root}" && pwd)
work_dir=$(mktemp -d "${staging_root%/}/sidecar-upload.XXXXXX")
trap 'rm -rf "${work_dir}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
case "${work_dir}/" in
    "${backup_path}/"*) echo "ERROR: ZIP staging directory must be outside the backup being archived" >&2; exit 1 ;;
esac

# Archive the directory contents at the ZIP root, as the existing GS uploader does.
archive="${work_dir}/backup.zip"
echo "INFO: creating ZIP for completed backup ${backup_path}"
(cd -- "${backup_path}" && zip -q -r -y "${archive}" .)
echo "INFO: uploading ${object_name}"
if rclone copyto "${archive}" "${remote_path}" --no-check-dest --no-traverse; then
    echo "INFO: upload completed"
else
    upload_status=$?
    echo "ERROR: backup upload failed (exit ${upload_status}); rotation will not run" >&2
    exit "${upload_status}"
fi
