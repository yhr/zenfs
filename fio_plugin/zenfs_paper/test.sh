#!/bin/sh

LD_PRELOAD=/usr/local/lib/librocksdb.so fio --filename=/tmp/test --ioengine=$PWD/rocksdbfs_fio_engine.so --readwrite=write --size=10G --name=test --fs_uri="zenfs://dev:nvme2n1"
