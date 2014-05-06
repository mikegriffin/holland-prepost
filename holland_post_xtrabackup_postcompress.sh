#!/bin/bash

###
## This script is intended to be run as after-backup-command for holland-xtrabackup
## When compression and streaming are disabled, the prepare (apply-log) phase is possible
## This script will then tar the prepared backup in post
## Required settings for the backupset
## 
## [holland:backup]
## plugin = xtrabackup
## estimated-size-factor = 1.3
## after-backup-command=/usr/local/bin/holland_post_xtrabackup_postcompress.sh ${backupdir}
##
## [xtrabackup]
## stream = no
## apply-logs = yes
###

## Error on unset variables
set -o nounset

## Ensure proper invokation of this script
[[ "${#}" -eq 1 && -n "${1}" ]]  ||  { echo 'Bad arugments. Expecting Holland to invoke with ${backupdir} as the only argument.' >&2; exit 1; }

## Set paths
backup_dir="${1}"
holland_destination="${backup_dir}/data"
backup_root="${backup_dir}/backup_root"

## Backup this script itself
cp -a "${0}" "${backup_dir}" || exit 1

## Rename the "data" directory to "backup_root" and create an empty "data" directory
mv "${holland_destination}" "${backup_root}" || exit 1
mkdir "${holland_destination}" || exit 1
cd "${backup_root}" || exit 1

echo "Compress backup data"
## Default to using tar piped to single threaded gzip
/bin/tar --group=mysql --owner=mysql -cf - . | gzip --fast > "${holland_destination}"/backup.tar.gz
## Use tar piped to pigz for systems with more than 8 CPU cores
#/bin/tar --group=mysql --owner=mysql -cf - . | pigz --fast -p4 > "${holland_destination}"/backup.tar.gz
## Check that no errors occurred in the pipe
[[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || exit 1

## Purge out uncompressed data and fix permissions
echo "Purge uncompressed data"
cd "${backup_dir}" || exit 1
rm -rf "${backup_root}" || exit 1
## By default the parent directory does not have world read permissions
## This chown allows the mysql system user to read these files if the parent allows it
chown -R mysql: "${backup_dir}" || exit 1
