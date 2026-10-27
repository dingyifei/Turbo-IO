#ifndef TIO_LANGUAGE_STATE_H
#define TIO_LANGUAGE_STATE_H
#include "lang_flag.h"
/* Stored only in the launcher's RAM controller. Never writes menu banks. */
typedef struct {uint8_t lang,source;} TLGLanguageState;
static inline bool tlg_state_accept(TLGLanguageState *s,const TLGCommand *q,bool allowed,TLGReply *r){
 unsigned result=allowed?TLG_OK:TLG_BLOCKED;bool changed=false;
 if(q->op>TLG_SET||q->lang>TLG_ZH||(q->op==TLG_QUERY&&q->lang!=TLG_EN))result=TLG_INVALID;
 if(result==TLG_OK&&q->op==TLG_SET){changed=s->lang!=q->lang;s->lang=q->lang;s->source=TLG_SOURCE_PHONE;}
 *r=(TLGReply){q->request,q->op,s->lang,(uint8_t)result,s->source};return changed;
}
#endif
