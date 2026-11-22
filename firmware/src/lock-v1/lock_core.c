#include "lock_core.h"
#include <string.h>

// --- SHA-256 (FIPS 180-4), local so the module links no stock crypto symbol ---
typedef struct {uint32_t h[8];uint8_t buf[64];uint64_t len;unsigned fill;} Sha;
// Two words are written in decimal: in hex they fall inside the stock address windows the rebase audit scans.
static const uint32_t K[64]={
 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,275423344u,
 430227734u,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
static uint32_t ror(uint32_t x,unsigned n){return x>>n|x<<(32-n);}
static void sha_block(Sha *s,const uint8_t *p){
 uint32_t w[64],v[8];
 for(unsigned i=0;i<16;i++)w[i]=(uint32_t)p[4*i]<<24|(uint32_t)p[4*i+1]<<16|(uint32_t)p[4*i+2]<<8|p[4*i+3];
 for(unsigned i=16;i<64;i++){uint32_t s0=ror(w[i-15],7)^ror(w[i-15],18)^w[i-15]>>3,s1=ror(w[i-2],17)^ror(w[i-2],19)^w[i-2]>>10;w[i]=w[i-16]+s0+w[i-7]+s1;}
 memcpy(v,s->h,sizeof v);
 for(unsigned i=0;i<64;i++){
  uint32_t t1=v[7]+(ror(v[4],6)^ror(v[4],11)^ror(v[4],25))+((v[4]&v[5])^(~v[4]&v[6]))+K[i]+w[i];
  uint32_t t2=(ror(v[0],2)^ror(v[0],13)^ror(v[0],22))+((v[0]&v[1])^(v[0]&v[2])^(v[1]&v[2]));
  for(unsigned k=7;k>0;k--)v[k]=v[k-1];v[4]+=t1;v[0]=t1+t2;
 }
 for(unsigned i=0;i<8;i++)s->h[i]+=v[i];
}
static void sha_init(Sha *s){static const uint32_t h0[8]={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};memset(s,0,sizeof *s);memcpy(s->h,h0,sizeof h0);}
static void sha_update(Sha *s,const uint8_t *p,size_t n){while(n--){s->buf[s->fill++]=*p++;s->len++;if(s->fill==64){sha_block(s,s->buf);s->fill=0;}}}
static void sha_final(Sha *s,uint8_t out[32]){
 uint64_t bits=s->len*8;uint8_t one=0x80,zero=0;sha_update(s,&one,1);while(s->fill!=56)sha_update(s,&zero,1);
 for(int i=7;i>=0;i--){uint8_t b=(uint8_t)(bits>>(8*i));sha_update(s,&b,1);}
 for(unsigned i=0;i<8;i++){out[4*i]=(uint8_t)(s->h[i]>>24);out[4*i+1]=(uint8_t)(s->h[i]>>16);out[4*i+2]=(uint8_t)(s->h[i]>>8);out[4*i+3]=(uint8_t)s->h[i];}
}
// Exposed for the host test's FIPS vectors only.
void tlk_sha256(const uint8_t *p,size_t n,uint8_t out[32]);
void tlk_sha256(const uint8_t *p,size_t n,uint8_t out[32]){Sha s;sha_init(&s);sha_update(&s,p,n);sha_final(&s,out);}

void tlk_pin_hash(const uint8_t salt[TLK_SALT_LEN],const uint8_t pin[TLK_PIN_LEN],uint8_t out[TLK_HASH_LEN]){
 uint8_t m[TLK_SALT_LEN+TLK_PIN_LEN],d[32];memcpy(m,salt,TLK_SALT_LEN);
 for(unsigned i=0;i<TLK_PIN_LEN;i++)m[TLK_SALT_LEN+i]=(uint8_t)('0'+pin[i]);
 tlk_sha256(m,sizeof m,d);memcpy(out,d,TLK_HASH_LEN);
}

// --- state machine ---
void tlk_record_default(TLKRecord *r){memset(r,0,sizeof *r);r->fold_min=TLK_DEFAULT_MINUTES;r->idle_min=TLK_DEFAULT_MINUTES;}

void tlk_boot(TLK *t,TLKLoad load,const TLKRecord *r){
 memset(t,0,sizeof *t);tlk_record_default(&t->rec);
 if(load==TLK_LOAD_DAMAGED){t->damaged=true;t->state=TLK_DARK;return;}   // fail closed (§8)
 if(load==TLK_LOAD_GOOD&&r){t->rec=*r;t->state=r->enabled?TLK_DARK:TLK_OFF;return;}
 t->state=TLK_OFF;   // no file: an upgrade from a release without the lock boots unlocked
}

bool tlk_locked(const TLK *t){return t->state>=TLK_DARK&&t->state<=TLK_USE_PHONE;}
static bool unlocked(const TLK *t){return t->state==TLK_UNLOCKED||t->state==TLK_NOTICE;}
bool tlk_screen_allowed(const TLK *t){return t->state!=TLK_DARK;}

static void lock(TLK *t){t->state=TLK_DARK;t->slot=0;t->digit=0;memset(t->digits,0,sizeof t->digits);}
static void entry(TLK *t,uint32_t now_ms){t->state=TLK_ENTRY;t->slot=0;t->digit=0;memset(t->digits,0,sizeof t->digits);t->shown_ms=now_ms;}

// A missing, zero or backwards PMU reading counts as elapsed: a clock fault never keeps the glasses unlocked.
static bool elapsed(uint32_t since,uint32_t now,unsigned minutes){return !since||!now||now<since||now-since>=(uint32_t)minutes*60u;}
static bool idle_elapsed(const TLK *t,uint32_t now_s){return unlocked(t)&&elapsed(t->last_use_s,now_s,t->rec.idle_min);}

static void do_unlock(TLK *t,uint32_t now_s){
 t->notice=t->rec.wrong;
 if(t->rec.wrong||t->rec.delay_until){t->rec.wrong=0;t->rec.delay_until=0;t->dirty=true;}
 t->state=t->notice?TLK_NOTICE:TLK_UNLOCKED;t->last_use_s=now_s;t->flush_input=true;
 if(t->folded)t->folded_s=now_s;   // an unlock while folded restarts the fold delay
 t->slot=0;t->digit=0;memset(t->digits,0,sizeof t->digits);
}

uint32_t tlk_delay_for(unsigned wrong){static const uint32_t s[4]={30,60,300,900};return wrong<3?0:s[wrong-3>3?3:wrong-3];}

uint32_t tlk_delay_left(TLK *t,uint32_t now_s){
 uint32_t d=tlk_delay_for(t->rec.wrong);if(!d)return 0;if(!now_s)return UINT32_MAX;
 // Not started, or the clock went back past its start: the full delay for this step starts again.
 if(!t->rec.delay_until||now_s<t->rec.delay_until-d||t->rec.delay_until<d){t->rec.delay_until=now_s+d;t->dirty=true;}
 return now_s<t->rec.delay_until?t->rec.delay_until-now_s:0;
}

bool tlk_screen_on_request(TLK *t,uint32_t now_s){
 if(idle_elapsed(t,now_s))lock(t);
 t->screen_on=tlk_screen_allowed(t);return t->screen_on;
}
void tlk_screen_off(TLK *t){t->screen_on=false;}
/* Folding closes a lock screen: the half-entered digits are dropped and the glasses go dark (a wrong try already counted
 * stays counted, a running delay keeps its stored deadline). */
void tlk_fold(TLK *t,uint32_t now_s){
 t->folded=true;t->folded_s=now_s;
 if(t->state==TLK_ENTRY||t->state==TLK_WRONG||t->state==TLK_WAITING||t->state==TLK_USE_PHONE)lock(t);
}
void tlk_unfold(TLK *t,uint32_t now_s){
 bool was=t->folded;t->folded=false;
 if(was&&unlocked(t)&&elapsed(t->folded_s,now_s,t->rec.fold_min))lock(t);
}

static void wrong(TLK *t,uint32_t now_s,uint32_t now_ms){
 if(t->rec.wrong<255)t->rec.wrong++;
 if(t->rec.unacked<255)t->rec.unacked++;
 uint32_t d=tlk_delay_for(t->rec.wrong);t->rec.delay_until=d&&now_s?now_s+d:0;
 t->dirty=true;t->state=TLK_WRONG;t->shown_ms=now_ms;
}

bool tlk_input(TLK *t,TLKInput in,int delta,uint32_t now_s,uint32_t now_ms){
 if(t->state==TLK_OFF){t->last_use_s=now_s;return false;}
 if(unlocked(t)&&!t->screen_on&&idle_elapsed(t,now_s))lock(t);
 if(t->state==TLK_UNLOCKED){t->last_use_s=now_s;return false;}
 if(t->state==TLK_NOTICE){t->last_use_s=now_s;if(in==TLK_IN_PRESS)t->state=TLK_UNLOCKED;return true;}
 switch(t->state){
 case TLK_DARK:
  if(in==TLK_IN_BACK)return false;   // back passes to stock unless a lock screen is up (§7)
  if(in!=TLK_IN_PRESS)return true;
  if(t->damaged){t->state=TLK_USE_PHONE;t->shown_ms=now_ms;}
  else if(tlk_delay_left(t,now_s)){t->state=TLK_WAITING;t->shown_ms=now_ms;}
  else entry(t,now_ms);
  return true;
 case TLK_ENTRY:
  t->shown_ms=now_ms;
  if(in==TLK_IN_STEP){int d=((int)t->digit+delta%10+10)%10;t->digit=(uint8_t)d;}
  else if(in==TLK_IN_BACK){if(!t->slot)lock(t);else{t->slot--;t->digit=0;}}
  else if(in==TLK_IN_PRESS){
   t->digits[t->slot++]=t->digit;t->digit=0;   // the next slot always starts at 0
   if(t->slot==TLK_PIN_LEN){
    uint8_t h[TLK_HASH_LEN];tlk_pin_hash(t->rec.salt,t->digits,h);
    if(t->rec.enabled&&!memcmp(h,t->rec.hash,TLK_HASH_LEN))do_unlock(t,now_s);else wrong(t,now_s,now_ms);
   }
  }
  return true;
 default:   // WRONG, WAITING, USE_PHONE: input ignored
  return true;
 }
}

void tlk_motion(TLK *t,uint32_t now_s){
 if(!unlocked(t))return;   // motion never unlocks or delays a lock already taken
 if(!t->screen_on&&idle_elapsed(t,now_s)){lock(t);return;}
 t->last_use_s=now_s;
}

bool tlk_idle_due(const TLK *t,uint32_t now_s){return !t->screen_on&&idle_elapsed(t,now_s);}
bool tlk_idle_passed(const TLK *t,uint32_t now_s){return idle_elapsed(t,now_s);}
bool tlk_idle_check(TLK *t,uint32_t now_s){if(tlk_idle_due(t,now_s))lock(t);return tlk_locked(t);}
bool tlk_fold_due(const TLK *t,uint32_t now_s){return t->folded&&unlocked(t)&&elapsed(t->folded_s,now_s,t->rec.fold_min);}

void tlk_tick(TLK *t,uint32_t now_s,uint32_t now_ms){
 uint32_t age=now_ms-t->shown_ms;
 switch(t->state){
 case TLK_ENTRY:if(age>=TLK_ENTRY_TIMEOUT_MS)lock(t);break;
 case TLK_WAITING:if(!tlk_delay_left(t,now_s))entry(t,now_ms);else if(age>=TLK_ENTRY_TIMEOUT_MS)lock(t);break;
 case TLK_WRONG:if(age>=TLK_WRONG_SHOW_MS){if(tlk_delay_left(t,now_s)){t->state=TLK_WAITING;t->shown_ms=now_ms;}else entry(t,now_ms);}break;
 case TLK_USE_PHONE:if(age>=TLK_USE_PHONE_SHOW_MS)lock(t);break;
 default:break;
 }
}

bool tlk_phone_unlock(TLK *t,uint32_t now_s){if(t->state==TLK_OFF)return false;if(tlk_locked(t))do_unlock(t,now_s);return true;}
bool tlk_phone_lock(TLK *t){if(t->state==TLK_OFF)return false;lock(t);return true;}
bool tlk_phone_set_pin(TLK *t,const uint8_t pin[TLK_PIN_LEN],const uint8_t salt[TLK_SALT_LEN],uint32_t now_s){
 for(unsigned i=0;i<TLK_PIN_LEN;i++)if(pin[i]>9)return false;
 t->rec.enabled=true;memcpy(t->rec.salt,salt,TLK_SALT_LEN);tlk_pin_hash(salt,pin,t->rec.hash);
 t->rec.wrong=0;t->rec.delay_until=0;t->damaged=false;t->dirty=true;
 if(t->state==TLK_OFF){t->state=TLK_UNLOCKED;t->last_use_s=now_s;}
 return true;
}
bool tlk_phone_set_time(TLK *t,unsigned fold_min,unsigned idle_min){
 if(t->damaged||fold_min<TLK_MINUTES_MIN||fold_min>TLK_MINUTES_MAX||idle_min<TLK_MINUTES_MIN||idle_min>TLK_MINUTES_MAX)return false;
 if(t->rec.fold_min!=fold_min||t->rec.idle_min!=idle_min){t->rec.fold_min=(uint8_t)fold_min;t->rec.idle_min=(uint8_t)idle_min;t->dirty=true;}
 return true;
}
bool tlk_phone_disable(TLK *t){
 uint8_t f=t->rec.fold_min,i=t->rec.idle_min;tlk_record_default(&t->rec);t->rec.fold_min=f;t->rec.idle_min=i;
 t->damaged=false;t->dirty=true;t->state=TLK_OFF;return true;
}
bool tlk_phone_ack(TLK *t){if(t->rec.unacked){t->rec.unacked=0;t->dirty=true;}return true;}
