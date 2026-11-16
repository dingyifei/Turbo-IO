import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {validateHost,validateOptions,validateResearchPair,entitlementsFor,locationUsageFor} from './package.mjs';
import {inspectedHost} from './host-compatibility.mjs';
import {inspectMachO,addEmbeddedLoad} from './macho-embed.mjs';
import {patch,verifyRoute} from './patch-route.mjs';
// The stock 1.0.21/1 app, the only host. The 1.0.7/230 and 1.0.11/259 identities stay here only as hosts that must be refused.
const info={CFBundleIdentifier:'com.rayneo.venus.pub',CFBundleExecutable:'Runner',CFBundleShortVersionString:'1.0.21',CFBundleVersion:'1'};
const uuid1021='74da0780dcf0384f9e841ac12f56cdf5';
const old107={info:{...info,CFBundleShortVersionString:'1.0.7',CFBundleVersion:'230'},uuid:'410defdbf93739eaacf2f616abff9d0b'};
const old1011={info:{...info,CFBundleShortVersionString:'1.0.11',CFBundleVersion:'259'},uuid:'22724c972ef9388d8e6a6e051855a555'};
const options={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-ios1021-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub',firmware:'/example/TMG12.zip','stock-firmware':'/example/stock.zip',host:'ios1021'};
test('exact version, build and UUID of the one inspected host; mismatches and old hosts rejected',()=>{
 assert.ok(inspectedHost(info,uuid1021));
 assert.equal(inspectedHost({...info,CFBundleVersion:'2'},uuid1021),null);
 assert.equal(inspectedHost(info,old1011.uuid),null);
 // An old real host (1.0.2 to 1.0.11) is unknown now, so macho-embed refuses it like any unsupported app.
 for(const old of [old107,old1011,{info:{...info,CFBundleShortVersionString:'1.0.5',CFBundleVersion:'201'},uuid:'748fd301da603095a2449bd0558faca5'}])assert.equal(inspectedHost(old.info,old.uuid),null);
});
// There is no default host: a packaging without --host, or with a removed host, is refused.
test('--host is required; the removed 1.0.7 and 1.0.11 hosts are unknown; other candidates rejected',()=>{
 const {host,...noHost}=options;
 assert.throws(()=>validateOptions(noHost),/host_required/);
 for(const removed of ['ios107','ios1011','ios1011-download','1011','107',''])assert.throws(()=>validateOptions({...options,host:removed}),/unknown_host_profile/,removed);
 for(const flag of ['TMG11','TMG9','TMG8','TMG7','TMG6','TMG5','TMG4','TMG3','TMG2','TMIG1','enabled',''])assert.throws(()=>validateOptions({...options,'experimental-ota':flag}));
 assert.throws(()=>validateOptions({...options,firmware:undefined}));
 // The release lists a stock package: its ZIP is required, as an absolute path.
 assert.throws(()=>validateOptions({...options,'stock-firmware':undefined}),/stock_firmware_resource_required/);
 assert.throws(()=>validateOptions({...options,'stock-firmware':'relative/stock.zip'}),/stock_firmware_resource_required/);
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
 for(const profile of ['ios1021','ios1021-download']){
  assert.throws(()=>validateHost({...info,TIOPackagingRevision:'private'},Buffer.alloc(32),Buffer.alloc(32),profile),/requires_original_ios1021_1/);
  assert.throws(()=>validateHost({...info,CFBundleShortVersionString:'1.0.6'},Buffer.alloc(32),Buffer.alloc(32),profile),/requires_original_ios1021_1/);
  assert.throws(()=>validateHost(info,Buffer.alloc(32),Buffer.alloc(32),profile),/thin arm64 Mach-O/); // not a pinned image
 }
 // No default profile.
 assert.throws(()=>validateHost(info,Buffer.alloc(32),Buffer.alloc(32)),/unknown_host_profile/);
});
test('phone gates require exact host, healthy source and inspected new offsets',()=>{
 const s=fs.readFileSync(new URL('./ExperimentalOTAFlash.m',import.meta.url),'utf8');
 // The full host takes the one flash gate in every build: the download-only refusal first, then the full-host
 // check, then the flash-build return for any other app, where a flash build passes only the empty version query.
 const snapshot=s.slice(s.indexOf('BOOL TIOOTAFlashBlockCallSnapshot('),s.indexOf('BOOL TIOOTAFlashAuthorize('));
 assert.ok(snapshot.indexOf('if(TIOOTADownloadOnlyHost())return DownloadOnlyBlock(')>0);
 assert.ok(snapshot.indexOf('if(TIOOTADownloadOnlyHost())return DownloadOnlyBlock(')<snapshot.indexOf('BOOL full=TIOOTAFullHost();'));
 assert.ok(snapshot.indexOf('BOOL full=TIOOTAFullHost();')<snapshot.indexOf('if(!full&&!TIOOTAFlashBuild())return NO;'));
 assert.match(snapshot,/if\(!full\)return !TIOOTAIsEmptyVersionQuery\(data\);\n\s*return !\[Current\(\) allows:data device:args\[@"deviceId"\] uptime:NSProcessInfo\.processInfo\.systemUptime\];/);
 // No per-frame host check: the exact host and its pinned image are checked once, first thing in TIOOTAFlashAuthorize.
 assert.doesNotMatch(snapshot,/TIOOTA1021HostMatches|TIOHostFullImageMatches|TIOOTAHostMatches/);
 assert.match(s,/BOOL TIOOTAFlashAuthorize\(NSError \*\*error\)\{\n[^\n]*\n(?:\s*\/\/[^\n]*\n)*\s*if\(!TIOOTA1021HostMatches\(info\)\|\|!TIOHostFullImageMatches\(TIOHostMainImage\(\),info\)\)\{Error\(error,TIOText\(@"ota\.authorize\.host"\)\);return NO;\}/);
 // No arm step, no routing marker and no raw-JSON key check remain.
 assert.doesNotMatch(s,/FlashArm|Disarm|ArmRequired|QueryRouting|ROUTING_MARKER|RawJSON/);
 assert.doesNotMatch(fs.readFileSync(new URL('./OTAHost.h',import.meta.url),'utf8'),/QueryRouting|ROUTING_MARKER|ArmHost/);
 assert.match(s,/bootstrapEligible[\s\S]*?healthPassed/);
 assert.match(fs.readFileSync(new URL('./ExperimentalOTAFeed.m',import.meta.url),'utf8'),/TIOOTAHostProfile\(bundle\.infoDictionary\)[\s\S]*?TIOHostFullImageMatches\(TIOHostMainImage\(\),bundle\.infoDictionary\)[\s\S]*?TIOOTARouteFileMatches\(file,profile\)/);
 assert.equal(fs.existsSync(new URL('./patch-ios106-route.mjs',import.meta.url)),false);
});
// The release ZIP (the gate passes the only release's checked ZIP) against that release's pins.
test('exact firmware resource, not a flash authorization',async t=>{
 const p=process.env.TIO_TEST_RELEASE_ZIP;if(!p)return t.skip('set TIO_TEST_RELEASE_ZIP');
 const {releasePins}=await import('./package.mjs');const name=releasePins().name;
 const b=fs.readFileSync(p),sym='_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap';
 validateResearchPair(sym,name,b);const bad=Buffer.from(b);bad[bad.length-1]^=1;
 assert.throws(()=>validateResearchPair(sym,name,bad));
 assert.throws(()=>validateResearchPair('',name,b));
 assert.throws(()=>validateResearchPair(sym,'TMG9',b));
});
// The stock package (the gate passes the release's checked stock ZIP): accepted only as the stock package, and the
// TMG ZIP or a changed stock ZIP is refused before bundling.
test('stock package ZIP verified before bundling; a wrong second ZIP refused',async t=>{
 const p=process.env.TIO_TEST_STOCK_ZIP;if(!p)return t.skip('set TIO_TEST_STOCK_ZIP');
 const m=await import('./package.mjs');const c21=m.releasePins();const b=fs.readFileSync(p);
 assert.ok(m.validateStockPackage(b,c21));
 const bad=Buffer.from(b);bad[bad.length-1]^=1;assert.throws(()=>m.validateStockPackage(bad,c21),/stock_firmware_identity_mismatch/);
 assert.throws(()=>m.validateStockPackage(b.subarray(1),c21),/stock_firmware_identity_mismatch/);
 assert.throws(()=>validateResearchPair('_TIOMenuLayoutController OBJC_CLASS_$_TIORoadMap',c21.name,b),/navs3_firmware_identity_mismatch/);
 const tmg=process.env.TIO_TEST_RELEASE_ZIP;if(tmg)assert.throws(()=>m.validateStockPackage(fs.readFileSync(tmg),c21),/stock_firmware_identity_mismatch/);
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

test('packaging is self-contained',()=>{
 const source=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 assert.doesNotMatch(source,/from ['"]\.\.\//);
 assert.doesNotMatch(source,/['"]\.\.\//);
 assert.ok(!source.includes('focusEdition'));
 // The wizard reads each package's ZIP from the bundle by its fixed resource name (FirmwarePins.h, phone_pins.py),
 // which is the name the packager writes it under.
 const ui=fs.readFileSync(new URL('./ExperimentalOTAUI.m',import.meta.url),'utf8');
 assert.match(ui,/NSString \*resource=package\[@"resource"\];/);assert.doesNotMatch(ui,/@"Turbo[A-Za-z]*Candidate"/);
 const pins=JSON.parse(fs.readFileSync(new URL('./firmware-pins-c21.json',import.meta.url),'utf8'));
 assert.deepEqual(pins.packages.map(e=>e.resource),[leakGuard.CANDIDATE_RESOURCE,leakGuard.STOCK_RESOURCE]);
 assert.equal(leakGuard.STOCK_RESOURCE,'TurboStockFirmware.zip');
 assert.equal([...source.matchAll(/fs\.writeFileSync\(path\.join\(app,CANDIDATE_RESOURCE\),firmware/g)].length,1);
 assert.equal([...source.matchAll(/fs\.writeFileSync\(path\.join\(app,STOCK_RESOURCE\),stockFirmware,\{flag:'wx'\}\)/g)].length,1);
 assert.ok(source.indexOf('validateStockPackage(stockFirmware,release)')<source.indexOf('fs.mkdirSync(destination'),'the stock ZIP is verified before anything is bundled');
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

// Download-only 1.0.21/1 profile (C19): stock App.framework, no route patch, no ZIP, no flash marker.
import {HOST_PROFILES,hostProfile,verifyStockApp,verifySignedStockApp} from './package.mjs';
import * as packaging from './package.mjs';
import {stripCodeSignature} from './macho-embed.mjs';
import {createHash} from 'node:crypto';
const optionsDL={app:'/example/Runner.app',addon:'/example/addon.dylib',profile:'/example/profile.mobileprovision',out:'/example/new-ios1021-download-package',identity:'A'.repeat(40),device:'TEST-DEVICE-01',bundle:'com.rayneo.venus.pub',host:'ios1021-download'};
const sha256=b=>createHash('sha256').update(b).digest('hex');
test('host profile table: the two 1.0.21 rows only; ios1021-download has no route patch and no firmware',()=>{
 assert.deepEqual(Object.keys(HOST_PROFILES).sort(),['ios1021','ios1021-download']);
 assert.throws(()=>hostProfile(),/unknown_host_profile/);
 for(const bad of ['ios107','ios1011','ios1011-download','ios1011-full','IOS1021','1021','__proto__'])assert.throws(()=>hostProfile(bad),/unknown_host_profile/,bad);
 // C19: the download-only 1.0.21/1 row keeps its own pins; no route patch, no firmware. C20 left it exactly as
 // C19 committed it (the snapshot below), and added the separate full row ios1021.
 assert.deepEqual(JSON.parse(JSON.stringify(HOST_PROFILES['ios1021-download'])),{name:'ios1021-download',version:'1.0.21',build:'1',uuid:'74da0780dcf0384f9e841ac12f56cdf5',hostError:'requires_original_ios1021_1',
  acceptedPairs:[['9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2','0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273']],
  frameworks:{'RayneoNet.framework/RayneoNet':'d8befe5f3144d21e4725bc27791c55954a210ee11e5738c197dbb1c18350bfa3','Flutter.framework/Flutter':'4c16499adee04bf904f7795f98e983b9fb593fb93b607ca7941761c2949f0e9a'},
  routes:[['/xrlauncherapi/v1/signApi/gray/upgrade',46796656],['/xrlauncherhwapi/v1/signApi/gray/upgrade',37435136]],
  sourceIPASHA256:'7cecd8847944e118c24beba8d9ae7cb5d42387047e8570feb184dca7f60b8f4a',
  routePatch:false,firmware:false,stripStaleSignature:true,runtimeMarker:'ios1021-download',packagingRevision:'APP1021-DOWNLOAD-ONLY-01'});
 const n=HOST_PROFILES['ios1021-download'];
 assert.equal(n.routeProfile,undefined);assert.equal(n.fullHost,undefined);
 // The packager pin, the JS host matrix and the native header name the same UUID.
 const nat=fs.readFileSync(new URL('./HostCompatibility.h',import.meta.url),'utf8').match(/"1\.0\.21"\]&&\[build isEqual:@"1"\]\)return @"([0-9A-F-]{36})"/);
 assert.ok(nat);assert.equal(nat[1].replaceAll('-','').toLowerCase(),n.uuid);
 const h=inspectedHost(info,n.uuid);
 assert.equal(h.profile,'ios1021-download');assert.equal(h.downloadOnly,true);assert.equal(h.staleSignature,true);
 assert.equal(inspectedHost({...info,CFBundleVersion:'2'},n.uuid),null);assert.equal(inspectedHost(old1011.info,n.uuid),null);
});
test('download-only options take no firmware, candidate flag, release or product',()=>{
 validateOptions(optionsDL);
 for(const extra of [{firmware:'/example/TMG12.zip'},{product:'iPhone17,1'},{'experimental-ota':'TMG12'},{bundle:'example.other'},{release:'c21'}])assert.throws(()=>validateOptions({...optionsDL,...extra}));
 assert.throws(()=>validateOptions({...optionsDL,host:'ios1021'}),/exact_host_and_firmware_resource_required/);
 assert.throws(()=>validateOptions({...options,host:'ios1021-download'}),/download_only_host_takes_no_firmware_or_product/);
});
test('download-only host gate rejects other versions, TIO markers and unknown bytes',()=>{
 for(const bad of [old107.info,old1011.info,{...info,CFBundleVersion:'2'},{...info,TIOHostProfile:'ios1021-download'},{...info,CFBundleIdentifier:'example.other'}])
  assert.throws(()=>validateHost(bad,Buffer.alloc(32),Buffer.alloc(32),'ios1021-download'),/requires_original_ios1021_1/);
 assert.throws(()=>validateHost(info,Buffer.alloc(32),Buffer.alloc(32),'ios1021-download'),/thin arm64 Mach-O/); // not a pinned image
 assert.throws(()=>verifyStockApp(Buffer.alloc(64),'ios1021-download'),/download_only_app_changed/);
 // The full profile patches its route records, so it is never a stock-app profile; no default profile either.
 assert.throws(()=>verifyStockApp(Buffer.alloc(64),'ios1021'),/download_only_app_changed/);assert.throws(()=>verifyStockApp(Buffer.alloc(64)),/unknown_host_profile/);
});
test('packager source keeps the download-only path free of route patch, ZIP and flash marker',()=>{
 const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 const branch=s.slice(s.indexOf('if(!host.routePatch){'),s.indexOf('}else{',s.indexOf('if(!host.routePatch){')));
 assert.ok(branch.includes('verifyStockApp('));assert.ok(branch.includes("'TIOHostProfile'"));
 for(const forbidden of ['patchOTARoute','TIOExperimentalOTAQueryRouting','TIOExperimentalOTABuild','CANDIDATE_RESOURCE','UISupportedDevices','NSAllowsLocalNetworking'])assert.ok(!branch.includes(forbidden),forbidden);
 assert.match(s,/if\(host\.routePatch\)verifyRoute\(/);assert.match(s,/else verifySignedStockApp\(/);
 assert.match(s,/host\.stripStaleSignature\?\['--strip-stale-signature'\]:\[\]/);
 // No device-model list is ever written: no host takes a product.
 assert.doesNotMatch(s,/UISupportedDevices\.0/);
});
test('real 1.0.21 input: pins, unpatched routes and deterministic signature strip',t=>{
 const p=process.env.IOS1021_TEST_APP;if(!p)return t.skip('set IOS1021_TEST_APP');
 const r=fs.readFileSync(p+'/Runner'),a=fs.readFileSync(p+'/Frameworks/App.framework/App');
 const frameworks={'RayneoNet.framework/RayneoNet':fs.readFileSync(p+'/Frameworks/RayneoNet.framework/RayneoNet'),'Flutter.framework/Flutter':fs.readFileSync(p+'/Frameworks/Flutter.framework/Flutter')};
 const plist=JSON.parse(runFixtureCommand('plutil',['-convert','json','-o','-',p+'/Info.plist'],{encoding:'utf8'}));
 validateHost(plist,r,a,'ios1021-download',frameworks);assert.ok(inspectedHost(plist,inspectMachO(r).uuid).downloadOnly);
 assert.throws(()=>validateHost(plist,r,a,'ios1021-download'),/host_framework_identity_mismatch/);
 const badNet=Buffer.from(frameworks['RayneoNet.framework/RayneoNet']);badNet[4096]^=1;assert.throws(()=>validateHost(plist,r,a,'ios1021-download',{...frameworks,'RayneoNet.framework/RayneoNet':badNet}));
 const badApp=Buffer.from(a);badApp[4096]^=1;assert.throws(()=>validateHost(plist,r,badApp,'ios1021-download',frameworks));assert.throws(()=>verifyStockApp(badApp,'ios1021-download'));
 const badRunner=Buffer.from(r);badRunner[4096]^=1;assert.throws(()=>validateHost(plist,badRunner,a,'ios1021-download',frameworks));
 assert.ok(verifyStockApp(a,'ios1021-download'));assert.throws(()=>patch(a));
 for(const [route,offset] of HOST_PROFILES['ios1021-download'].routes){const moved=Buffer.from(a);moved[offset]^=1;assert.throws(()=>verifyStockApp(moved,'ios1021-download'));}
 // Strip: deterministic, idempotent, removes exactly LC_CODE_SIGNATURE and its blob.
 const h=inspectMachO(r),one=stripCodeSignature(r),two=stripCodeSignature(r);
 assert.equal(one.stripped,true);assert.ok(one.output.equals(two.output));assert.equal(stripCodeSignature(one.output).stripped,false);
 assert.equal(sha256(one.output),'3a5f9cd1f90ffe15557a7e9ec044c9350b5e9c3754b3a52002a11116757670b4');
 const u=inspectMachO(one.output);assert.equal(u.uuid,h.uuid);assert.equal(u.count,h.count-1);assert.equal(u.encrypted,false);assert.equal(one.output.length,77280000);
 const embedded=inspectMachO(addEmbeddedLoad(one.output));assert.equal(embedded.uuid,h.uuid);assert.equal(embedded.count,h.count);
 assert.deepEqual(embedded.dependencies.filter(x=>!inspectMachO(r).dependencies.includes(x)),['@executable_path/Frameworks/TurboIOPrivateAddon.dylib']);
 assert.equal(sha256(r),HOST_PROFILES['ios1021-download'].acceptedPairs[0][0]); // input untouched
 // After signing only the signature may differ: same stripped bytes, same route records.
 assert.ok(verifySignedStockApp(a,a,'ios1021-download'));assert.throws(()=>verifySignedStockApp(badApp,a,'ios1021-download'));
 // Simulated re-sign (no codesign): replace the signature blob with one of another size,
 // as codesign_allocate lays it out. A smaller blob keeps __LINKEDIT vmsize, a larger one grows it.
 const layout=b=>{let p=32,sig,link;for(let i=0;i<b.readUInt32LE(16);i++){const c=b.readUInt32LE(p);if(c===0x1d)sig=p;if(c===0x19&&b.toString('latin1',p+8,p+24).startsWith('__LINKEDIT'))link=p;p+=b.readUInt32LE(p+4);}return {sig,link};};
 const resign=(b,size,vmsize)=>{const {sig,link}=layout(b),dataoff=b.readUInt32LE(sig+8),out=Buffer.concat([b.subarray(0,dataoff),Buffer.alloc(size,0xfa)]);
  out.writeUInt32LE(size,sig+12);const filesize=BigInt(out.length)-out.readBigUInt64LE(link+40);out.writeBigUInt64LE(filesize,link+48);
  out.writeBigUInt64LE(vmsize??((filesize+0x3fffn)&~0x3fffn),link+32);return out;};
 const keepVm=b=>b.readBigUInt64LE(layout(b).link+32);
 // The stock 1.0.21 App's own blob is 1404576 bytes, so 1700000 is past its __LINKEDIT slack.
 const smaller=resign(a,400000,keepVm(a)),larger=resign(a,1700000);
 assert.notEqual(keepVm(larger),keepVm(a));
 assert.ok(verifySignedStockApp(smaller,a,'ios1021-download'));assert.ok(verifySignedStockApp(larger,a,'ios1021-download'));
 const flipped=Buffer.from(larger);flipped[4096]^=1;assert.throws(()=>verifySignedStockApp(flipped,a,'ios1021-download'),/changed_after_signing/);
 assert.throws(()=>verifySignedStockApp(resign(a,1700000,keepVm(a)),a,'ios1021-download'),/changed_after_signing/); // vmsize below filesize
});
test('real 1.0.21 input: unsigned preparation leaves App.framework byte-identical to stock',t=>{
 const p=process.env.IOS1021_TEST_APP,addon=path.join(packageTestDirectory,'build/mapkit/TurboIOPrivateAddon.dylib');
 if(!p)return t.skip('set IOS1021_TEST_APP');if(!fs.existsSync(addon))return t.skip('build the embedded addon first');
 const root=fs.mkdtempSync(path.join(packageTestDirectory,'build','h1021-prepare-'));
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
  assert.equal(sha256(app),'0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273');assert.ok(verifyStockApp(app,'ios1021-download'));
  assert.equal(fs.existsSync(path.join(out,'_CodeSignature')),false);assert.ok(fs.existsSync(path.join(src,'_CodeSignature/CodeResources')));
  const runner=fs.readFileSync(path.join(out,'Runner')),report=JSON.parse(fs.readFileSync(path.join(out,'TurboIOPrivatePreparation.json'),'utf8'));
  assert.equal(stripCodeSignature(runner).stripped,false);assert.equal(inspectMachO(runner).uuid,uuid1021);
  assert.equal(report.hostImage,'1.0.21/1');assert.equal(report.hostProfile,undefined);assert.equal(report.staleSignatureRemoved,true);
  assert.equal(report.originalExecutableSHA256,'9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2');
  assert.equal(report.unsignedExecutableSHA256,'3a5f9cd1f90ffe15557a7e9ec044c9350b5e9c3754b3a52002a11116757670b4');
  assert.equal(report.preparedExecutableSHA256,sha256(runner));
  const plist=plistJSON(path.join(out,'Info.plist'));
  for(const k of ['TIOExperimentalOTAQueryRouting','TIOExperimentalOTABuild','UISupportedDevices','TIOHostProfile'])assert.equal(plist[k],undefined,k);
  assert.equal(fs.existsSync(path.join(out,leakGuard.CANDIDATE_RESOURCE)),false);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('wrappers: --host is required and is 1021 or 1021-full; --host 1021 packages without firmware or product; the gate has no 1.0.11 stage',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 assert.match(wrapper,/\nhost=''\n/);
 assert.match(wrapper,/\[\[ -n \$host \]\] \|\| \{ echo 'PACKAGE FAIL: --host is required[^\n]*exit 2; \}/);
 assert.match(wrapper,/1021\|1021-full\) host=\$2; shift 2 ;;/);
 assert.match(wrapper,/107\|1011\|1011-full\) printf 'PACKAGE FAIL: --host %s is no longer supported[^\n]*exit 2 ;;/);
 const branch=wrapper.slice(wrapper.indexOf('if [[ $host == 1021 ]]; then\npkg_host'),wrapper.indexOf('\nelse\n# The full 1.0.21 host'));
 assert.ok(branch.length>0);
 assert.match(branch,/pkg_host=ios1021-download; pkg_app=\$TURBO_APP1021/);
 assert.match(branch,/--host "\$pkg_host" --app "\$pkg_app"/);
 assert.doesNotMatch(branch,/--firmware|--product|TURBO_APP107|TURBO_APP1011/);
 assert.match(branch,/report\['hostProfile'\]=='ios1021-download'/);
 assert.match(wrapper,/\nunset TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_APP1021\n/);
 assert.match(wrapper,/\nrequired=\(TURBO_PROFILE TURBO_SIGN_ID TURBO_DEVICE TURBO_APP1021\)\n/);
 // The 1.0.7 and 1.0.11 inputs are never read.
 assert.doesNotMatch(wrapper,/TURBO_APP107|TURBO_PATCHED_APP|TURBO_APP1011|TURBO_PRODUCT|TURBO_FIRMWARE/);
 const gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 assert.doesNotMatch(gate,/host1011|TURBO_APP107|TURBO_PATCHED_APP|TURBO_APP1011|TURBO_PRODUCT|TURBO_FIRMWARE|IOS107_TEST|IOS1011_TEST|--app107|--patched-app|--app1011/);
 // One test stage: the full test.py run for the first release (C21), the release groups alone for any other; the
 // real 1.0.21 app is required there, in the node tests and in the 1.0.21 package stage.
 assert.match(gate,/stage test test_stage\n    stage package-test package_test_stage\n    stage host1021 host1021_stage\n/);assert.doesNotMatch(gate,/release_stage|--host 1011-full/);
 for(const fn of ['test_stage','package_test_stage','host1021_stage']){const body=gate.slice(gate.indexOf(fn+'() {'),gate.indexOf('\n}\n',gate.indexOf(fn+'() {')));assert.match(body,/^[^\n]*\n  require_app1021\n/,fn);}
 assert.match(gate,/IOS1021_TEST_APP="\$TURBO_APP1021" node --test package\.test\.mjs/);
});
// The full host's export panel model is pure and tested (DownloadOnlySafetyTests); pin the UI's call so
// the guard row's green still needs the installed hook and a stock call seen in this launch.
test('full host: the export panel passes the hook state and stock traffic to the guard row model',()=>{
 const ui=fs.readFileSync(new URL('./FirmwareExportUI.m',import.meta.url),'utf8');
 const model=ui.slice(ui.indexOf('static NSDictionary *SafetyModel(void){'),ui.indexOf('NSString *TIOFirmwareExportHubStatus(void){'));
 const full=model.slice(model.indexOf('if([TIOHostProfile() isEqual:TIO_HOST_PROFILE_1021_FULL]){'),model.indexOf('\n    }\n'));
 assert.ok(model.indexOf('if([TIOHostProfile() isEqual:TIO_HOST_PROFILE_1021_FULL]){')>0);
 assert.equal([...model.matchAll(/TIOFirmwareExportSafetyModelFull\(/g)].length,1);
 assert.match(full,/return TIOFirmwareExportSafetyModelFull\(TIOGlassesChannelHookInstalled\(\)&&\[TIOOTAGuardStatus\(\)\[@"transportHookReady"\] boolValue\]&&TIOOTAFullHost\(\),\s*TIOGlassesChannelStockTrafficSeen\(\),\[TIOOTAFlashStatus\(\)\[@"authorized"\] boolValue\],NSUserDefaults\.standardUserDefaults\.dictionaryRepresentation\);/);
 assert.match(fs.readFileSync(new URL('./DownloadOnlySafety.h',import.meta.url),'utf8'),/TIOFirmwareExportSafetyModelFull\(BOOL gateReady, BOOL stockTrafficSeen, BOOL authorized, NSDictionary \*_Nullable preferences\);/);
});
// The full host's flash gate lives in the same rayneonet hook. Load must install it
// on the full host, not only when the voice/AlwaysOn signatures match, and the
// install must be idempotent (the valid path may already have installed it).
test('full host: Load installs the gate hook on the full host',()=>{
 const src=f=>fs.readFileSync(new URL('./'+f,import.meta.url),'utf8');
 const addon=src('Addon.m'),load=addon.slice(addon.indexOf('static void Load(void)'));
 const valid=load.indexOf('if(valid){TIOInstallGlassesChannelHook();TIOInstallTodoRuntime();}');
 const full=load.indexOf('\n            if(TIOOTAFullHost())TIOInstallGlassesChannelHook();\n');
 assert.ok(valid>0&&full>valid,'full-host hook install missing or before the feature hooks');
 // Unconditional on the feature checks: the line is not part of an if/else chain on valid.
 const between=load.slice(valid,full);assert.doesNotMatch(between.split('\n').slice(-1)[0],/else/);
 assert.ok(full<load.indexOf('TCCameraReportLoaded();'),'the hook must be installed before setup reports loaded');
 assert.match(load,/if\(TIOOTAFullHost\(\)\)\[loadInfo appendFormat:@"fullHost=1\\n%@\\n",TIOOTAFullHostGuardMarker\];/);
 assert.match(load,/if\(TIOOTAFullHost\(\)&&!TIOGlassesChannelHookInstalled\(\)\)\[loadInfo appendFormat:@"FLASH GATE NOT ACTIVE:/);
 const hook=src('GlassesChannelHook.m');
 assert.match(hook,/BOOL TIOInstallGlassesChannelHook\(void\)\{if\(Installed\)return YES;/);
 assert.match(hook,/Installed=YES;InstallFailure=nil;TIOOTARecordTransportHookReady\(\);/);
});
// The download-only guard depends on Load() installing the rayneonet hook on the
// download-only host; no host test links Addon.m, so pin the source shape here.
test('download-only host: Load installs only the guard hook and sends nothing on its own',()=>{
 const src=f=>fs.readFileSync(new URL('./'+f,import.meta.url),'utf8');
 const addon=src('Addon.m'),load=addon.slice(addon.indexOf('static void Load(void)'));
 assert.match(load,/BOOL downloadOnly=\[TIOHostProfile\(\) isEqual:@"ios1021-download"\];/);
 // The profile uses the refusal's own host test (image OR packager marker) before the image-only
 // lookup, so Load installs the hook and the hub hides the full catalog whenever the refusal applies.
 const profile=addon.match(/NSString \*TIOHostProfile\(void\) \{([\s\S]*?)\n\}/);assert.ok(profile);
 assert.ok(profile[1].indexOf('if(TIOOTADownloadOnlyHost())return @"ios1021-download";')>0);
 assert.ok(profile[1].indexOf('if(TIOOTADownloadOnlyHost())')<profile[1].indexOf('TIOHostProfileFor(MainImage()'));
 assert.match(load,/HOST PROFILE MISMATCH: image=%@; marker=%@; treated as download-only/);
 assert.match(load,/if\(valid\)\{TIOInstallGlassesChannelHook\(\);TIOInstallTodoRuntime\(\);\}\n(?:\s*\/\/[^\n]*\n)*\s*else if\(downloadOnly\)TIOInstallGlassesChannelHook\(\);/);
 assert.equal([...addon.matchAll(/TIOInstallGlassesChannelHook\(\)/g)].length,3);
 // No addon-originated glasses frames on the download-only host.
 assert.equal([...addon.matchAll(/TIOLanguageFlagStart\(\)/g)].length,1);assert.match(load,/if\(!downloadOnly\)TIOLanguageFlagStart\(\);/);
 assert.equal([...addon.matchAll(/TIOClenchLabInstallRecovery\(\)/g)].length,1);assert.match(load,/if\(!downloadOnly\)TIOClenchLabInstallRecovery\(\);/);
 // The guard row is green only when every part of the safety net is present. The
 // refusal is flag-independent (G1), so the predicate no longer asks for TIOOTAFlashBuild().
 const guard=addon.match(/BOOL TIOHostDownloadOnlyGuardActive\(void\) \{([\s\S]*?)\n\}/);assert.ok(guard);
 for(const part of ['TIODownloadOnlyGuardActiveFor(TIOHostProfile(),TIOGlassesChannelHookInstalled(),[TIOOTAGuardStatus()[@"transportHookReady"] boolValue])','TIOOTADownloadOnlyHost()'])assert.ok(guard[1].includes(part),part);
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
 const guardDL=pos('run_logged download-only-guard download_only_guard "$ADDON"\n# Download-only');
 const copy=pos('cp -p "$ADDON" "$LOG_DIR/addon/TurboIOPrivateAddon.dylib"\nADDON=$LOG_DIR/addon/TurboIOPrivateAddon.dylib');
 assert.ok(sourced<scrub&&scrub<remove&&remove<build&&build<built&&built<check&&check<copy&&copy<buildOnly&&buildOnly<sign&&sign<guardDL);
 // The signed dylib is the checked copy: its SHA-256 is checked again right before each package.mjs run.
 // Two package runs: download-only and full, both 1.0.21.
 assert.equal([...wrapper.matchAll(/run_logged addon-unchanged addon_unchanged\nrun_logged package node "\$ED\/package\.mjs"/g)].length,2);
 assert.equal([...wrapper.matchAll(/run_logged package node/g)].length,2);
 assert.ok(wrapper.includes("addon_sha=$(tail -n 1 \"$LOG_DIR/addon-check.log\")"));
 // The fresh build is not inside a host branch: it runs for both hosts alike.
 assert.ok(build<wrapper.indexOf('if [[ $host == 1021 ]]; then\n  [[ -f "$TURBO_PROFILE"'));
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
 // Next the full host's gate, chosen before any flag-dependent code: nothing above the full-host branch reads a build flag.
 const head=body.slice(0,body.indexOf('    if(!full&&!TIOOTAFlashBuild())return NO;')).replace(/\n\s*\/\/[^\n]*/g,'');
 assert.equal(head,'BOOL TIOOTAFlashBlockCallSnapshot(id call,NSDictionary **teleprompter){\n    if(teleprompter)*teleprompter=nil;\n    if(TIOOTADownloadOnlyHost())return DownloadOnlyBlock(call,teleprompter);\n    BOOL full=TIOOTAFullHost();\n');
 for(const f of ['static void ObserveDisconnect(','static BOOL Business9Call(','BOOL TIOOTAFullHost(void){']){const fn=flash.slice(flash.indexOf(f),flash.indexOf('\n}\n',flash.indexOf(f)));assert.ok(fn.length>0,f);assert.doesNotMatch(fn,/#if|TIO_[A-Z_]+_ENABLED|TIO_DISPLAY_|TIOOTAFlashBuild/);}
 assert.match(flash,/\nBOOL TIOOTAFlashBlockCall\(id call\)\{return TIOOTAFlashBlockCallSnapshot\(call,NULL\);\}\n/);
 assert.match(flash,/\nBOOL TIOOTADownloadOnlyBlockCall\(id call\)\{return DownloadOnlyBlock\(call,NULL\);\}\n/);
 const pure=flash.slice(flash.indexOf('NSString *const TIOOTADownloadOnlyGuardMarker'),flash.indexOf('// Full 1.0.21 host (profile ios1021)'));
 assert.ok(pure.length>0);assert.doesNotMatch(pure,/#if|TIO_[A-Z_]+_ENABLED|TIO_DISPLAY_|TIOOTAFlashBuild|ScopedFileSenders/);
 assert.ok(pure.includes(packaging.DOWNLOAD_ONLY_GUARD_MARKER));
 // The full-host region compiles in every build: no preprocessor branch, and it carries the packager's marker.
 const fullRegion=flash.slice(flash.indexOf('NSString *const TIOOTAFullHostGuardMarker'),flash.indexOf('BOOL TIOOTAFlashBlockCallSnapshot(id call,'));
 assert.ok(fullRegion.includes('TIOOTAFullHostGuardMarker=@"'+packaging.FULL_HOST_GUARD_MARKER+'"'));assert.doesNotMatch(fullRegion,/#if|TIO_[A-Z_]+_ENABLED|TIO_DISPLAY_/);
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
 const branch=wrapper.slice(wrapper.indexOf('if [[ $host == 1021 ]]; then\npkg_host'),wrapper.indexOf('run_logged package node "$ED/package.mjs" --host "$pkg_host"'));
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
import {ROUTE_PROFILES,routeProfile} from './patch-route.mjs';
// The full host gate check (validateFull1021Addon): the download-only guard and the flag-independent full-host gate
// (its marker and the functions it names) are both required, in the packager and in the wrapper.
test('full host gate check: the download-only guard and the full-host gate are required',()=>{
 const names=[...packaging.DOWNLOAD_ONLY_GUARD_SYMBOLS,...packaging.FULL_HOST_GUARD_SYMBOLS];
 const symbols=names.map(n=>'0000000000000000 T '+n).join('\n'),addon=Buffer.from('x\0'+packaging.DOWNLOAD_ONLY_GUARD_MARKER+'\0'+packaging.FULL_HOST_GUARD_MARKER+'\0');
 assert.ok(packaging.validateFull1021Addon(symbols,addon));assert.ok(packaging.validateFullHostAddon('ios1021',symbols,addon));
 for(const n of names)assert.throws(()=>packaging.validateFull1021Addon(symbols.split('\n').filter(l=>!l.endsWith(' '+n)).join('\n'),addon),/guard_missing/,n);
 assert.throws(()=>packaging.validateFull1021Addon(symbols,Buffer.from(packaging.DOWNLOAD_ONLY_GUARD_MARKER)),/full_host_guard_missing:marker/);
 assert.throws(()=>packaging.validateFull1021Addon(symbols,Buffer.from(packaging.FULL_HOST_GUARD_MARKER)),/download_only_guard_missing:marker/);
 // An addon from C20 (the arm markers, no full-host gate marker) is refused.
 const c20=Buffer.from('x\0'+packaging.DOWNLOAD_ONLY_GUARD_MARKER+'\0ota guard=FULL-DISARM-01; flag-independent\0ota guard=FULL1021-ARM-01\0');
 assert.throws(()=>packaging.validateFull1021Addon(symbols,c20),/full_host_guard_missing:marker/);
 for(const h of ['ios107','ios1011','ios1011-download','ios1021-download','IOS1021','',undefined])assert.throws(()=>packaging.validateFullHostAddon(h,symbols,addon),/not_a_full_host/);
 assert.equal(packaging.FULL_1011_ARM_SYMBOLS,undefined);assert.equal(packaging.FULL_1021_ARM_SYMBOLS,undefined);assert.equal(packaging.validateFull1011Addon,undefined);
 // The native marker is the packager's string; the wrapper and the gate check the same names and marker.
 assert.ok(fs.readFileSync(new URL('./ExperimentalOTAFlash.m',import.meta.url),'utf8').includes('TIOOTAFullHostGuardMarker=@"'+packaging.FULL_HOST_GUARD_MARKER+'"'));
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8'),gate=fs.readFileSync(new URL('../../scripts/turbo-gate.sh',import.meta.url),'utf8');
 for(const n of packaging.FULL_HOST_GUARD_SYMBOLS){assert.ok(wrapper.includes(n),n);assert.ok(gate.includes(n),n);}
 assert.ok(wrapper.includes(packaging.FULL_HOST_GUARD_MARKER)&&gate.includes(packaging.FULL_HOST_GUARD_MARKER));
 assert.doesNotMatch(wrapper,/ARM-0|DISARM|full_1011_guard|_TIOOTAFlashArm|_TIOOTAArm/);assert.doesNotMatch(gate,/ARM-0|DISARM|_TIOOTAFlashArm|_TIOOTAArm|_TIOExperimentalOTAMemberCount/);
});
test('packager source: the full host build patches its own offsets, writes its profile marker and checks its pinned output',()=>{
 const s=fs.readFileSync(new URL('./package.mjs',import.meta.url),'utf8');
 assert.match(s,/if\(host\.fullHost\)validateFullHostAddon\(host\.name,symbols,fs\.readFileSync\(o\.addon\)\);/);
 assert.ok(s.indexOf('validateFullHostAddon(host.name,symbols,')<s.indexOf('fs.mkdirSync(destination'));
 assert.deepEqual(Object.values(HOST_PROFILES).filter(h=>h.fullHost).map(h=>[h.name,h.fullHost]),[['ios1021','1021-full']]);
 // Every row is either the route-patched full host or the stock download-only host.
 for(const h of Object.values(HOST_PROFILES))assert.equal(!!h.fullHost,h.routePatch===true,h.name);
 assert.match(s,/patchOTARoute\(fs\.readFileSync\(image\),host\.routeProfile\)\.output/);
 assert.match(s,/if\(host\.hostProfileMarker\)run\('plutil',\['-insert','TIOHostProfile','-string',host\.hostProfileMarker,plist\]\);/);
 assert.doesNotMatch(s,/TIOExperimentalOTAQueryRouting|routingMarker|flashArmed|captureBeforeArming/);
 assert.match(s,/wireLogCapture:`Capture a wire log during every flash\./);
 assert.match(s,/plist\.TIOHostProfile!==host\.hostProfileMarker\|\|plist\.TIOExperimentalOTABuild!==release\.name\|\|plist\.UISupportedDevices!==undefined\|\|!fs\.existsSync\(path\.join\(app,CANDIDATE_RESOURCE\)\)/);
 assert.match(s,/if\(!routeProfile\(host\.routeProfile\)\.outputSHA\|\|digest\(fs\.readFileSync\(path\.join\(app,'Frameworks\/App\.framework\/App'\)\)\)!==routeProfile\(host\.routeProfile\)\.outputSHA\)throw Error\(tag\+'_route_output_mismatch'\)/);
 assert.match(s,/if\(host\.routePatch\)verifyRoute\(fs\.readFileSync\(path\.join\(app,'Frameworks\/App\.framework\/App'\)\),host\.routeProfile\);/);
});
test('wrappers: --host 1021-full packages the full build with the release ZIP and without product',()=>{
 const wrapper=fs.readFileSync(new URL('../../scripts/turbo-package.sh',import.meta.url),'utf8');
 const branch=wrapper.slice(wrapper.indexOf('\nelse\n# The full 1.0.21 host'),wrapper.indexOf('\nfi\nactive=timings'));
 assert.ok(branch.length>0);
 assert.match(branch,/full_profile=ios1021\n/);
 assert.match(branch,/run_logged full-1021-guard full_1021_guard "\$ADDON"/);
 assert.match(branch,/--host "\$full_profile" --app "\$TURBO_APP1021"/);assert.match(branch,/--firmware "\$firmware" --release "\$release"/);
 assert.match(branch,/assert profile=='ios1021', 'unknown full host profile'\n/);assert.doesNotMatch(branch,/routing/);
 // Without --release the build is the only release in releases.json (several: --release required). The full host
 // takes the release's checked ZIP from releases.json, only when releases.json lists that host for the release; the
 // download-only host refuses an explicit --release.
 assert.match(wrapper,/firmware=''\n/);assert.doesNotMatch(wrapper,/release_built_for default|release:-default|'firmware-pins\.json'/);
 assert.match(wrapper,/if len\(names\)!=1: sys\.exit\("several releases in releases\.json: pass --release cN"\)/);
 assert.match(wrapper,/if \[\[ \$host == 1021 \]\]; then\n  \[\[ -z \$explicit_release \]\] \|\| \{ echo 'PACKAGE FAIL: --release needs --host 1021-full[^\n]*exit 2; \}\nelse\n  release_built_for "\$release" "\$host" \|\| \{[^\n]*exit 2; \}\n  firmware=\$\(python3 -I "\$REPO\/firmware\/tools\/phone_pins\.py" --resolve "\$release" --inputs "\$TURBO_INPUTS"\)/);
 assert.match(wrapper,/sys\.argv\[3\] in r\["hosts"\]/);
 assert.match(wrapper,/\[\[ \$host != 1021-full \]\] \|\| run_logged full-1021-guard full_1021_guard "\$ADDON"/);
 assert.match(wrapper,/\[\[ \$host != 1021 \]\] \|\| run_logged download-only-guard download_only_guard "\$ADDON"/);
 assert.match(wrapper,/full_1021_guard\(\) \{\n  local symbols name\n  download_only_guard "\$1" \|\| return 1\n/);
 for(const n of packaging.FULL_HOST_GUARD_SYMBOLS)assert.ok(wrapper.includes(n),n);assert.ok(wrapper.includes(packaging.FULL_HOST_GUARD_MARKER));
 assert.match(wrapper,/\nbuild_flags\+=\(TIO_RELEASE="\$release"\)\n/);
 assert.match(branch,/'firmware-pins-'\+sys\.argv\[2\]\+'\.json'/);
 assert.match(branch,/report\['release'\]==sys\.argv\[2\]/);
 assert.match(branch,/ipa\.read\('Payload\/Runner\.app\/TurboWeReadCandidate\.zip'\)/);assert.match(branch,/bundled ZIP in the signed IPA is not the release ZIP/);
 assert.doesNotMatch(branch,/--product|TURBO_APP107|TURBO_APP1011|ios1011'|ios1011-download|ios1021-download/);
 assert.match(branch,/report\['hostProfile'\]==profile and report\['flashAuthorized'\] is False, 'unexpected host profile or flash authorization'/);
 assert.match(branch,/info\.get\('TIOHostProfile'\)==profile/);
 assert.match(branch,/'UISupportedDevices' not in info/);
});

// Release configurations (releases.json, firmware/tools/phone_pins.py): C21 (TMG12 on stock 1.0.6.11, for the full
// 1.0.21 host) is the only release, and a build that names no release is C21.
test('releases: the only release C21, its pins, the addon release marker and the full-host-only --release',async()=>{
 const m=await import('./package.mjs');
 assert.deepEqual(m.releaseNames(),Object.keys(JSON.parse(fs.readFileSync(new URL('./releases.json',import.meta.url),'utf8')).releases));assert.deepEqual(m.releaseNames(),['c21']);
 assert.equal(m.soleRelease(),'c21');
 const c21=m.releasePins('c21');assert.deepEqual(m.releasePins(),c21);
 assert.equal(c21.release,'c21');assert.equal(c21.name,'TMG12');assert.equal(c21.zipSHA256,'3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373');assert.equal(c21.zipBytes,9549211);
 assert.equal(c21.otaVersion,'Strix OS 1.0.6.11');assert.equal(c21.folder,'Strix_OS_1.0.6.11');assert.equal(c21.stockBase,'1.0.6.11');
 assert.deepEqual(c21.acceptOsVersions,['Strix OS 1.0.5.12','Strix OS 1.0.6.11']);assert.deepEqual(c21.acceptQueryCodes,['01.00.05.0012','01.00.06.0011']);
 assert.equal(c21.feedVersionName,'0100060011');assert.equal(c21.feedVersionCode,100060011);
 // No firmware-pins.json any more, and no pins file for a removed release.
 for(const f of ['firmware-pins.json','firmware-pins-c16.json','firmware-pins-c17.json','firmware-pins-c18.json','firmware-pins-c20.json'])assert.equal(fs.existsSync(new URL('./'+f,import.meta.url)),false,f);
 for(const bad of ['c99','c20','C21','default','default ','../c21','',null,1])assert.throws(()=>m.releasePins(bad),/unknown_release/);
 // Two packages: TMG12 (the default) and stock 1.0.6.11, each with its resource name; the marker lists both.
 assert.deepEqual(m.releasePackages(c21).map(e=>[e.name,e.kind,e.resource,e.zipBytes,e.zipSHA256]),[
  ['TMG12','TMG','TurboWeReadCandidate.zip',9549211,'3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373'],
  ['STOCK-1.0.6.11','STOCK','TurboStockFirmware.zip',9447267,'5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e']]);
 for(const broken of [{...c21,packages:[]},{...c21,packages:[c21.packages[1],c21.packages[0]]},{...c21,packages:[{...c21.packages[0],zipSHA256:'0'.repeat(64)},c21.packages[1]]},{...c21,packages:[c21.packages[0],{...c21.packages[1],resource:'TurboWeReadCandidate.zip'}]},{...c21,packages:[c21.packages[0],{...c21.packages[1],name:'STOCK-1.0.5.12'}]}])assert.throws(()=>m.releasePackages(broken),/release_packages_invalid/);
 const tail='Strix OS 1.0.5.12, Strix OS 1.0.6.11; target Strix OS 1.0.6.11';
 const addon=r=>Buffer.from('x\0'+m.releaseMarker(r)+tail+m.packageMarker(c21.packages[1])+tail+'\0y');
 assert.ok(m.validateReleaseAddon(addon(c21),c21));
 assert.throws(()=>m.validateReleaseAddon(Buffer.from('x\0'+m.releaseMarker(c21)+tail+'\0y'),c21),/addon_release_mismatch/);
 assert.throws(()=>m.validateReleaseAddon(Buffer.from('x\0'+m.releaseMarker(c21)+tail+m.packageMarker({...c21.packages[1],zipSHA256:'0'.repeat(64)})+tail+'\0y'),c21),/addon_release_mismatch/);
 const other={...c21,release:'c22'};
 assert.throws(()=>m.validateReleaseAddon(addon(other),c21),/addon_release_mismatch/);
 assert.throws(()=>m.validateReleaseAddon(addon({...c21,zipSHA256:'0'.repeat(64)}),c21),/addon_release_mismatch/);
 assert.throws(()=>m.validateReleaseAddon(Buffer.from('ota release=c20; firmware=TMG12; zip='+c21.zipSHA256),c21),/addon_release_mismatch/);
 assert.throws(()=>m.validateResearchPair(['_TIOMenuLayoutController','OBJC_CLASS_$_TIORoadMap'].join(' '),'TMG12',Buffer.alloc(c21.zipBytes),c21),/navs3_firmware_identity_mismatch/);
 const base={app:'/a/Runner.app',addon:'/a/x.dylib',profile:'/a/p',out:'/a/new-out-'+Date.now(),identity:'a'.repeat(40),device:'device-1234',bundle:'com.rayneo.venus.pub',firmware:'/a/f.zip','stock-firmware':'/a/s.zip'};
 assert.throws(()=>m.validateOptions({...base,release:'c21'}),/host_required/);
 assert.throws(()=>m.validateOptions({...base,host:'ios1021-download',firmware:undefined,release:'c21'}),/release_requires_full_host/);
 assert.throws(()=>m.validateOptions({...base,host:'ios1021-download',firmware:undefined,'stock-firmware':'/a/s.zip'}),/download_only_host_takes_no_firmware_or_product/);
 m.validateOptions({...base,host:'ios1021',release:'c21'});m.validateOptions({...base,host:'ios1021'});
 assert.throws(()=>m.validateOptions({...base,host:'ios1021',release:'c99'}),/unknown_release/);
});

// C20: the full 1.0.21/1 host (ios1021). The same pinned input as the download-only C19 row, the route patch at the
// 1.0.21 offsets with a pinned output, its own markers, and only a release whose releases.json hosts list 1021-full.
test('full 1.0.21 profile: the C19 pins, its own route profile and markers, and a release built for it',async()=>{
 const f=HOST_PROFILES.ios1021,d=HOST_PROFILES['ios1021-download'];
 for(const k of ['version','build','uuid','hostError','sourceIPASHA256'])assert.equal(f[k],d[k],k);
 assert.deepEqual(f.acceptedPairs,d.acceptedPairs);assert.deepEqual(f.frameworks,d.frameworks);
 assert.equal(f.routePatch,true);assert.equal(f.routeProfile,'ios1021');assert.equal(f.firmware,true);assert.equal(f.stripStaleSignature,true);assert.equal(f.noProduct,true);
 assert.equal(f.hostProfileMarker,'ios1021');assert.equal(f.packagingRevision,'APP1021-OTA-FULL-01');assert.equal(f.fullHost,'1021-full');assert.equal(f.runtimeMarker,undefined);
 const otaHost=fs.readFileSync(new URL('./OTAHost.h',import.meta.url),'utf8');
 assert.equal(f.routingMarker,undefined);assert.doesNotMatch(otaHost,/ROUTING_MARKER/);
 assert.match(fs.readFileSync(new URL('./HostCompatibility.h',import.meta.url),'utf8'),/#define TIO_HOST_PROFILE_1021_FULL @"ios1021"/);
 const r=routeProfile('ios1021');
 assert.deepEqual([...r.offsets],d.routes.map(([,o])=>o));assert.deepEqual([...r.inputs],[d.acceptedPairs[0][1]]);
 assert.equal(r.outputSHA,'cd8be91e82bdbc1c98b5dda4fa0d358b91a2187ea4571200760fac0c53cb7852');assert.equal(r.host,'1.0.21');assert.equal(r.build,1);
 // One route profile, ios1021, and one offset table in three places: patch-route.mjs, OTAHost.h and the download-only row.
 assert.deepEqual(Object.keys(ROUTE_PROFILES),['ios1021']);
 for(const [name,want] of Object.entries(ROUTE_PROFILES)){const m=otaHost.match(new RegExp(`if\\(\\[profile isEqual:@"${name}"\\]\\)return @\\[@(\\d+),@(\\d+)\\];`));assert.ok(m,name);assert.deepEqual([+m[1],+m[2]],[...want.offsets]);}
 for(const bad of ['ios107','ios1011','ios1021-download','IOS1021','','__proto__',undefined])assert.throws(()=>routeProfile(bad),/Unknown route profile/,String(bad));
 // Releases: every release lists 1021-full only. It is accepted on ios1021 (named, or as the only release when none is
 // named) and refused on the download-only host.
 const m=await import('./package.mjs');
 assert.deepEqual(m.RELEASE_HOST_NAMES,{ios1021:'1021-full'});
 assert.deepEqual(m.releaseHosts(),['1021-full']);assert.deepEqual(m.releaseHosts('c21'),['1021-full']);
 for(const bad of ['c99','c20','__proto__','',' default','default'])assert.throws(()=>m.releaseHosts(bad),/unknown_release/);
 const base={app:'/a/Runner.app',addon:'/a/x.dylib',profile:'/a/p',out:'/a/new-out-1021-'+Date.now(),identity:'a'.repeat(40),device:'device-1234',bundle:'com.rayneo.venus.pub',firmware:'/a/f.zip','stock-firmware':'/a/s.zip',host:'ios1021'};
 m.validateOptions(base);m.validateOptions({...base,'experimental-ota':'TMG12'});
 assert.throws(()=>m.validateOptions({...base,'experimental-ota':'TMG11'}),/only_exact_tmg12_supported/);
 for(const n of ['c16','c17','c18','c20','c99'])assert.throws(()=>m.validateOptions({...base,release:n}),/unknown_release/,n);
 assert.throws(()=>m.validateOptions({...base,product:'iPhone17,1'}),/full_host_takes_no_product/);
 assert.throws(()=>m.validateOptions({...base,firmware:undefined}),/exact_host_and_firmware_resource_required/);
 const releases=JSON.parse(fs.readFileSync(new URL('./releases.json',import.meta.url),'utf8')).releases;
 for(const [n,spec] of Object.entries(releases)){
  assert.deepEqual(spec.hosts,['1021-full'],n);m.validateOptions({...base,release:n});
  assert.throws(()=>m.validateOptions({...base,host:'ios1021-download',firmware:undefined,release:n}),/release_requires_full_host/,n);
  for(const removed of ['ios1011','ios107'])assert.throws(()=>m.validateOptions({...base,host:removed,release:n}),/unknown_host_profile/,n);
 }
});
test('real addon build carries the full 1.0.21 host gate',t=>{
 const addon=path.join(packageTestDirectory,'build/mapkit/TurboIOPrivateAddon.dylib');if(!fs.existsSync(addon))return t.skip('build the embedded addon first');
 assert.ok(packaging.validateFull1021Addon(runFixtureCommand('/usr/bin/nm',['-g',addon],{encoding:'utf8',maxBuffer:64*1024*1024}),fs.readFileSync(addon)));
});
test('real 1.0.21 input: route patch profile ios1021 gives the pinned output; one byte off the pin is refused',t=>{
 const p=process.env.IOS1021_TEST_APP;if(!p)return t.skip('set IOS1021_TEST_APP');
 const r=fs.readFileSync(p+'/Runner'),a=fs.readFileSync(p+'/Frameworks/App.framework/App');
 const frameworks={'RayneoNet.framework/RayneoNet':fs.readFileSync(p+'/Frameworks/RayneoNet.framework/RayneoNet'),'Flutter.framework/Flutter':fs.readFileSync(p+'/Frameworks/Flutter.framework/Flutter')};
 const plist=JSON.parse(runFixtureCommand('plutil',['-convert','json','-o','-',p+'/Info.plist'],{encoding:'utf8'}));
 validateHost(plist,r,a,'ios1021',frameworks);validateHost(plist,r,a,'ios1021-download',frameworks);
 assert.throws(()=>validateHost({...plist,TIOHostProfile:'ios1021'},r,a,'ios1021',frameworks),/requires_original_ios1021_1/);
 for(const removed of ['ios1011','ios107',undefined])assert.throws(()=>validateHost(plist,r,a,removed,frameworks),/unknown_host_profile/);
 const {output,report}=patch(a,'ios1021');
 assert.equal(sha256(output),routeProfile('ios1021').outputSHA);assert.equal(report.profile,'ios1021');assert.equal(report.host,'1.0.21');assert.equal(report.build,1);
 assert.deepEqual(report.changes.map(c=>c.offset),[46796656,37435136]);assert.equal(report.deviceIO,false);assert.equal(output.length,a.length);
 assert.ok(verifyRoute(output,'ios1021'));assert.throws(()=>verifyRoute(output,'ios1011'),/Unknown route profile/);assert.throws(()=>verifyRoute(output),/Unknown route profile/);assert.throws(()=>verifyRoute(a,'ios1021'));
 assert.throws(()=>patch(a,'ios1011'),/Unknown route profile/);assert.throws(()=>patch(a),/Unknown route profile/);assert.throws(()=>patch(output,'ios1021'),/requires pinned 1\.0\.21\/1/);assert.throws(()=>patch(a,'ios1021-download'));
 // One byte off the pinned input, anywhere (here far from both records, then inside one): refused before patching.
 for(const at of [4096,46796656+3]){const near=Buffer.from(a);near[at]^=1;assert.throws(()=>patch(near,'ios1021'),/requires pinned 1\.0\.21\/1/,String(at));}
 let differing=0;for(let i=0;i<a.length;i++)if(a[i]!==output[i])differing++;assert.ok(differing>0&&differing<=report.changes.reduce((n,c)=>n+c.bytes,0));
});
