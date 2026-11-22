// Host test for the PIN lock core: every row of the state table (docs/lock-design.md §2, §2a)
// and the start-up table (§8), the delay schedule, the delay across a simulated reboot,
// the focused digit starting at 0, and SHA-256 against FIPS 180-4 vectors.
#include "../src/lock-v1/lock_core.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

void tlk_sha256(const uint8_t *p,size_t n,uint8_t out[32]);
static void hex(const uint8_t *d,char *o){for(unsigned i=0;i<32;i++)snprintf(o+2*i,3,"%02x",d[i]);}
static void sha_vectors(void){
 uint8_t d[32];char h[65];
 tlk_sha256((const uint8_t *)"abc",3,d);hex(d,h);assert(!strcmp(h,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
 tlk_sha256((const uint8_t *)"",0,d);hex(d,h);assert(!strcmp(h,"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
 const char *m="abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
 tlk_sha256((const uint8_t *)m,strlen(m),d);hex(d,h);assert(!strcmp(h,"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"));
}

static const uint8_t PIN[4]={1,2,3,4},SALT[8]={9,8,7,6,5,4,3,2};
enum {T0=1000000};   // a valid PMU reading

static TLKRecord enabled_record(void){TLK t;tlk_boot(&t,TLK_LOAD_NONE,NULL);assert(tlk_phone_set_pin(&t,PIN,SALT,T0));return t.rec;}
static void boot_locked(TLK *t){TLKRecord r=enabled_record();tlk_boot(t,TLK_LOAD_GOOD,&r);assert(t->state==TLK_DARK);}
// Enter a PIN by knob from the current state; ms advances 100 per input.
static uint32_t ms;
#define enter(t,pin,now) enter_at(__LINE__,t,pin,now)
static void enter_at(int line,TLK *t,const uint8_t pin[4],uint32_t now_s){
 if(t->state!=TLK_ENTRY&&t->state!=TLK_DARK)fprintf(stderr,"enter at line %d from state %d\n",line,t->state);
 if(t->state!=TLK_ENTRY)assert(tlk_input(t,TLK_IN_PRESS,0,now_s,ms+=100));   // wake the PIN screen from dark
 for(unsigned i=0;i<4;i++){
  if(!(t->state==TLK_ENTRY&&t->slot==i&&t->digit==0))fprintf(stderr,"enter at line %d: state %d slot %u\n",line,t->state,t->slot);
  assert(t->state==TLK_ENTRY&&t->slot==i&&t->digit==0);   // the focused digit always starts at 0
  for(unsigned k=0;k<pin[i];k++)assert(tlk_input(t,TLK_IN_STEP,1,now_s,ms+=100));
  assert(tlk_input(t,TLK_IN_PRESS,0,now_s,ms+=100));
 }
}

static void startup_table(void){
 TLK t;TLKRecord r=enabled_record();
 tlk_boot(&t,TLK_LOAD_NONE,NULL);assert(t.state==TLK_OFF&&!tlk_locked(&t)&&tlk_screen_allowed(&t));   // no file: Off (TMG12 upgrade)
 tlk_boot(&t,TLK_LOAD_GOOD,&r);assert(t.state==TLK_DARK&&tlk_locked(&t)&&!tlk_screen_allowed(&t)); // good, enabled: Locked
 r.enabled=false;tlk_boot(&t,TLK_LOAD_GOOD,&r);assert(t.state==TLK_OFF);                            // good, disabled: Off
 tlk_boot(&t,TLK_LOAD_DAMAGED,NULL);assert(t.state==TLK_DARK&&t.damaged);                           // damaged: Locked
 // Damaged: knob refused with "Use phone" for 2 s, then dark; SET_TIME refused; phone unlock and SET_PIN work.
 ms=0;assert(tlk_input(&t,TLK_IN_PRESS,0,T0,ms)&&t.state==TLK_USE_PHONE&&tlk_screen_allowed(&t));
 assert(tlk_input(&t,TLK_IN_STEP,1,T0,ms+10)&&t.state==TLK_USE_PHONE);
 tlk_tick(&t,T0,ms+1999);assert(t.state==TLK_USE_PHONE);tlk_tick(&t,T0,ms+2000);assert(t.state==TLK_DARK);
 assert(!tlk_phone_set_time(&t,10,10));
 assert(tlk_phone_unlock(&t,T0)&&t.state==TLK_UNLOCKED&&t.damaged);
 assert(tlk_phone_lock(&t)&&t.state==TLK_DARK);
 assert(tlk_phone_set_pin(&t,PIN,SALT,T0)&&!t.damaged&&t.rec.enabled&&t.state==TLK_DARK&&t.dirty);
 tlk_boot(&t,TLK_LOAD_DAMAGED,NULL);assert(tlk_phone_disable(&t)&&t.state==TLK_OFF&&!t.damaged&&!t.rec.enabled);
 // 24 boots of an enabled record all start locked, whatever ran before.
 for(unsigned i=0;i<24;i++){r=enabled_record();tlk_boot(&t,TLK_LOAD_GOOD,&r);assert(t.state==TLK_DARK);}
}

static void transitions(void){
 TLK t;ms=0;
 // Knob press while dark -> PIN entry; correct PIN -> Unlocked (no wrong tries: no notice).
 boot_locked(&t);
 assert(tlk_input(&t,TLK_IN_STEP,3,T0,ms)&&t.state==TLK_DARK);           // turn while dark: consumed, nothing shown
 enter(&t,PIN,T0);assert(t.state==TLK_UNLOCKED&&t.flush_input&&!tlk_locked(&t)&&t.last_use_s==T0);
 assert(!tlk_input(&t,TLK_IN_PRESS,0,T0+1,ms+=100));                     // unlocked: input passes to stock
 // Digit wraps 9 -> 0 and backwards 0 -> 9.
 boot_locked(&t);assert(tlk_input(&t,TLK_IN_PRESS,0,T0,ms+=100));
 for(unsigned k=0;k<10;k++)tlk_input(&t,TLK_IN_STEP,1,T0,ms+=100);assert(t.digit==0);
 tlk_input(&t,TLK_IN_STEP,-1,T0,ms+=100);assert(t.digit==9);tlk_input(&t,TLK_IN_STEP,-23,T0,ms+=100);assert(t.digit==6);
 // Long press steps back one slot (digit back at 0), and on the first slot leaves to dark.
 tlk_input(&t,TLK_IN_PRESS,0,T0,ms+=100);assert(t.slot==1&&t.digit==0);
 tlk_input(&t,TLK_IN_STEP,4,T0,ms+=100);tlk_input(&t,TLK_IN_BACK,0,T0,ms+=100);assert(t.slot==0&&t.digit==0&&t.state==TLK_ENTRY);
 assert(tlk_input(&t,TLK_IN_BACK,0,T0,ms+=100)&&t.state==TLK_DARK);
 assert(!tlk_input(&t,TLK_IN_BACK,0,T0,ms+=100)&&t.state==TLK_DARK);      // back while dark passes to stock
 // 30 s without input on the PIN screen -> dark; input restarts the 30 s.
 tlk_input(&t,TLK_IN_PRESS,0,T0,ms=50000);tlk_tick(&t,T0,ms+29999);assert(t.state==TLK_ENTRY);
 tlk_input(&t,TLK_IN_STEP,1,T0,ms+29999);tlk_tick(&t,T0,ms+30000);assert(t.state==TLK_ENTRY);
 tlk_tick(&t,T0,ms+29999+30000);assert(t.state==TLK_DARK);
 // Phone "Lock now" -> dark; phone unlock -> unlocked; both refused while Off.
 assert(tlk_phone_unlock(&t,T0)&&t.state==TLK_UNLOCKED);assert(tlk_phone_lock(&t)&&t.state==TLK_DARK);
 tlk_boot(&t,TLK_LOAD_NONE,NULL);assert(!tlk_phone_lock(&t)&&!tlk_phone_unlock(&t,T0)&&t.state==TLK_OFF);
 assert(!tlk_input(&t,TLK_IN_PRESS,0,T0,ms)&&t.state==TLK_OFF);           // Off: everything passes
 // SET_PIN from Off -> Unlocked (no lock now); SET_PIN while locked keeps it locked; bad digits refused.
 uint8_t bad[4]={1,2,3,10};assert(!tlk_phone_set_pin(&t,bad,SALT,T0)&&t.state==TLK_OFF);
 assert(tlk_phone_set_pin(&t,PIN,SALT,T0)&&t.state==TLK_UNLOCKED&&t.last_use_s==T0);
 assert(tlk_screen_on_request(&t,T0+10));                                   // fresh enable is not idle
 tlk_phone_lock(&t);uint8_t pin2[4]={0,0,0,7};assert(tlk_phone_set_pin(&t,pin2,SALT,T0)&&t.state==TLK_DARK);
 enter(&t,pin2,T0);assert(t.state==TLK_UNLOCKED);
 // DISABLE from any state -> Off.
 tlk_phone_lock(&t);assert(tlk_phone_disable(&t)&&t.state==TLK_OFF&&!t.rec.enabled);
 // SET_TIME range.
 boot_locked(&t);assert(!tlk_phone_set_time(&t,0,5)&&!tlk_phone_set_time(&t,5,241)&&tlk_phone_set_time(&t,240,1)&&t.rec.fold_min==240&&t.rec.idle_min==1);
}

static void wrong_tries(void){
 TLK t;ms=0;boot_locked(&t);uint8_t bad[4]={4,3,2,1};
 // Delay schedule from the wrong-try count.
 assert(tlk_delay_for(0)==0&&tlk_delay_for(2)==0&&tlk_delay_for(3)==30&&tlk_delay_for(4)==60&&tlk_delay_for(5)==300&&tlk_delay_for(6)==900&&tlk_delay_for(200)==900);
 uint32_t now=T0;
 for(unsigned n=1;n<=2;n++){
  enter(&t,bad,now);assert(t.state==TLK_WRONG&&t.rec.wrong==n&&t.rec.unacked==n&&t.dirty&&tlk_screen_allowed(&t));
  assert(tlk_input(&t,TLK_IN_PRESS,0,now,ms+=100)&&t.state==TLK_WRONG);   // input ignored during "Wrong PIN"
  tlk_tick(&t,now,ms+2000);assert(t.state==TLK_ENTRY&&t.slot==0&&t.digit==0);   // then the slots again
  tlk_input(&t,TLK_IN_BACK,0,now,ms+=2100);assert(t.state==TLK_DARK);
 }
 enter(&t,bad,now);assert(t.rec.wrong==3&&t.rec.delay_until==now+30);
 tlk_tick(&t,now,ms+=2000);assert(t.state==TLK_WAITING&&tlk_screen_allowed(&t));
 assert(tlk_input(&t,TLK_IN_PRESS,0,now,ms+=100)&&t.state==TLK_WAITING);  // knob ignored while waiting
 tlk_tick(&t,now+29,ms+=100);assert(t.state==TLK_WAITING);
 tlk_tick(&t,now+30,ms+=100);assert(t.state==TLK_ENTRY);                  // delay over while shown: slots appear
 now+=30;
 // Waiting screen also goes dark after 30 s; a press while dark during a delay shows waiting, not slots.
 enter(&t,bad,now);assert(t.rec.wrong==4&&t.rec.delay_until==now+60);tlk_tick(&t,now,ms+=2000);assert(t.state==TLK_WAITING);
 tlk_tick(&t,now+31,ms+=30000);assert(t.state==TLK_DARK);
 assert(tlk_input(&t,TLK_IN_PRESS,0,now+40,ms+=100)&&t.state==TLK_WAITING);
 // Reboot during the delay: the record keeps count and deadline; a valid clock continues the remaining time.
 TLKRecord saved=t.rec;tlk_boot(&t,TLK_LOAD_GOOD,&saved);assert(t.state==TLK_DARK&&tlk_delay_left(&t,now+45)==15);
 // Reboot with no valid clock: running (knob waits); first valid reading after a backwards jump restarts the full step.
 tlk_boot(&t,TLK_LOAD_GOOD,&saved);assert(tlk_delay_left(&t,0)==UINT32_MAX);
 assert(tlk_delay_left(&t,now-500)==60&&t.rec.delay_until==now-440);
 // With no valid clock a running delay shows the waiting screen.
 tlk_boot(&t,TLK_LOAD_GOOD,&saved);assert(tlk_input(&t,TLK_IN_PRESS,0,0,ms+=100)&&t.state==TLK_WAITING);
 // A wrong try with no valid clock stores no deadline; the full delay starts at the first valid reading.
 tlk_boot(&t,TLK_LOAD_GOOD,&saved);t.rec.wrong=2;t.rec.delay_until=0;enter(&t,bad,0);assert(t.rec.wrong==3&&t.rec.delay_until==0);
 assert(tlk_delay_left(&t,now)==30&&t.rec.delay_until==now+30);
 // Later tries: 5 min, then 15 min for every later try.
 tlk_boot(&t,TLK_LOAD_GOOD,&saved);t.rec.wrong=4;t.rec.delay_until=now;   // the 4th delay is over
 enter(&t,bad,now);assert(t.rec.delay_until==now+300);now+=300;tlk_tick(&t,now,ms+=2000);tlk_tick(&t,now,ms+=100);assert(t.state==TLK_ENTRY);
 tlk_input(&t,TLK_IN_BACK,0,now,ms+=100);
 enter(&t,bad,now);assert(t.rec.delay_until==now+900);now+=900;tlk_tick(&t,now,ms+=2000);tlk_input(&t,TLK_IN_BACK,0,now,ms+=100);
 enter(&t,bad,now);assert(t.rec.delay_until==now+900&&t.rec.wrong==7);now+=900;tlk_tick(&t,now,ms+=2000);tlk_input(&t,TLK_IN_BACK,0,now,ms+=100);
 // Correct PIN after wrong tries: failure notice with the count, counters reset, unacked kept for the phone.
 t.dirty=false;enter(&t,PIN,now);assert(t.state==TLK_NOTICE&&t.notice==7&&t.rec.wrong==0&&t.rec.delay_until==0&&t.dirty&&t.rec.unacked==7);
 assert(!tlk_locked(&t)&&tlk_screen_allowed(&t));
 assert(tlk_input(&t,TLK_IN_STEP,1,now,ms+=100)&&t.state==TLK_NOTICE);   // only a press dismisses it
 assert(tlk_input(&t,TLK_IN_PRESS,0,now,ms+=100)&&t.state==TLK_UNLOCKED);
 t.dirty=false;assert(tlk_phone_ack(&t)&&t.rec.unacked==0&&t.dirty);t.dirty=false;tlk_phone_ack(&t);assert(!t.dirty);
 // Phone unlock after wrong tries also shows the notice and clears the knob counter and delay.
 boot_locked(&t);enter(&t,bad,T0);tlk_tick(&t,T0,ms+=2000);assert(tlk_phone_unlock(&t,T0)&&t.state==TLK_NOTICE&&t.notice==1&&t.rec.wrong==0);
 // Unlock with no new wrong tries after a notice: no second notice.
 tlk_phone_lock(&t);assert(tlk_phone_unlock(&t,T0)&&t.state==TLK_UNLOCKED);
 // SET_PIN resets the knob counter and delay (forgotten-PIN path).
 boot_locked(&t);t.rec.wrong=6;t.rec.delay_until=T0+900;assert(tlk_phone_set_pin(&t,PIN,SALT,T0)&&t.rec.wrong==0&&t.rec.delay_until==0);
 assert(tlk_input(&t,TLK_IN_PRESS,0,T0,ms+=100)&&t.state==TLK_ENTRY);
 // Counters saturate.
 boot_locked(&t);t.rec.wrong=255;t.rec.unacked=255;t.rec.delay_until=T0;enter(&t,bad,T0);assert(t.rec.wrong==255&&t.rec.unacked==255);
}

// Lock, then unlock by phone at now: a fresh unlocked state with last use = now.
static void fresh(TLK *t,uint32_t now){tlk_phone_lock(t);assert(tlk_phone_unlock(t,now));t->screen_on=false;}
static void fold_and_idle(void){
 TLK t;ms=0;uint32_t now=T0;
 boot_locked(&t);fresh(&t,now);t.flush_input=false;
 // Unfold: lock if folded time >= fold delay (5 min), not before.
 tlk_fold(&t,now);tlk_unfold(&t,now+299);assert(t.state==TLK_UNLOCKED);
 tlk_fold(&t,now);tlk_unfold(&t,now+300);assert(t.state==TLK_DARK);
 // Clock faults at unfold count as elapsed: zero, backwards, or no fold reading.
 fresh(&t,now);tlk_fold(&t,now);tlk_unfold(&t,0);assert(t.state==TLK_DARK);
 fresh(&t,now);tlk_fold(&t,now);tlk_unfold(&t,now-1);assert(t.state==TLK_DARK);
 fresh(&t,now);tlk_fold(&t,0);tlk_unfold(&t,now);assert(t.state==TLK_DARK);
 // Unfold without a fold seen does nothing; motion never delays the fold lock.
 fresh(&t,now);tlk_unfold(&t,now+10000);assert(t.state==TLK_UNLOCKED);
 tlk_fold(&t,now);tlk_motion(&t,now+200);tlk_unfold(&t,now+300);assert(t.state==TLK_DARK);
 // Folding closes a lock screen: digits dropped, dark; unfolding stays dark and a press opens a fresh entry.
 {TLK u;boot_locked(&u);u.flush_input=false;assert(tlk_input(&u,TLK_IN_PRESS,0,now,ms+=100)&&u.state==TLK_ENTRY);
  tlk_input(&u,TLK_IN_STEP,3,now,ms+=100);tlk_input(&u,TLK_IN_PRESS,0,now,ms+=100);assert(u.slot==1);
  tlk_fold(&u,now);assert(u.state==TLK_DARK&&u.slot==0&&u.digit==0&&u.digits[0]==0);
  tlk_unfold(&u,now+10);assert(u.state==TLK_DARK);
  assert(tlk_input(&u,TLK_IN_PRESS,0,now+10,ms+=100)&&u.state==TLK_ENTRY&&u.slot==0&&u.digit==0);}
 // A phone unlock while folded restarts the fold delay.
 tlk_fold(&t,now);assert(tlk_phone_unlock(&t,now+1000));tlk_unfold(&t,now+1100);assert(t.state==TLK_UNLOCKED);
 // Screen about to turn on: lock if idle >= idle time (5 min) since last use; the check runs before anything draws.
 t.last_use_s=now;tlk_screen_off(&t);assert(tlk_screen_on_request(&t,now+299)&&t.state==TLK_UNLOCKED);
 tlk_screen_off(&t);assert(!tlk_screen_on_request(&t,now+300)&&t.state==TLK_DARK&&!t.screen_on);
 fresh(&t,now);tlk_screen_off(&t);assert(!tlk_screen_on_request(&t,0)&&t.state==TLK_DARK);           // zero clock
 fresh(&t,now);tlk_screen_off(&t);assert(!tlk_screen_on_request(&t,now-5)&&t.state==TLK_DARK);       // backwards
 // Knob/key input is use: it moves the idle point.
 fresh(&t,now);tlk_screen_off(&t);assert(!tlk_input(&t,TLK_IN_STEP,1,now+200,ms+=100));
 assert(tlk_screen_on_request(&t,now+499));
 // Input while the screen is off after the idle time: lock first, and the input is handled as locked input.
 tlk_screen_off(&t);assert(tlk_input(&t,TLK_IN_PRESS,0,now+200+300,ms+=100)&&t.state==TLK_ENTRY);
 // Input while the screen is on never idle-locks.
 fresh(&t,now);assert(tlk_screen_on_request(&t,now+1));assert(!tlk_input(&t,TLK_IN_PRESS,0,now+10000,ms+=100)&&t.state==TLK_UNLOCKED);
 // Motion is use while unlocked; motion after the still period has passed locks instead (once still, locked even if picked up).
 fresh(&t,now);tlk_screen_off(&t);tlk_motion(&t,now+290);tlk_motion(&t,now+580);assert(t.state==TLK_UNLOCKED&&t.last_use_s==now+580);
 assert(tlk_screen_on_request(&t,now+800));
 tlk_screen_off(&t);tlk_motion(&t,now+580+300);assert(t.state==TLK_DARK);
 tlk_motion(&t,now+900);assert(t.state==TLK_DARK);                         // motion never unlocks
 // A display wake not caused by use (notification, phone) does not count as use: screen-on requests stamp nothing.
 fresh(&t,now);tlk_screen_off(&t);assert(tlk_screen_on_request(&t,now+100));tlk_screen_off(&t);
 assert(!tlk_screen_on_request(&t,now+300)&&t.state==TLK_DARK);
 // Notice state is still subject to the idle lock.
 boot_locked(&t);t.rec.wrong=1;fresh(&t,now);assert(t.state==TLK_NOTICE);tlk_screen_off(&t);
 assert(!tlk_screen_on_request(&t,now+300)&&t.state==TLK_DARK);
 // The read-only checks used by the screen gate match the transitions.
 fresh(&t,now);tlk_screen_off(&t);assert(!tlk_idle_due(&t,now+299)&&tlk_idle_due(&t,now+300)&&t.state==TLK_UNLOCKED);
 t.screen_on=true;assert(!tlk_idle_due(&t,now+300));t.screen_on=false;
 assert(!tlk_idle_check(&t,now+299)&&t.state==TLK_UNLOCKED&&tlk_idle_check(&t,now+300)&&t.state==TLK_DARK);
 fresh(&t,now);tlk_fold(&t,now);assert(!tlk_fold_due(&t,now+299)&&tlk_fold_due(&t,now+300)&&tlk_fold_due(&t,0));
 tlk_unfold(&t,now+1);assert(!tlk_fold_due(&t,now+1000)&&t.state==TLK_UNLOCKED);
 // Off ignores fold and idle.
 tlk_boot(&t,TLK_LOAD_NONE,NULL);tlk_fold(&t,now);tlk_unfold(&t,now+100000);assert(tlk_screen_on_request(&t,0)&&t.state==TLK_OFF);
 // SET_TIME changes the thresholds.
 boot_locked(&t);tlk_phone_set_time(&t,1,2);fresh(&t,now);tlk_fold(&t,now);tlk_unfold(&t,now+60);assert(t.state==TLK_DARK);
 fresh(&t,now);tlk_screen_off(&t);assert(tlk_screen_on_request(&t,now+119));tlk_screen_off(&t);assert(!tlk_screen_on_request(&t,now+120));
}

static void hash_props(void){
 uint8_t a[8],b[8],s2[8]={1};tlk_pin_hash(SALT,PIN,a);tlk_pin_hash(SALT,PIN,b);assert(!memcmp(a,b,8));
 tlk_pin_hash(s2,PIN,b);assert(memcmp(a,b,8));uint8_t p2[4]={1,2,3,5};tlk_pin_hash(SALT,p2,b);assert(memcmp(a,b,8));
 // Every one of the 10^4 PINs verifies only itself for a fixed salt (no 8-byte collision in the space).
 static uint8_t all[10000][8];for(unsigned n=0;n<10000;n++){uint8_t p[4]={n/1000,n/100%10,n/10%10,n%10};tlk_pin_hash(SALT,p,all[n]);}
 for(unsigned i=0;i<10000;i++)for(unsigned j=i+1;j<10000;j+=97)assert(memcmp(all[i],all[j],8));
}

int main(void){
 sha_vectors();startup_table();transitions();wrong_tries();fold_and_idle();hash_props();
 puts("PASS lock_core: start-up table, every state transition, delay schedule and reboot, fold/idle/motion with clock faults, digit at 0, SHA-256 vectors");
}
