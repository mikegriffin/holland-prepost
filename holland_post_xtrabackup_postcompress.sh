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
compression_max_cpu_cores=4

## Log the intent of this post script to stderr, so it comes first in dry run
echo "INFO: Compressing already prepared xtrabackup in after-backup-command" 1>&2

## Ensure proper invocation of this script
[[ "${#}" -eq 1 && -n "${1}" ]]  ||  { echo "Bad arugments. Expecting Holland to invoke with \${backupdir} as the only argument." >&2; exit 1; }

## Set paths
backupdir="${1}"
datadir="${backupdir}/data"

## Verify that this appears to be an uncompressed backup that has already been prepared
[[ -f "${datadir}"/xtrabackup_logfile &&
   -f "${datadir}"/ib_logfile0 &&
   -f "${datadir}"/ib_logfile1 ]] ||  { echo "Backup not prepared or holland in dry-run. Set stream=no and apply-logs=yes in backupset" >&2; exit 1; }

## Backup this script itself
cp -a "${0}" "${backupdir}" || exit 1

## Create compressed tar of datadir in backupdir
compression_level_valid=`echo $(((${compression_level}*2)/2))`
[[ ${compression_level_valid} == ${compression_level} && ${compression_level_valid} -le 9 ]] || { echo "Invalid compression_level: ${compression_level}" >&2; exit 1; }
if [[ "${compression_max_cpu_cores}" -le 1 ]]
 then
     echo "$(date "+%y%m%d %H:%M:%S") Compressing with single thread at level ${compression_level}"
     /bin/tar --group=mysql --owner=mysql -cf - -C "${datadir}" .| gzip -"${compression_level}" > "${backupdir}"/backup.tar.gz
     [[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || { echo "Compression failed" >&2; exit 1; }
else
 if [[ "${compression_max_cpu_cores}" -gt 1 && -x $(type -fP pigz) ]] || { echo "pigz not in path and compression_max_cpu_cores > 1 in ${0}" >&2; exit 1; }
 then 
     echo "$(date "+%y%m%d %H:%M:%S") Compressiong with ${compression_max_cpu_cores} threads at level ${compression_level}"
     /bin/tar --group=mysql --owner=mysql -cf - -C "${datadir}" .| pigz -"${compression_level}" -p"${compression_max_cpu_cores}" > "${backupdir}"/backup.tar.gz
     [[ $((${PIPESTATUS[@]/%/+}0)) -eq 0 ]] || { echo "Compression failed" >&2; exit 1; }
 fi
fi

## Echo peak usage while holding both an uncompressed copy and a compressed copy
echo "$(date "+%y%m%d %H:%M:%S") Peak disk usage was: $(du -sh ${backupdir} | cut -f1)"

## Purge out uncompressed data in datadir
echo "$(date "+%y%m%d %H:%M:%S") Purge uncompressed data"
rm -rf "${datadir}" || exit 1

## Echo final on disk size
echo "$(date "+%y%m%d %H:%M:%S") Final size: $(du -sh ${backupdir} | cut -f1)"

## By default the parent directory does not have world read permissions
## This chown allows the mysql system user to read these files if the parent allows it
chown -R mysql: "${backupdir}" || exit 1
