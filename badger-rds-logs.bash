#!/bin/bash

set -u

# TODO: error checking
# TODO: file size check, before we download?
# TODO: allow user to specify a certain file, instead of the entire day

# This is a bit FUd because the actual filename is in UTC, but the date in the AWS console is local time. :P

# Additional step, not shown: configure an IAM user for rds_log_reader that has permissions
# to only describe & download the Pg log files!
export AWS_DEFAULT_PROFILE='rds_log_reader'

RDS_INSTANCE=''
DATE_TO_SEARCH=''

usage() {
    echo "Usage: $0 -i [instance] [ -d [date] ]"
    echo "e.g.: $0 -i my-db 2016-01-16"
    echo "Date must be in YYYY-MM-DD format, eg 2016-01-16 for Jan 16, 2016"
    echo "Date isn't required;  default is yesterday's logs"
    exit
}

[[ $# -gt 0 ]] || {
    usage
}

while getopts "i:d:" opt
    do
    case $opt in
        i)
            RDS_INSTANCE=${OPTARG}
            ;;
        d)
            DATE_TO_SEARCH=${OPTARG}
            ;;
        \?)
            echo "Invalid option -$OPTARG" >&2
            usage
        ;;
    esac
done

# sample default var assignment:
if [ -z "${DATE_TO_SEARCH}" ]
then
    # may need to use date -d 'yesterday' depending on version of date utility
    DATE_TO_SEARCH=`date -v -1d "+%Y-%m-%d"`
    echo "no date supplied;  will use ${DATE_TO_SEARCH}"
fi

LOG_PATH='/path/to/your/log/storage'
LOG_FILE="postgresql.log.${DATE_TO_SEARCH}"
LOG_FILE="${LOG_PATH}/${RDS_INSTANCE}-${LOG_FILE}"
REPORT=${LOG_FILE}.html

echo "Finding logs for ${RDS_INSTANCE}"
echo "For date: ${DATE_TO_SEARCH}"
echo "Will save to: $LOG_FILE"
echo "Badger report name: $REPORT"

cat /dev/null > ${LOG_FILE} # in case we're running this multiple times

for log in `aws rds describe-db-log-files \
--db-instance-identifier ${RDS_INSTANCE} \
--filename-contains ${DATE_TO_SEARCH}- \
--output text \
--query 'DescribeDBLogFiles[*].{Name:LogFileName,SizeInBytes:Size}' | awk '{print $1}'`
do
    aws rds download-db-log-file-portion \
--db-instance-identifier ${RDS_INSTANCE} \
--log-file-name ${log} >> ${LOG_FILE}
echo "done with ${log}"
done

if [ ! -s ${LOG_FILE} ]
then
    echo "Something went wrong; ${LOG_FILE} is empty!"
    exit 1
fi

echo "badgering logs"
pgbadger -p '%t:%r:%u@%d:[%p]:' -o ${REPORT} ${LOG_FILE}
