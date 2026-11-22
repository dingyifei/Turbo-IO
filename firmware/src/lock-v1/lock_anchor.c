#include "lock_anchor.h"
#include <stddef.h>
#include <string.h>
extern void *stream_memalign(size_t,size_t),*stream_timer_next(void *);
#include "../lock_stock.h"   /* tio_key_interceptors: stock's input-interceptor list head (RAM word) */
#define ANCHOR_MAGIC 0x544c4b41u   /* "TLKA" */
/* Stock's node is {name, handler, u8 last result, next}; ours adds two words after it. */
typedef struct AnchorNode {const char *name;int (*handler)(void *);uint8_t last,pad[3];struct AnchorNode *next;uint32_t magic;void *state;} AnchorNode;
#if UINTPTR_MAX==0xffffffffu   /* the stock node layout is 32-bit; host tests run 64-bit */
_Static_assert(offsetof(AnchorNode,handler)==4&&offsetof(AnchorNode,last)==8&&offsetof(AnchorNode,next)==0xc&&offsetof(AnchorNode,magic)==0x10,"stock interceptor node");
#endif
static int pass(void *event){(void)event;return 0;}   /* never consumes a key */
static const char name[]="turbo_lock_anchor";
void *lock_anchor_ui(void (*tick)(void *)){
 void *t=NULL;
 for(unsigned j=0;j<512;j++){
  t=stream_timer_next(t);if(!t)return NULL;
  void (*cb)(void *);void *user;memcpy(&cb,(uint8_t *)t+TIO_STOCK_TIMER_CB,sizeof cb);
  if(cb==tick){memcpy(&user,(uint8_t *)t+TIO_STOCK_TIMER_USER,sizeof user);return user;}
 }
 return NULL;
}
void *lock_anchor_any(void){
 AnchorNode *n=tio_key_interceptors;
 return n&&n->handler==pass&&n->magic==ANCHOR_MAGIC?n->state:NULL;
}
void *lock_anchor_find(void){
 unsigned n=0;
 for(AnchorNode *p=tio_key_interceptors;p&&n<64;p=p->next,n++)if(p->handler==pass&&p->magic==ANCHOR_MAGIC)return p->state;
 return NULL;
}
bool lock_anchor_present(const void *state){return state&&lock_anchor_any()==state;}
bool lock_anchor_install(void *state){
 if(lock_anchor_present(state))return true;
 /* A node of ours that fell behind the head (something was put in front of it) is reused, not duplicated. */
 for(AnchorNode *p=tio_key_interceptors,*prev=NULL;p;prev=p,p=p->next){
  if(p->handler==pass&&p->magic==ANCHOR_MAGIC){
   if(prev)prev->next=p->next;
   p->state=state;p->next=prev?(AnchorNode *)tio_key_interceptors:p->next;
   __atomic_thread_fence(__ATOMIC_SEQ_CST);tio_key_interceptors=p;return true;
  }
 }
 AnchorNode *n=stream_memalign(8,sizeof *n);if(!n)return false;memset(n,0,sizeof *n);
 n->name=name;n->handler=pass;n->magic=ANCHOR_MAGIC;n->state=state;n->next=tio_key_interceptors;
 __atomic_thread_fence(__ATOMIC_SEQ_CST);tio_key_interceptors=n;return true;
}
