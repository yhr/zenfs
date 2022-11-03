/*
 * RocksDB FileSystem IO Engine
 *
 * Based on the skeleton example https://github.com/axboe/fio/blob/master/engines/skeleton_external.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <assert.h>

#include "fio.h"
#include "optgroup.h"

#include "rocksdbfs_shim.h"

/*
 * The core of the module is identical to the ones included with fio,
 * read those. You cannot use register_ioengine() and unregister_ioengine()
 * for external modules, they should be gotten through dlsym()
 */

/*
 * The io engine can define its own options within the io engine source.
 * The option member must not be at offset 0, due to the way fio parses
 * the given option. Just add a padding pointer unless the io engine has
 * something usable.
 */


struct fio_rocksdbfs_opts {
  void *foo;
  char *fs_uri;
};

struct fio_option options[] = {
  {
   .name = "fs_uri",
   .lname = "RocksDB file system URI",
   .type = FIO_OPT_STR_STORE,
   .off1 = offsetof(struct fio_rocksdbfs_opts, fs_uri),
   .help = "RocksDB file system URI e.g posix://",
   .category = FIO_OPT_C_ENGINE,
   .group = FIO_OPT_G_INVALID,
   },
  {
   .name = NULL,
  },
};


/*
 * The ->event() hook is called to match an event number with an io_u.
 * After the core has called ->getevents() and it has returned eg 3,
 * the ->event() hook must return the 3 events that have completed for
 * subsequent calls to ->event() with [0-2]. Required.
 */
static struct io_u *fio_rocksdbfs_event(struct thread_data *td, int event)
{
	return NULL;
}

/*
 * The ->getevents() hook is used to reap completion events from an async
 * io engine. It returns the number of completed events since the last call,
 * which may then be retrieved by calling the ->event() hook with the event
 * numbers. Required.
 */
static int fio_rocksdbfs_getevents(struct thread_data *td, unsigned int min,
				  unsigned int max, const struct timespec *t)
{
	return 0;
}

/*
 * The ->cancel() hook attempts to cancel the io_u. Only relevant for
 * async io engines, and need not be supported.
 */
static int fio_rocksdbfs_cancel(struct thread_data *td, struct io_u *io_u)
{
	return 0;
}

/*
 * The ->queue() hook is responsible for initiating io on the io_u
 * being passed in. If the io engine is a synchronous one, io may complete
 * before ->queue() returns. Required.
 *
 * The io engine must transfer in the direction noted by io_u->ddir
 * to the buffer pointed to by io_u->xfer_buf for as many bytes as
 * io_u->xfer_buflen. Residual data count may be set in io_u->resid
 * for a short read/write.
 */
static enum fio_q_status fio_rocksdbfs_queue(struct thread_data *td,
					    struct io_u *io_u)
{
  int ret = 0;
  int fd = io_u->file->fd;

	/*
	 * Double sanity check to catch errant write on a readonly setup
	 */
	fio_ro_check(td, io_u);

 if (io_u->ddir == DDIR_READ)
    ret = rocksdb::file_read(fd, io_u->xfer_buf, io_u->xfer_buflen, io_u->offset);
	else if (io_u->ddir == DDIR_WRITE)
    ret = rocksdb::file_write(fd, io_u->xfer_buf, io_u->xfer_buflen, io_u->offset);
	else if (io_u->ddir == DDIR_SYNC) {
    ret = rocksdb::file_sync(fd);
  } else if (io_u->ddir == DDIR_DATASYNC) {
    ret = rocksdb::file_datasync(fd);
  }

  if (ret) {
    io_u->error = ret;
	  td_verror(td, io_u->error, "xfer");
  }

	return FIO_Q_COMPLETED;
}

/*
 * The ->prep() function is called for each io_u prior to being submitted
 * with ->queue(). This hook allows the io engine to perform any
 * preparatory actions on the io_u, before being submitted. Not required.
 */
static int fio_rocksdbfs_prep(struct thread_data *td, struct io_u *io_u)
{
	return 0;
}

static int fio_rocksdbfs_setup(struct thread_data *td)
{
  struct fio_rocksdbfs_opts *fs_opts = (struct fio_rocksdbfs_opts *)td->eo;
  void *fs_cookie;
  int ret;

  if (td->io_ops_data)
    return 0;

  ret = rocksdb::get_filesystem(fs_opts->fs_uri, &fs_cookie);
  if (ret) {
    td_verror(td, ret, "Failed to set up filesystem");
    return 1;
  }

//  dprintf(FD_FILE, "Filesystem setup from URI: %s \n", fs_opts->fs_uri);
  td->io_ops_data = fs_cookie;

	return 0;
}

/*
 * This is paired with the ->init() function and is called when a thread is
 * done doing io. Should tear down anything setup by the ->init() function.
 * Not required.
 */
static void fio_rocksdbfs_cleanup(struct thread_data *td)
{
}

/*
 * Hook for opening the given file. Unless the engine has special
 * needs, it usually just provides generic_open_file() as the handler.
 */
static int fio_rocksdbfs_open(struct thread_data *td, struct fio_file *f)
{
  bool read = false, write = false;

  if (td_write(td)) {
    write = true;
  }

  if (td_read(td)) {
    read = true;
  }

  int fd = rocksdb::file_open(td->io_ops_data, f->file_name,
                              td->o.odirect, td_read(td), td_write(td));

  if (fd < 0) {
    td_verror(td, fd, "File open failed");
    return fd;
  }

  f->fd = fd;
	return 0;
}

/*
 * Hook for closing a file. See fio_rocksdbfs_open().
 */
static int fio_rocksdbfs_close(struct thread_data *td, struct fio_file *f)
{
  int ret = rocksdb::file_close(f->fd);
  if (ret) {
    td_verror(td, ret, "File close failed");
  }

  f->fd = -1;
	return ret;
}

static int fio_rocksdbfs_invalidate(struct thread_data *td, struct fio_file *f) {
  int ret = rocksdb::file_invalidate(f->fd);
  if (ret) {
    td_verror(td, ret, "Cache invalidation failed");
  }
  return ret;
}

/*
 * Note that the structure is exported, so that fio can get it via
 * dlsym(..., "ioengine"); for (and only for) external engines.
 */
struct ioengine_ops ioengine = {
	.name		= "rocksdbfs",
	.version	= FIO_IOOPS_VERSION,
  .flags = FIO_SYNCIO,
	.setup		= fio_rocksdbfs_setup,
	.prep		= fio_rocksdbfs_prep,
	.queue		= fio_rocksdbfs_queue,
	.getevents	= fio_rocksdbfs_getevents,
	.event		= fio_rocksdbfs_event,
	.cancel		= fio_rocksdbfs_cancel,
	.cleanup	= fio_rocksdbfs_cleanup,
	.open_file	= fio_rocksdbfs_open,
	.close_file	= fio_rocksdbfs_close,
  .invalidate = fio_rocksdbfs_invalidate,
	.option_struct_size	= sizeof(struct fio_rocksdbfs_opts),
	.options	= options,
};
