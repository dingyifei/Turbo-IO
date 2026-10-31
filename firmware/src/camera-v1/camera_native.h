#ifndef TURBO_CAMERA_NATIVE_H
#define TURBO_CAMERA_NATIVE_H
#include "../image-upload-test/native_file_bridge.h"
#include "../focus-v1/tile_live.h"
typedef struct {void *row,*label,*icon,*dot,*app,*control;} TCSlot;
TCSlot *tc_slot_create(void *);
void tc_slot_destroy(TCSlot *);
void tc_slot_hidden(TCSlot *);
bool tc_slot_open(TCSlot *);
bool tc_native_visible(void *);
void tc_slot_live(TCSlot *,TSLive *);   /* read-only snapshot for the menu tile state */
bool tc_native_event(void *);
void tc_native_wheel(void *,int);
void tc_native_message(const TIONativeMessage *);
#endif
