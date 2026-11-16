#ifndef TURBO_MENU_CONFIG_H
#define TURBO_MENU_CONFIG_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
enum { TML_QUERY=0,TML_SET=1,TML_OK=0,TML_BLOCKED=1,TML_SESSION=2,TML_STORAGE=3,TML_UNAVAILABLE=4 };
/* Layout record values: 1 is the TMG8 carousel, 2 and 3 are the grid row counts.
 *
 * Wire byte 7 of a TMG2 command is the peer byte: the newest glasses generation the phone has seen (from the caps bits of the glasses'
 * own status) and speaks for. It is 0 on every query and on every command meant for TMG7 or older glasses, which require exactly that.
 *   TML_PEER_TMG8  the phone has seen TD_CAP_MENU_CAROUSEL. Written only on a carousel SET (value 1).
 *   TML_PEER_TMG9  the phone has seen TD_CAP_KNOB_DETENT. TMG9 is a superset of TMG8: it is accepted wherever TMG8 is (the carousel) and also
 *                  on a grid SET (values 2 and 3), so a TMG9 peer can set any layout and carry D in the same command.
 * Wire bytes 24..27 (the spare u32) are the knob detent D, 300..600 raw counts in steps of 50. They are 0 on every query and on every
 * command whose peer byte is not TML_PEER_TMG9. In a TMG9 SET, D = 0 means "leave the stored D unchanged" (a layout change from a TMG9 phone
 * that does not touch the knob step must not reset it), and a non-zero D must be in range and a multiple of 50. A command that breaks any of
 * this is refused by tml_decode and again by tml_accept (TML_BLOCKED, session token dropped). TMG8 glasses reject byte 7 = 2 and a non-zero
 * u32 at 24 outright, so a phone must never send either to a peer that did not report TD_CAP_KNOB_DETENT.
 *
 * Storage (TMC2, the 20-byte record in the two-bank file): byte 6 holds D/50 (6..12), 0 meaning the default 400. A record is written with
 * byte 6 = 0 whenever D is the default, which keeps it readable by TMG7 and TMG8 (they require byte 6 = 0 and ignore the record otherwise). */
enum { TML_CAROUSEL=1,TML_PEER_TMG8=1,TML_PEER_TMG9=2 };
enum { TML_DETENT_MIN=300,TML_DETENT_MAX=600,TML_DETENT_STEP=50,TML_DETENT_DEFAULT=400 };
typedef struct {uint32_t request,token,generation,client,detent;uint8_t op,rows,caps;} TMLCommand; /* detent: D, or 0 = unchanged / absent */
typedef struct {uint32_t generation;unsigned rows,bank;bool readable;unsigned detent;} TMLStored; /* detent: the live D; 0 reads as the default */
typedef struct {uint32_t token,client,issued;TMLStored stored;} TMLState;
typedef struct {void *ctx;int (*read)(void *,unsigned,uint8_t *,size_t);bool (*write)(void *,unsigned,const uint8_t *,size_t);} TMLIO;
uint32_t tml_crc(const uint8_t *,size_t);
bool tml_decode(const uint8_t *,size_t,TMLCommand *);
void tml_encode(uint8_t *,const TMLCommand *);
size_t tml_carrier(uint8_t *,const uint8_t *,bool);
bool tml_uncarrier(const uint8_t *,size_t,uint8_t *,bool);
TMLStored tml_load(const TMLIO *);
bool tml_detent_valid(unsigned);            /* 300..600 in steps of 50 */
unsigned tml_detent(const TMLStored *);      /* the live D: the stored value, or 400 when none is stored */
bool tml_store(const TMLIO *,TMLStored *,unsigned rows,unsigned detent); /* detent 0: keep the current D */
unsigned tml_accept(TMLState *,const TMLCommand *,uint32_t,uint32_t,bool,const TMLIO *);
void tml_reply(uint8_t *,const TMLState *,const TMLCommand *,unsigned);
unsigned fm_menu_rows(void); /* the stored layout value: 1 carousel, 2 or 3 grid rows */
void fm_relayout(unsigned);
#endif
