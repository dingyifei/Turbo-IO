import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {validateHost,validateOptions,validateResearchPair,entitlementsFor,locationUsageFor} from './package.mjs';
import {inspectedHost} from './host-compatibility.mjs';
import {inspectMachO,addEmbeddedLoad} from './macho-embed.mjs';
import {patch,verifyRoute} from './patch-route.mjs';
const info={CFBundleIdentifier:'com.rayneo.venus.pub',CFBundleExecutable:'Runner',CFBundleShortVersionString:'1.0.7',CFBundleVersion:'230'};
const options={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-ios107-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub',firmware:'/example/TMG8.zip'};
test('exact new version, build and UUID; mismatches rejected',()=>{
 assert.ok(inspectedHost(info,'410defdbf93739eaacf2f616abff9d0b'));
 assert.equal(inspectedHost({...info,CFBundleVersion:'231'},'410defdbf93739eaacf2f616abff9d0b'),null);
 assert.equal(inspectedHost(info,'98a03b57e8163ba19778e55fabe8d762'),null);
});
test('TMG8 OTA packaging is available by default; other candidates rejected',()=>{
 validateOptions(options);
 validateOptions({...options,'experimental-ota':'TMG8'});
 for(const flag of ['TMG7','TMG6','TMG5','TMG4','TMG3','TMG2','TMIG1','enabled',''])assert.throws(()=>validateOptions({...options,'experimental-ota':flag}));
 assert.throws(()=>validateOptions({...options,firmware:undefined}));
 assert.throws(()=>validateOptions({...options,bundle:'example.other'}));
});
test('entitlements restricted to existing profile grants',()=>{
 const p={certs:[options.identity],devices:[options.device],expires:'2099-01-01T00:00:00Z',entitlements:{'application-identifier':'EXAMPLE.*'}};
 assert.equal(entitlementsFor(p,options)['aps-environment'],undefined);
 assert.throws(()=>entitlementsFor({...p,devices:[]},options));
 assert.throws(()=>entitlementsFor({...p,expires:'2000-01-01T00:00:00Z'},options));
});
test('location prompt follows the linked navigation provider',()=>{
 assert.match(locationUsageFor('_x OBJC_CLASS_$_TIOMapKitNavigationPanel _y'),/turn-by-turn/);
 assert.equal(locationUsageFor('_x'),null);
 assert.equal(locationUsageFor('_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap'),null);
});
test('unknown original image bytes and private markers rejected',()=>{
 assert.throws(()=>validateHost({...info,TIOPackagingRevision:'private'},Buffer.alloc(32),Buffer.alloc(32)));
 assert.throws(()=>validateHost({...info,CFBundleShortVersionString:'1.0.6'},Buffer.alloc(32),Buffer.alloc(32)));
 assert.throws(()=>validateHost(info,Buffer.alloc(32),Buffer.alloc(32)));
});
test('phone gates require exact host, healthy source and inspected new offsets',()=>{
 const s=fs.readFileSync(new URL('./ExperimentalOTAFlash.m',import.meta.url),'utf8');
 assert.match(s,/if\(!TIOOTA107HostMatches\(NSBundle.mainBundle.infoDictionary\)\)\s*return !TIOOTAIsEmptyVersionQuery\(data\)/);
 assert.match(s,/BOOL TIOOTAFlashAuthorize[\s\S]*?TIOOTA107HostMatches[\s\S]*?return NO;/);
 assert.match(s,/bootstrapEligible[\s\S]*?healthPassed/);
 assert.match(fs.readFileSync(new URL('./ExperimentalOTAFeed.m',import.meta.url),'utf8'),/TIOHostImageMatches/);
 assert.equal(fs.existsSync(new URL('./patch-ios106-route.mjs',import.meta.url)),false);
});
test('exact firmware resource, not a flash authorization',t=>{
 const p=process.env.IOS107_TEST_FIRMWARE;if(!p)return t.skip('set IOS107_TEST_FIRMWARE');
 const b=fs.readFileSync(p),sym='_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap';
 validateResearchPair(sym,'TMG8',b);const bad=Buffer.from(b);bad[bad.length-1]^=1;
 assert.throws(()=>validateResearchPair(sym,'TMG8',bad));
 assert.throws(()=>validateResearchPair('', 'TMG8',b));
});
test('real decrypted original input and loader preservation',t=>{
 const runner=process.env.IOS107_TEST_RUNNER,image=process.env.IOS107_TEST_APP_IMAGE;
 if(!runner||!image)return t.skip('set IOS107_TEST_RUNNER and IOS107_TEST_APP_IMAGE');
 const r=fs.readFileSync(runner),a=fs.readFileSync(image);validateHost(info,r,a);
 const h=inspectMachO(r),after=inspectMachO(addEmbeddedLoad(r));
 assert.equal(after.uuid,h.uuid);assert.equal(after.count,h.count+1);
 const bad=Buffer.from(a);bad[4096]^=1;assert.throws(()=>validateHost(info,r,bad));
 const wrong=Buffer.from(r);wrong[4096]^=1;assert.throws(()=>validateHost(info,wrong,a));
 const {output,report}=patch(a);assert.equal(report.outputSHA,'fd68e86bbad4a0a700e0e3ba844c9dc182876fa67bc46d82b695ecafa84a0e28');
 assert.ok(verifyRoute(output));assert.throws(()=>patch(output));assert.throws(()=>patch(bad));
 assert.throws(()=>verifyRoute(a));assert.throws(()=>verifyRoute(Buffer.alloc(0)));
 for(const offset of [41206352,32115728,41206340,32115716,41206344,32115720]){
   const corrupt=Buffer.from(output);corrupt[offset]^=1;assert.throws(()=>verifyRoute(corrupt));
 }
});
test('published unsigned original accepted; mutations and mixed input pairs rejected',t=>{
 const p=process.env.IOS107_TEST_UNSIGNED_APP;
 if(!p)return t.skip('set IOS107_TEST_UNSIGNED_APP');
 const r=fs.readFileSync(p+'/Runner'),a=fs.readFileSync(p+'/Frameworks/App.framework/App');
 validateHost(info,r,a);
 assert.equal(inspectMachO(addEmbeddedLoad(r)).uuid,inspectMachO(r).uuid);
 const {output}=patch(a);assert.ok(verifyRoute(output));assert.throws(()=>patch(output));
 const bad=Buffer.from(a);bad[4096]^=1;assert.throws(()=>validateHost(info,r,bad));assert.throws(()=>patch(bad));
 const wrong=Buffer.from(r);wrong[4096]^=1;assert.throws(()=>validateHost(info,wrong,a));
 if(process.env.IOS107_TEST_RUNNER)assert.throws(()=>validateHost(info,fs.readFileSync(process.env.IOS107_TEST_RUNNER),a));
 if(process.env.IOS107_TEST_APP_IMAGE)assert.throws(()=>validateHost(info,r,fs.readFileSync(process.env.IOS107_TEST_APP_IMAGE)));
});

import {usageDescriptions,applyUsageDescriptions} from './package.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync as runFixtureCommand} from 'node:child_process';
const packageTestDirectory=path.dirname(fileURLToPath(import.meta.url));
function permissionFixture(){
 const root=fs.mkdtempSync(path.join(packageTestDirectory,'build','wp1-permission-'));
 const app=path.join(root,'Runner.app');fs.mkdirSync(app,{recursive:true});
 const info=path.join(app,'Info.plist');
 const base={CFBundleIdentifier:'fixture',NSCameraUsageDescription:'Old base camera.',NSPhotoLibraryAddUsageDescription:'Old base photo add.',NSPhotoLibraryUsageDescription:'Host base photo-library access.',NSMicrophoneUsageDescription:'Host microphone remains unchanged.'};
 const xml='<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>'+Object.entries(base).map(([k,v])=>`<key>${k}</key><string>${v}</string>`).join('')+'</dict></plist>';
 fs.writeFileSync(info,xml);runFixtureCommand('plutil',['-convert','binary1',info]);
 const localizedFiles=[];
 for(const directory of ['zh-Hans-CN.lproj','zh-HK.lproj','zh-TW.lproj']){
  const lproj=path.join(app,directory);fs.mkdirSync(lproj);const strings=path.join(lproj,'InfoPlist.strings');
  fs.writeFileSync(strings,'"NSCameraUsageDescription" = "Host avatar camera.";\n"NSMicrophoneUsageDescription" = "Host voice assistant microphone.";\n"NSPhotoLibraryUsageDescription" = "Host photo library access.";\n');
  runFixtureCommand('plutil',['-convert','binary1',strings]);localizedFiles.push(strings);
 }
 return {root,app,info,strings:localizedFiles[0],hant:localizedFiles.slice(1)};
}
function plistJSON(file){return JSON.parse(runFixtureCommand('plutil',['-convert','json','-o','-',file],{encoding:'utf8'}));}
test('permission usage description variants stay in their allowed languages and write lists',()=>{
 for(const resources of [null,{}]){
  const values=usageDescriptions(resources);
  assert.doesNotMatch(Object.values(values.base).join(' '),/[㐀-鿿]/);
  assert.match(values.zhHans.NSCameraUsageDescription,/[㐀-鿿]/);assert.match(values.zhHans.NSPhotoLibraryAddUsageDescription,/[㐀-鿿]/);
  assert.match(values.zhHant.NSCameraUsageDescription,/[㐀-鿿]/);assert.match(values.zhHant.NSPhotoLibraryAddUsageDescription,/[㐀-鿿]/);
  assert.equal(Object.hasOwn(values.base,'NSMicrophoneUsageDescription'),false);
  assert.deepEqual(values.lproj,['NSCameraUsageDescription','NSPhotoLibraryAddUsageDescription']);
  assert.equal(values.lproj.includes('NSMicrophoneUsageDescription'),false);assert.equal(values.lproj.includes('NSPhotoLibraryUsageDescription'),false);
 }
});
test('applyUsageDescriptions updates only camera and photo-add keys in binary base and lproj files',()=>{
 const f=permissionFixture();try{applyUsageDescriptions(f.app,null);
  const base=plistJSON(f.info),localized=plistJSON(f.strings);
  assert.equal(base.NSCameraUsageDescription,usageDescriptions(null).base.NSCameraUsageDescription);
  assert.equal(base.NSPhotoLibraryAddUsageDescription,usageDescriptions(null).base.NSPhotoLibraryAddUsageDescription);
  assert.equal(base.NSMicrophoneUsageDescription,'Host microphone remains unchanged.');
  assert.equal(base.NSPhotoLibraryUsageDescription,'Host base photo-library access.');
  assert.equal(localized.NSCameraUsageDescription,usageDescriptions(null).zhHans.NSCameraUsageDescription);
  assert.equal(localized.NSPhotoLibraryAddUsageDescription,usageDescriptions(null).zhHans.NSPhotoLibraryAddUsageDescription);
  assert.equal(localized.NSMicrophoneUsageDescription,'Host voice assistant microphone.');
  assert.equal(localized.NSPhotoLibraryUsageDescription,'Host photo library access.');
  for(const file of f.hant){const hant=plistJSON(file);assert.equal(hant.NSCameraUsageDescription,usageDescriptions(null).zhHant.NSCameraUsageDescription);assert.equal(hant.NSPhotoLibraryAddUsageDescription,usageDescriptions(null).zhHant.NSPhotoLibraryAddUsageDescription);assert.equal(hant.NSMicrophoneUsageDescription,'Host voice assistant microphone.');assert.equal(hant.NSPhotoLibraryUsageDescription,'Host photo library access.');}
 }finally{fs.rmSync(f.root,{recursive:true,force:true});}
});
test('translationResources argument does not expand the helper write lists or alter host permission values',()=>{
 const f=permissionFixture();try{applyUsageDescriptions(f.app,{});const base=plistJSON(f.info),localized=plistJSON(f.strings);
  assert.equal(Object.hasOwn(usageDescriptions({}).base,'NSMicrophoneUsageDescription'),false);
  assert.equal(base.NSMicrophoneUsageDescription,'Host microphone remains unchanged.');
  assert.equal(base.NSPhotoLibraryUsageDescription,'Host base photo-library access.');
  assert.equal(localized.NSMicrophoneUsageDescription,'Host voice assistant microphone.');
  assert.equal(localized.NSPhotoLibraryUsageDescription,'Host photo library access.');
 }finally{fs.rmSync(f.root,{recursive:true,force:true});}
});

test('music packaging has no NetEase leftovers or URL-scheme registration',()=>{const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');assert.doesNotMatch(s,/B[e]ans|UIBackgroundModes|const music|CFBundleURLTypes/);});
test('firmware candidate keeps the shared resource filename',()=>{const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');assert.doesNotMatch(s,/TurboNavigationCandidate/);assert.equal(leakGuard.CANDIDATE_RESOURCE,'TurboWeReadCandidate.zip');assert.match(s,/path\.join\(app,CANDIDATE_RESOURCE\)/);});
test('package does not ship decorative art',()=>{assert.ok(!fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8').includes('TurboIOArt'));});

// WP7 opt-in wrapper contract: no signing, packaging, or device operations.
import {execFileSync as appleExec} from 'node:child_process';
test('Apple AI wrapper leaves flag-off package argv unchanged',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 assert.match(wrapper,/apple_args=\(\)/);
 assert.match(wrapper,/if \[\[ -n "\$apple_ai_out" \]\]/);
 assert.match(wrapper,/TIO_APPLE_AI=1 .*bash "\$ED\/build.sh" embedded/);
 assert.match(wrapper,/python3 "\$ED\/apple-ai\/build.py" --out "\$apple_ai_out"/);
 const empty=appleExec('bash',['-c','apple_args=(); set -- existing ${apple_args[@]+"${apple_args[@]}"}; printf "%s\\n" "$@"'],{encoding:'utf8'});
 assert.equal(empty,'existing\n');
 const on=appleExec('bash',['-c','apple_args=(--apple-ai-dylib "/synthetic/module dir/TurboAppleAI.dylib"); set -- existing ${apple_args[@]+"${apple_args[@]}"}; printf "%s\\n" "$@"'],{encoding:'utf8'});
 assert.equal(on,'existing\n--apple-ai-dylib\n/synthetic/module dir/TurboAppleAI.dylib\n');
});

import * as leakGuard from './package.mjs';
import os from 'node:os';
test('private files are rejected by name pattern',()=>{
 assert.equal(typeof leakGuard.privateBundleNames,'function');
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-leak-guard-'));
 try{
  for(const name of ['TurboIOPrivateTTSBootstrap.json','TurboRideSandboxPrivate.plist','TurboIOPrivateBootstrap.json','TIOAMapPrivate.json','TurboMusicCookieImport.txt','TurboIOKnowledgeConnection.json']){
   fs.writeFileSync(path.join(root,name),'fixture');
   assert.deepEqual(leakGuard.privateBundleNames(root),[name]);
   fs.unlinkSync(path.join(root,name));
  }
  for(const name of ['PrivacyInfo.xcprivacy','Info.plist'])fs.writeFileSync(path.join(root,name),'fixture');
  fs.mkdirSync(path.join(root,'permission_handler_apple_privacy.bundle'));
  assert.deepEqual(leakGuard.privateBundleNames(root),[]);
  fs.writeFileSync(path.join(root,'TurboIOPrivatePreparation.json'),'fixture');
  assert.deepEqual(leakGuard.privateBundleNames(root),['TurboIOPrivatePreparation.json']);
  assert.deepEqual(leakGuard.privateBundleNames(root,leakGuard.ALLOWED_BUNDLE_PRIVATE),[]);
  assert.deepEqual(leakGuard.privateArchiveNames(['Payload/Runner.app/Frameworks/TurboIOPrivateAddon.dylib','Payload/Runner.app/TurboIOPrivatePreparation.json','Payload/Runner.app/']),[]);
  assert.deepEqual(leakGuard.privateArchiveNames(['Payload/Runner.app/TurboRideSandboxPrivate.plist']),['Payload/Runner.app/TurboRideSandboxPrivate.plist']);
  assert.deepEqual(leakGuard.privateArchiveNames(['Payload/Runner.app/Frameworks/TurboIOPrivateTTSBootstrap.json']),['Payload/Runner.app/Frameworks/TurboIOPrivateTTSBootstrap.json']);
  assert.ok(!fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8').includes('TurboIOPrivateTTS.json'));
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test('ios107 packaging is self-contained',()=>{
 const source=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 assert.doesNotMatch(source,/from ['"]\.\.\//);
 assert.doesNotMatch(source,/['"]\.\.\//);
 assert.ok(!source.includes('focusEdition'));
 const ui=fs.readFileSync(new URL('./ExperimentalOTAUI.m',import.meta.url),'utf8');
 const loop=ui.match(/for \(NSString \*name in @\[([^\]]+)\]\)/);assert.ok(loop);
 const names=[...loop[1].matchAll(/@"(Turbo[A-Za-z]*Candidate)"/g)].map(m=>m[1]);
 assert.ok(names.includes(leakGuard.CANDIDATE_RESOURCE.replace('.zip','')));
 assert.equal([...source.matchAll(/fs\.writeFileSync\(path\.join\(app,CANDIDATE_RESOURCE\),firmware/g)].length,1);
 assert.doesNotMatch(source,/path\.join\(app,["\x27][^"\x27]*Candidate\.zip/);
});


test('nested private resources are rejected before signing',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-nested-leak-'));
 try{
  const forbidden=['Frameworks/TurboIOPrivateTTSBootstrap.json','Resources/TurboRideSandboxPrivate.plist','TurboCaptionLicenses/LicensePrivate.txt','Resources/TurboMusicCookieImport.txt','Resources/TurboIOKnowledgeConnection.json','Resources/TurboIOPrivatePreparation.json','Resources/TurboIOPrivateAddon.dylib'];
  for(const name of forbidden){fs.mkdirSync(path.dirname(path.join(root,name)),{recursive:true});fs.writeFileSync(path.join(root,name),'harmless fixture');}
  assert.deepEqual(leakGuard.privateBundleNames(root),[...forbidden].sort());
  assert.deepEqual(leakGuard.privateBundleNames(root,leakGuard.ALLOWED_BUNDLE_PRIVATE),[...forbidden].sort());
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test('bundle private allowances match exact regular-file paths',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'turbo-private-allowance-'));
 try{
  fs.mkdirSync(path.join(root,'Frameworks'));
  fs.writeFileSync(path.join(root,'Frameworks/TurboIOPrivateAddon.dylib'),'fixture');
  fs.writeFileSync(path.join(root,'TurboIOPrivatePreparation.json'),'fixture');
  assert.deepEqual(leakGuard.privateBundleNames(root),['Frameworks/TurboIOPrivateAddon.dylib','TurboIOPrivatePreparation.json']);
  assert.deepEqual(leakGuard.privateBundleNames(root,leakGuard.ALLOWED_BUNDLE_PRIVATE),[]);
  fs.unlinkSync(path.join(root,'Frameworks/TurboIOPrivateAddon.dylib'));
  fs.mkdirSync(path.join(root,'Frameworks/TurboIOPrivateAddon.dylib'));
  fs.writeFileSync(path.join(root,'Frameworks/TurboIOPrivateAddon.dylib/secret.json'),'fixture');
  assert.deepEqual(leakGuard.privateBundleNames(root,leakGuard.ALLOWED_BUNDLE_PRIVATE),['Frameworks/TurboIOPrivateAddon.dylib','Frameworks/TurboIOPrivateAddon.dylib/secret.json']);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

// Download-only 1.0.11/259 profile: stock App.framework, no route patch, no ZIP, no flash marker.
import {HOST_PROFILES,hostProfile,verifyStockApp,verifySignedStockApp} from './package.mjs';
import {stripCodeSignature} from './macho-embed.mjs';
import {createHash} from 'node:crypto';
const info1011={CFBundleIdentifier:'com.rayneo.venus.pub',CFBundleExecutable:'Runner',CFBundleShortVersionString:'1.0.11',CFBundleVersion:'259'};
const options1011={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-ios1011-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub',host:'ios1011-download'};
const sha256=b=>createHash('sha256').update(b).digest('hex');
test('host profile table: ios107 keeps the route patch and firmware; ios1011-download has neither',()=>{
 assert.deepEqual(Object.keys(HOST_PROFILES).sort(),['ios1011-download','ios107']);
 assert.equal(hostProfile(),HOST_PROFILES.ios107);assert.throws(()=>hostProfile('ios1011'));assert.throws(()=>hostProfile('__proto__'));
 const a=HOST_PROFILES.ios107,d=HOST_PROFILES['ios1011-download'];
 assert.equal(a.routePatch,true);assert.equal(a.firmware,true);assert.equal(a.stripStaleSignature,undefined);
 assert.equal(d.routePatch,false);assert.equal(d.firmware,false);assert.equal(d.stripStaleSignature,true);
 assert.equal(d.acceptedPairs.length,1);assert.deepEqual(d.acceptedPairs[0],['09598f8b1b03cc55f8ea7fd983e886e7b8c5b561016f06000c3111a57578ad95','0688e01c2541e9e4b6bfadf16a87075b6ba4e5fca78f627d2ca1488cf81354be']);
 assert.deepEqual(d.routes,[['/xrlauncherapi/v1/signApi/gray/upgrade',39886000],['/xrlauncherhwapi/v1/signApi/gray/upgrade',30868352]]);
 assert.equal(d.sourceIPASHA256,'e097f1f86cbb91b4d95e242b3c3de7c363d6abd38b7ece4408989c40d7cae19f');
 // The packager pin, the JS host matrix and the native header name the same UUID.
 const native=fs.readFileSync(new URL('./HostCompatibility.h',import.meta.url),'utf8').match(/"1\.0\.11"\]&&\[build isEqual:@"259"\]\)return @"([0-9A-F-]{36})"/);
 assert.ok(native);assert.equal(native[1].replaceAll('-','').toLowerCase(),d.uuid);
 assert.equal(inspectedHost(info1011,d.uuid).profile,'ios1011-download');assert.equal(inspectedHost(info1011,d.uuid).downloadOnly,true);
 assert.equal(inspectedHost({...info1011,CFBundleVersion:'260'},d.uuid),null);assert.equal(inspectedHost(info1011,HOST_PROFILES.ios107.uuid),null);
 assert.equal(inspectedHost(info,d.uuid),null);assert.equal(inspectedHost(info,HOST_PROFILES.ios107.uuid).downloadOnly,undefined);
});
test('download-only options take no firmware, candidate flag or product',()=>{
 validateOptions(options1011);
 for(const extra of [{firmware:'/example/TMG8.zip'},{product:'iPhone17,1'},{'experimental-ota':'TMG8'},{bundle:'example.other'}])assert.throws(()=>validateOptions({...options1011,...extra}));
 assert.throws(()=>validateOptions({...options1011,host:'ios1011'}));
 assert.throws(()=>validateOptions({...options,host:'ios1011-download'}));
 validateOptions({...options,host:'ios107'});
});
test('download-only host gate rejects other versions, TIO markers and unknown bytes',()=>{
 for(const bad of [info,{...info1011,CFBundleVersion:'258'},{...info1011,TIOHostProfile:'ios1011-download'},{...info1011,CFBundleIdentifier:'example.other'}])
  assert.throws(()=>validateHost(bad,Buffer.alloc(32),Buffer.alloc(32),'ios1011-download'),/requires_original_ios1011_259/);
 assert.throws(()=>validateHost(info1011,Buffer.alloc(32),Buffer.alloc(32),'ios1011-download'));
 assert.throws(()=>validateHost(info1011,Buffer.alloc(32),Buffer.alloc(32)),/requires_original_ios107_230/);
 assert.throws(()=>verifyStockApp(Buffer.alloc(64)),/download_only_app_changed/);assert.throws(()=>verifyStockApp(Buffer.alloc(64),'ios107'));
});
test('packager source keeps the download-only path free of route patch, ZIP and flash marker',()=>{
 const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 const branch=s.slice(s.indexOf('if(!host.routePatch){'),s.indexOf('}else{',s.indexOf('if(!host.routePatch){')));
 assert.ok(branch.includes('verifyStockApp('));assert.ok(branch.includes("'TIOHostProfile'"));
 for(const forbidden of ['patchOTARoute','TIOExperimentalOTAQueryRouting','TIOExperimentalOTABuild','CANDIDATE_RESOURCE','UISupportedDevices','NSAllowsLocalNetworking'])assert.ok(!branch.includes(forbidden),forbidden);
 assert.match(s,/if\(host\.routePatch\)verifyRoute\(/);assert.match(s,/else verifySignedStockApp\(/);
 assert.match(s,/host\.stripStaleSignature\?\['--strip-stale-signature'\]:\[\]/);
});
test('real 1.0.11 input: pins, unpatched routes and deterministic signature strip',t=>{
 const p=process.env.IOS1011_TEST_APP;if(!p)return t.skip('set IOS1011_TEST_APP');
 const r=fs.readFileSync(p+'/Runner'),a=fs.readFileSync(p+'/Frameworks/App.framework/App');
 const frameworks={'RayneoNet.framework/RayneoNet':fs.readFileSync(p+'/Frameworks/RayneoNet.framework/RayneoNet'),'Flutter.framework/Flutter':fs.readFileSync(p+'/Frameworks/Flutter.framework/Flutter')};
 const plist=JSON.parse(runFixtureCommand('plutil',['-convert','json','-o','-',p+'/Info.plist'],{encoding:'utf8'}));
 validateHost(plist,r,a,'ios1011-download',frameworks);assert.ok(inspectedHost(plist,inspectMachO(r).uuid).downloadOnly);
 assert.throws(()=>validateHost(plist,r,a,'ios1011-download'),/host_framework_identity_mismatch/);
 assert.throws(()=>validateHost(plist,r,a,'ios107',frameworks));
 const badNet=Buffer.from(frameworks['RayneoNet.framework/RayneoNet']);badNet[4096]^=1;assert.throws(()=>validateHost(plist,r,a,'ios1011-download',{...frameworks,'RayneoNet.framework/RayneoNet':badNet}));
 const badApp=Buffer.from(a);badApp[4096]^=1;assert.throws(()=>validateHost(plist,r,badApp,'ios1011-download',frameworks));assert.throws(()=>verifyStockApp(badApp));
 const badRunner=Buffer.from(r);badRunner[4096]^=1;assert.throws(()=>validateHost(plist,badRunner,a,'ios1011-download',frameworks));
 assert.ok(verifyStockApp(a));assert.throws(()=>patch(a));
 for(const [route,offset] of HOST_PROFILES['ios1011-download'].routes){const moved=Buffer.from(a);moved[offset]^=1;assert.throws(()=>verifyStockApp(moved));}
 // Strip: deterministic, idempotent, removes exactly LC_CODE_SIGNATURE and its blob.
 const h=inspectMachO(r),one=stripCodeSignature(r),two=stripCodeSignature(r);
 assert.equal(one.stripped,true);assert.ok(one.output.equals(two.output));assert.equal(stripCodeSignature(one.output).stripped,false);
 assert.equal(sha256(one.output),'c28032569765077b0246a3ba9c54fede700f5bed4d3445f61cea0e40fcdbd6f6');
 const u=inspectMachO(one.output);assert.equal(u.uuid,h.uuid);assert.equal(u.count,h.count-1);assert.equal(u.encrypted,false);assert.equal(one.output.length,42246528);
 const embedded=inspectMachO(addEmbeddedLoad(one.output));assert.equal(embedded.uuid,h.uuid);assert.equal(embedded.count,h.count);
 assert.deepEqual(embedded.dependencies.filter(x=>!inspectMachO(r).dependencies.includes(x)),['@executable_path/Frameworks/TurboIOPrivateAddon.dylib']);
 assert.equal(sha256(r),HOST_PROFILES['ios1011-download'].acceptedPairs[0][0]); // input untouched
 // After signing only the signature may differ: same stripped bytes, same route records.
 assert.ok(verifySignedStockApp(a,a));assert.throws(()=>verifySignedStockApp(badApp,a));
});
test('real 1.0.11 input: unsigned preparation leaves App.framework byte-identical to stock',t=>{
 const p=process.env.IOS1011_TEST_APP,addon=path.join(packageTestDirectory,'build/mapkit/TurboIOPrivateAddon.dylib');
 if(!p)return t.skip('set IOS1011_TEST_APP');if(!fs.existsSync(addon))return t.skip('build the embedded addon first');
 const root=fs.mkdtempSync(path.join(packageTestDirectory,'build','h1011-prepare-'));
 try{
  // Minimal fixture copied from the real input: Info.plist, Runner, App.framework and the stale seal.
  const src=path.join(root,'src/Runner.app');fs.mkdirSync(path.join(src,'Frameworks/App.framework'),{recursive:true});fs.mkdirSync(path.join(src,'_CodeSignature'));
  for(const f of ['Info.plist','Runner','Frameworks/App.framework/App','Frameworks/App.framework/Info.plist','_CodeSignature/CodeResources'])fs.copyFileSync(path.join(p,f),path.join(src,f));
  const embed=path.join(packageTestDirectory,'macho-embed.mjs');
  assert.throws(()=>runFixtureCommand(process.execPath,[embed,src,path.join(root,'plain/Runner.app'),addon,'com.rayneo.venus.pub'],{stdio:'pipe'}),e=>/require --strip-stale-signature/.test(String(e.stderr)));
  assert.equal(fs.existsSync(path.join(root,'plain')),false);
  const out=path.join(root,'out/Runner.app');
  runFixtureCommand(process.execPath,[embed,src,out,addon,'com.rayneo.venus.pub','--strip-stale-signature'],{stdio:'pipe'});
  const app=fs.readFileSync(path.join(out,'Frameworks/App.framework/App'));
  assert.equal(sha256(app),'0688e01c2541e9e4b6bfadf16a87075b6ba4e5fca78f627d2ca1488cf81354be');assert.ok(verifyStockApp(app));
  assert.equal(fs.existsSync(path.join(out,'_CodeSignature')),false);assert.ok(fs.existsSync(path.join(src,'_CodeSignature/CodeResources')));
  const runner=fs.readFileSync(path.join(out,'Runner')),report=JSON.parse(fs.readFileSync(path.join(out,'TurboIOPrivatePreparation.json'),'utf8'));
  assert.equal(stripCodeSignature(runner).stripped,false);assert.equal(inspectMachO(runner).uuid,'22724c972ef9388d8e6a6e051855a555');
  assert.equal(report.hostProfile,'ios1011-download');assert.equal(report.staleSignatureRemoved,true);
  assert.equal(report.originalExecutableSHA256,'09598f8b1b03cc55f8ea7fd983e886e7b8c5b561016f06000c3111a57578ad95');
  assert.equal(report.unsignedExecutableSHA256,'c28032569765077b0246a3ba9c54fede700f5bed4d3445f61cea0e40fcdbd6f6');
  assert.equal(report.preparedExecutableSHA256,sha256(runner));
  const plist=plistJSON(path.join(out,'Info.plist'));
  for(const k of ['TIOExperimentalOTAQueryRouting','TIOExperimentalOTABuild','UISupportedDevices','TIOHostProfile'])assert.equal(plist[k],undefined,k);
  assert.equal(fs.existsSync(path.join(out,leakGuard.CANDIDATE_RESOURCE)),false);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('wrappers: --host 1011 packages without firmware or product; the 1.0.11 gate stage is optional',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 const branch=wrapper.slice(wrapper.indexOf('if [[ $host == 1011 ]]; then\n# Download-only:'),wrapper.indexOf('\nelse\nrun_logged package'));
 assert.match(branch,/--host ios1011-download --app "\$TURBO_APP1011"/);
 assert.doesNotMatch(branch,/--firmware|--product|TURBO_APP107/);
 assert.match(branch,/hostProfile'\]=='ios1011-download'/);
 assert.match(wrapper,/unset [^\n]*TURBO_APP1011/);
 assert.match(wrapper,/--firmware "\$TURBO_FIRMWARE" --product "\$TURBO_PRODUCT"/);
 const gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 assert.match(gate,/if \[\[ -n "\$TURBO_APP1011" \]\]; then stage host1011 host1011_stage; else report skip host1011 'TURBO_APP1011 not set'; fi/);
 assert.match(gate,/stage test test_stage\n    stage package-test package_test_stage/);
});
