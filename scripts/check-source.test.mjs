import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {audit} from './check-source.mjs';

function fixture(files,run){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-source-audit-'));
  try{for(const [name,value] of Object.entries(files)){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);}run(audit(root));}
  finally{fs.rmSync(root,{recursive:true,force:true});}
}
test('allows blank-key original Android source',()=>{
  fixture({'SecretStore.java':'String apiKey = "";'},r=>assert.deepEqual(r.findings,[]));
});
test('rejects model key without returning the secret',()=>{
  const fake='sk-'+'z'.repeat(24);
  fixture({'settings.json':JSON.stringify({api_key:fake})},r=>{
    assert.ok(r.findings.some(f=>f.rule==='api-key'));
    assert.ok(!JSON.stringify(r).includes(fake));
  });
});
for(const extension of ['apk','dex','jar','jks','keystore','jsonl','hap','har','p12','p7b','cer']){
  test('rejects '+extension+' artifacts',()=>fixture({['sample.'+extension]:'fixture'},r=>assert.ok(r.findings.some(f=>f.rule==='non-source-artifact'))));
}
test('rejects private developer home paths',()=>{
  fixture({'build.sh':'sdk="'+['','Users','sample-person','Library','Android','sdk'].join('/')+'"'},r=>assert.ok(r.findings.some(f=>f.rule==='private-home')));
});
test('rejects a dedicated weather tenant host',()=>{
  fixture({'settings.ts':"'private-fixture."+'re.qweatherapi.com'+"'"},r=>assert.ok(r.findings.some(f=>f.rule==='dedicated-weather-tenant')));
});
test('permits generated build directory without treating it as publishable',()=>{
  fixture({'build/output.dex':'fixture','README.md':'Source only'},r=>{assert.equal(r.files,1);assert.deepEqual(r.findings,[]);});
});


test('hash-pinned exception rejects changed bytes, and unpinned media stays rejected',()=>{
  fixture({'firmware/baseline/animation-frames.l8':'changed'},r=>assert.ok(r.findings.some(f=>f.rule==='screenshot-needs-privacy-review')));
  fixture({'firmware/baseline/unreviewed.png':'unreviewed'},r=>assert.ok(r.findings.some(f=>f.rule==='non-source-artifact')));
});

test('allows only the exact ios107 translation source table',()=>{
  const table='ios-addon/i18n/strings.jsonl';
  fixture({[table]:'{"key":"fixture","en":"Fixture","zh":"Fixture"}\n'},r=>assert.deepEqual(r.findings,[]));
  for(const name of ['ios-addon/i18n/other.jsonl','strings.jsonl','elsewhere/strings.jsonl']){
    fixture({[name]:'{}'},r=>assert.ok(r.findings.some(f=>f.rule==='non-source-artifact')));
  }
});
test('translation table exemption retains credential and binary-content checks',()=>{
  const table='ios-addon/i18n/strings.jsonl';
  fixture({[table]:'sk-'+'z'.repeat(24)},r=>assert.ok(r.findings.some(f=>f.rule==='api-key')));
  fixture({[table]:Buffer.from([0])},r=>assert.ok(r.findings.some(f=>f.rule==='binary-content')));
});
