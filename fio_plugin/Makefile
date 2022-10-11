# ZenFS fio ioengine target

TARGET_LIB = rocksdbfs_fio_engine.so

CXX ?= g++
OBJCOPY ?= objcopy

ROCKSDB_CXXFLAGS := $(shell pkg-config --cflags rocksdb)
ifneq ($(.SHELLSTATUS),0)
$(error pkg-config failed)
endif

ROCKSDB_LIBS := $(shell pkg-config --libs rocksdb)
ifneq ($(.SHELLSTATUS),0)
$(error pkg-config failed)
endif

CXXFLAGS += -I$(CONFIG_FIO_SOURCE_DIR) -DCONFIG_HAVE_GETTID
CXXFLAGS += -O2 -g 
CXXFLAGS += $(ROCKSDB_CXXFLAGS) -fPIC -u zenfs_filesystem_reg
CXXFLAGS += $(EXTRA_CXXFLAGS)

LDFLAGS +=  $(EXTRA_LDFLAGS)
LDFLAGS += -shared -rdynamic
LDFLAGS += $(ROCKSDB_LIBS)

SRCS = rocksdbfs_fio_engine.cc rocksdbfs_fio_shim.cc
OBJS = $(SRCS:.cc=.o)

all: $(TARGET_LIB)

$(TARGET_LIB): $(OBJS)
	$(CXX) ${LDFLAGS} -o $@ $^

$(SRCS:.cc=.d):%.d:%.cc
	$(CXX) $(CXXFLAGS) -MM $< >$@

include $(SRCS:.cc=.d)

clean:
	$(RM) $(TARGET_LIB) $(OBJS) *.d


