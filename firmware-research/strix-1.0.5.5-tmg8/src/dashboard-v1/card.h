#ifndef TURBO_DASHBOARD_CARD_H
#define TURBO_DASHBOARD_CARD_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#define DC_SURFACE "turbo_ui_devcard_v1"
#define DC_COMPONENT "root"
/* Versioned test template. RAM is tenths of GB, disk is GB. No credentials. */
typedef struct {unsigned weekly,claude5h,claudeWeek,ramFree,ramTotal,diskFree,diskTotal,icons[3];} DCValues;
bool dc_parse(const char *,size_t,DCValues *);
/* Round 2 card (256x194, LensDashCard board). Intensities are the lens ladder of tio_ui.h written out as green values, because this file is
 * shared byte-for-byte with the phone: DC_MID = TIO_LENS_MID, DC_HIGH = TIO_LENS_HIGH, DC_FULL = TIO_LENS_FULL, DC_TRACK = TIO_LENS_TRACK
 * (native.c asserts it). No icons and no divider lines: the wire still carries icons[3] and dc_parse still checks it, dc_render ignores it. */
#define DC_W 256
#define DC_H 194
#define DC_SAFE 6
#define DC_MID   0x007700u
#define DC_HIGH  0x00b000u
#define DC_FULL  0x00ff00u
#define DC_TRACK 0x003800u
#define DC_BAR_W 70
#define DC_BAR_H 3
typedef struct {
 void *(*root)(void *parent);
 bool (*text)(void *,int x,int y,int w,int h,unsigned size,unsigned color,const char *);
 bool (*bar)(void *,int x,int y,int w,unsigned pct);   /* track DC_TRACK, fill DC_HIGH, DC_BAR_H high */
 void (*destroy)(void *);
} DCAPI;
void *dc_render(const DCAPI *,void *parent,const DCValues *);
#endif
