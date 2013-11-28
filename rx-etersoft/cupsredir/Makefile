all: libcupsredir.so

CC=gcc
CFLAGS=-g -O2 -Wall -fPIC
LIBNAME=libcupsredir.so
VERSION=0

libcupsredir.so: cupsredir.o
	$(CC) -fPIC $(CFLAGS) -shared -Wl,-soname,$(LIBNAME).$(VERSION) -o $(LIBNAME).$(VERSION) cupsredir.o -ldl 

clean:
	rm -f $(LIBNAME)
	rm -f $(LIBNAME).$(VERSION)
	rm -f *.o

ifneq ($(NX_VERSION),)
install: all
	install -m755 $(LIBNAME).$(VERSION) $(DESTDIR)/$$PATH_LIB/rx-etersoft/
	install -m755 cupsredir $(DESTDIR)/$$PATH_BIN/
	perl -pi -e "s,PATH_LIB=.*,PATH_LIB=\"$$PATH_LIB\",g" $(DESTDIR)/$$PATH_BIN/cupsredir
else
install: all
	echo "run only under global makefile"
	exit 1
endif

.PHONY: clean install
