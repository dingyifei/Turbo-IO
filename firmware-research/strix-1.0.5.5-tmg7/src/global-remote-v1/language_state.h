#ifndef TIO_LANGUAGE_STATE_H
#define TIO_LANGUAGE_STATE_H
#include "lang_store.h"
/* Heap-owned controller state. Only the existing first-show path loads it. */
typedef struct {uint8_t lang,source;bool loaded;TLSStored stored;} TLGLanguageState;
static inline bool tlg_state_load(TLGLanguageState *s,const TLSIO *io){uint8_t previous=s->lang;s->stored=tls_load(io);s->loaded=true;s->lang=s->stored.lang;s->source=s->stored.generation?TLG_SOURCE_PERSISTED:TLG_SOURCE_DEFAULT;return previous!=s->lang;}
static inline bool tlg_state_accept(TLGLanguageState *s,const TLGCommand *q,bool allowed,const TLSIO *io,TLGReply *r){
 unsigned result=allowed?TLG_OK:TLG_BLOCKED;bool changed=false;
 if(q->op>TLG_SET||q->lang>TLG_ZH||(q->op==TLG_QUERY&&q->lang!=TLG_EN))result=TLG_INVALID;
 if(result==TLG_OK&&!s->loaded)result=TLG_UNAVAILABLE;
 if(result==TLG_OK&&q->op==TLG_SET){uint8_t previous=s->lang;bool saved=tls_store(io,&s->stored,q->lang);s->lang=s->stored.lang;s->source=s->stored.generation?TLG_SOURCE_PERSISTED:TLG_SOURCE_DEFAULT;changed=previous!=s->lang;if(!saved)result=TLG_STORAGE;}
 *r=(TLGReply){q->request,q->op,s->lang,(uint8_t)result,s->source};return changed;
}
#endif
