#include "native_file_bridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t source[TIO_WIRE],queued[TIO_WIRE];
static TIOImageJob job;
static TIONativeMessage saved,posted;
static unsigned calls,copies,frees,handled;
static int enqueue_result;
static bool waiting;
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void never_called(void *p){(void)p;abort();}
/* A model of stock's queue for a message whose release word is 0: the post copies `bytes` bytes into a heap block it
 * owns and never writes the sender's message; a failed post frees that copy. The consumer (consume() below) hands the
 * handler a message with the release word still 0 and frees the copy after the handler returns. */
static int enqueue(unsigned module,const TIONativeMessage *m){
 assert(module==1&&m->release==NULL&&m->bytes==TIO_WIRE&&!waiting);calls++;
 const TIONativeMessage before=*m;
 uint8_t *copy=malloc(m->bytes);assert(copy);copies++;memcpy(copy,m->data,m->bytes);
 assert(!memcmp(&before,m,sizeof before));
 if(enqueue_result){free(copy);frees++;return enqueue_result;}
 posted=*m;posted.data=copy;posted.release=NULL;waiting=true;return 0;
}
static TIOImageResult consume(void){
 assert(waiting&&posted.release==NULL);waiting=false;handled++;
 TIOImageResult r=tio_native_message_copy(&posted,&job);
 memcpy(queued,posted.data,posted.bytes);saved=posted;saved.data=queued;
 free((void *)posted.data);frees++;posted=(TIONativeMessage){0};return r;
}
static void packet(void){
 const uint8_t h[20]=TIO_WIRE_PREFIX;
 memset(source,0,sizeof source);memcpy(source,h,sizeof h);
 put32(source+20,1);put32(source+24,7392);
 for(unsigned i=32;i<sizeof source;i++)source[i]=(uint8_t)i;
 put32(source+28,tio_image_crc32(source+32,TIO_PIXELS));
}
int main(void){
 packet();TIONativeFile f={.data=source,.declared=TIO_WIRE,.received=TIO_WIRE,.complete=1};
 strcpy(f.filename,"turbo-photo.timg");
 assert(tio_native_file_receive(&f,enqueue)==TIO_OK&&calls==1&&copies==1&&frees==0);
 memset(source,0xa5,sizeof source); /* real receiver frees/reuses on return */
 assert(consume()==TIO_OK&&handled==1&&frees==1);
 assert(job.session==7392&&job.frame==1&&job.pixels[0]==32);
 assert(tio_native_message_copy(&saved,&job)==TIO_OK);
 packet();enqueue_result=-1;
 assert(tio_native_file_receive(&f,enqueue)==TIO_BUSY&&calls==2&&copies==2&&frees==2&&!waiting);enqueue_result=0;
 unsigned before=calls;
 f.complete=0;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.complete=1;
 f.received--;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.received++;
 f.declared++;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.declared--;
 f.filename[sizeof("turbo-photo.timg")-1]='x';
 assert(tio_native_file_receive(&f,enqueue)==TIO_FOREIGN);strcpy(f.filename,"turbo-photo.timg");
 memset(f.filename,'x',sizeof f.filename);
 assert(tio_native_file_receive(&f,enqueue)==TIO_FOREIGN);strcpy(f.filename,"turbo-photo.timg");
 f.data=NULL;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_SIZE);f.data=source;
 source[40]^=1;assert(tio_native_file_receive(&f,enqueue)==TIO_BAD_CRC);source[40]^=1;
 assert(calls==before&&copies==frees&&handled==1);
 TIONativeMessage m=saved;m.release=never_called;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_HEADER);
 m=saved;m.reserved=1;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_HEADER);
 m=saved;m.context=&job;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_HEADER);
 m=saved;m.bytes--;
 assert(tio_native_message_copy(&m,&job)==TIO_BAD_SIZE);
 m=saved;m.id=47;
 assert(!tio_native_message_is_ours(&m));assert(tio_native_message_copy(&m,&job)==TIO_FOREIGN);
 puts("PASS native file ABI adapter: copied lifetime, partial failure, queue full, exact filename, malformed messages");
}
