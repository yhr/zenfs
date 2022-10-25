#!/bin/sh
set -e

FIO_SCRIPT=$1

FIO_COMMON="fio"
ROCKSDB_IOENGINE="--ioengine=./rocksdbfs_fio_engine.so"

echo Running $FIO_SCRIPT on top of ZENFS
$FIO_COMMON $ROCKSDB_IOENGINE --fs_uri=zenfs://dev:nvme2n1                               $FIO_SCRIPT | tee $FIO_SCRIPT-zenfs.log
echo Running $FIO_SCRIPT on top of XFS
$FIO_COMMON $ROCKSDB_IOENGINE --fs_uri=posix://             --directory=/mnt/xfs_nvme1n1 $FIO_SCRIPT | tee $FIO_SCRIPT-xfs_posix.log

vimdiff $FIO_SCRIPT-xfs_posix.log $FIO_SCRIPT-zenfs.log

