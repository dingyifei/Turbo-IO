#include "lock_service.h"
#include <string.h>
void tlk_service_boot(TLKService *s,const TLRIO *io){
 memset(s,0,sizeof *s);TLKRecord r;TLKLoad load=tlr_load(io,&r,&s->stored);tlk_boot(&s->lock,load,load==TLK_LOAD_GOOD?&r:NULL);
}
bool tlk_service_persist(TLKService *s,const TLRIO *io){
 if(!s->lock.dirty)return true;if(!tlr_store(io,&s->stored,&s->lock.rec))return false;s->lock.dirty=false;return true;
}
static unsigned apply(TLKService *s,const TLKCommand *q,uint32_t now_s,const uint8_t salt[TLK_SALT_LEN]){
 TLK *t=&s->lock;
 switch(q->op){
 case TLK_OP_QUERY:return TLK_R_OK;
 case TLK_OP_UNLOCK:return tlk_phone_unlock(t,now_s)?TLK_R_OK:TLK_R_REFUSED;
 case TLK_OP_LOCK_NOW:return tlk_phone_lock(t)?TLK_R_OK:TLK_R_REFUSED;
 case TLK_OP_SET_PIN:return tlk_phone_set_pin(t,q->pin,salt,now_s)?TLK_R_OK:TLK_R_INVALID;
 case TLK_OP_SET_TIME:return tlk_phone_set_time(t,q->fold_min,q->idle_min)?TLK_R_OK:TLK_R_REFUSED;
 case TLK_OP_DISABLE:return tlk_phone_disable(t)?TLK_R_OK:TLK_R_REFUSED;
 case TLK_OP_ACK_FAILURES:return tlk_phone_ack(t)?TLK_R_OK:TLK_R_REFUSED;
 case TLK_OP_MOTION_ON:if(!s->motion_supported||t->state==TLK_OFF)return TLK_R_REFUSED;s->motion_on=true;return TLK_R_OK;
 default:return TLK_R_INVALID;
 }
}
unsigned tlk_service_command(TLKService *s,const TLKCommand *q,TLKReply *out,uint32_t now_ms,uint32_t now_s,uint32_t nonce,const uint8_t salt[TLK_SALT_LEN],bool allowed,const TLRIO *io){
 unsigned r;
 if(!allowed){s->session.token=0;r=TLK_R_BLOCKED;}
 else if((r=tlk_session(&s->session,q,now_ms,nonce))==TLK_R_OK){r=apply(s,q,now_s,salt);if(!tlk_service_persist(s,io)&&r==TLK_R_OK)r=TLK_R_STORAGE;}
 TLK *t=&s->lock;uint32_t left=tlk_delay_left(t,now_s);
 if(t->dirty)tlk_service_persist(s,io);   // a delay restarted by the read above
 *out=(TLKReply){.request=q->request,.client=q->client,.op=q->op,.result=(uint8_t)r,.delay_left=left,
  .token=q->op==TLK_OP_QUERY&&r==TLK_R_OK?s->session.token:0,
  .flags=(uint8_t)((t->rec.enabled?TLK_F_ENABLED:0)|(tlk_locked(t)?TLK_F_LOCKED:0)|(t->damaged?TLK_F_DAMAGED:0)|(s->motion_on?TLK_F_MOTION:0)|(s->motion_supported?TLK_F_MOTION_SUPPORTED:0)),
  .fold_min=t->rec.fold_min,.idle_min=t->rec.idle_min,.wrong=t->rec.wrong,.unacked=t->rec.unacked};
 return r;
}
