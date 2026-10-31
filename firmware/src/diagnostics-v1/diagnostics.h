#ifndef TURBO_DIAGNOSTICS_V1_H
#define TURBO_DIAGNOSTICS_V1_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "knob_calibration.h"

/* All access MUST use the same existing UI executor. Not an ISR/BT-thread API.
 * No allocator, timer, storage, Bluetooth or sleep-lock ownership in this core. */
#define TD_RING 64u
#define TD_WIRE_BYTES 256u
#define TD_BUILD_TMG4 0x00040001u
#define TD_CAPS_ALL 0x3fu
#define TD_BUILD_TMG5 0x00050001u
#define TD_BUILD_TMG6 0x00060001u
#define TD_CAP_NAV_PASSING (1u<<8)
#define TD_CAP_NAV_SMOOTH 0x40u
#define TD_CAP_MUSIC_CONTROLS 0x80u
#define TD_CAPS_TMG5 (TD_CAPS_ALL|TD_CAP_NAV_SMOOTH|TD_CAP_MUSIC_CONTROLS)
#define TD_CAPS_TMG6 (TD_CAPS_TMG5|TD_CAP_NAV_PASSING)
/* TMG8: the glasses can show the carousel menu layout (layout record value 1). TMG7 and older never set it. */
#define TD_CAP_MENU_CAROUSEL (1u<<9)
#define TD_CAPS_TMG8 (TD_CAPS_TMG6|TD_CAP_MENU_CAROUSEL)
enum {TD_SAMPLE=0,TD_STATUS=1,TD_CALIBRATION=2};
enum {TD_EXT_NAND=1,TD_EXT_TILES=2,TD_EXT_LANGUAGE=4,TD_EXT_CALIBRATION=8};
#define TD_MAX_LEASE_MS 600000u
enum TDMetric {
 TD_LV_TOTAL, TD_LV_USED, TD_LV_PEAK, TD_LV_FREE, TD_LV_MAX_BLOCK,
 TD_SYS_TOTAL, TD_SYS_USED, TD_SYS_PEAK, TD_SYS_FREE, TD_SYS_MAX_BLOCK,
 TD_OWNED, TD_OWNED_PEAK, TD_ALLOC_FAILURES, TD_RX_COUNT, TD_RX_BYTES,
 TD_RX_MAX_MS, TD_RENDER_COUNT, TD_RENDER_MAX_MS, TD_ERRORS, TD_RESERVED,
 TD_METRICS
};
enum TDEventCode {TD_START=1,TD_STOP,TD_EXPIRED,TD_ALLOCATION_FAILED,TD_BAD_FREE,
 TD_RX,TD_RENDER,TD_ERROR,TD_SLOW_PROBE};
typedef struct {uint32_t sequence,tick_ms,code,a,b,c;} TDEvent;
typedef struct {
 uint32_t session,sequence,tick_ms,probe_ms,valid,build;
 uint32_t values[TD_METRICS],event_count,events_lost,flags;
 uint8_t kind,build_sha[32];uint32_t caps,extension_valid;
 uint64_t nand_total,nand_available;uint32_t tile_generation,detent;
 uint8_t language,language_source,calibration_state,calibration_result;
 uint32_t calibration_window,calibration_elapsed,calibration_samples;
 int64_t calibration_net;uint64_t calibration_absolute;
 uint32_t calibration_sequence,settings_flags;
} TDSample;
typedef struct {
 uint32_t build,session,started,lease_ms,last_sample,sample_seq,event_seq;
 uint32_t values[TD_METRICS],valid,count,head,lost;
 bool enabled,sampled;
 TDEvent events[TD_RING];
} TDDiagnostics;
void td_init(TDDiagnostics *,uint32_t build);
bool td_start(TDDiagnostics *,uint32_t session,uint32_t now,uint32_t lease_ms);
void td_stop(TDDiagnostics *,uint32_t now);
bool td_active(TDDiagnostics *,uint32_t now);
void td_metric(TDDiagnostics *,enum TDMetric,uint32_t value,bool valid);
void td_event(TDDiagnostics *,uint32_t now,enum TDEventCode,uint32_t,uint32_t,uint32_t);
void td_allocation(TDDiagnostics *,uint32_t now,uint32_t bytes,bool success);
bool td_free(TDDiagnostics *,uint32_t now,uint32_t bytes);
void td_rx(TDDiagnostics *,uint32_t now,uint32_t bytes,uint32_t elapsed_ms);
void td_render(TDDiagnostics *,uint32_t now,uint32_t elapsed_ms);
/* Probe is called only when due, enabled and connected; must be nonblocking,
 * O(1), execute in owner context, and must not walk heaps or create logs. */
typedef void (*TDProbe)(void *,TDDiagnostics *);
typedef uint32_t (*TDClock)(void *);
bool td_sample(TDDiagnostics *,uint32_t now,bool connected,TDProbe,TDClock,void *,TDSample *);
size_t td_events(const TDDiagnostics *,TDEvent *,size_t capacity);
bool td_encode(const TDSample *,uint8_t *,size_t);
bool td_decode(const uint8_t *,size_t,TDSample *);
uint32_t td_crc(const void *,size_t);
bool td_nand_metrics(const void *,size_t,uint64_t *,uint64_t *);
#endif
