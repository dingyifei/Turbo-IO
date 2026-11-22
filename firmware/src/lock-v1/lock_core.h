#ifndef TIO_LOCK_CORE_H
#define TIO_LOCK_CORE_H
// Glasses PIN lock: the pure state machine (docs/lock-design.md §2, §2a, §3, §7, §8).
// No stock calls. Times: now_s = PMU clock seconds (0 = no valid reading), now_ms = boot-relative ms.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {TLK_PIN_LEN=4,TLK_SALT_LEN=8,TLK_HASH_LEN=8};
enum {TLK_MINUTES_MIN=1,TLK_MINUTES_MAX=240,TLK_DEFAULT_MINUTES=5};
enum {TLK_ENTRY_TIMEOUT_MS=30000,TLK_WRONG_SHOW_MS=2000,TLK_USE_PHONE_SHOW_MS=2000,TLK_UNLOCKED_SHOW_MS=2000};
/* Input on the PIN screen counts only once the screen has been lit for this long (the panel takes a moment to light on
 * the device; the press that woke it and impatient presses or turns before it is visible are dropped). */
enum {TLK_ENTRY_GRACE_MS=600};

typedef enum {
 TLK_OFF=0,        // no PIN set
 TLK_UNLOCKED,     // PIN set, in use
 TLK_DARK,         // locked, nobody interacting: display off
 TLK_ENTRY,        // locked, PIN screen
 TLK_WRONG,        // locked, "Wrong PIN" for 2 s
 TLK_WAITING,      // locked, delay running, "Try again in m:ss"
 TLK_USE_PHONE,    // locked, damaged record, "Use phone" for 2 s
 TLK_NOTICE,       // unlocked, failure notice until pressed
 TLK_UNLOCKED_MSG, // unlocked by the phone: "Unlocked" for 2 s, then the failure notice if there were wrong tries
} TLKState;

// What is kept in the lock file (two banks, see lock_store).
typedef struct {
 bool enabled;
 uint8_t fold_min,idle_min;
 uint8_t salt[TLK_SALT_LEN],hash[TLK_HASH_LEN];
 uint8_t wrong;          // consecutive wrong tries; reset at unlock
 uint8_t unacked;        // wrong tries the phone has not acknowledged
 uint32_t delay_until;   // PMU seconds; 0 = not started (restart the full delay)
} TLKRecord;

// How the stored record came back at boot (§8 start-up table).
typedef enum {TLK_LOAD_NONE=0,TLK_LOAD_GOOD,TLK_LOAD_DAMAGED} TLKLoad;

typedef struct {
 TLKRecord rec;
 TLKState state;
 bool damaged;           // both banks damaged: knob entry refused until SET_PIN/DISABLE
 bool dirty;             // rec changed; the caller writes it
 bool screen_on;
 uint8_t slot,digit,digits[TLK_PIN_LEN];
 uint8_t notice;         // wrong tries shown by the failure notice
 uint32_t shown_ms;      // when the current locked screen (or its last input) started
 uint32_t lit_ms;        // when the PIN screen was lit (tlk_entry_lit); input counts from lit_ms + TLK_ENTRY_GRACE_MS
 bool lit;               // the PIN screen has been lit since it was opened
 uint32_t folded_s;      // PMU seconds at fold; 0 = unknown
 bool folded;
 uint32_t last_use_s;    // later of input, motion and unlock; 0 = none since boot
 bool flush_input;       // set at unlock: the caller drops queued key/knob events
} TLK;

typedef enum {TLK_IN_STEP=1,TLK_IN_PRESS,TLK_IN_BACK,TLK_IN_OTHER} TLKInput;

void tlk_record_default(TLKRecord *);
void tlk_boot(TLK *,TLKLoad,const TLKRecord *);
bool tlk_locked(const TLK *);
bool tlk_screen_allowed(const TLK *);           // may the display be on now
bool tlk_screen_on_request(TLK *,uint32_t now_s); // runs the idle check, then answers tlk_screen_allowed
void tlk_screen_off(TLK *);
// Closes a lock screen to dark, dropping half-entered digits: at fold, and when something is drawn over the cover.
void tlk_close_screen(TLK *);
void tlk_fold(TLK *,uint32_t now_s);
void tlk_unfold(TLK *,uint32_t now_s);
// Knob/key input. Returns true when the lock consumed it (stock must not see it).
bool tlk_input(TLK *,TLKInput,int delta,uint32_t now_s,uint32_t now_ms);
void tlk_motion(TLK *,uint32_t now_s);
// The idle rule without input: true when unlocked, the screen is off and the idle time has passed (read-only; safe
// from the screen gate). tlk_idle_check applies it (locks) and returns whether the glasses are locked afterwards.
bool tlk_idle_due(const TLK *,uint32_t now_s);
bool tlk_idle_check(TLK *,uint32_t now_s);
// The idle time alone (unlocked and the idle time passed), whatever the cached screen flag says: the screen gate runs
// when stock asks to turn the panel on, which is itself the "leaving a screen-off period" event.
bool tlk_idle_passed(const TLK *,uint32_t now_s);
// The fold lock without an unfold event: true when unlocked, a fold was seen, and the fold delay has passed.
bool tlk_fold_due(const TLK *,uint32_t now_s);
void tlk_tick(TLK *,uint32_t now_s,uint32_t now_ms);
uint32_t tlk_delay_for(unsigned wrong);          // seconds of delay after this many wrong tries
uint32_t tlk_delay_left(TLK *,uint32_t now_s);   // 0 = no delay; UINT32_MAX = running, clock invalid
// Phone operations (TLK: commands). Return false when refused.
// A phone unlock while locked shows "Unlocked" (TLK_UNLOCKED_MSG) unless the glasses are folded.
bool tlk_phone_unlock(TLK *,uint32_t now_s,uint32_t now_ms);
// The caller lit the panel with the PIN screen up: input counts from now_ms + TLK_ENTRY_GRACE_MS; queued input is dropped.
void tlk_entry_lit(TLK *,uint32_t now_ms);
bool tlk_phone_lock(TLK *);
bool tlk_phone_set_pin(TLK *,const uint8_t pin[TLK_PIN_LEN],const uint8_t salt[TLK_SALT_LEN],uint32_t now_s);
bool tlk_phone_set_time(TLK *,unsigned fold_min,unsigned idle_min);
bool tlk_phone_disable(TLK *);
bool tlk_phone_ack(TLK *);
void tlk_pin_hash(const uint8_t salt[TLK_SALT_LEN],const uint8_t pin[TLK_PIN_LEN],uint8_t out[TLK_HASH_LEN]);
#endif
