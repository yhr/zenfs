
#include <map>
#include <mutex>
#include <atomic>

#include <rocksdb/convenience.h>
#include <rocksdb/file_system.h>
#include <rocksdb/env.h>

#include <linux/errno.h>

namespace ROCKSDB_NAMESPACE {

static std::map<std::string, std::shared_ptr<FileSystem>> filesystems_;
static std::mutex filesystems_mtx_;

class RocksDBFile;
static std::map<int, std::shared_ptr<RocksDBFile>> file_descriptors_;
static std::mutex file_descriptors_mutex_;
static std::atomic<int> next_fd_ = 42;

class RocksDBFile {
  private:
    std::unique_ptr<FSWritableFile> wFile_;
    std::unique_ptr<FSRandomAccessFile> rFile_;
    std::mutex wr_mtx_; /* ensures that only one thread writes to the backing file at a time */
    std::string filename_;
    FileSystem *fs_;
    unsigned long long wp_ = 0;

    /* A best-effort reverse mapping of rocksdb io errors to linux errno.h errors */
    const std::map<Status::Code, int> errno_map = {
                                                    {Status::Code::kOk, 0},
                                                    {Status::Code::kNotFound, -ENOENT},
                                                    {Status::Code::kCorruption, -EIO},
                                                    {Status::Code::kNotSupported, -ENOTSUP},
                                                    {Status::Code::kInvalidArgument, -EINVAL},
                                                    {Status::Code::kIOError, -EIO},
                                                    {Status::Code::kIncomplete, -EINTR},
                                                    {Status::Code::kShutdownInProgress, -ESHUTDOWN},
                                                    {Status::Code::kTimedOut, -ETIME},
                                                    {Status::Code::kAborted, -EIO},
                                                    {Status::Code::kBusy, -EBUSY},
                                                    {Status::Code::kExpired, -ETIME},
                                                    {Status::Code::kTryAgain, -EAGAIN},
                                                  };
    int GetErrno(IOStatus &s) {
      std::map<Status::Code, int>::const_iterator p;

      p = errno_map.find(s.code());
      if (p != errno_map.end()) {
        return p->second;
      }

      return -EINVAL; /* We don't know */
    }

  public:

  RocksDBFile(FileSystem *fs) {
    fs_ = fs;
  }

  int Open(char *filename, bool direct, bool read, bool write) {
    IODebugContext dbg;
    FileOptions fopts;
    IOOptions iopts;
    IOStatus s;

    fopts.use_direct_reads = fopts.use_direct_writes = direct;

    if (write) {
      s = fs_->NewWritableFile(filename, fopts, &wFile_, &dbg);
      if (!s.ok()) {
        return GetErrno(s);
      }
    }

    if (read) {
      s = fs_->NewRandomAccessFile(filename, fopts, &rFile_, &dbg);
      if (!s.ok()) {
        wFile_ = nullptr;
        return GetErrno(s);
      }
    }

    return 0;
  }

  void Close() {
    IODebugContext dbg;
    IOOptions iopts;
    if (wFile_)
        wFile_->Close(iopts, &dbg);
  }

  int Write(int fd, void *buf, unsigned long long buflen, unsigned long long offset) {
    std::lock_guard<std::mutex> wr_lock(wr_mtx_);
    Slice slice((char *)buf, (size_t)(buflen));
    IODebugContext dbg;
    IOOptions iopts;
    IOStatus s;

    if (wp_ != offset) {
      return -EIO;
    }

    s = wFile_->Append(slice, iopts, &dbg);
    if (!s.ok()) {
      return GetErrno(s);
    }

    wp_ += buflen;
    return 0;
  }

  int Read(int fd, void *buf, unsigned long long len, unsigned long long offset) {
    Slice result;
    IODebugContext dbg;
    IOOptions iopts;
    IOStatus s;

    if (!rFile_) {
      return -EINVAL;
    }

    s = rFile_->Read((uint64_t)offset, len, iopts, &result, (char *)buf, &dbg);
    if (!s.ok()) {
      return GetErrno(s);
    }

    /* We don't expect that the data will be at an offset in the buffer (should not be possible)*/
    if (result.data() != (char*)buf) {
      return -EIO;
    }

    return 0;
  }

  int Sync(bool syncMetadata) {
    IODebugContext dbg;
    IOOptions iopts;
    IOStatus s;

    if (!wFile_)
      return -EIO;

    if(wFile_->IsSyncThreadSafe()) {
      if (syncMetadata) {
        s = wFile_->Fsync(iopts, &dbg);
      } else {
        s = wFile_->Sync(iopts, &dbg);
      }
    } else {
      std::lock_guard<std::mutex> wr_lock(wr_mtx_);
      if (syncMetadata) {
        s = wFile_->Fsync(iopts, &dbg);
      } else {
        s = wFile_->Sync(iopts, &dbg);
      }
    }

    return GetErrno(s);
  }

  int Invalidate() {
    /* If the file is not open for reading, we cannot invalidate through
     * the FileSystem interface */
    if (!rFile_) {
      return 0;
    }

    /* Invalidate the cache for the whole file */
    IOStatus s = rFile_->InvalidateCache(0, 0);
    return GetErrno(s);
  }
};

int get_filesystem(char *fs_uri, void **fs_cookie) {
  std::lock_guard<std::mutex> filesystem_lock(filesystems_mtx_);

  /* Do we already have an instance of this filesystem? */
  if (filesystems_.find(fs_uri) != filesystems_.end()) {
    *fs_cookie = (void *)filesystems_[fs_uri].get();
    return 0;
  }

  ConfigOptions config_options;
  std::shared_ptr<FileSystem> fs;
  Status s = FileSystem::CreateFromString(config_options, fs_uri, &fs);

  if (!s.ok() || fs == nullptr) {
    return -EINVAL;
  }

  filesystems_.insert(std::make_pair(fs_uri, fs));
  *fs_cookie = (void *)fs.get();
  return 0;
}

int file_open(void *fs_cookie, char *filename, bool direct, bool read, bool write) {
  FileSystem *fs = (FileSystem *)fs_cookie;
  std::shared_ptr<RocksDBFile> file = std::make_shared<RocksDBFile>(fs);

  int ret = file->Open(filename, direct, read, write);
  if (ret)
    return ret;

  std::lock_guard<std::mutex> file_descriptors_lock(file_descriptors_mutex_);
  int fd = next_fd_++;
  file_descriptors_[fd] = file;

  return fd;
}

int file_close(int fd) {
  std::lock_guard<std::mutex> file_descriptors_lock(file_descriptors_mutex_);

  if (file_descriptors_.find(fd) == file_descriptors_.end()) {
      return -EINVAL;
  }

  std::shared_ptr<RocksDBFile> file = file_descriptors_[fd];
  file_descriptors_.erase(fd);
  file->Close();

  return 0;
}

static std::shared_ptr<RocksDBFile> get_file(int fd) {
  std::lock_guard<std::mutex> file_descriptors_lock(file_descriptors_mutex_);
  std::shared_ptr<RocksDBFile> file;

  if (file_descriptors_.find(fd) != file_descriptors_.end()) {
    file = file_descriptors_[fd];
  }
  return file;
}

int file_write(int fd, void *buf, unsigned long long buflen, unsigned long long offset) {
  std::shared_ptr<RocksDBFile> file = get_file(fd);

  if (!file) {
    return -EINVAL;
  }
  return file->Write(fd, buf, buflen, offset);
}

int file_read(int fd, void *buf, unsigned long long buflen, unsigned long long offset) {
  std::shared_ptr<RocksDBFile> file = get_file(fd);

  if (!file) {
    return -EINVAL;
  }
  return file->Read(fd, buf, buflen, offset);
}

int file_sync(int fd) {
  std::shared_ptr<RocksDBFile> file = get_file(fd);

  if (!file) {
    return -EINVAL;
  }
  return file->Sync(true);
}

int file_datasync(int fd) {
  std::shared_ptr<RocksDBFile> file = get_file(fd);

  if (!file) {
    return -EINVAL;
  }
  return file->Sync(false);
}

int file_invalidate(int fd) {
  std::shared_ptr<RocksDBFile> file = get_file(fd);

  if (!file) {
    return -EINVAL;
  }
  return file->Invalidate();
}
} // ROCKSDB_NAMESPACE
