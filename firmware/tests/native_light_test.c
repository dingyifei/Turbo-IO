/* The production native_light.c (through native_light_host.inc, written by native_light_host_test.py) against a stub of
 * stock's latest-light getter and host copies of the two LVGL memory counters. The bucket edges checked here come from
 * native_light_stock_edges.inc, which the driver writes from the stock AP image. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "native_light.h"
static uint32_t host_lv_used, host_lv_peak;
static int tid = 7;
int td_gettid(void) { return tid; }
#if TIO_SENSORS_LIGHT
/* Stub of the stock getter: mode 1 copies the cached sample and returns 1; mode 0 returns 0 and leaves the buffer as it
 * was (as stock does when nothing is cached); mode 2 returns an unexpected value with a valid-looking sample. */
static int mode;
static unsigned calls;
static uint8_t cached[TIO_STOCK_LIGHT_SAMPLE_BYTES];
int tio_light_latest(void *out) {
    calls++;
    assert(out);
    if (mode == 0) return 0;
    memcpy(out, cached, sizeof cached);
    return mode == 2 ? 2 : 1;
}
static void cache_lux(float lux) {
    memset(cached, 0xa5, sizeof cached);   /* timestamp and IR bytes are not read */
    memcpy(cached + TIO_STOCK_LIGHT_SAMPLE_LUX, &lux, sizeof lux);
}
static int bucket_of(float lux) { mode = 1; cache_lux(lux); return td_light_bucket(); }
#include "native_light_stock_edges.inc"
#endif
#include "native_light_host.inc"
int main(void) {
    TDDiagnostics d;
    TDLightOwner owner = {7}, other = {8};
    /* UI heap: valid only for the owner thread and only when the peak is not below the count in use. */
    host_lv_used = 8790000; host_lv_peak = 8800000;
    td_init(&d, 0); td_stock_light(&owner, &d);
    assert(d.valid == ((1u << TD_LV_USED) | (1u << TD_LV_PEAK)) && d.values[TD_LV_USED] == 8790000 && d.values[TD_LV_PEAK] == 8800000);
    assert(!(d.valid & (1u << TD_LV_TOTAL)) && !d.values[TD_LV_TOTAL]);
    host_lv_used = host_lv_peak = 0xffffffffu;   /* no capacity bound any more */
    td_init(&d, 0); td_stock_light(&owner, &d);
    assert(d.values[TD_LV_USED] == 0xffffffffu && (d.valid & (1u << TD_LV_PEAK)));
    host_lv_used = 2; host_lv_peak = 1;
    td_init(&d, 0); td_stock_light(&owner, &d); assert(!d.valid);
    host_lv_used = 1; host_lv_peak = 2;
    td_init(&d, 0); td_stock_light(&other, &d); assert(!d.valid);
    td_init(&d, 0); td_stock_light(NULL, &d); assert(!d.valid);
#if TIO_SENSORS_LIGHT
    /* Light: the bucket edges are stock's table, read from the AP image by the driver; lo <= lux < hi. */
    float edge[TD_LIGHT_BUCKETS];
    _Static_assert(sizeof stock_edge_bits == sizeof edge, "one stock edge per bucket");
    memcpy(edge, stock_edge_bits, sizeof edge);
    for (int k = 0; k < TD_LIGHT_BUCKETS; k++) {
        assert(bucket_of(edge[k]) == k);
        if (k) assert(bucket_of(edge[k] - edge[k] / 4096.0f) == k - 1);
    }
    assert(bucket_of(3.4028234e38f) == TD_LIGHT_BUCKETS - 1 && bucket_of(-0.0f) == 0);
    float inf, nan;
    uint32_t inf_bits = 0x7f800000u, nan_bits = 0x7fc00000u;
    memcpy(&inf, &inf_bits, 4); memcpy(&nan, &nan_bits, 4);
    assert(bucket_of(-1.0f) == -1 && bucket_of(inf) == -1 && bucket_of(nan) == -1 && bucket_of(-inf) == -1);
    /* Not valid: the getter returns 0 (nothing cached) or anything but 1. */
    cache_lux(250.0f); mode = 0; assert(td_light_bucket() == -1);
    mode = 2; assert(td_light_bucket() == -1);
    mode = 1; assert(td_light_bucket() == 3);
    printf("PASS native light (Light line on): UI heap used/peak for the owner thread only, peak below use refused, no "
           "capacity reported; Light buckets at stock's %d edges read from the image, NaN/infinite/negative and a not-valid getter give n/a "
           "(%u getter calls)\n", TD_LIGHT_BUCKETS, calls);
#else
    printf("PASS native light (Light line off): UI heap used/peak for the owner thread only, peak below use refused, no "
           "capacity reported; no light getter referenced\n");
#endif
    return 0;
}
