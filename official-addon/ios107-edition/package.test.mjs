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
test('TMG9 OTA packaging is available by default; other candidates rejected',()=>{
 validateOptions(options);
 validateOptions({...options,'experimental-ota':'TMG9'});
 for(const flag of ['TMG8','TMG7','TMG6','TMG5','TMG4','TMG3','TMG2','TMIG1','enabled',''])assert.throws(()=>validateOptions({...options,'experimental-ota':flag}));
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
 // Each OTA host (ios107, or the full ios1011 with its own marker) passes only through TIOOTAHostMatches.
 assert.match(s,/if\(!TIOOTAHostMatches\(NSBundle.mainBundle.infoDictionary\)\)\s*return !TIOOTAIsEmptyVersionQuery\(data\)/);
 assert.match(s,/BOOL TIOOTAFlashAuthorize[\s\S]*?TIOOTAHostMatches[\s\S]*?return NO;/);
 assert.doesNotMatch(s,/TIOOTA107HostMatches/);
 // C15: the full 1.0.11 host is refused while disarmed, before the flash-build early return, and authorization checks the arm.
 const snapshot=s.slice(s.indexOf('BOOL TIOOTAFlashBlockCallSnapshot('));
 assert.ok(snapshot.indexOf('if(TIOOTADownloadOnlyHost())return DownloadOnlyBlock(')<snapshot.indexOf('if(TIOOTAArmRequired()&&!ArmedForTransfer())return DisarmedBlock(call,teleprompter);'));
 assert.ok(snapshot.indexOf('if(TIOOTAArmRequired()&&!ArmedForTransfer())return DisarmedBlock(call,teleprompter);')<snapshot.indexOf('if(!TIOOTAFlashBuild())return NO;'));
 assert.match(s,/BOOL TIOOTAFlashAuthorize[^\n]*\n[^\n]*TIOOTAHostMatches[^\n]*\n\s*if\(TIOOTAArmRequired\(\)&&!ArmedForTransfer\(\)\)\{Error\(/);
 assert.match(s,/bootstrapEligible[\s\S]*?healthPassed/);
 assert.match(fs.readFileSync(new URL('./ExperimentalOTAFeed.m',import.meta.url),'utf8'),/TIOOTAHostProfile\(bundle\.infoDictionary\)[\s\S]*?TIOHostFullImageMatches\(TIOHostMainImage\(\),bundle\.infoDictionary\)[\s\S]*?TIOOTARouteFileMatches\(file,profile\)/);
 // TIOOTA107HostMatches itself is unchanged.
 assert.match(fs.readFileSync(new URL('./OTAHost.h',import.meta.url),'utf8'),/static inline BOOL TIOOTA107HostMatches\(NSDictionary \*info\) \{\n    return \[info\[@"CFBundleIdentifier"\] isEqual:@"com\.rayneo\.venus\.pub"\] &&\n        \[info\[@"CFBundleShortVersionString"\] isEqual:@"1\.0\.7"\] &&\n        \[info\[@"CFBundleVersion"\] isEqual:@"230"\] &&\n        \[info\[@"TIOExperimentalOTAQueryRouting"\] isEqual:@"ios107-tmg2-loopback-flash-gated"\];\n\}/);
 assert.equal(fs.existsSync(new URL('./patch-ios106-route.mjs',import.meta.url)),false);
});
test('exact firmware resource, not a flash authorization',t=>{
 const p=process.env.IOS107_TEST_FIRMWARE;if(!p)return t.skip('set IOS107_TEST_FIRMWARE');
 const b=fs.readFileSync(p),sym='_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap';
 validateResearchPair(sym,'TMG9',b);const bad=Buffer.from(b);bad[bad.length-1]^=1;
 assert.throws(()=>validateResearchPair(sym,'TMG9',bad));
 assert.throws(()=>validateResearchPair('', 'TMG9',b));
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
 // The Apple AI flag set feeds the one fresh addon build every package run makes.
 assert.match(wrapper,/build_flags=\(TIO_APPLE_AI=1 [^)]*\)/);
 assert.match(wrapper,/env -i [^\n]*"\$\{build_flags\[@\]\}" bash "\$ED\/build.sh" embedded/);
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
import * as packaging from './package.mjs';
import {stripCodeSignature} from './macho-embed.mjs';
import {createHash} from 'node:crypto';
const info1011={CFBundleIdentifier:'com.rayneo.venus.pub',CFBundleExecutable:'Runner',CFBundleShortVersionString:'1.0.11',CFBundleVersion:'259'};
const options1011={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-ios1011-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub',host:'ios1011-download'};
const sha256=b=>createHash('sha256').update(b).digest('hex');
test('host profile table: ios107 keeps the route patch and firmware; ios1011-download has neither',()=>{
 assert.deepEqual(Object.keys(HOST_PROFILES).sort(),['ios1011','ios1011-download','ios107']);
 assert.equal(hostProfile(),HOST_PROFILES.ios107);for(const bad of ['ios1011-full','IOS1011','1011','__proto__'])assert.throws(()=>hostProfile(bad));
 const a=HOST_PROFILES.ios107,d=HOST_PROFILES['ios1011-download'];
 assert.equal(a.routePatch,true);assert.equal(a.firmware,true);assert.equal(a.stripStaleSignature,undefined);
 assert.equal(a.routeProfile,'ios107');assert.equal(a.routingMarker,'ios107-tmg2-loopback-flash-gated');assert.equal(a.packagingRevision,'APP107-OTA-PUBLIC-SOURCE-01');assert.equal(a.hostProfileMarker,undefined);
 assert.equal(d.routePatch,false);assert.equal(d.firmware,false);assert.equal(d.stripStaleSignature,true);
 assert.equal(d.acceptedPairs.length,1);assert.deepEqual(d.acceptedPairs[0],['09598f8b1b03cc55f8ea7fd983e886e7b8c5b561016f06000c3111a57578ad95','0688e01c2541e9e4b6bfadf16a87075b6ba4e5fca78f627d2ca1488cf81354be']);
 assert.deepEqual(d.routes,[['/xrlauncherapi/v1/signApi/gray/upgrade',39886000],['/xrlauncherhwapi/v1/signApi/gray/upgrade',30868352]]);
 assert.equal(d.sourceIPASHA256,'e097f1f86cbb91b4d95e242b3c3de7c363d6abd38b7ece4408989c40d7cae19f');
 // The packager pin, the JS host matrix and the native header name the same UUID.
 const native=fs.readFileSync(new URL('./HostCompatibility.h',import.meta.url),'utf8').match(/"1\.0\.11"\]&&\[build isEqual:@"259"\]\)return @"([0-9A-F-]{36})"/);
 assert.ok(native);assert.equal(native[1].replaceAll('-','').toLowerCase(),d.uuid);
 assert.equal(inspectedHost(info1011,d.uuid).profile,'ios1011-download');assert.equal(inspectedHost(info1011,d.uuid).downloadOnly,true);assert.equal(inspectedHost(info1011,d.uuid).staleSignature,true);
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
 // Simulated re-sign (no codesign): replace the signature blob with one of another size,
 // as codesign_allocate lays it out. A smaller blob keeps __LINKEDIT vmsize, a larger one grows it.
 const layout=b=>{let p=32,sig,link;for(let i=0;i<b.readUInt32LE(16);i++){const c=b.readUInt32LE(p);if(c===0x1d)sig=p;if(c===0x19&&b.toString('latin1',p+8,p+24).startsWith('__LINKEDIT'))link=p;p+=b.readUInt32LE(p+4);}return {sig,link};};
 const resign=(b,size,vmsize)=>{const {sig,link}=layout(b),dataoff=b.readUInt32LE(sig+8),out=Buffer.concat([b.subarray(0,dataoff),Buffer.alloc(size,0xfa)]);
  out.writeUInt32LE(size,sig+12);const filesize=BigInt(out.length)-out.readBigUInt64LE(link+40);out.writeBigUInt64LE(filesize,link+48);
  out.writeBigUInt64LE(vmsize??((filesize+0x3fffn)&~0x3fffn),link+32);return out;};
 const keepVm=b=>b.readBigUInt64LE(layout(b).link+32);
 const smaller=resign(a,400000,keepVm(a)),larger=resign(a,1400000);
 assert.notEqual(keepVm(larger),keepVm(a));
 assert.ok(verifySignedStockApp(smaller,a));assert.ok(verifySignedStockApp(larger,a));
 const flipped=Buffer.from(larger);flipped[4096]^=1;assert.throws(()=>verifySignedStockApp(flipped,a),/changed_after_signing/);
 assert.throws(()=>verifySignedStockApp(resign(a,1400000,keepVm(a)),a),/changed_after_signing/); // vmsize below filesize
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
  assert.equal(report.hostImage,'1.0.11/259');assert.equal(report.hostProfile,undefined);assert.equal(report.staleSignatureRemoved,true);
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
 const branch=wrapper.slice(wrapper.indexOf('if [[ $host == 1011 ]]; then\n# G1/G2'),wrapper.indexOf('\nelif [[ $host == 1011-full ]]; then\n# C15'));
 assert.match(branch,/--host ios1011-download --app "\$TURBO_APP1011"/);
 assert.doesNotMatch(branch,/--firmware|--product|TURBO_APP107/);
 assert.match(branch,/hostProfile'\]=='ios1011-download'/);
 assert.match(wrapper,/unset [^\n]*TURBO_APP1011/);
 assert.match(wrapper,/--firmware "\$TURBO_FIRMWARE" --product "\$TURBO_PRODUCT"/);
 const gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 assert.match(gate,/if \[\[ -n "\$TURBO_APP1011" \]\]; then stage host1011 host1011_stage; else report skip host1011 'TURBO_APP1011 not set'; fi/);
 assert.match(gate,/stage test test_stage\n    stage package-test package_test_stage/);
});
// The 1.0.11 guard depends on Load() installing the rayneonet hook on the
// download-only host; no host test links Addon.m, so pin the source shape here.
test('download-only host: Load installs only the guard hook and sends nothing on its own',()=>{
 const src=f=>fs.readFileSync(new URL('./'+f,import.meta.url),'utf8');
 const addon=src('Addon.m'),load=addon.slice(addon.indexOf('static void Load(void)'));
 assert.match(load,/BOOL downloadOnly=\[TIOHostProfile\(\) isEqual:@"ios1011-download"\];/);
 // The profile uses the refusal's own host test (image OR packager marker) before the image-only
 // lookup, so Load installs the hook and the hub hides the 1.0.7 catalog whenever the refusal applies.
 const profile=addon.match(/NSString \*TIOHostProfile\(void\) \{([\s\S]*?)\n\}/);assert.ok(profile);
 assert.ok(profile[1].indexOf('if(TIOOTADownloadOnlyHost())return @"ios1011-download";')>0);
 assert.ok(profile[1].indexOf('if(TIOOTADownloadOnlyHost())')<profile[1].indexOf('TIOHostProfileFor(MainImage()'));
 assert.match(load,/HOST PROFILE MISMATCH: image=%@; marker=%@; treated as download-only/);
 assert.match(load,/if\(valid\)\{TIOInstallGlassesChannelHook\(\);TIOInstallTodoRuntime\(\);\}\n(?:\s*\/\/[^\n]*\n)*\s*else if\(downloadOnly\)TIOInstallGlassesChannelHook\(\);/);
 assert.equal([...addon.matchAll(/TIOInstallGlassesChannelHook\(\)/g)].length,2);
 // No addon-originated glasses frames on the download-only host.
 assert.equal([...addon.matchAll(/TIOLanguageFlagStart\(\)/g)].length,1);assert.match(load,/if\(!downloadOnly\)TIOLanguageFlagStart\(\);/);
 assert.equal([...addon.matchAll(/TIOClenchLabInstallRecovery\(\)/g)].length,1);assert.match(load,/if\(!downloadOnly\)TIOClenchLabInstallRecovery\(\);/);
 const watch=src('WatchRemoteAddon.m'),ctor=watch.slice(watch.indexOf('static void TIOWatchLoad(void)'));
 assert.ok(ctor.indexOf('if([TIOHostProfile() isEqual:@"ios1011-download"])return;')>=0);
 assert.ok(ctor.indexOf('if([TIOHostProfile() isEqual:@"ios1011-download"])return;')<ctor.indexOf('activate]'));
 // The guard row is green only when every part of the safety net is present. The
 // refusal is flag-independent (G1), so the predicate no longer asks for TIOOTAFlashBuild().
 const guard=addon.match(/BOOL TIOHostDownloadOnlyGuardActive\(void\) \{([\s\S]*?)\n\}/);assert.ok(guard);
 for(const part of ['TIODownloadOnlyGuardActiveFor(TIOHostProfile(),TIOGlassesChannelHookInstalled(),[TIOOTAGuardStatus()[@"transportHookReady"] boolValue])','TIOOTADownloadOnlyHost()','!TIOOTA107HostMatches('])assert.ok(guard[1].includes(part),part);
 assert.doesNotMatch(guard[1],/\|\||TIOOTAFlashBuild/);
 // G2: a failed hook install on the download-only host is written to the load info.
 assert.match(load,/if\(downloadOnly&&!TIOGlassesChannelHookInstalled\(\)\)\[loadInfo appendFormat:@"DOWNLOAD-ONLY GUARD NOT ACTIVE: [^"]*",TIOGlassesChannelHookFailure\(\)\];/);
 assert.match(load,/TIOOTADownloadOnlyGuardMarker\]/);
 assert.match(load,/downloadOnlyGuard=%d; stockTraffic=%d\\n%@\\n",[^;]*TIOGlassesChannelStockTrafficSeen\(\),TIOOTADownloadOnlyGuardMarker\]/);
 // The hook applies the OTA guard before any observer or the stock handler runs. The guard stage is the
 // shared TIOMethodHookGuardStage (MethodHookStages.h), which the host guard sweeps also run.
 const hook=src('GlassesChannelHook.m'),body=hook.slice(hook.indexOf('static void MethodHook('),hook.indexOf('static void Send('));
 const stages=src('MethodHookStages.h'),stage=stages.slice(stages.indexOf('static inline BOOL TIOMethodHookGuardStage('));
 const block=stage.indexOf('@try{otaBlocked=TIOOTAFlashBlockCallSnapshot(call,&teleprompter);}@catch(__unused id e){otaBlocked=YES;teleprompter=nil;}');assert.ok(block>0);
 // D5: the guard starts from blocked, and a teleprompter pass forwards the checked snapshot (or blocks when none can be built).
 assert.ok(stage.includes('NSDictionary *teleprompter=nil;BOOL otaBlocked=YES;'));
 assert.ok(stage.includes('if(!otaBlocked&&teleprompter){id checked=TIOStockTeleprompterForwardCall(teleprompter);if(checked)call=checked;else otaBlocked=YES;}'));
 assert.ok(stage.indexOf('TIOStockTeleprompterForwardCall(')<stage.indexOf('if(otaBlocked)'));
 assert.match(stage,/if\(otaBlocked\)\{if\(result\)\(\(void\(\^\)\(id\)\)result\)\(@\{@"success":@NO,@"message":TIOMethodHookBlockedMessage\}\);return YES;\}\n    allowed\(call,result\);/);
 // Observers and the prior method run only inside `allowed`, i.e. after the guard let the call through.
 const allowed=body.indexOf('^(id forwarded,id reply){');assert.ok(allowed>0);
 for(const s of ['TIOGlassesLogBlockCall(forwarded)','TIOProtocolObserveCall(','TIOTodoObserveSnapshotMessage(','PriorMethod(self,cmd,forwarded,reply);'])assert.ok(body.indexOf(s)>allowed,s);
 assert.equal([...body.matchAll(/PriorMethod\(/g)].length,1);
 // G2 runtime evidence: MethodHook records a stock rayneonet call before the guard stage can
 // refuse it and return, and after the off-main sendFile redispatch (so one call counts once).
 const evidence=body.indexOf('RecordStockEvidence(call,result);');assert.ok(evidence>0);
 assert.equal(body.split('RecordStockEvidence(call,result);').length,2);
 assert.ok(evidence<body.indexOf('TIOMethodHookGuardStage(wireChannel,call,result,'));
 assert.ok(evidence>body.indexOf('if(TIOMethodHookHopToMain(call,^{MethodHook(self,cmd,call,result);}))return;'));
 assert.match(stages,/if\(\[TIOMethodHookRead\(call,@"method"\) isEqual:@"rayneonet_sendFile"\]&&!NSThread\.isMainThread\)\{\n        dispatch_async\(dispatch_get_main_queue\(\),again\);return YES;/);
 assert.ok(stage.indexOf('TIOOTAFlashBlockCallSnapshot(')===stage.lastIndexOf('TIOOTAFlashBlockCallSnapshot('));
 assert.ok(!body.includes('TIOOTAFlashBlockCall'));
 // Only stock calls count: the origin is the image of the result block's invoke function, checked by
 // the tested TIOChannelResultImageIsStock; the addon's own senders count separately as addonCalls.
 const record=hook.slice(hook.indexOf('static void RecordStockEvidence('),hook.indexOf('static void MethodHook('));
 assert.match(record,/\[method hasPrefix:@"rayneonet_"\]/);
 assert.match(record,/if\(!StockOrigin\(result\)\)\{atomic_fetch_add_explicit\(&AddonCalls,1,memory_order_relaxed\);return;\}/);
 assert.match(hook,/if\(!TIOChannelResultImageIsStock\(@\(theirs\.dli_fname\),addonImage,bundle\)\)return NO;/);
 assert.match(hook,/Installed=YES;InstallFailure=nil;TIOOTARecordTransportHookReady\(\);/);
 // G2: the install resolves both targets through the tested check and swaps nothing on failure.
 const install=hook.slice(hook.indexOf('BOOL TIOInstallGlassesChannelHook(void)'));
 const check=install.indexOf('NSString *failure=TIOChannelHookTargetFailure(bridge,engine);if(failure){InstallFailure=failure;return NO;}');
 assert.ok(check>0&&check<install.indexOf('method_setImplementation('));
 assert.doesNotMatch(hook,/static BOOL Sign\(/);
});
// Wire log port: the hook order is fixed. The stock-traffic evidence must read the original result block
// (its origin check looks at where the block's code lives; the recorder's wrapper lives in the addon), the
// recorder wraps before the guard so a blocked call is recorded with the guard's reply, and the guard
// decides before the prior method runs.
test('MethodHook order: hop, stock evidence, wire log, guard, prior method',()=>{
 const src=f=>fs.readFileSync(new URL('./'+f,import.meta.url),'utf8');
 const hook=src('GlassesChannelHook.m'),body=hook.slice(hook.indexOf('static void MethodHook('),hook.indexOf('static void Send('));
 const stages=src('MethodHookStages.h'),stage=stages.slice(stages.indexOf('static inline BOOL TIOMethodHookGuardStage('));
 const once=(t,s)=>{const i=t.indexOf(s);assert.ok(i>0,s);assert.equal(t.indexOf(s,i+1),-1,'once: '+s);return i;};
 // In MethodHook: claim, hop, evidence (original result block), the shared guard stage; the prior method only in `allowed`.
 const claim=once(body,'wireChannel=TIOWireLogClaimBridgeCall();');
 const hop=once(body,'if(TIOMethodHookHopToMain(call,^{MethodHook(self,cmd,call,result);}))return;');
 const evidence=once(body,'RecordStockEvidence(call,result);');
 const guardStage=once(body,'TIOMethodHookGuardStage(wireChannel,call,result,');
 const prior=once(body,'PriorMethod(self,cmd,forwarded,reply);');
 assert.ok(claim<hop&&hop<evidence&&evidence<guardStage&&guardStage<prior);
 // Nothing in MethodHook replaces the call or the result block; the evidence reads the stock block.
 assert.doesNotMatch(body,/\bresult=|\bcall=/);
 // In the shared stage: wrap, guard, verdict, forward, forwarded note, blocked reply, allowed.
 const wrap=once(stage,'result=TIOWireLogWrapBridgeResult(wireChannel,call,result);');
 const guard=once(stage,'@try{otaBlocked=TIOOTAFlashBlockCallSnapshot(call,&teleprompter);}@catch(__unused id e){otaBlocked=YES;teleprompter=nil;}');
 const verdict=once(stage,'if(decided)decided(otaBlocked);');
 const forward=once(stage,'if(!otaBlocked&&teleprompter){id checked=TIOStockTeleprompterForwardCall(teleprompter);if(checked)call=checked;else otaBlocked=YES;}');
 const noted=once(stage,'if(!otaBlocked&&teleprompter)TIOWireLogBridgeForwarded(result,call);');
 const blocked=once(stage,'if(otaBlocked){if(result)((void(^)(id))result)(');
 const allowed=once(stage,'allowed(call,result);');
 assert.ok(wrap<guard&&guard<verdict&&verdict<forward&&forward<noted&&noted<blocked&&blocked<allowed);
 assert.equal([...stage.matchAll(/\bresult=/g)].length,1);assert.equal([...stage.matchAll(/\bcall=/g)].length,1);
 // The host guard sweeps call the same stage function, not a copy of it.
 const harness=src('tests/WireLogGuardHarness.h');
 assert.match(harness,/#import "MethodHookStages\.h"/);assert.match(harness,/TIOMethodHookGuardStage\(@"com\.rayneo\/sdk",call,stock,/);
 assert.doesNotMatch(harness,/TIOOTAFlashBlockCallSnapshot|TIOWireLogWrapBridgeResult|TIOStockTeleprompterForwardCall/);
 // Every wire log line in the shared sources is compiled only with TIO_WIRE_LOG, so the default build has none of it.
 for(const f of ['GlassesChannelHook.m','Addon.m','ResearchCatalog.m','MethodHookStages.h']){
  const stack=[];let seen=0;
  for(const line of src(f).split('\n')){
   if(/^#if/.test(line))stack.push(line.trim());
   else if(/^#el/.test(line))stack[stack.length-1]='#else';
   else if(/^#endif/.test(line))stack.pop();
   else if(/TIOWireLog|WireLog(UI)?\.h|"wireLog"/.test(line)){seen++;assert.ok(stack.includes('#if TIO_WIRE_LOG'),f+': '+line);}
  }
  assert.ok(seen>0,f);
 }
 // The recorder never reads non-plain objects and never changes what it forwards.
 const wire=src('WireLog.m');
 assert.match(wire,/if \(!WLPlain\(v\)\) return WLClassOnly\(v\);/);
 assert.match(wire,/original\(value\); \/\/ first and unchanged/);
 assert.doesNotMatch(wire,/TIOOTAFlash|TIOStockTeleprompter|PriorMethod|sendOnChannel:message:binaryReply:/);
});
// A package run builds the addon itself (both hosts), so a stale build/mapkit dylib is never packaged.
test('turbo-package.sh builds the addon fresh with the requested flags before signing',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 const gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 const pos=s=>{const i=wrapper.indexOf(s);assert.ok(i>0,s);return i;};
 const scrub=pos('for name in $(compgen -e); do [[ $name != TIO_* ]] || unset "$name"; done');
 const remove=pos('rm -f "$ADDON"\n[[ ! -e "$ADDON" ]] ||');
 const sourced=pos('source "$TURBO_INPUTS/package.env"');
 const build=pos('run_logged addon-build env -i PATH="$PATH" HOME="$HOME" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} "${build_flags[@]}" bash "$ED/build.sh" embedded com.rayneo.venus.pub');
 const built=pos("[[ -f \"$ADDON\" ]] || { echo 'PACKAGE FAIL: the addon was not built in this run' >&2; exit 1; }");
 const check=pos('run_logged addon-check addon_check');
 const buildOnly=pos('if [[ $build_only == 1 ]]; then');
 const sign=pos('run_logged signing-preflight codesign');
 const guard1011=pos('run_logged download-only-guard download_only_guard "$ADDON"\n# Download-only');
 const copy=pos('cp -p "$ADDON" "$LOG_DIR/addon/TurboIOPrivateAddon.dylib"\nADDON=$LOG_DIR/addon/TurboIOPrivateAddon.dylib');
 assert.ok(sourced<scrub&&scrub<remove&&remove<build&&build<built&&built<check&&check<copy&&copy<buildOnly&&buildOnly<sign&&sign<guard1011);
 // The signed dylib is the checked copy: its SHA-256 is checked again right before each package.mjs run.
 // Three package runs: 1.0.7, download-only 1.0.11 and full 1.0.11 (C15).
 assert.equal([...wrapper.matchAll(/run_logged addon-unchanged addon_unchanged\nrun_logged package node "\$ED\/package\.mjs"/g)].length,3);
 assert.equal([...wrapper.matchAll(/run_logged package node/g)].length,3);
 assert.ok(wrapper.includes("addon_sha=$(tail -n 1 \"$LOG_DIR/addon-check.log\")"));
 // The fresh build is not inside a host branch: it runs for 1.0.7 and 1.0.11 alike.
 assert.ok(build<wrapper.indexOf('if [[ $host == 1011 ]]; then\n  [[ -f "$TURBO_PROFILE"'));
 assert.equal([...wrapper.matchAll(/build\.sh/g)].length,1);
 // Flag sets: the default is the gate's own build, --apple-ai keeps its earlier set, --wire-log only adds TIO_WIRE_LOG=1.
 const gateFlags=gate.match(/build_stage\(\) \{\n  cd "\$ED"\n  ([^\n]*)\\\n    ([^\n]*)\\\n    ([^\n]*) bash build\.sh embedded/);assert.ok(gateFlags);
 const flags=t=>t.trim().split(/\s+/).filter(x=>x.startsWith('TIO_')).sort();
 const want=flags(gateFlags.slice(1).join(' '));
 const defaults=wrapper.match(/else\n  build_flags=\(([^)]*)\)\nfi/);assert.ok(defaults);
 assert.deepEqual(flags(defaults[1]),want);
 const apple=wrapper.match(/if \[\[ -n "\$apple_ai_out" \]\]; then\n  build_flags=\(([^)]*)\)/);assert.ok(apple);
 assert.deepEqual(flags(apple[1]),['TIO_APPLE_AI=1','TIO_CLASSIC_BINDINGS=1','TIO_DISPLAY_FLASH=1','TIO_DISPLAY_PHONE=1','TIO_IMAGE_RX_LAB=1','TIO_MAPKIT_ENABLED=1','TIO_OTA_FLASH_ENABLED=1']);
 assert.ok(wrapper.includes('[[ $wire_log != 1 ]] || build_flags+=(TIO_WIRE_LOG=1)'));
 assert.ok(!want.includes('TIO_WIRE_LOG=1'));
 // The built addon carries the recorder exactly when it was asked for.
 const addonCheck=wrapper.slice(wrapper.indexOf('addon_check() {'),wrapper.indexOf('run_logged addon-check addon_check'));
 assert.match(addonCheck,/grep -Eq ' _TIOWireLogStart\$' <<<"\$symbols"/);
 // --build-only stops before the identity is used or an output directory is named.
 const stop=wrapper.slice(buildOnly,wrapper.indexOf('\nfi\n',buildOnly));
 assert.match(stop,/exit 0$/);assert.ok(buildOnly<wrapper.indexOf('OUT=$TURBO_INPUTS/signed-'));
 // The gate's default build must have no recorder at all.
 assert.match(gate,/\n  bash "\$REPO\/scripts\/wirelog-absent\.sh" "\$addon"\n/);
 assert.match(addonCheck,/bash "\$REPO\/scripts\/wirelog-absent\.sh" "\$ADDON"/);
 // No piped nm check anywhere in the scripts: under pipefail a match reads as nm's SIGPIPE.
 for(const text of [wrapper,gate,fs.readFileSync(new URL('../../scripts/wirelog-absent.sh',import.meta.url),'utf8')])assert.doesNotMatch(text.split('\n').filter(l=>!/^\s*#/.test(l)).join('\n'),/\bnm [^\n|]*\|\s*grep/);
});
// The leak check must really fire. A dylib with the real recorder (WireLog.m built with TIO_WIRE_LOG=1) and
// enough other symbols that nm is still writing when grep matches: the check fails on it and passes without
// the recorder, while the old piped form (`nm | grep -q` under pipefail) misses it.
import {spawnSync} from 'node:child_process';
test('wirelog-absent.sh fails on a TIO_WIRE_LOG=1 build',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'wirelog-absent-'));
 try{
  const filler=path.join(dir,'filler.c');
  let c='';for(let i=0;i<30000;i++)c+=`int tio_filler_${String(i).padStart(5,'0')}(void){return ${i};}\n`;
  fs.writeFileSync(filler,c);
  const wire=path.join(dir,'wire.dylib'),plain=path.join(dir,'plain.dylib');
  const cc=(out,extra)=>{const r=spawnSync('xcrun',['clang','-dynamiclib','-O0','-fobjc-arc','-framework','Foundation','-o',out,filler,...extra],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);};
  cc(wire,['-DTIO_WIRE_LOG=1','-I',packageTestDirectory,path.join(packageTestDirectory,'WireLog.m')]);
  cc(plain,[]);
  const check=f=>spawnSync('bash',[path.join(packageTestDirectory,'../../scripts/wirelog-absent.sh'),f],{encoding:'utf8'});
  const hit=check(wire);assert.equal(hit.status,1,hit.stdout+hit.stderr);assert.match(hit.stderr,/Unexpected wire log symbol/);
  const clean=check(plain);assert.equal(clean.status,0,clean.stderr);
  const piped=spawnSync('bash',['-c','set -o pipefail; if nm "$1" | grep -q WireLog; then exit 0; else exit 1; fi','x',wire]);
  assert.equal(piped.status,1,'the piped form should miss the match here, or this test proves nothing');
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
// G1: on the download-only host TIOOTAFlashBlockCall delegates before any flag-dependent code.
test('download-only refusal comes first in TIOOTAFlashBlockCall and depends on no flag',()=>{
 const flash=fs.readFileSync(new URL('./ExperimentalOTAFlash.m',import.meta.url),'utf8');
 const body=flash.slice(flash.indexOf('BOOL TIOOTAFlashBlockCallSnapshot(id call,'));
 // C15: the full 1.0.11 host's disarmed refusal comes next, also before any flag-dependent code.
 assert.match(body,/^BOOL TIOOTAFlashBlockCallSnapshot\(id call,NSDictionary \*\*teleprompter\)\{\n    if\(teleprompter\)\*teleprompter=nil;\n    if\(TIOOTADownloadOnlyHost\(\)\)return DownloadOnlyBlock\(call,teleprompter\);\n    if\(TIOOTAArmRequired\(\)&&!ArmedForTransfer\(\)\)return DisarmedBlock\(call,teleprompter\);\n    if\(!TIOOTAFlashBuild\(\)\)return NO;/);
 assert.match(flash,/\nBOOL TIOOTAFlashBlockCall\(id call\)\{return TIOOTAFlashBlockCallSnapshot\(call,NULL\);\}\n/);
 assert.match(flash,/\nBOOL TIOOTADownloadOnlyBlockCall\(id call\)\{return DownloadOnlyBlock\(call,NULL\);\}\n/);
 const pure=flash.slice(flash.indexOf('NSString *const TIOOTADownloadOnlyGuardMarker'),flash.indexOf('// Full 1.0.11 host (ios1011, C15)'));
 assert.ok(pure.length>0);assert.doesNotMatch(pure,/#if|TIO_[A-Z_]+_ENABLED|TIO_DISPLAY_|TIOOTAFlashBuild|ScopedFileSenders/);
 assert.ok(pure.includes(packaging.DOWNLOAD_ONLY_GUARD_MARKER));
 // The disarm region compiles in every build: no preprocessor branch. Only arming and the armed
 // check read TIOOTAFlashBuild (an armed transfer needs the flash path); the business-9 refusal never does.
 const arm=flash.slice(flash.indexOf('// Full 1.0.11 host (ios1011, C15)'),flash.indexOf('BOOL TIOOTAFlashBlockCallSnapshot(id call,'));
 assert.ok(arm.includes(packaging.FULL_1011_ARM_MARKER));assert.doesNotMatch(arm,/#if|TIO_[A-Z_]+_ENABLED|TIO_DISPLAY_/);
 const disarmed=arm.slice(arm.indexOf('static BOOL DisarmedBlock('),arm.indexOf('BOOL TIOOTADisarmedBlockCall('));
 assert.ok(disarmed.length>0);assert.doesNotMatch(disarmed,/TIOOTAFlashBuild|Current\(\)|AutoUpdate/);
 // test.py builds the guard test with and without the flash/phone flags and compares the sweep.
 const py=fs.readFileSync(new URL('./test.py',import.meta.url),'utf8');
 assert.match(py,/'noflags':\(\[\],\[\],False\)/);assert.match(py,/refusal differs between flag sets/);
});
test('download-only addon gate: guard symbols and marker are required',()=>{
 const symbols=packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS.map(n=>'0000000000001000 T '+n).join('\n')+'\n';
 const addon=Buffer.concat([Buffer.alloc(16),Buffer.from(packaging.DOWNLOAD_ONLY_GUARD_MARKER+'; business 9 refused'),Buffer.alloc(16)]);
 assert.ok(packaging.validateDownloadOnlyAddon(symbols,addon));
 for(const name of packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS){
  assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols.replace(' T '+name+'\n','\n'),addon),new RegExp('download_only_guard_missing:'+name));
  assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols.replace(' T '+name+'\n',' T '+name+'X\n'),addon));
 }
 assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols,Buffer.alloc(64)),/download_only_guard_missing:marker/);
 // G4: an addon built before the businessId width check (marker 01) is refused.
 assert.match(packaging.DOWNLOAD_ONLY_GUARD_MARKER,/GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed$/);
 // D5: an addon built before the teleprompter allow-list (marker 02) is refused.
 assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols,Buffer.from('ota guard=IOS1011-DOWNLOAD-GUARD-02; flag-independent; businessId above 255 refused; business 9 refused except the empty version query')),/download_only_guard_missing:marker/);
 assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols,Buffer.from('ota guard=IOS1011-DOWNLOAD-GUARD-01; flag-independent; business 9 refused except the empty version query')),/download_only_guard_missing:marker/);
 assert.throws(()=>packaging.validateDownloadOnlyAddon(symbols,undefined),/marker/);
 const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 assert.match(s,/if\(!host\.routePatch\)validateDownloadOnlyAddon\(symbols,fs\.readFileSync\(o\.addon\)\);/);
 assert.ok(s.indexOf('validateDownloadOnlyAddon(symbols,')<s.indexOf("fs.mkdirSync(destination"));
 // The wrapper and the gate check the same names before anything is packaged.
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8'),gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 for(const name of packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS)assert.ok(wrapper.includes(name),name);
 for(const name of packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS.filter(n=>!['_TIOOTAFlashBlockCall','_TIOInstallGlassesChannelHook'].includes(n)))assert.ok(gate.includes(name),name);
 assert.ok(wrapper.includes(packaging.DOWNLOAD_ONLY_GUARD_MARKER)&&gate.includes(packaging.DOWNLOAD_ONLY_GUARD_MARKER));
 const branch=wrapper.slice(wrapper.indexOf('if [[ $host == 1011 ]]; then\n# G1/G2'),wrapper.indexOf('run_logged package node "$ED/package.mjs" --host ios1011-download'));
 assert.match(branch,/run_logged download-only-guard download_only_guard "\$ADDON"/);
});
test('real addon build carries the download-only guard',t=>{
 const addon=path.join(packageTestDirectory,'build/mapkit/TurboIOPrivateAddon.dylib');if(!fs.existsSync(addon))return t.skip('build the embedded addon first');
 assert.ok(packaging.validateDownloadOnlyAddon(runFixtureCommand('/usr/bin/nm',['-g',addon],{encoding:'utf8',maxBuffer:64*1024*1024}),fs.readFileSync(addon)));
});
// G3: the export panel reads Auto Update and never writes RayNeo's preferences.
test('export panel reads Auto Update without writing preferences',()=>{
 const src=f=>fs.readFileSync(new URL('./'+f,import.meta.url),'utf8');
 for(const f of ['FirmwareExportUI.m','DownloadOnlySafety.m']){
  const text=src(f);
  assert.doesNotMatch(text,/setObject:|setBool:|setValue:|removeObjectForKey:|synchronize|TIOOTAFlashDisableAutoUpdate/,f);
 }
 const ui=src('FirmwareExportUI.m');
 assert.match(ui,/TIOFirmwareExportSafetyModel\(TIOHostProfile\(\),TIOGlassesChannelHookInstalled\(\)&&Guarded\(\),\[TIOOTAGuardStatus\(\)\[@"transportHookReady"\] boolValue\],TIOGlassesChannelStockTrafficSeen\(\),/);
 // The guard row is green, amber or red from the model's guardLevel, refreshed while the panel is visible.
 assert.match(ui,/\[\(self\.safety\?:SafetyModel\(\)\)\[@"guardLevel"\] isEqual:@"ok"\]/);
 assert.match(ui,/\[\(self\.safety\?:SafetyModel\(\)\)\[@"guardLevel"\] isEqual:@"warn"\]/);
 assert.match(ui,/scheduledTimerWithTimeInterval:1 repeats:YES block:/);
 assert.match(ui,/name:TIOGlassesChannelStockTrafficNotification object:nil\]/);
 assert.match(ui,/if\(\[m\[@"guardLevel"\] isEqual:@"warn"\]\)return TIOText\(@"hub\.status\.firmwareExport\.waiting"\);/);
 assert.match(ui,/NSUserDefaults\.standardUserDefaults\.dictionaryRepresentation/);
 assert.match(ui,/- \(void\)viewWillAppear:\(BOOL\)animated\{\[super viewWillAppear:animated\];\[self updateSafety\];\}/);
 assert.match(ui,/if\(s==SectionStatus\)return 3;/);
 assert.match(ui,/self\.tableView\.tableHeaderView=box;/);
});
// Full 1.0.11/259 profile (ios1011, C15): the same pinned input as the download-only row,
// with the route patch at the 1.0.11 offsets, the TMG ZIP, both Info.plist markers and no
// device-model list. Flashing stays disarmed on the phone until armed there.
import {ROUTE_PROFILES,routeProfile} from './patch-route.mjs';
test('full 1.0.11 profile row: same pinned input, 1.0.11 route offsets, firmware, markers, no product',()=>{
 const f=HOST_PROFILES.ios1011,d=HOST_PROFILES['ios1011-download'];
 for(const k of ['version','build','uuid','hostError','sourceIPASHA256'])assert.equal(f[k],d[k],k);
 assert.deepEqual(f.acceptedPairs,d.acceptedPairs);assert.deepEqual(f.frameworks,d.frameworks);
 assert.equal(f.routePatch,true);assert.equal(f.routeProfile,'ios1011');assert.equal(f.firmware,true);assert.equal(f.stripStaleSignature,true);
 assert.equal(f.noProduct,true);assert.equal(f.hostProfileMarker,'ios1011');assert.equal(f.packagingRevision,'APP1011-OTA-FULL-01');
 const otaHost=fs.readFileSync(new URL('./OTAHost.h',import.meta.url),'utf8');
 assert.equal(otaHost.match(/#define TIO_OTA_1011_ROUTING_MARKER @"([^"]+)"/)[1],f.routingMarker);
 assert.match(fs.readFileSync(new URL('./HostCompatibility.h',import.meta.url),'utf8'),/#define TIO_HOST_PROFILE_1011_FULL @"ios1011"/);
 // One offset table in three places: patch-route.mjs, OTAHost.h and the download-only row's stock route records.
 const r=routeProfile('ios1011');
 assert.deepEqual([...r.offsets],d.routes.map(([,o])=>o));assert.deepEqual([...r.inputs],[d.acceptedPairs[0][1]]);
 assert.equal(r.outputSHA,'592d48d0e42869f11def2dde99a3a6960d4da7b83b99df47d228311dfc3b8ba6');assert.equal(ROUTE_PROFILES.ios107.outputSHA,null);
 for(const [name,want] of Object.entries(ROUTE_PROFILES)){const m=otaHost.match(new RegExp(`if\\(\\[profile isEqual:@"${name}"\\]\\)return @\\[@(\\d+),@(\\d+)\\];`));assert.ok(m,name);assert.deepEqual([+m[1],+m[2]],[...want.offsets]);}
 for(const bad of ['ios1011-download','IOS1011','','__proto__'])assert.throws(()=>routeProfile(bad),/Unknown route profile/);
});
test('full 1.0.11 options: firmware required, no product, exact candidate only',()=>{
 const o={...options1011,host:'ios1011',firmware:'/example/TMG9.zip'};
 validateOptions(o);validateOptions({...o,'experimental-ota':'TMG9'});
 assert.throws(()=>validateOptions({...o,firmware:undefined}),/exact_host_and_firmware_resource_required/);
 assert.throws(()=>validateOptions({...o,product:'iPhone17,1'}),/full_1011_host_takes_no_product/);
 for(const extra of [{'experimental-ota':'TMG8'},{bundle:'example.other'},{firmware:'relative/TMG9.zip'}])assert.throws(()=>validateOptions({...o,...extra}));
});
test('full 1.0.11 addon gate: both 1.0.11 guards and the arm step required',()=>{
 const names=[...packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS,...packaging.FULL_1011_ARM_SYMBOLS];
 const symbols=names.map(n=>'0000000000000000 T '+n).join('\n'),addon=Buffer.from('x\0'+packaging.DOWNLOAD_ONLY_GUARD_MARKER+'\0'+packaging.FULL_1011_ARM_MARKER+'\0');
 assert.ok(packaging.validateFull1011Addon(symbols,addon));
 for(const n of names)assert.throws(()=>packaging.validateFull1011Addon(symbols.split('\n').filter(l=>!l.endsWith(' '+n)).join('\n'),addon),/guard_missing/,n);
 assert.throws(()=>packaging.validateFull1011Addon(symbols,Buffer.from(packaging.DOWNLOAD_ONLY_GUARD_MARKER)),/full_1011_arm_guard_missing:marker/);
 assert.throws(()=>packaging.validateFull1011Addon(symbols,Buffer.from(packaging.FULL_1011_ARM_MARKER)),/download_only_guard_missing:marker/);
 // The native marker starts with the packager's string; the wrapper checks the same names and marker.
 assert.ok(fs.readFileSync(new URL('./ExperimentalOTAFlash.m',import.meta.url),'utf8').includes('TIOOTAArmGuardMarker=@"'+packaging.FULL_1011_ARM_MARKER));
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 for(const n of packaging.FULL_1011_ARM_SYMBOLS)assert.ok(wrapper.includes(n),n);assert.ok(wrapper.includes(packaging.FULL_1011_ARM_MARKER));
});
test('real addon build carries the full 1.0.11 arm guard',t=>{
 const addon=path.join(packageTestDirectory,'build/mapkit/TurboIOPrivateAddon.dylib');if(!fs.existsSync(addon))return t.skip('build the embedded addon first');
 assert.ok(packaging.validateFull1011Addon(runFixtureCommand('/usr/bin/nm',['-g',addon],{encoding:'utf8',maxBuffer:64*1024*1024}),fs.readFileSync(addon)));
});
test('packager source: the ios1011 build patches its own offsets, writes both markers and checks the pinned output',()=>{
 const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 assert.match(s,/if\(host\.name==='ios1011'\)validateFull1011Addon\(symbols,fs\.readFileSync\(o\.addon\)\);/);
 assert.ok(s.indexOf('validateFull1011Addon(symbols,')<s.indexOf('fs.mkdirSync(destination'));
 assert.match(s,/patchOTARoute\(fs\.readFileSync\(image\),host\.routeProfile\)\.output/);
 assert.match(s,/if\(host\.hostProfileMarker\)run\('plutil',\['-insert','TIOHostProfile','-string',host\.hostProfileMarker,plist\]\);/);
 assert.match(s,/run\('plutil',\['-insert','TIOExperimentalOTAQueryRouting','-string',host\.routingMarker,plist\]\);/);
 assert.match(s,/plist\.TIOHostProfile!=='ios1011'\|\|plist\.TIOExperimentalOTAQueryRouting!==host\.routingMarker\|\|plist\.TIOExperimentalOTABuild!==pins\.name\|\|plist\.UISupportedDevices!==undefined\|\|!fs\.existsSync\(path\.join\(app,CANDIDATE_RESOURCE\)\)/);
 assert.match(s,/digest\(fs\.readFileSync\(path\.join\(app,'Frameworks\/App\.framework\/App'\)\)\)!==routeProfile\('ios1011'\)\.outputSHA/);
 assert.match(s,/if\(host\.routePatch\)verifyRoute\(fs\.readFileSync\(path\.join\(app,'Frameworks\/App\.framework\/App'\)\),host\.routeProfile\);/);
});
test('real 1.0.11 input: route patch profile ios1011 gives the pinned output and nothing else',t=>{
 const p=process.env.IOS1011_TEST_APP;if(!p)return t.skip('set IOS1011_TEST_APP');
 const r=fs.readFileSync(p+'/Runner'),a=fs.readFileSync(p+'/Frameworks/App.framework/App');
 const frameworks={'RayneoNet.framework/RayneoNet':fs.readFileSync(p+'/Frameworks/RayneoNet.framework/RayneoNet'),'Flutter.framework/Flutter':fs.readFileSync(p+'/Frameworks/Flutter.framework/Flutter')};
 const plist=JSON.parse(runFixtureCommand('plutil',['-convert','json','-o','-',p+'/Info.plist'],{encoding:'utf8'}));
 validateHost(plist,r,a,'ios1011',frameworks);assert.throws(()=>validateHost({...plist,TIOHostProfile:'ios1011'},r,a,'ios1011',frameworks),/requires_original_ios1011_259/);
 const {output,report}=patch(a,'ios1011');
 assert.equal(sha256(output),routeProfile('ios1011').outputSHA);assert.equal(report.profile,'ios1011');assert.equal(report.host,'1.0.11');assert.equal(report.build,259);
 assert.deepEqual(report.changes.map(c=>c.offset),[39886000,30868352]);assert.equal(report.deviceIO,false);assert.equal(output.length,a.length);
 assert.ok(verifyRoute(output,'ios1011'));assert.throws(()=>verifyRoute(output,'ios107'));assert.throws(()=>verifyRoute(output));assert.throws(()=>verifyRoute(a,'ios1011'));
 assert.throws(()=>patch(a),/1\.0\.7\/230/);assert.throws(()=>patch(output,'ios1011'),/requires pinned 1\.0\.11\/259/);assert.throws(()=>patch(a,'ios1011-download'));
 let differing=0;for(let i=0;i<a.length;i++)if(a[i]!==output[i])differing++;assert.ok(differing>0&&differing<=report.changes.reduce((n,c)=>n+c.bytes,0));
});
test('wrappers: --host 1011-full packages the full 1.0.11 build with firmware and without product; --host 1011 unchanged',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 const branch=wrapper.slice(wrapper.indexOf('elif [[ $host == 1011-full ]]; then\n# C15'),wrapper.indexOf('\nelse\nrun_logged addon-unchanged'));
 assert.match(branch,/run_logged full-1011-guard full_1011_guard "\$ADDON"/);
 assert.match(branch,/--host ios1011 --app "\$TURBO_APP1011"/);assert.match(branch,/--firmware "\$TURBO_FIRMWARE"/);
 assert.doesNotMatch(branch,/--product|TURBO_APP107|ios1011-download/);
 assert.match(branch,/report\['hostProfile'\]=='ios1011' and report\['flashAuthorized'\] is False and report\['flashArmed'\] is False/);
 assert.match(branch,/'UISupportedDevices' not in info/);
 assert.match(wrapper,/elif \[\[ \$host == 1011-full \]\]; then required=\(TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_FIRMWARE TURBO_APP1011\)/);
 assert.match(wrapper,/if \[\[ \$host == 1011 \]\]; then required=\(TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_APP1011\)/);
 assert.match(wrapper,/\[\[ \$host != 1011-full \]\] \|\| run_logged full-1011-guard full_1011_guard "\$ADDON"/);
 assert.match(wrapper,/full_1011_guard\(\) \{\n  local symbols name\n  download_only_guard "\$1"/);
});
