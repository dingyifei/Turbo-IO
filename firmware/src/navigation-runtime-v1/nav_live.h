#ifndef TURBO_NAV_LIVE_H
#define TURBO_NAV_LIVE_H
/* TMG8: the menu's read-only view of the route session (tile line "<n> km to go" and the band T next-turn title). Pure over the runtime, so the host
 * tests run the same function nav_service.c does. The session outlives the Navigation page (tn_detach); it is shown while it is connected and not stale. */
#include "nav_runtime.h"
#include "../focus-v1/tile_live.h"
_Static_assert(TS_ROAD_MAX==TN_ROAD_MAX,"the menu's road buffer matches the scene's");
/* nav_turn means the session is connected and not stale; the road is copied bounded and NUL-terminated. A session kept without its page ends 60 s after
 * its last update or 30 s after its last packet (tn_tick); the read does not wait for that tick, so a title is never shown for a route already gone. */
static inline void tn_live_fill(const TNRuntime *r,uint32_t now,TSLive *out){
 if(!r||!out)return;
 bool live=r->active&&r->connected;
 if(live&&r->hidden&&((uint32_t)(now-r->last_update)>=TN_IDLE_MS||(uint32_t)(now-r->last_link)>=TN_LINK_MS))live=false;
 out->nav_active=live;out->nav_stale=r->stale;out->nav_remaining_m=r->scene.remaining_m;
 out->nav_turn=false;if(!live||r->stale)return;
 const TNScene *sc=&r->scene;out->nav_icon=sc->icon;out->nav_turn_m=sc->distance_m;
 unsigned n=0;while(n<TS_ROAD_MAX&&sc->road[n]){out->nav_road[n]=sc->road[n];n++;}out->nav_road[n]=0;out->nav_turn=true;
}
#endif
