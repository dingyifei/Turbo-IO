import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {REQUIRED,prepareAppleAI,copyAppleAI} from './package-resources.mjs';
test('Apple AI resources validate identity, symbols, pairing and exclusive copy',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'tai-package-'));
 try {
  assert.equal(prepareAppleAI(undefined,''),null);copyAppleAI(null,root);
  assert.throws(()=>prepareAppleAI('relative',''),/apple_ai_absolute_path_required/);
  const dylib=path.join(root,'TurboAppleAI.dylib'),info=path.join(root,'build-info.json');fs.writeFileSync(dylib,'synthetic module');
  assert.throws(()=>prepareAppleAI(dylib,''),/apple_ai_build_info_mismatch/);
  fs.writeFileSync(info,JSON.stringify({version:'wrong'}));assert.throws(()=>prepareAppleAI(dylib,''),/apple_ai_build_info_mismatch/);
  fs.writeFileSync(info,JSON.stringify({version:'APPLE-AI-01'}));
  const nm=()=>REQUIRED.map(x=>'0000 t _OBJC_CLASS_$_'+x).join('\n');
  assert.throws(()=>prepareAppleAI(dylib,'',{nm}),/apple_ai_addon_mismatch/);
  assert.throws(()=>prepareAppleAI(dylib,'_TIOAppleAILoaded',{nm:()=>''}),/apple_ai_symbols_missing/);
  assert.throws(()=>prepareAppleAI(dylib,'_TIOAppleAILoaded',{nm:()=>nm()+'Suffix'}),/apple_ai_symbols_missing/);
  const result=prepareAppleAI(dylib,'_TIOAppleAILoaded',{nm});assert.deepEqual(result,{dylib});
  const app=path.join(root,'Runner.app');fs.mkdirSync(path.join(app,'Frameworks'),{recursive:true});
  copyAppleAI(result,app);assert.equal(fs.readFileSync(path.join(app,'Frameworks/TurboAppleAI.dylib'),'utf8'),'synthetic module');
  assert.throws(()=>copyAppleAI(result,app),/apple_ai_already_present/);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
