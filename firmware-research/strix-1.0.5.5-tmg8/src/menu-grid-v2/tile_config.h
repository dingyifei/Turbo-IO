#ifndef TIO_TILE_CONFIG_H
#define TIO_TILE_CONFIG_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
enum {TT_QUERY=0,TT_SET=1,TT_OK=0,TT_BLOCKED=1,TT_SESSION=2,TT_STORAGE=3,TT_UNAVAILABLE=4,TT_ITEMS=13};
typedef struct {uint8_t order[TT_ITEMS];uint16_t hide;} TTConfig;
typedef struct {uint8_t count,ids[TT_ITEMS],rank[TT_ITEMS];} TTVisible;
typedef struct {uint32_t request,token,generation,client;uint16_t rank,hide;uint8_t op;} TTCommand;
typedef struct {uint32_t request,token,generation,client;uint16_t rank,hide;uint8_t op,count,result;} TTReply;
typedef struct {uint32_t generation;unsigned bank;bool readable;TTConfig config;} TTStored;
typedef struct {uint32_t token,client,issued;TTStored stored;bool loaded;} TTState;
typedef struct {void *ctx;int (*read)(void *,unsigned,uint8_t *,size_t);bool (*write)(void *,unsigned,const uint8_t *,size_t);} TTIO;
void tt_default(TTConfig *);
bool tt_valid(const TTConfig *);
bool tt_rank(const TTConfig *,uint16_t *);
bool tt_unrank(unsigned,unsigned,TTConfig *);
bool tt_compact(const TTConfig *,TTVisible *);
uint32_t tt_crc(const uint8_t *,size_t);
void tt_encode(uint8_t *,const TTCommand *);
bool tt_decode(const uint8_t *,size_t,TTCommand *);
void tt_reply_encode(uint8_t *,const TTReply *);
bool tt_reply_decode(const uint8_t *,size_t,TTReply *);
size_t tt_carrier(uint8_t *,const uint8_t *,bool);
bool tt_uncarrier(const uint8_t *,size_t,uint8_t *,bool);
void tt_file_encode(uint8_t *,const TTConfig *,uint32_t);
bool tt_file_decode(const uint8_t *,int,TTStored *);
TTStored tt_load(const TTIO *);
bool tt_store(const TTIO *,TTStored *,const TTConfig *);
unsigned tt_accept(TTState *,const TTCommand *,uint32_t,uint32_t,bool,const TTIO *);
void tt_reply(uint8_t *,const TTState *,const TTCommand *,unsigned);
#endif
