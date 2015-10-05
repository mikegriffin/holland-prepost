#!/bin/bash

set -euf -o pipefail

#################################
# Configuration options
#################################
compressed_file="backup.tar.gz"
uncompress_cat_command="pigz -dc"
uncompressed_dir=/uncompressed/
email_rcpt="root@localhost"
innobackupex_memory=128M

#################################
## Ensure proper invocation of this script
#################################
[[ "${#}" -eq 2 && -n "${1}" && -n "${2}" ]]  ||  { echo "Bad arugments. Expecting Holland to invoke with \${backupset} and \${backupdir} as arguments" >&2; exit 1; }
backupset=${1}
backupdir=${2}
[[ -f /etc/holland/backupsets/"${backupset}".conf ]] || { echo "Bad arugments.  \${backupset} ${backupset} does not exist" >&2; exit 1; }
[[ -d "${backupdir}" ]] || { echo "Bad arugments.  \${backupdir} ${backupdir} does not exist or is not a directory" >&2; exit 1; }
uncompressed_dir=$(echo "${uncompressed_dir}" | sed 's^/$^^') # find regex used breaks without this
daily_uncompressed=$(basename "${backupdir}")
[[ -d "${uncompressed_dir}" ]] || { echo "Bad configuration in after-backup-commmand ${0}: uncompressed_dir set to ${uncompressed_dir} but this path does not exist or is not a directory" >&2; exit 1; }

#################################
# Test for required software
#################################
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
[[ -x $(type -fP at) ]] ||
           { echo "${0} after-backup-command unable to find at in path" >&2; exit 1; }
[[ -x $(type -fP awk) ]] ||
           { echo "${0} after-backup-command unable to find awk in path" >&2; exit 1; }
[[ -x $(type -fP find) ]] ||
           { echo "${0} after-backup-command unable to find find in path" >&2; exit 1; }
[[ -x $(type -fP innobackupex) ]] ||
           { echo "${0} after-backup-command unable to find innobackupex in path" >&2; exit 1; }
[[ -x $(type -fP mutt) ]] ||
           { echo "${0} after-backup-command unable to find mutt in path" >&2; exit 1; }
[[ -x $(type -fP sed) ]] ||
           { echo "${0} after-backup-command unable to find sed in path" >&2; exit 1; }
[[ -x $(type -fP tar) ]] ||
           { echo "${0} after-backup-command unable to find tar in path" >&2; exit 1; }
[[ -x $(type -fP $(echo "${uncompress_cat_command}" | /bin/sed 's^[[:space:]].*^^')) ]] ||
           { echo "${0} after-backup-command unable to find $(echo "${uncompress_cat_command}" | /bin/sed 's^[[:space:]].*^^') in path" >&2; exit 1; }
ps -efa | awk 'BEGIN {zzz=1}; $8 ~ /\/.*\/atd$/ && $3 == 1 {zzz=0}; END {exit zzz}' ||
           { echo "${0} after-backup-command thinks atd is not running" >&2; exit 1; }


#################################
# Inject a decompression job in to atd and then return to holland without waiting
#################################

cat << ENDOFATSCRIPT | at now &> /dev/null  || { echo "${0} after-backup-command unable to inject decompression job to atd" | mutt -s "Nightly backup decompress failure" "${email_rcpt}"; exit 1; }
### BEGIN AT JOB BASH
#!/bin/bash
set -euf -o pipefail

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

# Delete directories in ${uncompressed_dir} that look like holland time format and haven't been modified in over eight hours
find ${uncompressed_dir} -maxdepth 1 -mmin +480 -type d -regextype posix-extended -regex "${uncompressed_dir}/+[2-9][[:digit:]]{7}_[[:digit:]]{6}" -exec rm -fr {} \+ ||
           { echo "${0} after-backup-command unable to purge in path ${uncompressed_dir}" | mutt -s "Nightly backup decompress failure" "${email_rcpt}"; exit 1; }


mkdir ${uncompressed_dir}/${daily_uncompressed} ||
           { echo "${0} after-backup-command unable to create ${uncompressed_dir}/${daily_uncompressed}" | mutt -s "Nightly backup decompress failure" "${email_rcpt}"; exit 1; }


{ ${uncompress_cat_command} ${backupdir}/${compressed_file} | tar ixf - -C ${uncompressed_dir}/${daily_uncompressed}; } ||
           { echo 'Decompression failed' | mutt -s 'Nightly backup decompress failure' ${email_rcpt} ; exit 1; }

innobackupex --use-memory="${innobackupex_memory}" --apply-log ${uncompressed_dir}/${daily_uncompressed} &> ${uncompressed_dir}/${daily_uncompressed}/innobackupex_apply_${daily_uncompressed}.log ||
           { echo 'innobackupex apply log (prepare) failed' | mutt -s 'Nightly backup decompress failure' ${email_rcpt} ; exit 1; }

### END AT JOB BASH
ENDOFATSCRIPT
