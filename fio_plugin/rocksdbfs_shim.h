namespace rocksdb {

int get_filesystem(char *fs_uri, void **fs_cookie);
int file_open(void *fs_cookie, char *filename, bool direct, bool read, bool write);
int file_close(int fd);
int file_write(int fd, void *buf, unsigned long long buflen, unsigned long long offset);
int file_read(int fd, void *buf, unsigned long long buflen, unsigned long long offset);
int file_sync(int fd);
int file_datasync(int fd);
int file_invalidate(int fd);

}

