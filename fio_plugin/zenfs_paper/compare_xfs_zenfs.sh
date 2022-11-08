#!/bin/sh
set -e

FIO_SCRIPT=$1
EXTRA_PARAMETERS="$2 $3 $4 $5 $6 $7 $8"
FIO_COMMON="fio"
ROCKSDB_IOENGINE="--ioengine=./rocksdbfs_fio_engine.so"

echo Running $FIO_SCRIPT on top of ZENFS
$FIO_COMMON $ROCKSDB_IOENGINE --fs_uri=zenfs://dev:nvme2n1 $EXTRA_PARAMETERS $FIO_SCRIPT | tee $FIO_SCRIPT-zenfs.log

#echo Running $FIO_SCRIPT on top of XFS (rocksdb io engine)
#$FIO_COMMON $ROCKSDB_IOENGINE --fs_uri=posix://             --directory=/mnt/xfs_nvme1n1 $FIO_SCRIPT | tee $FIO_SCRIPT-xfs_posix.log

XFS_IOENGINE=libaio
echo Running $FIO_SCRIPT on top of XFS
$FIO_COMMON --directory=/mnt/xfs_nvme1n1 --ioengine=$XFS_IOENGINE $EXTRA_PARAMETERS $FIO_SCRIPT | tee $FIO_SCRIPT-xfs_libaio.log

vimdiff $FIO_SCRIPT-xfs_$XFS_IOENGINE.log $FIO_SCRIPT-zenfs.log

