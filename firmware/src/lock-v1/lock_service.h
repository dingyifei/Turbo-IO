#ifndef TIO_LOCK_SERVICE_H
#define TIO_LOCK_SERVICE_H
// Applies a decoded TLK: command to the lock state and the record, and builds the TKA: reply. No stock calls.
#include "lock_codec.h"
#include "lock_core.h"
#include "lock_store.h"
/* motion_start: sends "motion on" to the head-motion hook (NULL: none); MOTION_ON is refused when it fails. */
typedef struct {TLK lock;TLKSession session;TLRStored stored;bool motion_on,motion_supported;bool (*motion_start)(void);} TLKService;
void tlk_service_boot(TLKService *,const TLRIO *);
// allowed: the TLK gate (no OTA running, bonded, connected; not fold state or top app).
unsigned tlk_service_command(TLKService *,const TLKCommand *,TLKReply *,uint32_t now_ms,uint32_t now_s,uint32_t nonce,const uint8_t salt[TLK_SALT_LEN],bool allowed,const TLRIO *);
// Writes the record if the lock state changed it (wrong tries, unlock after wrong tries). False when the write failed.
bool tlk_service_persist(TLKService *,const TLRIO *);
#endif
