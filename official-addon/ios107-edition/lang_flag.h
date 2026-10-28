#ifndef TURBO_LANG_FLAG_H
#define TURBO_LANG_FLAG_H
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
enum { TLG_QUERY=0, TLG_SET=1, TLG_EN=0, TLG_ZH=1,
       TLG_OK=0, TLG_BLOCKED=1, TLG_INVALID=2, TLG_STORAGE=3, TLG_UNAVAILABLE=4,
       TLG_SOURCE_DEFAULT=0, TLG_SOURCE_PHONE=1, TLG_SOURCE_PERSISTED=2 };
typedef struct { uint32_t request; uint8_t op,lang; } TLGCommand;
typedef struct { uint32_t request; uint8_t op,lang,result,source; } TLGReply;
uint32_t tlg_crc(const uint8_t *,size_t);
void tlg_encode(uint8_t *,const TLGCommand *);
bool tlg_decode(const uint8_t *,size_t,TLGCommand *);
void tlg_reply_encode(uint8_t *,const TLGReply *);
bool tlg_reply_decode(const uint8_t *,size_t,TLGReply *);
size_t tlg_carrier(uint8_t *,const uint8_t *,bool);
bool tlg_uncarrier(const uint8_t *,size_t,uint8_t *,bool);
#endif
