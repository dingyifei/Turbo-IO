#ifndef TIO_LOCK_STORE_H
#define TIO_LOCK_STORE_H
// The lock record: /mnt/nand_data/turbo_lock_v1_{0,1}.cfg, two banks, CRC'd, generation-numbered (docs/lock-design.md §8).
#include "lock_core.h"
enum {TLR_BYTES=48};
typedef struct {void *ctx;int (*read)(void *,unsigned,uint8_t *,size_t);bool (*write)(void *,unsigned,const uint8_t *,size_t);} TLRIO;
typedef struct {uint32_t generation;unsigned bank;} TLRStored;
uint32_t tlr_crc(const uint8_t *,size_t);
void tlr_encode(uint8_t *,const TLKRecord *,uint32_t generation);
bool tlr_decode(const uint8_t *,int,TLKRecord *,uint32_t *generation);
// Start-up table: both banks missing -> NONE; a valid bank -> GOOD (newest); anything else -> DAMAGED (fail closed).
TLKLoad tlr_load(const TLRIO *,TLKRecord *,TLRStored *);
// Writes the other bank with generation+1 and reads back. Unchanged records are skipped.
bool tlr_store(const TLRIO *,TLRStored *,const TLKRecord *);
#endif
