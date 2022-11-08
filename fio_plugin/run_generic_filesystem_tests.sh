#!/bin/bash
set -e

MIN_DATA_SYNC_INTERVAL_BYTES=$((1024 * 1024))

FS="$1"
FS_FILENAME="$2"
FS_PARAMETERS="$3 $4 $5 $6 $7 $8 $9"

DEV_BS=4096
DIRECT_REQUIRED=0

if [ -b $FS_FILENAME ]; then
  #no non-direct io for zoned block devices
  BDEV=$(echo "$FS_FILENAME" | sed 's#.*/##')
  ZONED_SYSFS="/sys/class/block/$BDEV/queue/zoned"
  if grep -Fxq "host-managed"  "$ZONED_SYSFS"; then
    echo "$BDEV is a zoned block device, skipping non-direct benchmarks"
    DIRECT_REQUIRED=1
  fi
fi

for DIRECT in {0..1}
do
  if [ $DIRECT -eq 0 ] && [ $DIRECT_REQUIRED -eq 1 ]; then
    continue
  fi

  for I in {0..14}
  do
    BS=$((256 * (2 ** $I)))
    
    DATASYNC=$(($MIN_DATA_SYNC_INTERVAL_BYTES / $BS))
    if [ $DATASYNC -lt 1 ]; then
      DATASYNC=1
    fi
    
    # We can't do sub-block-sized IO on a block device 
    if [ $BS -lt $DEV_BS ] && [ -b $FS_FILENAME ]; then
      continue
    fi

    if [ $DIRECT -gt 0 ]; then
      # no datasync for direct writes
      DATASYNC=0
      # we can only do direct io on multiples of device block size
      if [ $BS -lt $DEV_BS ]; then
        continue
      fi
    fi

    echo "# Testing blocksize $BS bytes, datasync every $DATASYNC blocks, direct=$DIRECT"

    if [ $DIRECT -eq 0 ]; then
      FIO_SCRIPT=generic_single_file_buffered.fio
    else
      FIO_SCRIPT=generic_single_file_direct.fio
    fi

    ./run_fio_test.sh "$FS-generic-direct=$DIRECT" "$FIO_SCRIPT" "$FS_PARAMETERS" "$BS" "--fdatasync=$DATASYNC --filename=$FS_FILENAME"
  done

done

