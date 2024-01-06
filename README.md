# mysql-backup-sidecar

This backup docker container creates incremental and compressed MySQL or MariaDB backups without blocking the database during the backup procedure. It is based on `XtraBackup` https://www.percona.com/doc/percona-xtrabackup/2.4/index.html and the forked version for MariaDB `Mariabackup` https://mariadb.com/kb/en/mariabackup/. If you are not familiar with the underlying backup tools, please, read the documentation to understand what commands are executed on your DB server. 

## Features

- non-blocking backup procedure (using XtraBackup/Mariabackup).
- runs in a separated container
- configurable cron schedule (e.g. every night, every second night, etc)
- configurable backup cycles (incremental, full backups)
- backup rotation (e.g. delete incremental backups after a full backup)
- delete old backups automatically after some time to free up disk space
- supports docker credentials and environment based password definitions

## How to get started

To have a running backup system it is sufficient to define the following environment variables:

- `MYSQL_HOST`
- `MYSQL_USER`
- `MYSQL_PASSWORD`

Use the example `docker-compose` file in the `examples` folder to get started.

## Config

### Configuration variables

The following environment variables are supported (incl. example values) for configuring the backup system:

| **Key**                | **Example Value**           | **Description**                                                                      |
|------------------------|-----------------------------|--------------------------------------------------------------------------------------|
| `CRON_SCHEDULE`        | "5 3 * * *"                 | Cron schedule for running the backup job (using the standard cron format).           |
| `INCREMENTAL`          | "true"                      | Specifies whether incremental backup should be performed (`true` or `false`).        |
| `COMPRESS_THREADS`     | 1                           | Number of threads used for compression by XtraBackup/Mariabackup.                    |
| `BACKUP_DIR`           | "/backup"                   | Directory where backup files will be stored.                                         |
| `DIR_DATE_PATTERN`     | "%Y%m%d"                    | Date pattern (command `date` is used) to be used for naming backup directories.      |
| `FULL_BACKUP_DATE_FORMAT` | "%a"                     | Date format (command `date` is used) to be used for naming full backup files.        |  
| `FULL_BACKUP_DATE_RESULT` | "Sun"                    | If the `date` output of the pattern `FULL_BACKUP_DATE_FORMAT` is equals to `FULL_BACKUP_DATE_RESULT` a full backup will be created. |
| `BEFORE_BACKUP_SCRIPT` | "/backup/before_script.sh"  | Path to the script that will be executed before starting the backup.                  |
| `AFTER_BACKUP_SCRIPT`  | "/backup/after_script.sh"   | Path to the script that will be executed after completing the backup.                 |
| `DATABASES_EXCLUDE`    | "db1 db2.table1"            | Databases or tables to be excluded from the backup, separated by space.               |
| `MYSQL_USER`           | "root"                      | MySQL database user for authentication.                                                |
| `MYSQL_PASSWORD`       | "secret"                    | MySQL database password for authentication.                                            |
| `MYSQL_PASSWORD_FILE`  | "/run/secrets/db_password"  | Path to the file containing the MySQL database password (when using e.g. docker secrets). |
| `MYSQL_HOST`           | "db"                        | Hostname or IP address of the MySQL database server.                                   |

### Backup Rotation Configuration

To save disk space, backups should be rotated automatically. The default pattern is:

- every day an incremental backup (`INCREMENTAL=true`)
- every Sunday a full backup (`FULL_BACKUP_DATE_FORMAT="%a"`, `FULL_BACKUP_DATE_RESULT="Sun"`)
- keep weekly backups for a month
- keep monthly backups for a year
- keep yearly backups after one year

To change this behavior, you can use the following environment variables to define three rotation cycles.
Every cycle is defined by a time range of days and a condition based on the Linux `date` command.
The default evaluation used `equals` but can be changed to `greater than` or `less than` by using the operators `<` or `>` as shown in the examples below.

| **Key**                | **Example Value**           | **Description**                                                                      |
|------------------------|-----------------------------|--------------------------------------------------------------------------------------|
| `ROTATION1_DAYS`       | 6                           | condition for backups older than specified number of days                            |
| `ROTATION1_DATE_FORMAT`| "%a"                        | linux `date` pattern that is used in the condition                                   |
| `ROTATION1_DATE_RESULT`| "Sun"                       | expected result of the `date` command to keep the backup                             |
| `ROTATION2_DAYS`       | 30                          | condition for backups older than specified number of days                            |
| `ROTATION2_DATE_FORMAT`| "%d"                        | linux `date` pattern that is used to evaluate the condition                          |
| `ROTATION2_DATE_RESULT`| "<8"                        | expected result of the `date` command to keep the backup                             |
| `ROTATION3_DAYS`       | 365                         | condition for backups older than specified number of days                            |
| `ROTATION3_DATE_FORMAT`| "%m"                        | linux `date` pattern that is used to evaluate the condition                          |
| `ROTATION3_DATE_RESULT`| "01"                        | expected result of the `date` command to keep the backup                             |
| `DELETE_OLDER_DAYS`    | 0                           | delete all backups older than specified number of days (0 = disabled)                |

The examples given above result in the following behavior:

- For backups older than 6 days, only backups that were done on a Sunday are kept.
- For backups older than 30 days, keep the backup that was done on a day of the first week of the month.
- For backups older than 365 days, keep the backup that was done in January.
- In this example yearly backups are kept forever.

## Example configuration

You  can find an example configuration in the `examples` folder. The available docker image versions can be found on [docker hub](https://hub.docker.com/r/woolfg/my sql-backup-sidecar/tags)

## More Information

Find a blog article about the project at https://wolfgang.gassler.org/docker-image-mysql-mariadb-backups/

## Restore a backup

Let's assume we have a valid backup in your sidecar container and we want to restore it. Please, think about the commands and their impact. Do not just copy/paste it and adapt it to your needs.

- Make sure that the main MySQL/MariaDB container is stopped and won't get restarted automatically by any restart policy.
- Login to the sidecar and make sure, that the `data` dir of MySQL is empty by e.g. executing `rm -rf /var/lib/mysql/*`
- Choose the backup you want to restore, e.g. `/backup/archive/20210606`
- If you deal with compressed data, you will have to uncompress it first. `xtrabackup --decompress --target-dir=/backup/archive/20210606` does the job. You might need to install the required compression tool `qpress` first by executing `apt-get install qpress`.
- You have to prepare the backup to be ready to be copied to the data directory. Use the `--prepare` and `--target-dir`. In case of incremental backups you have to prepare the full backup first and then apply all incremental backups sequentially. Have a look at the documentation for more details: ([Mariadbbackup](https://mariadb.com/kb/en/incremental-backup-and-restore-with-mariabackup/), [XtraBackup](https://docs.percona.com/percona-xtrabackup/8.0/prepare-incremental-backup.html))
- The restoration process itself is just a copy process of the data in the backup directory to the empty data dir of MySQL. In the sidecar, as you have direct access to the shared volume, you can just copy the data `cp -r /backup/archive/20210606/* /var/lib/mysql`. You might have to `chown` the data to the owner of `/var/lib/mysql`.

## Upload Backup Data

- If you want to upload your backups to an external storage we recommend the very flexible docker container https://github.com/lagun4ik/docker-backup
- For uploading backups to Google Cloud Storage automatically, you can use my sister project [woolfg/mysql-backup-sidecar-gs](https://github.com/woolfg/mysql-backup-sidecar-gs).

## After and Before scripts

You can run scripts right before and after backup routines. Just pass `BEFORE_BACKUP_SCRIPT` and/or `AFTER_BACKUP_SCRIPT` environment variables with the files locations.

The before script receives as only one argument the backup's target directory while the after script receives three: the status `succeed` or `failed`, the raw output and the backup's target directory.

## Credits

Contributors:
- [Guillaume L. (guillaumelamirand)](https://github.com/guillaumelamirand)
- [anton z (luzrain)](https://github.com/luzrain)

Thanks to the following resources which helped and inspired:

- https://www.percona.com/doc/percona-xtrabackup/2.4/index.html
- https://github.com/khoanguyen96/dockerfiles/blob/master/percona-xtrabackup/Dockerfile
- https://www.digitalocean.com/community/tutorials/how-to-configure-mysql-backups-with-percona-xtrabackup-on-ubuntu-16-04
