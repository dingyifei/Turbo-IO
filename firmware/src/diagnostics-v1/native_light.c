/* Read-only stock providers on 1.0.6.11, for the status sample and the Sensors page. Nothing here allocates, logs,
 * writes flash, touches I2C, starts or stops a sensor, walks blocks or reads arbitrary memory. */
#include "native_light.h"
#include <string.h>
/* UI heap: the LVGL global plus TIO_STOCK_LVGL_MEM_USED / TIO_STOCK_LVGL_MEM_PEAK, two word loads with no lock (the
 * LVGL allocator updates them without one, on the LVGL task). tests/stock_layout_test.py proves both offsets from two
 * stock functions each and checks that the rebase table's native_light_current and native_light_peak values equal
 * the LVGL global (table value display_unit) plus them; tools/rebase_apply.py writes the addresses. The pool capacity
 * has one witness only, so TD_LV_TOTAL is not reported and no capacity bound is applied. */
extern int td_gettid(void); /* Native gettid, hash-pinned by candidate builder. */
void td_stock_light(void *context,TDDiagnostics *d){
 TDLightOwner *owner=context;
 td_metric(d,TD_LV_TOTAL,0,false);td_metric(d,TD_LV_USED,0,false);td_metric(d,TD_LV_PEAK,0,false);
 if(!owner||owner->owner_tid<0||td_gettid()!=owner->owner_tid)return;
 const volatile uint32_t *current=(const volatile uint32_t *)(uintptr_t)0x1850cfd8;
 const volatile uint32_t *peak=(const volatile uint32_t *)(uintptr_t)0x1850cfdc;
 uint32_t a=*current,b=*peak;
 if(a>b)return; /* fail closed: the peak is never below the count in use */
 td_metric(d,TD_LV_USED,a,true);td_metric(d,TD_LV_PEAK,b,true);
 /* System heap/free/largest block/CPU/boot count intentionally unavailable. */
}
#if TIO_SENSORS_LIGHT
/* Stock's latest-light getter (link.ld). It copies the light manager's cached sample (TIO_STOCK_LIGHT_SAMPLE_BYTES)
 * to the buffer under the manager's mutex and returns 1, or returns 0 and leaves the buffer as it was when nothing has
 * been cached since boot (or the manager never started). No I2C; it never starts or stops the sensor. The cache
 * changes only when stock publishes a new debounce bucket, so a bucket is all the value can honestly show. */
extern int tio_light_latest(void *sample);
/* The low edge of each of stock's debounce buckets. tests/native_light_host_test.py reads stock's bucket table from the
 * AP image on every run and requires these values, TD_LIGHT_BUCKETS and the upper bound below to match it bit for bit. */
static const float edges[TD_LIGHT_BUCKETS]={0.0f,1.0f,3.0f,10.0f,300.0f,600.0f,1000.0f,4000.0f,5000.0f};
int td_light_bucket(void){
 uint8_t sample[TIO_STOCK_LIGHT_SAMPLE_BYTES]={0};
 if(tio_light_latest(sample)!=1)return -1;
 float lux;memcpy(&lux,sample+TIO_STOCK_LIGHT_SAMPLE_LUX,sizeof lux);
 if(!(lux>=0.0f)||lux>3.4028234e38f)return -1; /* NaN, negative or infinite: not a lux value */
 int k=0;
 while(k<TD_LIGHT_BUCKETS-1&&lux>=edges[k+1])k++;
 return k;
}
#endif
