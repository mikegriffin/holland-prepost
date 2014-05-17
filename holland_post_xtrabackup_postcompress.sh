#!/bin/bash

###
## This script is intended to be run as after-backup-command for holland-xtrabackup
## When compression and streaming are disabled, the prepare (apply-logs) phase is possible
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

###
## User configurable compression options
###
compression_level=1
compression_max_cpu_cores=1

## Ensure proper invokation of this script
[[ "${#}" -eq 1 && -n "${1}" ]]  ||  { echo "Bad arugments. Expecting Holland to invoke with ${backupdir} as the only argument." >&2; exit 1; }

## Set paths
backup_dir="${1}"
holland_destination="${backup_dir}/data"
backup_root="${backup_dir}/backup_root"

## Backup this script itself
cp -a "${0}" "${backup_dir}" || exit 1

## Verify that this appears to be an uncompressed backup that has already been prepared
[[ -f "${holland_destination}"/xtrabackup_logfile &&
   -f "${holland_destination}"/ib_logfile0 &&
   -f "${holland_destination}"/ib_logfile1 ]] ||  { echo "Backup not prepared. Set stream=no and apply-logs=yes in backupset" >&2; exit 1; }

## Rename the "data" directory to "backup_root" and create an empty "data" directory
mv "${holland_destination}" "${backup_root}" || exit 1
mkdir "${holland_destination}" || exit 1
cd "${backup_root}" || exit 1

## Compress data
compression_level_valid=`echo $(((${compression_level}*2)/2))`
[[ ${compression_level_valid} == ${compression_level} && ${compression_level_valid} -le 9 ]] || { echo "Invalid compression_level: ${compression_level}" >&2; exit 1; }
if [[ "${compression_max_cpu_cores}" -le 1 ]]
 then
     echo "$(date "+%y%m%d %H:%M:%S") Compressing with single thread at level ${compression_level}"
     /bin/tar --group=mysql --owner=mysql -cf - . | gzip -"${compression_level}" > "${holland_destination}"/backup.tar.gz
     [[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || { echo "Compression failed" >&2; exit 1; }
else
 if [[ "${compression_max_cpu_cores}" -gt 1 && -x $(type -fP pigz) ]] || { echo "pigz not in path and compression_cpu_cores > 1 in ${0}" >&2; exit 1; }
 then 
     echo "$(date "+%y%m%d %H:%M:%S") Compressiong with ${compression_max_cpu_cores} threads at level ${compression_level}"
     /bin/tar --group=mysql --owner=mysql -cf - . | pigz -"${compression_level}" -p"${compression_max_cpu_cores}" > "${holland_destination}"/backup.tar.gz
     [[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || { echo "Compression failed" >&2; exit 1; }
 fi
fi

## Purge out uncompressed data and fix permissions
echo "$(date "+%y%m%d %H:%M:%S") Purge uncompressed data"
cd "${backup_dir}" || exit 1
rm -rf "${backup_root}" || exit 1
## By default the parent directory does not have world read permissions
## This chown allows the mysql system user to read these files if the parent allows it
chown -R mysql: "${backup_dir}" || exit 1
