#ifndef TIO_LANG_STORE_H
#define TIO_LANG_STORE_H
#include "lang_flag.h"
typedef struct {uint32_t generation;unsigned bank;bool readable;uint8_t lang;} TLSStored;
typedef struct {void *ctx;int (*read)(void *,unsigned,uint8_t *,size_t);bool (*write)(void *,unsigned,const uint8_t *,size_t);} TLSIO;
uint32_t tls_crc(const uint8_t *,size_t);
void tls_file_encode(uint8_t *,unsigned,uint32_t);
bool tls_file_decode(const uint8_t *,int,TLSStored *);
TLSStored tls_load(const TLSIO *);
bool tls_store(const TLSIO *,TLSStored *,unsigned);
#endif
