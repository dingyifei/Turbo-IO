#ifndef TIO_TILE_NATIVE_H
#define TIO_TILE_NATIVE_H
#include "tile_config.h"
void fm_tile_snapshot(TTVisible *);
unsigned fm_tile_count(void),fm_tile_id(unsigned),fm_tile_rank(unsigned);
bool fm_tiles_apply(void *),fm_tiles_busy(void);
void fm_tiles_forget(void *);
#endif
