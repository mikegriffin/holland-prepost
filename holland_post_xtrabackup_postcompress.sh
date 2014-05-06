#!/bin/bash

###
## This script is intended to be run as after-backup-command for holland-xtrabackup
## When backupset's compression=none, the prepare (apply-log) phase happens by default
## This script will then tar and compress the prepared backup in post
###

## Set bash options
set -o nounset
shopt -s extglob

## Ensure proper invokation of this script
[[ "${#}" -eq 1 && -n "${1}" ]]  ||  { echo 'Bad arugments. Expecting Holland to invoke with ${backupdir} as the only argument.' >&2; exit 1; }

backup_dir="${1}"
holland_destination="${backup_dir}/data"
backup_root="${backup_dir}/backup_root"

## Backup this script
cp -a "${0}" "${backup_dir}" || exit 1

## Rename the "data" directory to "backup_root" and create an empty "data" directory
mv "${holland_destination}" "${backup_root}" || exit 1
mkdir -p "${holland_destination}" || exit 1
cd "${backup_root}" || exit 1

## Default to using tar piped to single threaded gzip
echo "Compress backup data"
/bin/tar --group=mysql --owner=mysql -cf - . | gzip --fast > "${holland_destination}"/backup.tar.gz
## Use tar piped to pigz for systems with more than 8 CPU cores
#/bin/tar --group=mysql --owner=mysql -cf - . | pigz --fast -p4 > "${holland_destination}"/backup.tar.gz
## Check that no errors occurred in the pipe
[[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || exit 1

## Purge out uncompressed data and fix permissions
echo "Purge uncompressed data"
cd "${backup_dir}" || exit 1
rm -rf "${backup_root}" || exit 1
chown -R mysql: "${backup_dir}" || exit 1
