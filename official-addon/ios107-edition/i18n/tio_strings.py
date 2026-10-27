#!/usr/bin/env python3
"""Strict, stdlib-only Objective-C localization tooling. Run from the edition root.

Parsing helpers and Tool(root) are public for fixtures and later batch automation.
All offsets address the original source; wrapping and unwrap checks preserve bytes.
"""
import argparse
from collections import Counter
from dataclasses import dataclass, field
import difflib
import fnmatch
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

COMPARISON_METHODS = frozenset('isEqual isEqualToString hasPrefix hasSuffix containsString rangeOfString stringByReplacingOccurrencesOfString withString indexOfObject containsObject componentsSeparatedByString characterSetWithCharactersInString addCharactersInString removeCharactersInString regularExpressionWithPattern initWithPattern'.split())
KEY_METHODS = frozenset('forKey objectForKey suiteName errorWithDomain identifier stringByAppendingPathComponent URLByAppendingPathComponent'.split())
PATH_METHODS = frozenset('forKey stringByAppendingPathComponent URLByAppendingPathComponent'.split())
MARKER = re.compile(r'/\*i18n:(id|keep|prompt|ui)\*/\Z')
IMPORT = '#import "TIOLanguage.h"'
FORMAT = re.compile(r"%(?:(\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfeEgGcCsSpaAF%]")

class ToolError(Exception):
    pass

@dataclass
class Token:
    kind: str
    text: str
    start: int
    end: int

@dataclass
class Group:
    start: int
    end: int
    value: str
    token_index: int
    marker: str = ''
    marker_start: int = -1
    wrapped: bool = False
    comparison: bool = False
    comparison_method: str = ''
    kind: str = ''
    reasons: list = field(default_factory=list)
    line: int = 0
    col: int = 0
    virtual_id: bool = False


def has_han(s):
    return any('\u3400' <= c <= '\u9fff' or '\uf900' <= c <= '\ufaff' for c in s)


def has_cjk(s):
    return has_han(s) or any('\u3000' <= c <= '\u303f' or '\uff00' <= c <= '\uffef' for c in s)


def decode_string(raw):
    """Decode C/ObjC escapes without corrupting literal UTF-8 characters."""
    out=[];i=0
    escapes={'n':'\n','t':'\t','r':'\r','a':'\a','b':'\b','f':'\f','v':'\v','\\':'\\','"':'"',"'":"'",'?':'?'}
    while i<len(raw):
        if raw[i]!='\\':out.append(raw[i]);i+=1;continue
        i+=1
        if i==len(raw):raise ToolError('unterminated escape')
        c=raw[i];i+=1
        if c in escapes:out.append(escapes[c])
        elif c=='\n':pass
        elif c=='\r':
            if i<len(raw) and raw[i]=='\n':i+=1
        elif c in 'uU':
            n=4 if c=='u' else 8;digits=raw[i:i+n]
            if len(digits)!=n or not re.fullmatch('[0-9a-fA-F]+',digits):raise ToolError('invalid Unicode escape')
            try:out.append(chr(int(digits,16)))
            except ValueError as e:raise ToolError('invalid Unicode codepoint') from e
            i+=n
        elif c=='x':
            m=re.match('[0-9a-fA-F]+',raw[i:])
            if not m:raise ToolError('invalid hex escape')
            out.append(chr(int(m[0],16)));i+=len(m[0])
        elif c in '01234567':
            m=re.match('[0-7]{0,2}',raw[i:]);digits=c+m[0];out.append(chr(int(digits,8)));i+=len(m[0])
        else:raise ToolError('unsupported escape \\'+c)
    return ''.join(out)


def tokenize(source):
    """Retain comments as tokens; whitespace is represented by source offsets."""
    tokens=[];i=0
    while i<len(source):
        if source[i].isspace():i+=1;continue
        start=i
        if source.startswith('//',i):
            j=source.find('\n',i);i=len(source) if j<0 else j;kind='comment'
        elif source.startswith('/*',i):
            j=source.find('*/',i+2)
            if j<0:raise ToolError('unterminated block comment')
            i=j+2;kind='comment'
        elif source.startswith('@"',i) or source[i] in '\"\'':
            objc=source.startswith('@"',i);quote='"' if objc else source[i];i+=2 if objc else 1
            while i<len(source):
                if source[i]=='\\':i+=2
                elif source[i]==quote:i+=1;break
                else:i+=1
            else:raise ToolError('unterminated string or character literal')
            kind='objc' if objc else ('cstring' if quote=='"' else 'char')
        elif source[i].isalpha() or source[i]=='_':
            i+=1
            while i<len(source) and (source[i].isalnum() or source[i]=='_'):i+=1
            kind='ident'
        else:i+=1;kind='punct'
        tokens.append(Token(kind,source[start:i],start,i))
    return tokens


def literal_groups(source):
    tokens=tokenize(source);groups=[];i=0
    while i<len(tokens):
        tok=tokens[i]
        if tok.kind!='objc':i+=1;continue
        start=tok.start;end=tok.end;values=[decode_string(tok.text[2:-1])];first=i;j=i+1
        while j<len(tokens):
            k=j
            while k<len(tokens) and tokens[k].kind=='comment':k+=1
            if k<len(tokens) and tokens[k].kind in ('objc','cstring'):
                v=tokens[k];values.append(decode_string(v.text[2:-1] if v.kind=='objc' else v.text[1:-1]));end=v.end;j=k+1
            else:break
        marker='';marker_start=-1
        if first and tokens[first-1].kind=='comment':
            m=MARKER.fullmatch(tokens[first-1].text)
            if m and (m[1]!='keep' or re.fullmatch(r'[ \t]*',source[tokens[first-1].end:start])):
                marker=m[1];marker_start=tokens[first-1].start
        # WP2 compatibility (coordinator ruling): only keep may be postfix,
        # immediately after the complete literal group on the same line. A
        # syntax token, another comment or a newline breaks that adjacency.
        # KEEP adjacency applies on both sides; other prefix marker contracts stay intact.
        if not marker and j<len(tokens) and tokens[j].text=='/*i18n:keep*/':
            if re.fullmatch(r'[ \t]*',source[end:tokens[j].start]):
                marker='keep';marker_start=tokens[j].start
        # Optional comments are legal inside TIOText( ... ).
        p=first-1
        while p>=0 and tokens[p].kind=='comment':p-=1
        wrapped=p>=1 and tokens[p].text=='(' and tokens[p-1].text=='TIOText'
        group=Group(start,end,''.join(values),first,marker,marker_start,wrapped)
        group.line=source.count('\n',0,start)+1;group.col=start-source.rfind('\n',0,start)
        groups.append(group);i=j
    return groups



def conditional_brace_depths(source, tokens):
    """Count alternative preprocessor branches once, without choosing build flags.

    Each #elif/#else restarts at its matching #if entry depth. Branch exits
    must agree (including the implicit empty branch if there is no #else),
    otherwise file scope cannot safely be inferred and scanning fails closed.
    """
    directives=[]
    for match in re.finditer(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b[^\r\n]*',source,re.M):
        # Only actual preprocessor lines, never text inside comments/literals.
        if any(t.start <= match.start()+len(match[0])-len(match[0].lstrip()) < t.end
               and t.kind in ('comment','objc','cstring','char') for t in tokens):continue
        directives.append((match.start(),match.end(),match[1]))
    depths={};depth=0;stack=[];di=0
    for token in tokens:
        while di<len(directives) and directives[di][0]<=token.start:
            start,end,command=directives[di];di+=1
            if command in ('if','ifdef','ifndef'):stack.append([depth,[],False])
            elif command in ('elif','else'):
                if not stack:raise ToolError('unmatched #'+command)
                frame=stack[-1];frame[1].append(depth);depth=frame[0]
                if command=='else':frame[2]=True
            else:
                if not stack:raise ToolError('unmatched #endif')
                entry,exits,has_else=stack.pop();exits.append(depth)
                if not has_else:exits.append(entry)
                if len(set(exits))!=1:raise ToolError('conditional branches have different brace depths')
                depth=exits[0]
        depths[token.start]=depth
        if token.kind not in ('comment','objc','cstring','char'):
            if token.text=='{':depth+=1
            elif token.text=='}':depth-=1
    return depths


def significant(tokens):
    return [t for t in tokens if t.kind!='comment']


def structure(tokens):
    pairs={};stack=[]
    for i,tok in enumerate(tokens):
        if tok.kind in ('objc','cstring','char','comment'):continue
        if tok.text in ('[','(','{'):stack.append(i)
        elif tok.text in (']',')','}'):
            match={']':'[',')':'(','}':'{'}[tok.text]
            if stack and tokens[stack[-1]].text==match:
                left=stack.pop();pairs[left]=i;pairs[i]=left
    return pairs


def context_groups(source):
    groups=literal_groups(source);tokens=significant(tokenize(source));pairs=structure(tokens)
    at={tok.start:i for i,tok in enumerate(tokens)}
    for g in groups:
        i=at[g.start]
        # Recognize wrapped operands as well as raw literals.
        arg=i
        if g.wrapped and i>=2 and tokens[i-1].text=='(' and tokens[i-2].text=='TIOText':arg=i-2
        if arg>=2 and tokens[arg-1].text==':' and tokens[arg-2].text in COMPARISON_METHODS:
            g.comparison=True;g.comparison_method=tokens[arg-2].text
        # An Objective-C array literal may itself be the comparison operand or
        # the receiver of containsObject:/indexOfObject:, including nested arrays.
        for left,right in pairs.items():
            if left>=right or tokens[left].text!='[' or not left or tokens[left-1].text!='@':continue
            if not (left<i<right):continue
            a=left-1
            if a>=2 and tokens[a-1].text==':' and tokens[a-2].text=='isEqual':g.comparison=True;g.comparison_method='isEqual'
            if right+2<len(tokens) and tokens[right+1].text in ('containsObject','indexOfObject') and tokens[right+2].text==':':g.comparison=True;g.comparison_method=tokens[right+1].text
    return groups,tokens,at


def same_formats(a,b):
    def specs(s):
        result=[];position=1
        for m in FORMAT.finditer(s):
            raw=m[0]
            if raw=='%%':result.append(('percent','%%'));continue
            index=int(m[1]) if m[1] else position
            if index<1:return None
            position+=1
            raw=re.sub(r'^%\d+\$','%',raw)
            result.append((index,raw))
        return result
    left,right=specs(a),specs(b)
    if left is None or right is None:return False
    if any(m[1] for m in FORMAT.finditer(a+b)):
        return Counter(left)==Counter(right)
    return left==right


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path,p) or ('/' not in p and fnmatch.fnmatchcase(PurePosixPath(path).name,p)) for p in patterns)


def c_string(s):
    out='"'
    for c in s:
        if c=='\\':out+='\\\\'
        elif c=='"':out+='\\"'
        elif c=='\n':out+='\\n'
        elif c=='\r':out+='\\r'
        elif c=='\t':out+='\\t'
        elif ord(c)<32 or ord(c)==127:out+='\\%03o'%ord(c)
        else:out+=c
    return out+'"'


def warn_gate(base,new):
    pat=re.compile(r'warning:.*\[-Wformat')
    return sum(bool(pat.search(x)) for x in Path(new).read_text().splitlines())<=sum(bool(pat.search(x)) for x in Path(base).read_text().splitlines())


def pinned_method_span(source,signature):
    """Find one real method, from exact signature through its balanced brace.

    Signature-looking strings/comments do not qualify. Braces in literals and
    comments do not affect the closing brace. Duplicate methods fail closed.
    """
    tokens=tokenize(source);candidates=[]
    for i,token in enumerate(tokens):
        if token.kind!='punct' or token.text!='-' or not source.startswith(signature,token.start):continue
        opening=next((j for j in range(i,len(tokens)) if tokens[j].start==token.start+len(signature)-1),None)
        if opening is None or tokens[opening].text!='{':continue
        depth=0
        for current in tokens[opening:]:
            if current.kind in ('comment','objc','cstring','char'):continue
            if current.text=='{':depth+=1
            elif current.text=='}':
                depth-=1
                if depth==0:
                    candidates.append((token.start,current.end));break
    return candidates[0] if len(candidates)==1 else None


def apply_virtual_ids(name,source,groups,config):
    """Recognize only the approved four raw diagnostics in pinned emitText.

    This is a per-literal annotation, never a source/region exclusion. Any byte
    change to the complete method invalidates every virtual ID. Surrounding
    imports and unrelated UI wrapping do not participate in the method hash.
    """
    if not config or name!='Addon.m' or config.get('file')!='Addon.m':return groups
    signature='- (void)emitText:(NSString *)text done:(BOOL)done error:(NSString *)error generation:(NSUInteger)gen {'
    if config.get('signature')!=signature or config.get('baseline')!='BASE85':return groups
    if not re.fullmatch(r'[0-9a-f]{64}',config.get('methodSHA256','')):return groups
    entries=config.get('groups',[])
    if not isinstance(entries,list) or len(entries)!=4:return groups
    span=pinned_method_span(source,signature)
    if span is None:return groups
    start,end=span;method=source[start:end]
    if hashlib.sha256(method.encode('utf-8')).hexdigest()!=config['methodSHA256']:return groups
    by_start={g.start:g for g in groups};targets=[]
    for entry in entries:
        if not isinstance(entry,dict) or not isinstance(entry.get('offset'),int) or not isinstance(entry.get('length'),int):return groups
        group=by_start.get(start+entry['offset'])
        if group is None or group.end-group.start!=entry['length'] or group.end>end or group.marker or group.wrapped:return groups
        if group.value!=entry.get('key') or not has_cjk(group.value):return groups
        if hashlib.sha256(source[group.start:group.end].encode('utf-8')).hexdigest()!=entry.get('literalSHA256'):return groups
        targets.append(group)
    if len({g.start for g in targets})!=4:return groups
    # The pinned method has precisely these four raw CJK groups; no additional
    # group may inherit a virtual marker even if an entry were malformed.
    actual={g.start for g in groups if start<=g.start<end and has_cjk(g.value)}
    if actual!={g.start for g in targets}:return groups
    for group in targets:group.marker='id';group.virtual_id=True
    return groups


class Tool:
    def __init__(self,root):
        self.root=Path(root).resolve();self.i18n=self.root/'i18n'
        try:self.scope=json.loads((self.i18n/'scope.json').read_text(encoding='utf-8'))
        except (OSError,ValueError) as e:raise ToolError('cannot read i18n/scope.json: '+str(e)) from e
        for key in ('tests','removed','owned','batches','unwrapExceptions'):
            if key not in self.scope:raise ToolError('scope missing '+key)
        self.generated=self.scope.get('generated',['Localization.m'])

    def read(self,name):
        # Disable newline conversion: unwrap-diff must distinguish LF and CRLF.
        with (self.root/name).open(encoding='utf-8',newline='') as f:return f.read()

    def write(self,name,text):
        p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True)
        with p.open('w',encoding='utf-8',newline='') as f:f.write(text)

    def excluded(self,name):
        return matches(name,self.scope['tests']+self.scope['removed']+self.scope['owned']+self.generated)

    def sources(self,collision=False):
        # No directory-level shortcuts: all unexcluded .m/.inc/.h files are live.
        return sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob('*') if p.is_file() and p.suffix in ('.m','.inc','.h') and not matches(p.relative_to(self.root).as_posix(),self.scope['tests']+self.generated if collision else self.scope['tests']+self.scope['removed']+self.scope['owned']+self.generated))

    def select(self,files=None):
        if files is None:return self.sources()
        result=[];configured={x for batch in self.scope['batches'].values() for x in batch}
        for name in files:
            p=Path(name);p=(self.root/p).resolve() if not p.is_absolute() else p.resolve()
            try:name=p.relative_to(self.root).as_posix()
            except ValueError as e:raise ToolError('path outside edition root: '+str(p)) from e
            if not p.exists():
                if name in configured:print('SKIP missing configured batch file: '+name,file=sys.stderr);continue
                raise ToolError('missing file: '+name)
            if self.excluded(name):raise ToolError('ownership/scope conflict: '+name)
            if p.suffix not in ('.m','.inc','.h'):raise ToolError('not an Objective-C source: '+name)
            result.append(name)
        return sorted(set(result))

    def context_groups(self,name,source):
        groups,tokens,at=context_groups(source)
        apply_virtual_ids(name,source,groups,self.scope.get('virtualIDs'))
        return groups,tokens,at

    def scan(self):
        return {name:self.context_groups(name,self.read(name))[0] for name in self.sources(collision=True)}

    def collision_index(self,scan):
        exact=set();prefixes={}
        for name,groups in scan.items():
            for g in groups:
                # id/keep are explicitly reviewed logic, even for indirect uses.
                if g.comparison or g.marker in ('id','keep'):exact.add(g.value)
                if g.comparison_method in ('hasPrefix','hasSuffix'):prefixes.setdefault(name,[]).append((g.comparison_method,g.value))
        return exact,prefixes

    def collisions(self,name,g,index):
        if g.marker=='ui':return []
        exact,prefixes=index;reasons=[]
        if g.value in exact:reasons.append('g:EXACT')
        if any(g.value!=p and (g.value.startswith(p) if method=='hasPrefix' else g.value.endswith(p)) for method,p in prefixes.get(name,[])):reasons.append('g:PREFIX')
        return reasons

    def classify(self,files=None):
        names=self.select(files);scan=self.scan();index=self.collision_index(scan);result={}
        for name in names:
            source=self.read(name);groups,tokens,at=self.context_groups(name,source)
            depths=conditional_brace_depths(source,tokenize(source))
            for g in groups:
                if not has_cjk(g.value):continue
                if g.wrapped:g.kind='WRAPPED';continue
                if g.marker in ('id','keep','prompt'):g.kind=g.marker.upper();continue
                i=at[g.start];prefix=tokens[:i]
                braces=depths[g.start]
                if braces==0:g.reasons.append('a')
                boundary=max((j for j,x in enumerate(prefix) if x.text in (';','{','}') and x.kind not in ('objc','cstring','char')),default=-1)
                stmt=prefix[boundary+1:]
                if stmt and stmt[0].text=='static':g.reasons.append('b')
                line_start=source.rfind('\n',0,g.start)+1
                # Fold preprocessor continuations backwards before checking define.
                logical=line_start
                while logical>0:
                    prev_start=source.rfind('\n',0,logical-1)+1
                    if source[prev_start:logical].rstrip('\r\n').endswith('\\'):logical=prev_start
                    else:break
                if re.match(r'\s*#\s*define\b',source[logical:g.start]):g.reasons.append('c')
                if g.comparison:g.reasons.append('d')
                direct=(i>=2 and tokens[i-1].text==':' and tokens[i-2].text in KEY_METHODS) or (i>=2 and tokens[i-1].text=='=' and tokens[i-2].text=='Identifier') or (i>=2 and tokens[i-1].text=='(' and tokens[i-2].text in ('NSSelectorFromString','NSClassFromString'))
                # A receiver appended to a key/path remains part of that key/path.
                after=[x for x in tokens if x.start>=g.end]
                appended=len(after)>=2 and after[0].text=='stringByAppendingString' and after[1].text==':'
                statement_end=next((j for j in range(i,len(tokens)) if tokens[j].text in (';','{','}') and tokens[j].kind not in ('objc','cstring','char')),len(tokens))
                whole_stmt=tokens[boundary+1:statement_end]
                path_feed=appended and any(whole_stmt[j].text in PATH_METHODS and j+1<len(whole_stmt) and whole_stmt[j+1].text==':' for j in range(len(whole_stmt)))
                if direct or path_feed:g.reasons.append('e')
                if g.marker!='ui' and not has_han(g.value) and not re.search('[A-Za-z]',g.value):g.reasons.append('f')
                g.reasons.extend(self.collisions(name,g,index))
                g.kind='MANUAL' if g.reasons else 'UNWRAPPED'
            result[name]=[g for g in groups if has_cjk(g.value)]
        return result

    def location(self,name,g):return f'{name}:{g.line}:{g.col}'

    def manual(self,files=None):
        result=[]
        for name,groups in self.classify(files).items():
            for g in groups:
                if g.kind=='MANUAL':result.append(f'{self.location(name,g)} MANUAL({",".join(g.reasons)}) {g.value[:100]!r}')
        return result

    def import_owners(self,name):
        if name.endswith('.m'):return {name}
        sources=self.sources();includes={p:[] for p in sources}
        for p in sources:
            # Includes are recognized only on actual directive lines, not strings.
            source=self.read(p)
            for m in re.finditer(r'^\s*#\s*(?:include|import)\s*"([^"]+)"',source,re.M):
                child=(PurePosixPath(p).parent/m[1]).as_posix()
                if child.startswith('./'):child=child[2:]
                includes[p].append(child)
        owners=set();seen=set()
        def visit(child):
            if child in seen:return
            seen.add(child)
            for parent,children in includes.items():
                if child in children:
                    if parent.endswith('.m'):owners.add(parent)
                    else:visit(parent)
        visit(name)
        if not owners:raise ToolError('no in-scope top-level .m includer for '+name)
        return owners

    def wrap(self,files):
        classified=self.classify(files)
        manual=[f'{self.location(n,g)} MANUAL({",".join(g.reasons)})' for n,gs in classified.items() for g in gs if g.kind=='MANUAL']
        if manual:raise ToolError('\n'.join(manual))
        changes={};owners=set()
        for name,groups in classified.items():
            targets=[g for g in groups if g.kind=='UNWRAPPED']
            if not targets:continue
            source=self.read(name)
            for g in reversed(targets):
                start=g.marker_start if g.marker=='ui' else g.start
                source=source[:start]+'TIOText('+source[start:g.end]+')'+source[g.end:]
            changes[name]=source;owners.update(self.import_owners(name))
        for name in sorted(owners):
            source=changes.get(name,self.read(name))
            if not re.search(r'^\s*#import "TIOLanguage.h"\s*$',source,re.M):
                m=re.search(r'^\s*#\s*import[^\r\n]*(?:\r?\n|$)',source,re.M)
                newline='\r\n' if '\r\n' in source else '\n'
                if m:
                    pos=m.end();lead='' if source[:pos].endswith('\n') else newline
                    source=source[:pos]+lead+IMPORT+newline+source[pos:]
                else:source=IMPORT+newline+source
            changes[name]=source
        for name,source in changes.items():self.write(name,source)
        return sorted(changes)

    def load_rows(self):
        rows={}
        p=self.i18n/'strings.jsonl'
        try:lines=p.read_text(encoding='utf-8').splitlines()
        except OSError as e:raise ToolError(str(e)) from e
        for number,line in enumerate(lines,1):
            if not line.strip():continue
            try:row=json.loads(line)
            except ValueError as e:raise ToolError(f'strings.jsonl:{number}: invalid JSON') from e
            self.validate_shape(row)
            if row['key'] in rows:raise ToolError('duplicate key: '+row['key'])
            rows[row['key']]=row
        return rows

    @staticmethod
    def validate_shape(row):
        if not isinstance(row,dict) or not isinstance(row.get('key'),str) or not row['key'] or not isinstance(row.get('en'),str):raise ToolError('row requires nonempty string key and string en')
        if '\0' in row['key'] or '\0' in row['en']:raise ToolError('NUL is not allowed in string rows')
        if not has_cjk(row['key']) and (not isinstance(row.get('zh'),str) or not row['zh']):raise ToolError('ASCII-id row requires zh: '+row['key'])
        if 'zh' in row and not isinstance(row['zh'],str):raise ToolError('zh must be a string')
        if '\0' in row.get('zh',''):raise ToolError('NUL is not allowed in zh')

    def save_rows(self,rows):
        self.write('i18n/strings.jsonl',''.join(json.dumps(row,ensure_ascii=False,separators=(',',':'))+'\n' for key,row in sorted(rows.items())))

    def used(self,files=None):
        used={}
        for name in self.select(files):
            for g in self.context_groups(name,self.read(name))[0]:
                # ASCII IDs are supported as first-class lookup keys.
                if g.wrapped or g.marker=='id':used.setdefault(g.value,[]).append((name,g))
        return used

    def extract(self):
        rows=self.load_rows()
        for key in self.used():
            if key not in rows:
                if not has_cjk(key):raise ToolError('new ASCII-id lookup needs explicit en/zh row: '+key)
                rows[key]={'key':key,'en':''}
        self.save_rows(rows)

    def todo(self,files):
        rows=self.load_rows();result=[]
        for key,sites in sorted(self.used(files).items()):
            if not rows.get(key,{}).get('en'):
                name,g=sites[0];line=self.read(name).splitlines()[g.line-1]
                result.append({'key':key,'en':'','context':f'{name}:{g.line} {line.strip()}'[:120]})
        return result

    @staticmethod
    def validate_translation(row):
        errors=[]
        if has_cjk(row['en']):errors.append('en contains CJK: '+repr(row['key']))
        if not same_formats(row.get('zh',row['key']),row['en']):errors.append('format specifier mismatch: '+repr(row['key']))
        return errors

    def apply(self,path):
        rows=self.load_rows()
        try:
            text=Path(path).read_text(encoding='utf-8')
            if text.lstrip().startswith('['):updates=json.loads(text)
            else:updates=[json.loads(x) for x in text.splitlines() if x.strip()]
        except (OSError,ValueError) as e:raise ToolError('invalid translation input: '+str(e)) from e
        if not isinstance(updates,list):raise ToolError('translation input must be JSON list or JSONL')
        seen=set()
        for update in updates:
            if not isinstance(update,dict) or not isinstance(update.get('key'),str) or not isinstance(update.get('en'),str):raise ToolError('translation row requires key/en')
            key=update['key']
            if key not in rows:raise ToolError('unknown translation key: '+key)
            if key in seen:raise ToolError('duplicate translation key: '+key)
            seen.add(key)
            row=dict(rows[key]);row['en']=update['en']
            self.validate_shape(row)
            if not row['en']:raise ToolError('empty translation: '+key)
            errors=self.validate_translation(row)
            if errors:raise ToolError('\n'.join(errors))
            rows[key]=row
        self.save_rows(rows)

    def prune(self):
        used=self.used();self.save_rows({k:v for k,v in self.load_rows().items() if k in used})

    def generate(self):
        rows=self.load_rows()
        text='// Generated by i18n/tio_strings.py gen. Do not edit.\n'+IMPORT+'\n#include <stddef.h>\n#import <dispatch/dispatch.h>\ntypedef struct{const char *key,*en,*zh;}TIOStringRow;\nstatic const TIOStringRow Rows[]={\n'
        for key,row in sorted(rows.items()):
            text+='    {'+c_string(key)+','+c_string(row['en'])+','+(c_string(row['zh']) if 'zh' in row else 'NULL')+'},\n'
        text+='''    {NULL,NULL,NULL}
};
NSDictionary<NSString*,NSArray<NSString*>*> *TIOStringTable(void){
    static NSDictionary<NSString*,NSArray<NSString*>*> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString*,NSArray<NSString*>*> *values=[NSMutableDictionary dictionary];
        for(const TIOStringRow *row=Rows;row->key!=NULL;++row){
            NSString *key=[NSString stringWithUTF8String:row->key];
            NSString *en=[NSString stringWithUTF8String:row->en];
            NSString *zh=row->zh?[NSString stringWithUTF8String:row->zh]:key;
            values[key]=@[en,zh];
        }
        table=[values copy];
    });
    return table;
}
'''
        return text

    def gen(self,check=False):
        expected=self.generate()
        if check:
            if not (self.root/'Localization.m').exists() or self.read('Localization.m')!=expected:raise ToolError('stale Localization.m; run gen')
        else:self.write('Localization.m',expected)

    def check(self,files=None):
        errors=[];groups=self.classify(files);rows=self.load_rows();index=self.collision_index(self.scan())
        for name,gs in groups.items():
            for g in gs:
                if g.kind in ('MANUAL','UNWRAPPED'):errors.append(f'{self.location(name,g)} {g.kind} {",".join(g.reasons)} {g.value!r}')
                if g.wrapped:
                    for reason in self.collisions(name,g,index):errors.append(f'{self.location(name,g)} COLLISION {reason.split(":")[1]} {g.value!r}')
        for key,sites in self.used(files).items():
            if key not in rows:errors.append('missing row: '+repr(key))
            elif not rows[key]['en']:errors.append('empty en: '+repr(key))
        for row in rows.values():errors.extend(self.validate_translation(row))
        try:self.gen(check=True)
        except ToolError as e:errors.append(str(e))
        return errors

    def git(self,*args,check=True):
        result=subprocess.run(['git','-C',str(self.root),*args],capture_output=True,check=False)
        if check and result.returncode:raise ToolError('git '+args[0]+': '+result.stderr.decode('utf-8','replace').strip())
        return result

    def base(self,ref):
        if ref:return ref
        try:return (self.root/'build/wp1-base.txt').read_text().strip()
        except OSError as e:raise ToolError('missing build/wp1-base.txt; pass --base') from e

    def repo_prefix(self):
        return self.git('rev-parse','--show-prefix').stdout.decode().strip()

    def baseline_paths(self,ref):
        prefix=self.repo_prefix()
        paths=self.git('ls-tree','--full-tree','-r','--name-only','-z',ref,'--',prefix or '.').stdout.decode().split('\0')
        return sorted(p[len(prefix):] for p in paths if p and p.startswith(prefix))

    def unwrap_diff(self,ref=None,files=None,scope=False):
        ref=self.base(ref);prefix=self.repo_prefix();errors=[]
        if scope:
            names=[p for p in self.baseline_paths(ref) if PurePosixPath(p).suffix in ('.m','.inc','.h') and not self.excluded(p) and p not in self.scope['unwrapExceptions']]
        else:names=self.select(files)
        for name in names:
            old_result=self.git('show',ref+':'+prefix+name,check=False)
            if old_result.returncode:raise ToolError('missing baseline file: '+name)
            if not (self.root/name).exists():errors.append(name+': missing working file');continue
            old=old_result.stdout.decode('utf-8');new=self.read(name)
            if IMPORT not in old.splitlines():
                lines=new.splitlines(keepends=True)
                for i,line in enumerate(lines):
                    if line.rstrip('\r\n')==IMPORT:del lines[i];break
                new=''.join(lines)
            try:new=unwrap(new,preserve_markers_from=old)
            except ToolError as e:
                errors.append(f'{name}: {e}');continue
            if old!=new:
                a=old.splitlines();b=new.splitlines();first=next((i+1 for i,(x,y) in enumerate(zip(a,b)) if x!=y),min(len(a),len(b))+1)
                errors.append(f'{name}:{first}: differs after unwrap\n'+''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='base/'+name,tofile='unwrapped/'+name,n=1)))
        return errors

    def frozen(self,ref=None):
        ref=self.base(ref);prefix=self.repo_prefix();patterns=self.scope['removed']+self.scope['owned'];errors=[]
        tracked=set(self.baseline_paths(ref))|set(p[len(prefix):] for p in self.git('ls-files','-z','--full-name').stdout.decode().split('\0') if p and p.startswith(prefix))
        paths=sorted(p for p in tracked if matches(p,patterns))
        if paths:
            result=self.git('diff','--quiet',ref,'--',*paths,check=False)
            if result.returncode:errors.append('frozen tracked files differ: '+', '.join(paths))
        untracked=self.git('ls-files','--others','--exclude-standard','-z').stdout.decode().split('\0')
        for name in untracked:
            if name and matches(name,patterns):errors.append('new frozen file: '+name)
        return errors


def unwrap(source,preserve_markers_from=None):
    """Remove only TIOText around a literal group or a single identifier."""
    tokens=tokenize(source);sig=significant(tokens);pairs=structure(sig);groups={g.start:g for g in literal_groups(source)};edits=[]
    for i,tok in enumerate(sig):
        if tok.kind!='ident' or tok.text!='TIOText' or i+1>=len(sig) or sig[i+1].text!='(':continue
        left=i+1;right=pairs.get(left)
        if right is None or right<=left+1:continue
        first=sig[left+1];last=sig[right-1];group=groups.get(first.start)
        if group and group.end==last.end:
            edits.extend([(tok.start,sig[left].end,''),(sig[right].start,sig[right].end,'')])
        elif right==left+2 and first.kind=='ident':
            edits.extend([(tok.start,sig[left].end,''),(sig[right].start,sig[right].end,'')])
    for start,end,replacement in sorted(edits,reverse=True):source=source[:start]+replacement+source[end:]
    # New explanation lines are permitted; every baseline byte otherwise survives.
    source=re.sub(r'^[ \t]*// i18n: [^\r\n]*(?:\r?\n|$)','',source,flags=re.M)
    expected={}
    if preserve_markers_from is not None:
        removed=0
        for tok in tokenize(preserve_markers_from):
            if tok.kind=='comment' and MARKER.fullmatch(tok.text):
                expected.setdefault(tok.start-removed,[]).append(tok.text)
                removed+=tok.end-tok.start
    # Markers already in BASE must retain kind and exact normalized character
    # offset. Only newly inserted markers may disappear in unwrap-diff.
    removed=0;edits=[]
    for tok in tokenize(source):
        if tok.kind!='comment' or not MARKER.fullmatch(tok.text):continue
        offset=tok.start-removed;removed+=tok.end-tok.start
        wanted=expected.get(offset,[])
        if wanted and wanted[0]==tok.text:wanted.pop(0)
        else:edits.append((tok.start,tok.end))
    if any(expected.values()):raise ToolError('baseline marker deleted, moved, or reclassified')
    for start,end in reversed(edits):source=source[:start]+source[end:]

    return source


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',default='.',help='edition root (default: current directory)')
    sub=parser.add_subparsers(dest='command',required=True)
    for cmd in ('stats','manual','check','wrap','todo','unwrap-diff'):
        p=sub.add_parser(cmd);p.add_argument('--files',nargs='+',required=cmd in ('wrap','todo'))
        if cmd=='todo':p.add_argument('--out',required=True)
        if cmd=='unwrap-diff':p.add_argument('--base');p.add_argument('--scope',action='store_true')
    for cmd in ('extract','prune'):sub.add_parser(cmd)
    p=sub.add_parser('apply');p.add_argument('path')
    p=sub.add_parser('gen');p.add_argument('--check',action='store_true')
    p=sub.add_parser('frozen');p.add_argument('--base')
    p=sub.add_parser('warn-gate');p.add_argument('base');p.add_argument('new')
    args=parser.parse_args(argv)
    try:
        if args.command=='warn-gate':
            if not warn_gate(args.base,args.new):raise ToolError('new -Wformat warnings')
            return 0
        tool=Tool(args.root);command=args.command
        if command=='stats':
            total=Counter();total_markers=Counter()
            for name,groups in tool.classify(args.files).items():
                counts=Counter(g.kind for g in groups);total.update(counts)
                markers=Counter(g.marker for g in groups if g.marker);total_markers.update(markers)
                print(name,json.dumps(dict(sorted(counts.items())),sort_keys=True),'markers='+json.dumps(dict(sorted(markers.items()))))
            print('TOTAL',json.dumps(dict(sorted(total.items())),sort_keys=True),'CJK='+str(sum(total.values())),'markers='+json.dumps(dict(sorted(total_markers.items()))))
        elif command in ('manual','check'):
            errors=tool.manual(args.files) if command=='manual' else tool.check(args.files)
            for error in errors:print(error)
            return int(bool(errors))
        elif command=='wrap':
            for name in tool.wrap(args.files):print('WRAPPED '+name)
        elif command=='extract':tool.extract()
        elif command=='prune':tool.prune()
        elif command=='todo':Path(args.out).write_text(json.dumps(tool.todo(args.files),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        elif command=='apply':tool.apply(args.path)
        elif command=='gen':tool.gen(check=args.check)
        elif command=='unwrap-diff':
            if args.scope==bool(args.files):raise ToolError('choose exactly one of --scope or --files')
            errors=tool.unwrap_diff(args.base,args.files,args.scope)
            for error in errors:print(error)
            return int(bool(errors))
        elif command=='frozen':
            errors=tool.frozen(args.base)
            for error in errors:print(error)
            return int(bool(errors))
        return 0
    except (ToolError,OSError,UnicodeError,ValueError) as e:
        print('ERROR: '+str(e),file=sys.stderr);return 1


if __name__=='__main__':sys.exit(main())
