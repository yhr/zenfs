#!/bin/sh
set -e

ZDEV=$1
CDEV=$2

ZDEVPATH="/dev/$1"
CDEVPATH="/dev/$2"

ZENFS_AUX_PATH="/tmp/$ZDEV-fio-aux"

CDEV_IO_SCHEDULER="none"
ZDEV_IO_SCHEDULER="deadline"
XFS_MOUNT_DIR=/mnt/xfs_$CDEV
EXT4_MOUNT_DIR=/mnt/ext4_$CDEV
ZBTRFS_MOUNT_DIR=/mnt/zbtrfs_$ZDEV
BTRFS_MOUNT_DIR=/mnt/btrfs_$CDEV

BTRFS_PROGS_PATH=/home/hans/repos/btrfs-progs
ZENFS_UTIL_PATH=/home/hans/repos/rocksdb/plugin/zenfs/util

prepare_cdev () {
  echo Setting io scheduler to $CDEV_IO_SCHEDULER for $CDEVPATH
  echo $CDEV_IO_SCHEDULER > /sys/class/block/$CDEV/queue/scheduler

  echo Discarding $CDEVPATH
  blkdiscard $CDEVPATH
}

prepare_zdev () {
  echo Setting io scheduler to deadline for $ZDEVPATH
  echo deadline > /sys/class/block/$ZDEV/queue/scheduler

  echo Resetting all zones for $ZDEVPATH
  blkzone reset $ZDEVPATH
}

prepare_xfs () {
  prepare_cdev

  echo Creating XFS file system on top of $CDEVPATH
  mkfs.xfs $CDEVPATH

  rm -rf $XFS_MOUNT_DIR
  mkdir $XFS_MOUNT_DIR
  echo Mounting XFS file system at $XFS_MOUNT_DIR
  mount $CDEVPATH $XFS_MOUNT_DIR
}

prepare_ext4 () {
  prepare_cdev

  echo Creating ext4 file system on top of $CDEVPATH
  mkfs.ext4 -q $CDEVPATH

  rm -rf $EXT4_MOUNT_DIR
  mkdir $EXT4_MOUNT_DIR
  echo Mounting ext4 file system at $EXT4_MOUNT_DIR
  mount $CDEVPATH $EXT4_MOUNT_DIR

}

prepare_zbtrfs () {
  prepare_zdev
  
  echo Creating zoned btrfs file system on top of $ZDEVPATH
  $BTRFS_PROGS_PATH/mkfs.btrfs -m single -d single $ZDEVPATH -f

  rm -rf $ZBTRFS_MOUNT_DIR
  mkdir $ZBTRFS_MOUNT_DIR
  echo Mounting zoned btrfs file system at $ZBTRFS_MOUNT_DIR
  mount -t btrfs $ZDEVPATH $ZBTRFS_MOUNT_DIR
}

prepare_btrfs () {
  prepare_cdev
  
  echo Creating conventional btrfs file system on top of $CDEVPATH
  $BTRFS_PROGS_PATH/mkfs.btrfs -m single -d single $CDEVPATH -f

  rm -rf $BTRFS_MOUNT_DIR
  mkdir $BTRFS_MOUNT_DIR
  echo Mounting btrfs file system at $BTRFS_MOUNT_DIR
  mount -t btrfs $CDEVPATH $BTRFS_MOUNT_DIR
}

prepare_zenfs () {
  prepare_zdev

  echo Creating ZenFS file system on top of $ZDEVPATH
  rm -rf $ZENFS_AUX_PATH 
  $ZENFS_UTIL_PATH/zenfs mkfs --zbd=$ZDEV --aux_path=$ZENFS_AUX_PATH --enable_gc
}

quit_ok () {
  echo ALL DONE, AWESOME!
  exit 0
}

# Notes:
# --create_on_open is used to read the file that has been previously written in stead of fio laying out a new one

run_lsm_tests () {

prepare_ext4
EXT4_FS_PARAMETERS="--directory=$EXT4_MOUNT_DIR --create_on_open=1"
EXT4_JOBNAME="ext4-$CDEV_IO_SCHEDULER"
./run_lsm_filesystem_tests.sh "$EXT4_JOBNAME" "$EXT4_FS_PARAMETERS"
umount "$EXT4_MOUNT_DIR"

#skipping zbtrfs for now as it hangs

#prepare_zbtrfs
#ZBTRFS_FS_PARAMETERS="--directory=$ZBTRFS_MOUNT_DIR --create_on_open=1"
#ZBTRFS_JOBNAME="zbtrfs-$CDEV_IO_SCHEDULER"
#./run_lsm_filesystem_tests.sh "$ZBTRFS_JOBNAME" "$ZBTRFS_FS_PARAMETERS"
#umount "$ZBTRFS_MOUNT_DIR"

prepare_btrfs
BTRFS_FS_PARAMETERS="--directory=$BTRFS_MOUNT_DIR --create_on_open=1"
BTRFS_JOBNAME="btrfs-$CDEV_IO_SCHEDULER"
./run_lsm_filesystem_tests.sh "$BTRFS_JOBNAME" "$BTRFS_FS_PARAMETERS"
umount "$BTRFS_MOUNT_DIR"

prepare_zenfs
ZENFS_FS_PARAMETERS="--ioengine=./rocksdbfs_fio_engine.so --fs_uri=zenfs://dev:$ZDEV --create_on_open=1"
ZENFS_JOBNAME="zenfs-$ZDEV_IO_SCHEDULER"
LD_PRELOAD=../../../librocksdb.so ./run_lsm_filesystem_tests.sh "$ZENFS_JOBNAME" "$ZENFS_FS_PARAMETERS"

prepare_xfs
XFS_FS_PARAMETERS="--directory=$XFS_MOUNT_DIR --create_on_open=1"
XFS_JOBNAME="xfs-$CDEV_IO_SCHEDULER"
./run_lsm_filesystem_tests.sh "$XFS_JOBNAME" "$XFS_FS_PARAMETERS"
umount "$XFS_MOUNT_DIR"

}

run_lsm_tests
quit_ok

prepare_cdev
RAW_CDEV_JOBNAME="raw-cdev-$CDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$RAW_CDEV_JOBNAME" "$CDEVPATH" ""

prepare_zdev
RAW_ZDEV_JOBNAME="raw-zdev-$ZDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$RAW_ZDEV_JOBNAME" "$ZDEVPATH" "--zonemode=zbd"

prepare_zenfs
ZENFS_FS_PARAMETERS="--ioengine=./rocksdbfs_fio_engine.so --fs_uri=zenfs://dev:$ZDEV --create_on_open=1"
ZENFS_JOBNAME="zenfs-$ZDEV_IO_SCHEDULER"
LD_PRELOAD=../../../librocksdb.so ./run_generic_filesystem_tests.sh "$ZENFS_JOBNAME" "test.dat" "$ZENFS_FS_PARAMETERS"

prepare_zbtrfs
ZBTRFS_FS_PARAMETERS="--directory=$ZBTRFS_MOUNT_DIR --create_on_open=1"
ZBTRFS_JOBNAME="zbtrfs-$ZDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$ZBTRFS_JOBNAME" "test.dat" "$ZBTRFS_FS_PARAMETERS"
umount "$ZBTRFS_MOUNT_DIR"

prepare_btrfs
BTRFS_FS_PARAMETERS="--directory=$BTRFS_MOUNT_DIR --create_on_open=1"
BTRFS_JOBNAME="btrfs-$CDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$BTRFS_JOBNAME" "test.dat" "$BTRFS_FS_PARAMETERS"
umount "$BTRFS_MOUNT_DIR"

prepare_xfs
XFS_FS_PARAMETERS="--directory=$XFS_MOUNT_DIR --create_on_open=1"
XFS_JOBNAME="xfs-$CDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$XFS_JOBNAME" "test.dat" "$XFS_FS_PARAMETERS"
 umount "$XFS_MOUNT_DIR"

prepare_ext4
EXT4_FS_PARAMETERS="--directory=$EXT4_MOUNT_DIR --create_on_open=1"
EXT4_JOBNAME="ext4-$CDEV_IO_SCHEDULER"
./run_generic_filesystem_tests.sh "$EXT4_JOBNAME" "test.dat" "$EXT4_FS_PARAMETERS"
umount "$EXT4_MOUNT_DIR"

quit_ok

