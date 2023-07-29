# mysql-backup-sidecar

This backup docker container creates incremental and compressed MySQL or MariaDB backups without blocking the database during the backup procedure. It is based on `XtraBackup` https://www.percona.com/doc/percona-xtrabackup/2.4/index.html and the forked version for MariaDB `Mariabackup` https://mariadb.com/kb/en/mariabackup/. If you are not familiar with the underlying backup tools, please, read the documentation to understand what commands are executed on your DB server. 

## Features

- non-blocking backup procedure (using XtraBackup/Mariabackup). 
- runs in a separated container
- configurable cron schedule (e.g. every night, every second night, etc)
- configurable backup cycles (incremental, full backups)
- backup rotation (e.g. delete incremental backups after a full backup)
- supports docker credentials and environment based password definitions

## Configuration

The following environment variables are supported (incl. example values):

- `CRON_SCHEDULE:` "5 3 * * *"
- `INCREMENTAL:` "true"
- `COMPRESS_THREADS:` 1
- `BACKUP_DIR:` /backup
- `DIR_DATE_PATTERN:` "%Y%m%d"
- `FULL_BACKUP_DATE_FORMAT:` "%a"
- `FULL_BACKUP_DATE_RESULT:` "Sun"
- `BEFORE_BACKUP_SCRIPT:` "/backup/before_script.sh"
- `AFTER_BACKUP_SCRIPT:` "/backup/after_script.sh"
- `DATABASES_EXCLUDE:` "example example1.table1"
- `ROTATION1_DAYS:` 6
- `ROTATION1_DATE_FORMAT:` "%a"
- `ROTATION1_DATE_RESULT:` "Sun"
- `ROTATION2_DAYS:` 30
- `ROTATION2_DATE_FORMAT:` "%d"
- `ROTATION2_DATE_RESULT:` "<8"
- `ROTATION3_DAYS:` 365
- `ROTATION3_DATE_FORMAT:` "%m"
- `ROTATION3_DATE_RESULT:` "01"
- `MYSQL_USER:` root
- `MYSQL_PASSWORD_FILE:` /run/secrets/db_password
- `MYSQL_HOST:` db

## Example configuration

You can find an example configuration in the `examples` folder. The available docker image versions can be found on [docker hub](https://hub.docker.com/r/woolfg/mysql-backup-sidecar/tags)

## More Information

Find a blog article about the project at https://wolfgang.gassler.org/docker-image-mysql-mariadb-backups/

## Restore a backup

Let's assume we have a valid backup in your sidecar container and we want to restore it. Please, think about the commands and their impact. Do not just copy/paste it and adapt it to your needs.

- Make sure that the main MySQL/MariaDB container is stopped and won't get restarted automatically by any restart policy.
- Login to the sidecar and make sure, that the `data` dir of MySQL is empty by e.g. executing `rm -rf /var/lib/mysql/*`
- Choose the backup you want to restore, e.g. `/backup/archive/20210606`
- If you deal with compressed data, you will have to uncompress it first. `xtrabackup --decompress --target-dir=/backup/archive/20210606` does the job. You might need to install the required compression tool `qpress` first by executing `apt-get install qpress`.
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
