#!/bin/sh
set -e

RUN_NAME=$1
FIO_SCRIPT=$2
FIO_FS_PARAMETERS=$3
FIO_BLOCKSIZE=$4
FIO_EXTRA_PARAMETERS=$5

if [ -z "$FIO_BLOCKSIZE" ]; then
  FIO_BLOCKSIZE="NA"
fi

TEST_RUN_FIELD_HEADERS="run_name;fio_blocksize;fio_script;fio_fs_parameters;fio_extra_parameters;"
TEST_RUN_FIELDS="$RUN_NAME;$FIO_BLOCKSIZE;$FIO_SCRIPT;$FIO_FS_PARAMETERS;$FIO_EXTRA_PARAMETERS;"

TMP_OUTPUT=/tmp/fio.csv
rm -rf "$TMP_OUTPUT"
REPORT_FILE=report.csv

if [ ! -f "$REPORT_FILE" ]; then
FIO_HEADERS=$(cat terse_version_3_headers.csv)
echo "$TEST_RUN_FIELD_HEADERS""$FIO_HEADERS" > "$REPORT_FILE"
fi

if [ "$FIO_BLOCKSIZE" != "NA" ]; then
  FIO_BS="--bs=$FIO_BLOCKSIZE"
fi

fio --minimal $FIO_BS $FIO_FS_PARAMETERS $FIO_EXTRA_PARAMETERS $FIO_SCRIPT > "$TMP_OUTPUT"

if grep -q "error" "$TMP_OUTPUT"; then
echo "$(tput setaf 1)There was at least one error:$(tput sgr 0)"
grep "error" "$TMP_OUTPUT"
exit 1
else 
echo "$(tput setaf 2)Test completed without errors in the output$(tput sgr 0)"
fi

awk '{ print "'"$TEST_RUN_FIELDS"'", $0 }' $TMP_OUTPUT >> $REPORT_FILE

