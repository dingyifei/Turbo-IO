#ifndef TIO_STOCK_LAYOUT_H
#define TIO_STOCK_LAYOUT_H
/* Stock object layout on the tree's one stock base. Every value has two witnesses (a derived value: one, plus its
 * parts) in tests/stock_layout_witnesses.json, checked by tests/stock_layout_test.py against the stock AP.
 * Stock addresses are not here: link.ld, build-inputs.json edits and the active rebase table hold them.
 * Module-owned models (tile ids, wire formats, the module tail) are not here either. */
#if !defined(TD_STOCK_10412) || !defined(TD_STOCK_1055) || !defined(TD_STOCK_10512) || !defined(TD_STOCK_10611)
#error stock_layout.h: every TD_STOCK_* base define must be set (build.py stock_defines; host tests: tests/host_layout.py)
#endif
#if TD_STOCK_10412 + TD_STOCK_1055 + TD_STOCK_10512 + TD_STOCK_10611 != 1
#error stock_layout.h: exactly one TD_STOCK_* base define must be 1
#endif
#if !TD_STOCK_10611
#error stock_layout.h: no proven layout for this stock base (proven: 1.0.6.11; released 1.0.5.x trees rebuild from their fw/tmgN tags)
#endif

/* Stock carousel menu object: allocated by the module, built by the stock constructor. */
/* Menu object: size of the stock object; the module tail follows it. */
#define TIO_STOCK_MENU_BYTES 0x10cu
/* Menu object: the root LVGL object, parent of the dots container. */
#define TIO_STOCK_MENU_ROOT 0x4u
/* Menu object: the lottie animation object. */
#define TIO_STOCK_MENU_LOTTIE 0x8u
/* Menu object: first of the per-tile row pointers. */
#define TIO_STOCK_MENU_ROWS 0xcu
/* Menu object: number of stock tiles (rows, labels and dots). */
#define TIO_STOCK_MENU_TILES 8u
/* Menu object: the dots container. */
#define TIO_STOCK_MENU_DOTS_PARENT 0x6cu
/* Menu object: first of the per-tile dot pointers. */
#define TIO_STOCK_MENU_DOTS 0x70u
/* Menu object: the selected tile index. */
#define TIO_STOCK_MENU_SELECTED 0x98u
/* Menu object: the tile index the label shows. */
#define TIO_STOCK_MENU_LABEL_INDEX 0x9cu
/* Menu object: the current animation frame. */
#define TIO_STOCK_MENU_FRAME 0xa0u
/* Menu object: the byte that says the wheel listener is registered. */
#define TIO_STOCK_MENU_ACTIVE 0xa4u
/* Menu object: the embedded carousel motion state. */
#define TIO_STOCK_MENU_MOTION 0xb0u
/* Carousel motion state: the item count. */
#define TIO_STOCK_MOTION_COUNT 0x0u
/* Carousel motion state: the rounded scroll position (a float). */
#define TIO_STOCK_MOTION_POSITION 0x10u
/* Menu object: the scroll position the slide renderer draws (derived from its two parts). */
#define TIO_MENU_SCROLL_POSITION_OFFSET (TIO_STOCK_MENU_MOTION+TIO_STOCK_MOTION_POSITION)
/* Menu object: the byte that blocks wheel input while an external action runs. */
#define TIO_MENU_EXTERNAL_ACTION_OFFSET 0x100u
/* Menu animation: frames per tile. */
#define TIO_STOCK_MENU_FRAMES_PER_TILE 30u
/* Menu animation: the frame of tile 0. */
#define TIO_STOCK_MENU_FIRST_FRAME 15u

/* Launcher, view manager, LVGL timer, LVGL event, keys and encoder. */
/* Launcher object: the view manager it owns. */
#define TIO_STOCK_LAUNCHER_MANAGER 0x15cu
/* View manager: the carousel menu object. */
#define TIO_STOCK_MANAGER_MENU 0x10u
/* View manager: its state word. */
#define TIO_STOCK_MANAGER_STATE 0x1cu
/* LVGL timer: the callback. */
#define TIO_STOCK_TIMER_CB 0x8u
/* LVGL timer: the user data. */
#define TIO_STOCK_TIMER_USER 0xcu
/* LVGL event: the event code (16 bits). */
#define TIO_STOCK_EVENT_CODE 0x8u
/* LVGL event: the parameter pointer. */
#define TIO_STOCK_EVENT_PARAM 0x10u
/* LVGL event: the key event code. */
#define TIO_STOCK_EVENT_KEY 0xeu
/* Key id: the confirm key that key events carry. */
#define TIO_STOCK_KEY_CONFIRM 0x3au
/* Key id: the back key that key events carry. */
#define TIO_STOCK_KEY_BACK 0x3bu
/* Encoder input driver: the step count (16 bits, signed). */
#define TIO_STOCK_ENCODER_STEP 0x6u
/* Encoder input driver: nonzero when the wheel direction is reversed (a byte). */
#define TIO_STOCK_ENCODER_REVERSE 0x9u

/* LVGL global, draw units, display and layers. */
/* LVGL global: the head of the draw-unit list. */
#define TIO_STOCK_LVGL_DRAW_UNITS 0x124u
/* Draw unit: the next draw unit. */
#define TIO_STOCK_DRAW_UNIT_NEXT 0x0u
/* Draw unit: the dispatch callback. */
#define TIO_STOCK_DRAW_UNIT_DISPATCH 0xcu
/* Draw unit: the task it is drawing. */
#define TIO_STOCK_DRAW_UNIT_TASK 0x18u
/* Draw unit: size of a draw unit. */
#define TIO_STOCK_DRAW_UNIT_BYTES 0x20u
/* Display: the head of its layer list. */
#define TIO_STOCK_DISPLAY_LAYERS 0x2a0u
/* Layer: the next layer. */
#define TIO_STOCK_LAYER_NEXT 0x40u
/* Layer: the head of its draw-task list. */
#define TIO_STOCK_LAYER_TASKS 0x38u
/* LVGL global: memory in use. */
#define TIO_STOCK_LVGL_MEM_USED 0x1bcu
/* LVGL global: peak memory in use. */
#define TIO_STOCK_LVGL_MEM_PEAK 0x1c0u

/* Message queue, queued message and file callback table. */
/* Message queue: the highest module id a send accepts (ids start at 1). */
#define TIO_STOCK_QUEUE_MODULE_MAX 20u
/* Message queue: the launcher module's id. */
#define TIO_STOCK_QUEUE_LAUNCHER 1u
/* Launcher message handler: number of message ids its dispatcher handles (1 to this value). */
#define TIO_STOCK_MESSAGE_ID_MAX 51u
/* Launcher message handler: the id of a raw phone-link payload message. */
#define TIO_STOCK_MESSAGE_RNLINK 1u
/* Queued message: the message id. */
#define TIO_STOCK_MESSAGE_ID 0x0u
/* Queued message: the data pointer. */
#define TIO_STOCK_MESSAGE_DATA 0x4u
/* Queued message: the data length. */
#define TIO_STOCK_MESSAGE_LENGTH 0x8u
/* Queued message: the release function for the data (zero selects the default). */
#define TIO_STOCK_MESSAGE_RELEASE 0x14u
/* File callback table: the receive callback. */
#define TIO_STOCK_FILE_CB_RECEIVE 0x18u

#if TIO_STOCK_QUEUE_LAUNCHER < 1 || TIO_STOCK_QUEUE_LAUNCHER > TIO_STOCK_QUEUE_MODULE_MAX
#error stock_layout.h: the launcher queue id is outside stock's module range
#endif
#endif
