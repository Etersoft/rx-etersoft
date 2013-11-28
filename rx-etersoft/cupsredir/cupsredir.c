/*
 * cupsredir is used to redirect the creation of a .pid file
 * by user, produced when NX session is established,
 * to another place. The goal is to have .pid file
 * for a basic cupsd launch (made by root)
 * and for a cupsd launch made by nx 
 * with user's rights
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <stdlib.h>

static int (*origin_open64)(const char *pathname, int flags, mode_t mode)=NULL;

int open64(const char *pathname, int flags, mode_t mode)
{
    fprintf(stderr,"open=%s\n\n",pathname);
    if(origin_open64 == NULL)
      origin_open64 = dlsym(RTLD_NEXT,"open64");
    if( strstr(pathname,"cupsd.pid")!=NULL )
    {
      fprintf(stderr,"cupsd.pid\n\n");
      const char *newpath = "/dev/null";
      return origin_open64(newpath,flags,mode);
    }
    return origin_open64(pathname,flags,mode);
}
