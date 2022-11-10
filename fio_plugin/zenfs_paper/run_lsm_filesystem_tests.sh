#!/bin/bash
set -e

FS="$1"
FS_PARAMETERS="$2 $3 $4 $5 $6 $8 $9"
DEV_BS=4096

FIO_SCRIPT="wal_performance.fio"
for I in {0..7} # 200b..16000b
do
  BS=$((200 * (2 ** $I)))
  DATASYNC=1
    
  echo "# Testing wal performance blocksize $BS bytes fs: $FS"
 
  ./run_fio_test.sh "$FS-wal-log" "$FIO_SCRIPT" "$FS_PARAMETERS" "$BS" "--fdatasync=$DATASYNC --direct=0 --filename=test.log"
  ./run_fio_test.sh "$FS-wal-dat" "$FIO_SCRIPT" "$FS_PARAMETERS" "$BS" "--fdatasync=$DATASYNC --direct=0 --filename=test.dat"

done


FIO_SCRIPT="sst_performance.fio"
DATASYNC=0
for DIRECT in {0..1}
do
  echo "# Testing sst performance direct=$DIRECT"
  ./run_fio_test.sh "$FS-sst-direct=$DIRECT" "$FIO_SCRIPT" "$FS_PARAMETERS" "NA" "--fdatasync=$DATASYNC --direct=$DIRECT"
done

