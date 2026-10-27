import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import sys

def sys_platform_is_macos():
    return sys.platform == 'darwin'
import unittest

import tio_strings as t


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'i18n').mkdir()
        self.scope = {'tests':['*Tests.m','*Test.m','*Fixture.m','tests/**','i18n/**','build/**','preview/**'], 'removed':['Old*.m','removed/**'], 'owned':['Owned.m'], 'generated':['Localization.m'], 'batches':{'B1':['Main.m','Gone.m']}, 'unwrapExceptions':[]}
        self.put('i18n/scope.json', json.dumps(self.scope))
        self.put('i18n/strings.jsonl', '')
        self.tool = t.Tool(self.root)

    def put(self, name, text):
        p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8');return p

    def source(self, code, name='Main.m'):
        self.put(name, code)
        return self.tool.classify([name])[name]

    def fn(self, code):
        return '#import <Foundation/Foundation.h>\nvoid f(){'+code+'}\n'

    def git(self,*args):
        return subprocess.run(['git','-C',str(self.root),*args],check=True,capture_output=True,text=True).stdout

    def baseline(self, name, text):
        self.put(name,text);self.git('init','-q');self.git('config','user.email','fixture@example.invalid');self.git('config','user.name','Fixture');self.git('add','.');self.git('commit','-qm','fixture');return self.git('rev-parse','HEAD').strip()

    def rows(self, *rows):
        self.tool.save_rows({r['key']:r for r in rows})

    def test_tokenizer_escapes_comments_and_adjacent_groups(self):
        src='// @"假"\n/* @"假" */ char c=\'"\'; const char*s="假"; @"甲\\n\\t\\\"\\\\\\r\\u4e59" /* gap */ "丙" @"丁"; @"尾";'
        g=t.literal_groups(src)
        self.assertEqual([x.value for x in g],['甲\n\t"\\\r乙丙丁','尾'])
        self.assertEqual(src[g[0].start:g[0].end], '@"甲\\n\\t\\\"\\\\\\r\\u4e59" /* gap */ "丙" @"丁"')

    def test_character_ranges(self):
        for s in ['㐀','豈','。','Ａ']:
            self.assertTrue(t.has_cjk(s))
        self.assertFalse(t.has_han('。Ａ'));self.assertTrue(t.has_han('甲'))

    def test_markers_and_wrapped(self):
        g=self.source(self.fn('/*i18n:id*/ @"甲"; /*i18n:keep*/@"乙"; /*i18n:prompt*/@"丙"; TIOText(/*i18n:ui*/@"丁"); /* unrelated */@"戊";'))
        self.assertEqual([x.kind for x in g],['ID','KEEP','PROMPT','WRAPPED','UNWRAPPED'])
        self.assertEqual(g[3].marker,'ui')
        g=self.source(self.fn('/*i18n:id*/ /*other*/@"甲";'))
        self.assertEqual(g[0].kind,'UNWRAPPED')

    def test_file_scope_static_define(self):
        cases=[('@"甲";', 'a'),(self.fn('static NSString*s=@"甲";'),'b'),('#define LABEL @"甲"\n','c'),('#define LABEL \\\n @"甲"\n','c')]
        for code, reason in cases:
            with self.subTest(reason=reason,code=code):self.assertIn(reason,self.source(code)[0].reasons)

    def test_preprocessor_alternatives_do_not_change_file_scope(self):
        source = ('void first(){ id rows=@[@{ @"rows":@[\n'
                  '#if FLAG\n@"English"]}];\n'
                  '#elif OTHER\n@"Other"]}];\n'
                  '#else\n@"Fallback"]}];\n#endif\n}\n'
                  'void second(){ Show(@"本地显示"); }\n'
                  'static NSString *label=@"文件常量";\n')
        groups=self.source(source)
        self.assertEqual(groups[0].kind,'UNWRAPPED')
        self.assertIn('a',groups[1].reasons)
        nested = ('void f(){\n#if OUTER\n#if INNER\nShow(@"甲");\n'
                  '#else\nShow(@"乙");\n#endif\n#else\nShow(@"丙");\n'
                  '#endif\nShow(@"丁");\n}\n')
        self.assertTrue(all(g.kind=='UNWRAPPED' for g in self.source(nested)))
        with self.assertRaisesRegex(t.ToolError,'different brace depths'):
            self.source('void f(){\n#if FLAG\n}\n#endif\nShow(@"甲");\n')

    def test_every_comparison_method(self):
        for method in t.COMPARISON_METHODS:
            with self.subTest(method=method):self.assertIn('d', self.source(self.fn('[a '+method+':@"甲"];'))[0].reasons)
        for expr in ['[@[@"甲",@"乙"] containsObject:x]','[@[@"甲"] indexOfObject:x]','[a isEqual:@[@"甲",@"乙"]]']:
            self.assertTrue(all('d' in g.reasons for g in self.source(self.fn(expr+';'))))
        self.assertIn('f',self.source(self.fn('[a addCharactersInString:@"，。！？"];'))[0].reasons)

    def test_every_identifier_path_context(self):
        for prefix in ['forKey:','objectForKey:','suiteName:','errorWithDomain:','Identifier=','identifier:','NSSelectorFromString(','NSClassFromString(','stringByAppendingPathComponent:','URLByAppendingPathComponent:']:
            with self.subTest(prefix=prefix):self.assertIn('e',self.source(self.fn(prefix+'@"甲");'))[0].reasons)
        for expr in ['[d setObject:x forKey:[@"甲" stringByAppendingString:y]]','[p URLByAppendingPathComponent:[@"甲" stringByAppendingString:y]]','[p stringByAppendingPathComponent:[@"甲" stringByAppendingString:y]]','[[@"甲" stringByAppendingString:y] URLByAppendingPathComponent:z]']:
            self.assertIn('e',self.source(self.fn(expr+';'))[0].reasons)
        self.assertEqual(self.source(self.fn('[@"甲" stringByAppendingString:y];'))[0].kind,'UNWRAPPED')

    def test_punctuation_and_ui_exemptions(self):
        self.assertIn('f',self.source(self.fn('@"，。！？,.!?、：:";'))[0].reasons)
        self.assertEqual(self.source(self.fn('/*i18n:ui*/@"，。";'))[0].kind,'UNWRAPPED')
        self.assertIn('d',self.source(self.fn('[a isEqual:/*i18n:ui*/@"甲"];'))[0].reasons)

    def test_exact_and_prefix_collision_current_tree_including_removed(self):
        self.put('OldLogic.m',self.fn('[x isEqual:/*i18n:keep*/@"甲"];'))
        self.assertIn('g:EXACT',self.source(self.fn('Show(@"甲");'))[0].reasons)
        self.put('OldLogic.m',self.fn('/*i18n:id*/@"乙";'))
        self.assertIn('g:EXACT',self.source(self.fn('Show(@"乙");'))[0].reasons)
        self.put('IgnoredTests.m',self.fn('[x isEqual:@"丙"];'))
        self.assertEqual(self.source(self.fn('Show(@"丙");'))[0].kind,'UNWRAPPED')
        groups=self.source(self.fn('[op hasPrefix:/*i18n:id*/@"读取"]; Query(@"读取当前状态"); [op hasSuffix:@"状态"]; Show(@"当前状态");'))
        self.assertIn('g:PREFIX',groups[1].reasons);self.assertIn('g:PREFIX',groups[3].reasons)

    def test_wrap_atomic_idempotent_and_inc_import_chain(self):
        self.put('Main.m', self.fn('@"甲";'))
        self.put('Other.m', '@"乙";')
        before=(self.root/'Main.m').read_bytes()
        with self.assertRaises(t.ToolError):self.tool.wrap(['Main.m','Other.m'])
        self.assertEqual((self.root/'Main.m').read_bytes(),before)
        self.put('FocusUI.inc',self.fn('/*i18n:ui*/@"，。";'))
        self.put('EditorialShell.inc','#include "FocusUI.inc"\n')
        self.put('ResearchUI.m','#import <Foundation/Foundation.h>\n#include "EditorialShell.inc"\n')
        self.tool.wrap(['Main.m','FocusUI.inc'])
        self.assertIn('TIOText(/*i18n:ui*/@"，。")',(self.root/'FocusUI.inc').read_text())
        self.assertIn('#import "TIOLanguage.h"',(self.root/'ResearchUI.m').read_text())
        before={p:p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        self.tool.wrap(['Main.m','FocusUI.inc'])
        self.assertEqual(before,{p:p.read_bytes() for p in before})

    def test_extract_todo_apply_prune_and_generated_exclusion(self):
        self.put('Main.m',self.fn('TIOText(@"甲 %@"); /*i18n:id*/@"乙"; /*i18n:keep*/@"丙"; /*i18n:prompt*/@"丁";'))
        self.put('Localization.m','@"生成";')
        self.rows({'key':'unused','en':'Unused','zh':'闲置'})
        self.tool.extract();rows=self.tool.load_rows()
        self.assertEqual(set(rows),{'甲 %@','乙','unused'})
        todo=self.tool.todo(['Main.m']);self.assertEqual(len(todo),2);self.assertLessEqual(len(todo[0]['context']),120)
        self.put('shard.json',json.dumps([{'key':'甲 %@','en':'A %@'},{'key':'乙','en':'B'}],ensure_ascii=False));self.tool.apply(self.root/'shard.json')
        self.tool.prune();self.assertEqual(set(self.tool.load_rows()),{'甲 %@','乙'})
        self.tool.gen();self.assertEqual(self.tool.check(['Main.m']),[])

    def test_apply_atomic_validation_and_jsonl(self):
        self.rows({'key':'甲 %@','en':''},{'key':'乙','en':''})
        before=(self.root/'i18n/strings.jsonl').read_bytes()
        for bad in [[{'key':'甲 %@','en':'A %d'}],[{'key':'乙','en':'中文'}],[{'key':'absent','en':'X'}]]:
            self.put('shard.json',json.dumps(bad,ensure_ascii=False))
            with self.assertRaises(t.ToolError):self.tool.apply(self.root/'shard.json')
            self.assertEqual(before,(self.root/'i18n/strings.jsonl').read_bytes())
        self.put('shard.jsonl',json.dumps({'key':'乙','en':'B'})+'\n');self.tool.apply(self.root/'shard.jsonl')
        self.assertEqual(self.tool.load_rows()['乙']['en'],'B')

    def test_formats(self):
        for a,b in [('%@ %% %.1f %lu','%@ %% %.1f %lu'),('%@ %d','%2$d %1$@'),('%1$@ %% %2$lu','%2$lu %% %1$@')]:self.assertTrue(t.same_formats(a,b),(a,b))
        for a,b in [('%@ %d','%d %@'),('%lu','%u'),('%.1f','%.2f'),('%@ %%','%@'),('%@ %@','%1$@ %1$@')]:self.assertFalse(t.same_formats(a,b),(a,b))

    def test_check_all_six_rules_and_ui_collision_exemption(self):
        self.put('OldLogic.m',self.fn('[x hasPrefix:/*i18n:id*/@"读取"]; [x isEqual:/*i18n:keep*/@"甲"];'))
        self.put('Main.m',self.fn('TIOText(@"甲"); [x hasPrefix:/*i18n:id*/@"读取"]; TIOText(@"读取当前状态");'))
        self.rows({'key':'甲','en':'A'},{'key':'读取','en':'Read'},{'key':'读取当前状态','en':'Read state'})
        self.tool.gen();errors=self.tool.check(['Main.m'])
        self.assertTrue(any('COLLISION EXACT' in x for x in errors));self.assertTrue(any('COLLISION PREFIX' in x for x in errors))
        self.put('Main.m',self.fn('TIOText(/*i18n:ui*/@"甲");'))
        self.tool.gen();self.assertEqual(self.tool.check(['Main.m']),[])
        self.put('Main.m',self.fn('@"未包裹"; TIOText(@"缺失");'))
        self.assertTrue(any('UNWRAPPED' in x for x in self.tool.check(['Main.m'])));self.assertTrue(any('missing row' in x for x in self.tool.check(['Main.m'])))
        self.rows({'key':'甲 %@','en':'错误 %d'})
        self.tool.gen();errors=self.tool.check(['Main.m']);self.assertTrue(any('CJK' in x for x in errors));self.assertTrue(any('format' in x for x in errors))
        self.put('Localization.m','stale');self.assertTrue(any('stale' in x for x in self.tool.check(['Main.m'])))
        self.put('Main.m',self.fn('TIOText(@"甲");'));self.rows({'key':'甲','en':''});self.tool.gen();self.assertTrue(any('empty en' in x for x in self.tool.check(['Main.m'])))

    def test_fullscope_unlisted_source_and_scope_overrides(self):
        self.put('Unlisted.m',self.fn('@"甲";'));self.put('Owned.m',self.fn('@"乙";'));self.put('Localization.m','@"丙";')
        self.assertIn('Unlisted.m',self.tool.select());self.assertNotIn('Owned.m',self.tool.select());self.assertNotIn('Localization.m',self.tool.select())
        self.assertTrue(any('Unlisted.m' in x for x in self.tool.check()))
        with self.assertRaises(t.ToolError):self.tool.select(['Owned.m'])
        with self.assertRaises(t.ToolError):self.tool.select(['Typo.m'])
        with contextlib.redirect_stderr(io.StringIO()) as output:self.assertEqual(self.tool.select(['Gone.m']),[])
        self.assertIn('SKIP missing',output.getvalue())

    def test_deterministic_gen_ascii_ids_and_empty_sentinel(self):
        empty=self.tool.generate();self.assertIn('{NULL,NULL,NULL}',empty);self.assertIn('#import "TIOLanguage.h"',empty);self.assertIn('TIOStringTable(void)',empty)
        self.rows({'key':'hub.title','en':'Hub','zh':'中心'},{'key':'甲\n"\\','en':'A\n"\\'})
        first=self.tool.generate();self.assertEqual(first,self.tool.generate());self.assertIn('"hub.title","Hub","中心"',first)
        self.assertIn('NULL,NULL,NULL',first);self.assertIn('dispatch_once',first)
        self.tool.gen();self.tool.gen(check=True);self.put('Localization.m','x')
        with self.assertRaises(t.ToolError):self.tool.gen(check=True)

    def test_unwrap_byte_exact_with_markers_and_identifiers(self):
        old='#import <Foundation/Foundation.h>\n- (void)f{if(a&&b) Show(@"甲" /*inside*/ "乙"); Show(state);}\n'
        ref=self.baseline('Main.m',old)
        wrapped='#import <Foundation/Foundation.h>\n#import "TIOLanguage.h"\n- (void)f{if(a&&b) Show(TIOText(/*i18n:ui*/@"甲" /*inside*/ "乙")); Show(TIOText(state));}\n'
        self.put('Main.m',wrapped);self.assertEqual(self.tool.unwrap_diff(ref,['Main.m']),[])
        for changed in [wrapped.replace('if(a&&b)','if((a)&&b)'),wrapped.replace('- (void)f','- (void)g'),wrapped+'int x;\n']:
            self.put('Main.m',changed);self.assertTrue(self.tool.unwrap_diff(ref,['Main.m']))

    def test_unwrap_preserves_existing_baseline_markers_exactly(self):
        old = ('#import <Foundation/Foundation.h>\n'
               'void f(){ Show(/*i18n:keep*/@"甲"); '
               'Show(@"乙" /*i18n:keep*/); Show(@"新"); }\n')
        ref=self.baseline('Main.m',old)
        self.assertEqual(self.tool.unwrap_diff(ref,['Main.m']),[])
        wrapped=old.replace('@"新"','TIOText(/*i18n:ui*/@"新")')
        wrapped=wrapped.replace('#import <Foundation/Foundation.h>\n',
                                '#import <Foundation/Foundation.h>\n#import "TIOLanguage.h"\n')
        self.put('Main.m',wrapped)
        self.assertEqual(self.tool.unwrap_diff(ref,['Main.m']),[])
        bads=[wrapped.replace('/*i18n:keep*/','',1),
              wrapped.replace('/*i18n:keep*/','/*i18n:prompt*/',1),
              wrapped.replace('/*i18n:keep*/@"甲"','@"甲"/*i18n:keep*/'),
              wrapped.replace('/*i18n:keep*/@"甲"',' /*i18n:keep*/@"甲"')]
        for bad in bads:
            self.put('Main.m',bad)
            self.assertTrue(self.tool.unwrap_diff(ref,['Main.m']))
        self.assertEqual(t.unwrap('Show(/*i18n:keep*/@"甲");'),'Show(@"甲");')

    def test_unwrap_scope_missing_base_and_removed_file(self):
        ref=self.baseline('Main.m',self.fn('@"甲";'))
        self.put('New.m',self.fn('@"新";'));self.assertEqual(self.tool.unwrap_diff(ref,scope=True),[])
        with self.assertRaises(t.ToolError):self.tool.unwrap_diff(ref,['New.m'])
        (self.root/'Main.m').unlink();self.assertTrue(self.tool.unwrap_diff(ref,scope=True))

    def test_frozen_tracked_untracked_and_staged(self):
        ref=self.baseline('Owned.m','original\n');self.assertEqual(self.tool.frozen(ref),[])
        self.put('Owned.m','changed\n');self.assertTrue(self.tool.frozen(ref));self.git('add','Owned.m');self.assertTrue(self.tool.frozen(ref))
        self.git('restore','--source=HEAD','--staged','--worktree','Owned.m');self.put('removed/new.h','new\n');self.assertTrue(self.tool.frozen(ref))

    def test_nested_edition_git_scope_and_frozen(self):
        self.put('official-addon/ios107-edition/i18n/scope.json',json.dumps(self.scope))
        self.put('official-addon/ios107-edition/i18n/strings.jsonl','')
        self.put('official-addon/ios107-edition/Main.m',self.fn('@"甲";'))
        ref=self.baseline('official-addon/ios107-edition/Owned.m','original\n')
        tool=t.Tool(self.root/'official-addon/ios107-edition')
        self.assertIn('Main.m',tool.baseline_paths(ref))
        self.assertEqual(tool.unwrap_diff(ref,scope=True),[])
        self.put('official-addon/ios107-edition/Main.m',self.fn('@"乙";'))
        self.assertTrue(tool.unwrap_diff(ref,scope=True))
        self.assertEqual(tool.frozen(ref),[])
        self.put('official-addon/ios107-edition/Owned.m','changed\n')
        self.assertTrue(tool.frozen(ref))
        self.put('official-addon/ios107-edition/removed/new.h','new\n')
        self.assertTrue(any('new frozen' in x for x in tool.frozen(ref)))

    def test_cli_pipeline(self):
        self.put('Main.m',self.fn('@"甲 %@";'))
        script=Path(t.__file__).resolve()
        def cli(*args,ok=True):
            r=subprocess.run(['python3',str(script),'--root',str(self.root),*args],text=True,capture_output=True)
            self.assertEqual(r.returncode,0 if ok else 1,r.stdout+r.stderr)
            return r
        cli('manual','--files','Main.m');cli('stats','--files','Main.m')
        cli('check','--files','Main.m',ok=False)
        cli('wrap','--files','Main.m');cli('extract')
        cli('todo','--files','Main.m','--out',str(self.root/'todo.json'))
        self.put('todo.json',json.dumps([{'key':'甲 %@','en':'A %@'}],ensure_ascii=False))
        cli('apply',str(self.root/'todo.json'));cli('gen');cli('gen','--check');cli('check');cli('prune')
        self.put('before','');self.put('after','');cli('warn-gate',str(self.root/'before'),str(self.root/'after'))

    def test_generator_compiles_empty_and_nonempty_with_frozen_signature(self):
        # Actual ObjC syntax validation on macOS; the test is portable elsewhere.
        import shutil
        if not sys_platform_is_macos() or not shutil.which('clang'):
            self.skipTest('macOS clang/Foundation required for compile fixture')
        self.put('TIOLanguage.h','#import <Foundation/Foundation.h>\nNSDictionary<NSString*,NSArray<NSString*>*> *TIOStringTable(void);\n')
        for rows in [[],[{'key':'甲 %@','en':'A %@'},{'key':'hub.title','en':'Hub','zh':'中心'}]]:
            self.rows(*rows);self.tool.gen()
            r=subprocess.run(['clang','-fsyntax-only','-fobjc-arc','-fblocks','-Wall','-Wextra','-Werror',str(self.root/'Localization.m')],text=True,capture_output=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)

    def test_warn_gate(self):
        self.put('before','x warning: format [-Wformat]\n');self.put('after','x warning: other [-Wextra]\nx warning: format [-Wformat]\n')
        self.assertTrue(t.warn_gate(self.root/'before',self.root/'after'));self.put('after','warning: x [-Wformat]\nwarning: x [-Wformat-extra-args]\n');self.assertFalse(t.warn_gate(self.root/'before',self.root/'after'))




class PostfixKeepTests(unittest.TestCase):
    def marker(self,source):
        return [g.marker for g in t.literal_groups(source)]

    def test_prefix_keep_contract_unchanged(self):
        self.assertEqual(self.marker('/*i18n:keep*/ @"甲";'),['keep'])
        self.assertEqual(self.marker('/*i18n:keep*/\n @"甲";'),[''])
        for kind in ('id','prompt','ui'):
            self.assertEqual(self.marker('/*i18n:'+kind+'*/\n @"甲";'),[kind])
        self.assertEqual(self.marker('/*i18n:id*/@"甲" /*i18n:keep*/;'),['id'])

    def test_same_line_adjacent_postfix_keep(self):
        for gap in ('',' ','\t',' \t  '):
            with self.subTest(gap=gap):
                groups=t.literal_groups('UIText(@"English",@"中文"'+gap+'/*i18n:keep*/);')
                self.assertEqual([g.marker for g in groups],['','keep'])
        groups=t.literal_groups('@"甲" /* ordinary */ "乙" \t/*i18n:keep*/;')
        self.assertEqual([(g.value,g.marker) for g in groups],[('甲乙','keep')])

    def test_tokens_or_comments_between_literal_and_marker_rejected(self):
        for gap in (', ','); ',') ', '; ', '+ ', ' /* another comment */ '):
            with self.subTest(gap=gap):self.assertEqual(self.marker('@"甲"'+gap+'/*i18n:keep*/'),[''])

    def test_next_line_and_other_whitespace_postfix_rejected(self):
        for gap in ('\n','\r\n','\v','\f',' \n\t'):
            with self.subTest(gap=gap):self.assertEqual(self.marker('@"甲"'+gap+'/*i18n:keep*/'),[''])

    def test_no_postfix_id_prompt_ui_and_no_double_attribution(self):
        for kind in ('id','prompt','ui'):
            with self.subTest(kind=kind):self.assertEqual(self.marker('@"甲" /*i18n:'+kind+'*/;'),[''])
        self.assertEqual(self.marker('Pair(@"甲" /*i18n:keep*/, @"乙");'),['keep',''])
        self.assertEqual(self.marker('Pair(@"甲", /*i18n:keep*/ @"乙");'),['','keep'])
        # A marker inside a concatenated runtime group cannot selectively protect
        # one fragment. It must precede or follow the complete group.
        self.assertEqual(self.marker('@"甲" /*i18n:keep*/ @"乙";'),[''])
        self.assertEqual(self.marker('@"甲" /*i18n:keep*/\n @"乙";'),[''])

    def test_postfix_keep_is_not_wrapped_or_extracted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'i18n').mkdir()
            (root/'i18n/scope.json').write_text(json.dumps({'tests':['i18n/**'],'removed':[],'owned':[],'batches':{},'unwrapExceptions':[]}))
            (root/'i18n/strings.jsonl').write_text('')
            source='#import <Foundation/Foundation.h>\nvoid f(){ UIText(@"English",@"中文" /*i18n:keep*/); }\n'
            (root/'Main.m').write_text(source);tool=t.Tool(root)
            self.assertEqual(tool.classify(['Main.m'])['Main.m'][0].kind,'KEEP')
            tool.wrap(['Main.m']);self.assertEqual((root/'Main.m').read_text(),source)
            tool.extract();self.assertEqual(tool.load_rows(),{})
            tool.gen();self.assertEqual(tool.check(['Main.m']),[])




FROZEN_EMIT_TEXT_BASE85 = '- (void)emitText:(NSString *)text done:(BOOL)done error:(NSString *)error generation:(NSUInteger)gen {\n    if(gen!=_generation||!_ownsTurn||_responseDone||!_listener)return;\n    if(error)text=[(_emitted?:@"") stringByAppendingFormat:@"\\n[%@]",error];\n    NSString *delta=TIOAppendDelta(_emitted?:@"",text);\n    if(!delta){\n        // Close an owned turn even if a provider rewrites a previous chunk.\n        // Keep ownership until the next turn so late official chunks stay suppressed.\n        [_request cancel];_request=nil;_responseDone=YES;\n        id failure=CopyResponse(_responseTemplate,TIOWebStatusText(@"stream.rewritten",TIOScriptLanguage(_requestQuestion?:@"",AddonUILanguage())),YES);\n        if(failure)OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),failure);\n        OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));\n        Diagnostic=@"模型输出不是追加流，已提交错误收尾";return;\n    }\n    if(delta.length||done){id wrapper=CopyResponse(_responseTemplate,delta,done);if(!wrapper){[_request cancel];_request=nil;_responseDone=YES;OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));Diagnostic=@"回复模板复制失败，已提交收尾";return;}OriginalNlp(_listener,NSSelectorFromString(@"onNlpResult:"),wrapper);_emitted=[text copy];if(TTSOn()&&!error)[VoiceTTS appendFullText:text finished:done];}\n    if(done){_responseDone=YES;if(!error&&_request&&text.length)[_history appendQuestion:_requestQuestion answer:text];Diagnostic=error?@"自定义回复失败，已提交错误收尾":@"自定义回复结束，已提交官方收尾回调";OriginalComplete(_listener,NSSelectorFromString(@"onResponseComplete"));}\n}'


class VirtualFrozenDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        (self.root/'i18n').mkdir();self.scope=json.loads((Path(t.__file__).parent/'scope.json').read_text())
        self.scope['tests']=['i18n/**'];self.scope['removed']=[];self.scope['owned']=[]
        self.save_scope();(self.root/'i18n/strings.jsonl').write_text('');self.tool=t.Tool(self.root)

    def save_scope(self):
        (self.root/'i18n/scope.json').write_text(json.dumps(self.scope,ensure_ascii=False))

    def groups(self,method=FROZEN_EMIT_TEXT_BASE85,before='',after='',name='Addon.m'):
        (self.root/name).write_text(before+method+after)
        return self.tool.classify([name])[name]

    def test_only_four_pinned_groups_are_virtual_ids(self):
        groups=self.groups();self.assertEqual(len(groups),4)
        self.assertTrue(all(g.kind=='ID' and g.virtual_id for g in groups))
        self.assertEqual({g.value for g in groups},{g['key'] for g in self.scope['virtualIDs']['groups']})
        self.assertTrue(all(not g.marker for g in t.literal_groups(FROZEN_EMIT_TEXT_BASE85) if t.has_cjk(g.value)))

    def test_complete_method_pin_rejects_body_literal_signature_and_whitespace_changes(self):
        changed=[FROZEN_EMIT_TEXT_BASE85.replace('if(gen!=_generation','if(gen==_generation',1),
                 FROZEN_EMIT_TEXT_BASE85.replace('模型输出不是追加流','模型输出已改动',1),
                 FROZEN_EMIT_TEXT_BASE85.replace('emitText:','emitOtherText:',1),
                 FROZEN_EMIT_TEXT_BASE85.replace('    if(gen','     if(gen',1)]
        for method in changed:
            with self.subTest(method=method[:110]):
                groups=self.groups(method);self.assertTrue(all(not g.virtual_id for g in groups))
                self.assertTrue(any(g.kind in ('UNWRAPPED','MANUAL') for g in groups))

    def test_new_cjk_inside_and_outside_method_is_not_virtual(self):
        changed=FROZEN_EMIT_TEXT_BASE85[:-1]+' Show(@"新增");}'
        groups=self.groups(changed);self.assertTrue(all(not g.virtual_id for g in groups))
        groups=self.groups(after='\nvoid other(){ Show(@"新增"); }\n')
        self.assertEqual(sum(g.virtual_id for g in groups),4)
        self.assertFalse(next(g for g in groups if g.value=='新增').virtual_id)
        self.assertTrue(any(g.value=='新增' and g.kind=='UNWRAPPED' for g in groups))
        groups=self.groups(before='void other(){ Diagnostic=@"模型输出不是追加流，已提交错误收尾"; }\n')
        self.assertEqual(sum(g.virtual_id for g in groups),4)
        self.assertFalse(groups[0].virtual_id)

    def test_outer_wrapping_and_imports_preserve_exact_method(self):
        groups=self.groups(before='#import "TIOLanguage.h"\nvoid other(){Show(TIOText(/*i18n:ui*/@"外部"));}\n',after='\nvoid last(){Show(TIOText(/*i18n:ui*/@"其他"));}')
        self.assertEqual(sum(g.virtual_id for g in groups),4)
        self.assertTrue(all(g.kind=='WRAPPED' for g in groups if not g.virtual_id))
        self.assertTrue(all(not g.virtual_id for g in self.groups(name='Other.m')))

    def test_no_scope_pin_no_virtual_ids_and_mismatched_pin_fail_closed(self):
        self.scope.pop('virtualIDs');self.save_scope();self.tool=t.Tool(self.root)
        self.assertTrue(all(not g.virtual_id for g in self.groups()))
        self.scope['virtualIDs']=json.loads((Path(t.__file__).parent/'scope.json').read_text())['virtualIDs']
        self.scope['virtualIDs']['methodSHA256']='0'*64;self.save_scope();self.tool=t.Tool(self.root)
        self.assertTrue(all(not g.virtual_id for g in self.groups()))

    def test_tokenizer_balanced_span_ignores_comments_strings_and_duplicate_methods(self):
        signature=self.scope['virtualIDs']['signature']
        body=signature+' id braces=@"}{"; /* }}} */ if(YES){int value=1;} }'
        self.assertEqual(t.pinned_method_span(body+'\nvoid later(){}',signature),(0,len(body)))
        # Matching a fake method entirely inside a comment must never qualify.
        groups=self.groups(method='/* '+FROZEN_EMIT_TEXT_BASE85+' */\nvoid x(){Show(@"未登记");}')
        self.assertTrue(all(not g.virtual_id for g in groups))
        groups=self.groups(method=FROZEN_EMIT_TEXT_BASE85+'\n'+FROZEN_EMIT_TEXT_BASE85)
        self.assertTrue(all(not g.virtual_id for g in groups))

    def test_wrap_preserves_method_and_extract_todo_use_virtual_keys(self):
        self.groups();before=(self.root/'Addon.m').read_bytes();self.tool.wrap(['Addon.m'])
        self.assertEqual((self.root/'Addon.m').read_bytes(),before)
        self.tool.extract();keys={g['key'] for g in self.scope['virtualIDs']['groups']}
        self.assertEqual(set(self.tool.load_rows()),keys);self.assertEqual(set(self.tool.used(['Addon.m'])),keys)
        self.assertEqual({r['key'] for r in self.tool.todo(['Addon.m'])},keys)

if __name__=='__main__':unittest.main()
