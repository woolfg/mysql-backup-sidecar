# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-11-15

### Added

- MySQL 8.4 and 9.7 LTS images with matching XtraBackup series
- MariaDB 10.11, 11.4, 11.8 and 12.3 LTS images with matching backup tools ([#26](https://github.com/woolfg/mysql-backup-sidecar/issues/26))
- Pinned rclone and optional ZIP uploads in all maintained images, with a generic destination for multiple storage backends ([#28](https://github.com/woolfg/mysql-backup-sidecar/issues/28))
- GCS compatibility settings, ZIP contents/naming, and legacy `node /gs-upload` hook support in the built-in uploader
- CI checks for full/incremental, compressed/uncompressed GCS ZIP upload/download/database restores, generic local destinations, remote failures and rotation; weekly image rebuilds

### Compatibility and upgrade notes

- This release publishes only `mysql-8.4`, `mysql-9.7`, `mariadb-10.11`, `mariadb-11.4`, `mariadb-11.8` and `mariadb-12.3` image suffixes on `linux/amd64`. MySQL 8.0 and MariaDB 10.4/10.5/10.8/10.9 are retired from routine builds. Existing tags and legacy Dockerfiles remain available, but there are no `0.4.0` images for those EOL series. Upgrading a database series requires a separate database upgrade; keep the matching older tools for restoring older backups.
- Backup, log-capture and hook failures now return nonzero status and prevent scheduled rotation. Before/after hooks must return zero on success; a failing before hook prevents the backup, and a failing after hook prevents upload and rotation.
- `BACKUP_DIR` is now honored and takes precedence over the legacy `BACKUP` variable. Review the destination if either setting previously relied on the old fallback to `/backup`.
- `DELETE_OLDER_DAYS` now applies to both `archive` and `current`. When incremental mode is enabled and no sufficiently recent full backup exists, deletion from `current` is skipped to preserve the backup chain. Review retention settings before upgrading.
- Nonempty backup target directories are rejected. Move failed backup directories aside or choose a new directory name before retrying a backup; upload-only retries can use the completed local backup directly.
- Backup credentials and exclusion arguments are passed literally instead of through shell evaluation. Hook commands support executable paths and whitespace-separated arguments; use wrapper scripts for shell expansion or globbing.
- New MySQL LTS images use Ubuntu 24.04; the legacy MySQL 8.0 Dockerfiles use Debian 12 instead of Debian 10. Custom hooks depending on OS-specific tools or packages may need adjustment.
- Setting `GS_BUCKET_NAME` now enables the built-in GCS uploader. Remove duplicate upload logic from custom hooks when enabling it. ZIPs are staged locally, so allow disk space for a complete archive; upload failures stop rotation, and missing uploads require manual retry in this initial implementation.
- The separate `woolfg/mysql-backup-sidecar-gs` image repository is not released, deleted or retagged by this release. Existing uploaded ZIPs remain usable; migrating to the main image preserves `GS_*` settings, archive contents and object names.

### Fixed

- Recognize `mariadb-backup`, retain the `mariabackup` fallback, and support `mariadb_backup_checkpoints` for incremental selection and rotation
- Exclude failed backup checkpoints from incremental backup selection
- Preserve the full backup needed by incremental backups when applying retention
- Preserve legacy hook commands while supporting executable paths containing spaces

## [0.3.8] - 2023-10-19

- Added env variable `DELETE_OLDER_DAYS` which allows to delete backups older than x days [#25](https://github.com/woolfg/mysql-backup-sidecar/issues/25)

## [0.3.7] - 2023-08-21

- Pump to percona-xtrabackup-80=8.0.34-29 which supports MySQL 8.0.35 and higher

## [0.3.6] - 2023-08-09

- Trigger new build to support new MySQL 8 versions (8.0.33)
- Output version of XtraBackup when running script

## [0.3.5] - 2023-03-05

- Added `before-script` option which allows to execute a custom script before each backup (thanks to @lightningspirit)
- Smaller fixes
- Rebuild contains new MySQL version (>8.0.27) which supports new default password schema

## [0.3.4] - 2021-03-04

- Small logging bug fixed

## [0.3.3] - 2021-03-02

- Add `curl` as basic tool for "after-scripts" in MariaDB images
- Add backup directory as an argument for the after backup script.

## [0.3.2] - 2021-02-01

### Added
- MariaDB 10.5 support added (thanks to @luzrain)

## [0.3.1] - 2020-10-27

### Added
- fix #3 - After script option which allows to execute a custom script after each backup (thanks to @guillaumelamirand)
- arm64v8 dockerfiles added (thanks to @guillaumelamirand)

### Changed
- fix #7 - Rebuild of MySQL version to support new redo log format of MySQL/XtraBackup 8.0.20. For more information see https://www.percona.com/blog/2020/04/28/percona-xtrabackup-8-x-and-mysql-8-0-20/ 

## [0.3.0] - 2020-02-24
### Added
- First public usable version
