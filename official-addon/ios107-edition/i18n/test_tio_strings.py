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


if __name__=='__main__':unittest.main()
