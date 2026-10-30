#ifndef TURBO_TILE_LIVE_H
#define TURBO_TILE_LIVE_H
#include <stdbool.h>
#include <stdint.h>
/* One read-only snapshot of the state the services already keep (TMG8 live tile state, tile_state.h turns it into text).
 * Each service fills only its own fields; nothing here writes, sends or wakes anything. Pointers borrow service memory
 * and are valid for the UI turn that filled them. */
enum { TS_ROAD_MAX=96 };   /* nav_runtime.h TN_ROAD_MAX (asserted in nav_service.c) */
typedef struct {
 bool phone;                                   /* bonded and connected (nav_bonded && nav_connection) */
 bool pomodoro;uint32_t pomodoro_ms;           /* timer running or paused, milliseconds left now */
 bool music_playing;uint32_t music_age_ms;const char *music_title;   /* last playing flag, ms since the phone last spoke, NUL-terminated within 96 bytes */
 bool nav_active,nav_stale;uint32_t nav_remaining_m;   /* route session, stale flag, metres to go */
 bool camera;                                  /* phone camera session open */
 bool nav_turn;uint8_t nav_icon;uint32_t nav_turn_m;char nav_road[TS_ROAD_MAX+1];   /* next turn (menu navigation title): route live and not stale, manoeuvre icon (TNIcon), metres to it, road name (UTF-8, may be empty) */
} TSLive;
#endif
