#ifndef TIO_LOCK_CODEC_H
#define TIO_LOCK_CODEC_H
/* TLK: (phone to glasses, record magic TLK1) and TKA: (reply, magic TKA1) in the 74-byte business-15 carrier
 * (docs/lock-design.md §5). Shared byte-identical with the phone (ios-addon/lock_codec.{c,h}).
 *
 * Command record (32 bytes, little-endian): 0 "TLK1" | 4 version 1 | 5 op | 6..7 zero | 8 request (nonzero) | 12 token
 * (0 in QUERY) | 16 client (nonzero) | 20 fold min | 21 idle min (SET_TIME only, 1..240) | 22 PIN (SET_PIN only, four
 * decimal digits as two BCD bytes, first digit in the high nibble of byte 22) | 24..27 zero | 28 CRC-32 of 0..27.
 * Reply record: 0 "TKA1" | 4 version 1 | 5 op | 6 result | 7 flags | 8 request | 12 token (the new token in a QUERY
 * reply, else 0) | 16 client | 20 fold min | 21 idle min | 22 wrong tries (knob counter) | 23 wrong tries not
 * acknowledged | 24 delay seconds left (0xffffffff: running, clock invalid) | 28 CRC-32 of 0..27.
 * Every op but QUERY needs the token from a QUERY by the same client within 120 s; a token is used once. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum {TLK_OP_QUERY=1,TLK_OP_UNLOCK,TLK_OP_LOCK_NOW,TLK_OP_SET_PIN,TLK_OP_SET_TIME,TLK_OP_DISABLE,TLK_OP_ACK_FAILURES,TLK_OP_MOTION_ON,TLK_OP_LAST=TLK_OP_MOTION_ON};
enum {TLK_R_OK=0,TLK_R_BLOCKED,TLK_R_INVALID,TLK_R_STORAGE,TLK_R_UNAVAILABLE,TLK_R_SESSION,TLK_R_REFUSED};
enum {TLK_F_ENABLED=1,TLK_F_LOCKED=2,TLK_F_DAMAGED=4,TLK_F_MOTION=8,TLK_F_MOTION_SUPPORTED=16};
enum {TLK_TOKEN_MS=120000};
typedef struct {uint32_t request,token,client;uint8_t op,fold_min,idle_min,pin[4];} TLKCommand;
typedef struct {uint32_t request,token,client,delay_left;uint8_t op,result,flags,fold_min,idle_min,wrong,unacked;} TLKReply;
typedef struct {uint32_t token,client,issued;} TLKSession;
uint32_t tlk_crc(const uint8_t *,size_t);
void tlk_encode(uint8_t *,const TLKCommand *);
bool tlk_decode(const uint8_t *,size_t,TLKCommand *);
void tlk_reply_encode(uint8_t *,const TLKReply *);
bool tlk_reply_decode(const uint8_t *,size_t,TLKReply *);
size_t tlk_carrier(uint8_t *,const uint8_t *,bool reply);
bool tlk_uncarrier(const uint8_t *,size_t,uint8_t *,bool reply);
// Glasses side: QUERY issues `nonce` as the token; every other op must match it. Returns TLK_R_OK or TLK_R_SESSION/UNAVAILABLE.
unsigned tlk_session(TLKSession *,const TLKCommand *,uint32_t now_ms,uint32_t nonce);
#endif
