# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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