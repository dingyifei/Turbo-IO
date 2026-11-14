#ifndef TURBO_DIAGNOSTICS_NATIVE_LIGHT_H
#define TURBO_DIAGNOSTICS_NATIVE_LIGHT_H
#include "diagnostics.h"
/* 1 (default): the Sensors page shows a Light line read through stock's latest-light getter. 0: no Light line and no
 * reference to the getter. */
#ifndef TIO_SENSORS_LIGHT
#define TIO_SENSORS_LIGHT 1
#endif
typedef struct {int owner_tid;} TDLightOwner;
/* LVGL UI memory: TD_LV_USED (bytes in use) and TD_LV_PEAK (most ever in use). Not the light sensor. */
void td_stock_light(void *,TDDiagnostics *);
/* Stock's light debounce buckets (table A on 1.0.6.11): 0-1, 1-3, 3-10, 10-300, 300-600, 600-1000, 1000-4000,
 * 4000-5000 and 5000+ lux. */
#define TD_LIGHT_BUCKETS 9
#if TIO_SENSORS_LIGHT
/* The bucket (0..8) of the light value stock last cached, or -1 when there is none or it is not a lux value >= 0. */
int td_light_bucket(void);
#endif
#endif
