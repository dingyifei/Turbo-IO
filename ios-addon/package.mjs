#!/usr/bin/env node
// Local-only source-release packager. Does not download, decrypt or upload apps.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync as exec } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {validateTranslationPair,prepareTranslationResources,copyTranslationResources} from './local-translation/package-resources.mjs';
import {prepareAppleAI,copyAppleAI} from './apple-ai/package-resources.mjs';
import {inspectMachO,stripCodeSignature} from './macho-embed.mjs';
import {patch as patchOTARoute,verifyRoute,routeProfile} from './patch-route.mjs';
export const CANDIDATE_RESOURCE='TurboWeReadCandidate.zip';
// The second package of a release, the stock ZIP of its base, has its own fixed resource name beside the TMG one.
export const STOCK_RESOURCE='TurboStockFirmware.zip';
export const PRIVATE_NAME=/Private|CookieImport|KnowledgeConnection/;
export const ALLOWED_BUNDLE_PRIVATE=new Set(['TurboIOPrivatePreparation.json','Frameworks/TurboIOPrivateAddon.dylib']);
export function privateBundleNames(dir,allowed=new Set()){
  const names=[];
  function visit(relative=''){
    for(const entry of fs.readdirSync(path.join(dir,relative),{withFileTypes:true})){
      const name=relative?`${relative}/${entry.name}`:entry.name;
      if(PRIVATE_NAME.test(name)&&(!allowed.has(name)||!entry.isFile()))names.push(name);
      if(entry.isDirectory())visit(name);
    }
  }
  visit();return names.sort();
}
export function privateArchiveNames(names){const ok=new Set(['Payload/Runner.app/TurboIOPrivatePreparation.json','Payload/Runner.app/Frameworks/TurboIOPrivateAddon.dylib']);return names.filter(n=>n&&!n.endsWith('/')&&PRIVATE_NAME.test(n)&&!ok.has(n));}
const here=path.dirname(fileURLToPath(import.meta.url));
// Release configurations (releases.json): every release is named cN, and its pins are firmware-pins-cN.json,
// written by firmware/tools/phone_pins.py from that ZIP. No --release means the only release in releases.json;
// with several releases, a release must be named.
function releasesJSON(){return JSON.parse(fs.readFileSync(new URL('./releases.json',import.meta.url),'utf8')).releases??{};}
// Every release name in releases.json (the generator's input), so a new release is covered without editing this file.
export function releaseNames(){
  const names=Object.keys(releasesJSON());
  if(!names.length||names.some(n=>!/^c[0-9]+$/.test(n)))throw Error('invalid_releases_json');
  return names;
}
// The release a build uses when none is named: the only one in releases.json.
export function soleRelease(){
  const names=releaseNames();
  if(names.length!==1)throw Error('release_required');
  return names[0];
}
export function releasePins(name=soleRelease()){
  if(typeof name!=='string'||!/^c[0-9]+$/.test(name)||!releaseNames().includes(name))throw Error('unknown_release');
  const file=new URL(`./firmware-pins-${name}.json`,import.meta.url);
  if(!fs.existsSync(file))throw Error('unknown_release');
  const p=JSON.parse(fs.readFileSync(file,'utf8'));
  if(p.release!==name)throw Error('unknown_release');
  return p;
}
// The packages of a release (firmware-pins-cN.json "packages", phone_pins.py): the first is the TMG build the
// top level describes, bundled as CANDIDATE_RESOURCE; a second one is the stock package, bundled as STOCK_RESOURCE.
export function releasePackages(p){
  const list=p?.packages;
  if(!Array.isArray(list)||list.length<1||list.length>2)throw Error('release_packages_invalid');
  list.forEach((e,i)=>{
    const want=i===0?{kind:'TMG',resource:CANDIDATE_RESOURCE}:{kind:'STOCK',resource:STOCK_RESOURCE};
    if(!e||e.kind!==want.kind||e.resource!==want.resource||typeof e.name!=='string'||!/^[0-9a-f]{64}$/.test(e.zipSHA256??'')||!Number.isInteger(e.zipBytes)||e.zipBytes<=0)throw Error('release_packages_invalid');
  });
  if(list[0].name!==p.name||list[0].zipSHA256!==p.zipSHA256||list[0].zipBytes!==p.zipBytes)throw Error('release_packages_invalid');
  if(list[1]&&list[1].name!=='STOCK-'+p.stockBase)throw Error('release_packages_invalid');
  return list;
}
export function stockPackage(p){return releasePackages(p)[1];}
// The addon names its release in one string (ExperimentalOTA.m, from FirmwarePins.h): it must be the requested
// release with its ZIPs, and must not also carry another release's marker. The first package keeps the old shape;
// each other package follows as "; package=<label>; zip=<sha>; accepts ...".
export function releaseMarker(p){return `ota release=${p.release}; firmware=${p.name}; zip=${p.zipSHA256}; accepts `;}
export function packageMarker(e){return `; package=${e.name}; zip=${e.zipSHA256}; accepts `;}
export function validateReleaseAddon(addon,p){
  if(!Buffer.isBuffer(addon)||!addon.includes(Buffer.from(releaseMarker(p))))throw Error('addon_release_mismatch');
  for(const e of releasePackages(p).slice(1))if(!addon.includes(Buffer.from(packageMarker(e))))throw Error('addon_release_mismatch');
  for(const other of releaseNames())if(other!==p.release&&addon.includes(Buffer.from(`ota release=${other}; `)))throw Error('addon_release_mismatch');
  return true;
}
const digest=b=>createHash('sha256').update(b).digest('hex');
// One row per accepted host input: the stock RayNeo AI 1.0.21/1 app, as a download-only build or as the full build.
// Exact pins only; a row never widens another. Any other host is unknown and refused.
export const HOST_PROFILES=Object.freeze({
  // Download-only 1.0.21/1 (C19): stock App.framework, no route patch, no TMG ZIP, no flash
  // marker. The stale Apple signature of the decrypted input is stripped before embedding.
  // The two route records are the stock Dart strings at their 1.0.21 offsets, recorded for
  // checks only; never patched in this profile.
  'ios1021-download':Object.freeze({name:'ios1021-download',version:'1.0.21',build:'1',uuid:'74da0780dcf0384f9e841ac12f56cdf5',hostError:'requires_original_ios1021_1',
    acceptedPairs:Object.freeze([
      ['9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2','0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273'],
    ]),
    frameworks:Object.freeze({'RayneoNet.framework/RayneoNet':'d8befe5f3144d21e4725bc27791c55954a210ee11e5738c197dbb1c18350bfa3','Flutter.framework/Flutter':'4c16499adee04bf904f7795f98e983b9fb593fb93b607ca7941761c2949f0e9a'}),
    routes:Object.freeze([['/xrlauncherapi/v1/signApi/gray/upgrade',46796656],['/xrlauncherhwapi/v1/signApi/gray/upgrade',37435136]]),
    sourceIPASHA256:'7cecd8847944e118c24beba8d9ae7cb5d42387047e8570feb184dca7f60b8f4a',
    // The addon's download-only guard keys on this one runtime marker (ExperimentalOTAFlash.m).
    routePatch:false,firmware:false,stripStaleSignature:true,runtimeMarker:'ios1021-download',packagingRevision:'APP1021-DOWNLOAD-ONLY-01'}),
  // Full 1.0.21 (C20): the pinned input of the download-only 1.0.21 row (same Runner, App, frameworks and source
  // IPA), with the route patch at the 1.0.21 offsets (pinned output), the bundled TMG candidate of a release built
  // for this host (releases.json hosts ["1021-full"]) and its own host-profile marker (OTAHost.h TIOOTA1021HostMatches).
  // The addon's flash gate refuses every transfer frame until the owner authorizes one flash in the wizard.
  ios1021:Object.freeze({name:'ios1021',version:'1.0.21',build:'1',uuid:'74da0780dcf0384f9e841ac12f56cdf5',hostError:'requires_original_ios1021_1',
    acceptedPairs:Object.freeze([
      ['9a226b80d3e32b1ec496f45cd51d46bdf5251650225cec99824d9a897f1dd1f2','0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273'],
    ]),
    frameworks:Object.freeze({'RayneoNet.framework/RayneoNet':'d8befe5f3144d21e4725bc27791c55954a210ee11e5738c197dbb1c18350bfa3','Flutter.framework/Flutter':'4c16499adee04bf904f7795f98e983b9fb593fb93b607ca7941761c2949f0e9a'}),
    sourceIPASHA256:'7cecd8847944e118c24beba8d9ae7cb5d42387047e8570feb184dca7f60b8f4a',
    routePatch:true,routeProfile:'ios1021',firmware:true,stripStaleSignature:true,noProduct:true,hostProfileMarker:'ios1021',
    packagingRevision:'APP1021-OTA-FULL-01',fullHost:'1021-full'}),
});
// The packager host name (turbo-package.sh --host, releases.json hosts) of each profile that bundles a release.
export const RELEASE_HOST_NAMES=Object.freeze({ios1021:'1021-full'});
// The hosts a release is built for (releases.json). A release ZIP is bundled only for one of them.
export function releaseHosts(name=soleRelease()){
  const releases=releasesJSON();
  if(!Object.hasOwn(releases,name)||!Array.isArray(releases[name].hosts)||releases[name].hosts.some(h=>typeof h!=='string'))throw Error('unknown_release');
  return releases[name].hosts;
}
// The profile must be named; there is no default host.
export function hostProfile(name){
  if(!Object.hasOwn(HOST_PROFILES,name))throw Error('unknown_host_profile');
  return HOST_PROFILES[name];
}
// frameworks: {'RayneoNet.framework/RayneoNet':Buffer,...}, required when the profile pins them.
export function validateHost(info,runner,appImage,profileName,frameworks={}){
  const p=hostProfile(profileName);
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleShortVersionString!==p.version||String(info.CFBundleVersion)!==p.build||Object.keys(info).some(k=>k.startsWith('TIO')))throw Error(p.hostError);
  const h=inspectMachO(runner);
  if(h.encrypted||h.uuid!==p.uuid||!p.acceptedPairs.some(([r,a])=>digest(runner)===r&&digest(appImage)===a))throw Error('host_image_identity_mismatch');
  for(const [name,sha] of Object.entries(p.frameworks??{}))if(!Buffer.isBuffer(frameworks[name])||digest(frameworks[name])!==sha)throw Error('host_framework_identity_mismatch');
}
// Download-only profile: App.framework/App must be the stock bytes, with each stock
// route record present exactly once at its recorded offset (i.e. not patched).
export function verifyStockApp(appImage,profileName){
  const p=hostProfile(profileName);
  if(p.routePatch||!Buffer.isBuffer(appImage)||!p.acceptedPairs.some(([,a])=>digest(appImage)===a))throw Error('download_only_app_changed');
  for(const [route,offset] of p.routes){const b=Buffer.from(route);if(appImage.indexOf(b)!==offset||appImage.indexOf(b,offset+1)!==-1)throw Error('download_only_route_mismatch');}
  return true;
}
// codesign_allocate sizes __LINKEDIT vmsize to the new signature, so a re-signed
// image may differ from stock there and nowhere else once the signature is gone.
// Returns the stripped image with that one field zeroed; vmsize must still cover filesize.
function linkeditAt(bytes){
  const info=inspectMachO(bytes);let p=32,at=[];
  for(let i=0;i<info.count;i++){if(bytes.readUInt32LE(p)===0x19&&bytes.toString('latin1',p+8,p+24).replace(/\0+$/,'')==='__LINKEDIT')at.push(p);p+=bytes.readUInt32LE(p+4);}
  if(at.length!==1)throw Error('download_only_app_changed_after_signing');
  return at[0];
}
function strippedForCompare(bytes){
  const p=linkeditAt(bytes),vmsize=bytes.readBigUInt64LE(p+32),filesize=bytes.readBigUInt64LE(p+48);
  if(vmsize<filesize||vmsize%0x4000n)throw Error('download_only_app_changed_after_signing');
  const {output}=stripCodeSignature(bytes);output.writeBigUInt64LE(0n,linkeditAt(output)+32);
  return output;
}
// After signing, App.framework/App carries a new signature. Everything else must equal stock.
export function verifySignedStockApp(signed,stock,profileName){
  verifyStockApp(stock,profileName);
  if(!strippedForCompare(signed).equals(strippedForCompare(stock)))throw Error('download_only_app_changed_after_signing');
  for(const [route,offset] of hostProfile(profileName).routes){const b=Buffer.from(route);if(signed.indexOf(b)!==offset||signed.indexOf(b,offset+1)!==-1)throw Error('download_only_route_mismatch');}
  return true;
}
// G1/G2 gate for the download-only host: the built addon must carry the
// flag-independent business-9 refusal, the hook target check and the panel's
// safety model. Missing any of them fails closed before anything is signed.
export const DOWNLOAD_ONLY_GUARD_MARKER='ota guard=DOWNLOAD-ONLY-GUARD-03; flag-independent; businessId above 255 refused; stock teleprompter sendFile allow-listed';
export const DOWNLOAD_ONLY_GUARD_SYMBOLS=Object.freeze(['_TIOOTAFlashBlockCall','_TIOOTADownloadOnlyHost','_TIOOTADownloadOnlyBlockCall','_TIOOTADownloadOnlyGuardMarker','_TIOInstallGlassesChannelHook','_TIOGlassesChannelHookFailure','_TIOChannelHookTargetFailure','_TIODownloadOnlyGuardActiveFor','_TIOFirmwareExportSafetyModel','_TIOHostDownloadOnlyGuardActive','_TIOStockTeleprompterSendAllowed']);
export function validateDownloadOnlyAddon(symbols,addon){
  const names=new Set(String(symbols).split('\n').map(l=>l.trim().split(/\s+/).pop()));
  for(const name of DOWNLOAD_ONLY_GUARD_SYMBOLS)if(!names.has(name))throw Error('download_only_guard_missing:'+name);
  if(!Buffer.isBuffer(addon)||!addon.includes(Buffer.from(DOWNLOAD_ONLY_GUARD_MARKER)))throw Error('download_only_guard_missing:marker');
  return true;
}
// Gate for the full 1.0.21 host: the addon must carry the flag-independent full-host gate (ExperimentalOTAFlash.m
// TIOOTAFullHostGuardMarker and the functions it names), and also the download-only guard, which takes over if the
// profile marker is ever missing. Fails closed before anything is signed.
export const FULL_HOST_GUARD_MARKER='ota guard=FULL-HOST-GATE-01; flag-independent; business 9 transfer frames refused without one confirmation; reads and the exact size query pass';
export const FULL_HOST_GUARD_SYMBOLS=Object.freeze(['_TIOOTAFullHost','_TIOOTAFullHostGuardMarker','_TIOOTAFlashBlockCallSnapshot','_TIOOTAFlashAuthorize','_TIOOTAFlashNoteRefused','_TIOFirmwareExportSafetyModelFull']);
export function validateFull1021Addon(symbols,addon){
  validateDownloadOnlyAddon(symbols,addon);
  const names=new Set(String(symbols).split('\n').map(l=>l.trim().split(/\s+/).pop()));
  for(const name of FULL_HOST_GUARD_SYMBOLS)if(!names.has(name))throw Error('full_host_guard_missing:'+name);
  if(!addon.includes(Buffer.from(FULL_HOST_GUARD_MARKER)))throw Error('full_host_guard_missing:marker');
  return true;
}
// The full-host addon check for a profile: ios1021 is the only full host; any other profile has none.
export function validateFullHostAddon(hostName,symbols,addon){
  if(hostName==='ios1021')return validateFull1021Addon(symbols,addon);
  throw Error('not_a_full_host');
}
export function validateOptions(o) {
  if(o.host===undefined)throw Error('host_required');
  const host=hostProfile(o.host);
  if(o.release!==undefined&&!host.fullHost)throw Error('release_requires_full_host');
  for(const k of ['app','addon','profile','out'])if(typeof o[k]!=='string'||!path.isAbsolute(o[k]))throw Error('absolute_paths_required');
  if(!o.app.endsWith('.app')||o.out.endsWith('.app'))throw Error('use_app_input_and_new_output_directory');
  if(!/^[a-f0-9]{40}$/i.test(o.identity||'')||!/^[a-z0-9-]{8,80}$/i.test(o.device||''))throw Error('explicit_identity_and_device_required');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(o.bundle||''))throw Error('invalid_bundle');
  if(fs.existsSync(o.out))throw Error('output_must_not_exist');
  if(!host.firmware){
    // Download-only: nothing to flash, no TMG candidate, no device-model injection.
    if(o.bundle!=='com.rayneo.venus.pub'||o.firmware!==undefined||o['stock-firmware']!==undefined||o['experimental-ota']!==undefined||o.product!==undefined)throw Error('download_only_host_takes_no_firmware_or_product');
    return;
  }
  if(host.noProduct&&o.product!==undefined)throw Error('full_host_takes_no_product');
  // The release (the only one when none is named) must be built for this host.
  if(!releaseHosts(o.release).includes(RELEASE_HOST_NAMES[host.name]))throw Error('release_not_built_for_host');
  const release=releasePins(o.release);
  if(o['experimental-ota']!==undefined&&o['experimental-ota']!==release.name)throw Error('only_exact_'+release.name.toLowerCase()+'_supported');
  if(o.bundle!=='com.rayneo.venus.pub'||typeof o.firmware!=='string'||!path.isAbsolute(o.firmware))throw Error('exact_host_and_firmware_resource_required');
  // A release with a stock package bundles its ZIP too (--stock-firmware); one without takes none.
  if(stockPackage(release)?(typeof o['stock-firmware']!=='string'||!path.isAbsolute(o['stock-firmware'])):o['stock-firmware']!==undefined)throw Error('stock_firmware_resource_required');
}
export function validateResearchPair(symbols, kind, firmware, p=releasePins()) {
  if(kind!==p.name||!symbols.includes('_TIOMenuLayoutController')||!symbols.includes('OBJC_CLASS_$_TIORoadMap'))throw Error('ios107_addon_required');
  if(!Buffer.isBuffer(firmware)||firmware.length!==p.zipBytes||createHash('sha256').update(firmware).digest('hex')!==p.zipSHA256)throw Error('navs3_firmware_identity_mismatch');

}
// The stock package's ZIP, size and SHA-256 against its entry, before it is bundled.
export function validateStockPackage(stock,p=releasePins()){
  const e=stockPackage(p);
  if(!e||!Buffer.isBuffer(stock)||stock.length!==e.zipBytes||createHash('sha256').update(stock).digest('hex')!==e.zipSHA256)throw Error('stock_firmware_identity_mismatch');
  return true;
}
// Location prompts for whichever navigation provider the addon links; null when none does.
export function locationUsageFor(symbols){
  if(symbols.includes('OBJC_CLASS_$_TIOMapKitNavigationPanel'))return 'Shows your position and gives turn-by-turn directions on your glasses while navigating.';
  return null;
}
export function usageDescriptions(translationResources){
  return {
    base:{
      NSCameraUsageDescription:'Used to set your profile picture, and to show the camera view when you start remote capture from your glasses.',
      NSPhotoLibraryAddUsageDescription:'Saves photos you take to your library.'
    },
    zhHans:{
      NSCameraUsageDescription:'用于设置头像，以及在你主动开启眼镜遥控拍照时取景。',
      NSPhotoLibraryAddUsageDescription:'用户拍摄后保存照片。'
    },
    zhHant:{
      NSCameraUsageDescription:'用於設定頭像，以及在你主動開啟眼鏡遙控拍照時取景。',
      NSPhotoLibraryAddUsageDescription:'拍攝後將照片儲存到相簿。'
    },
    lproj:['NSCameraUsageDescription','NSPhotoLibraryAddUsageDescription']
  };
}
export function applyUsageDescriptions(app,translationResources){
  const descriptions=usageDescriptions(translationResources);
  const plist=path.join(app,'Info.plist');
  for(const key of ['NSCameraUsageDescription','NSPhotoLibraryAddUsageDescription'])
    run('plutil',['-replace',key,'-string',descriptions.base[key],plist]);
  for(const [directory,localized] of [['zh-Hans-CN.lproj',descriptions.zhHans],['zh-HK.lproj',descriptions.zhHant],['zh-TW.lproj',descriptions.zhHant]]){
    const file=path.join(app,directory,'InfoPlist.strings');
    if(!fs.existsSync(file))continue;
    const values=JSON.parse(run('plutil',['-convert','json','-o','-',file],{encoding:'utf8'}));
    for(const key of descriptions.lproj){
      const operation=Object.hasOwn(values,key)?'-replace':'-insert';
      run('plutil',[operation,key,'-string',localized[key],file]);
    }
  }
}
export function entitlementsFor(p,o) {
  if(!Array.isArray(p.certs)||!p.certs.includes(o.identity.toUpperCase())||!Array.isArray(p.devices)||!p.devices.includes(o.device)||!(Date.parse(p.expires)>Date.now()))throw Error('profile_identity_device_or_expiry_mismatch');
  const e=structuredClone(p.entitlements), appID=e?.['application-identifier'];
  if(typeof appID!=='string'||(!appID.endsWith('.*')&&!appID.endsWith('.'+o.bundle)))throw Error('profile_bundle_mismatch');
  e['application-identifier']=appID.endsWith('.*')?appID.slice(0,-1)+o.bundle:appID;
  if(e['keychain-access-groups'])e['keychain-access-groups']=e['keychain-access-groups'].map(x=>x.endsWith('.*')?x.slice(0,-1)+o.bundle:x);
  return e; // Never synthesize official push, app groups or sign-in permissions.
}
function run(program,args,options={}){return exec(program,args,{stdio:['pipe','pipe','pipe'],...options});}
function main(){
  if(process.argv.includes('--help'))console.log('Optional Apple AI: --apple-ai-dylib /absolute/TurboAppleAI.dylib (requires TIO_APPLE_AI=1 addon)');
  if(process.argv.includes('--help'))console.log('Optional local translation: --translation-module-dir /absolute/module --translation-models /absolute/models (requires TIO_LOCAL_TRANSLATION=1 addon; see ios-addon/local-translation/README.md)');
  if(process.argv.includes('--help'))console.log('Download-only 1.0.21/1 (C19): --host ios1021-download, no --firmware, no --release and no --product. App.framework stays stock; no OTA flashing.');
  if(process.argv.includes('--help'))console.log('Full 1.0.21/1 (C22): --host ios1021 [--release cN] with --firmware (the TMG package) and --stock-firmware (the stock package, when the release lists one), no --product: a release whose releases.json hosts list 1021-full (without --release, the only release). Route patch at the 1.0.21 offsets; every TMG transfer frame needs one authorization in the wizard; needs an addon built for that release.');
  if(process.argv.includes('--help'))console.log('--host is required: ios1021-download or ios1021. Installation never grants flash permission.');
  if(process.argv.includes('--help')){console.log('node ios-addon/package.mjs --host ios1021 --app /absolute/Runner.app --addon /absolute/TurboIOPrivateAddon.dylib --profile /absolute/profile.mobileprovision --identity CERTIFICATE_SHA1 --device YOUR_DEVICE_ID --out /absolute/new-private-output --bundle com.rayneo.venus.pub --firmware /absolute/exact-release-CANDIDATE-NOT-APPROVED.zip --stock-firmware /absolute/stock-package.zip [--release cN]');return;}
  const o={bundle:'com.rayneo.venus.pub'};const args=process.argv.slice(2);
  if(args.length%2)throw Error('expected_named_arguments');
  const seen=new Set();for(let i=0;i<args.length;i+=2){const k=args[i].slice(2);if(!args[i].startsWith('--')||!['app','addon','profile','identity','device','out','bundle','product','experimental-ota','firmware','stock-firmware','translation-module-dir','translation-models','apple-ai-dylib','host','release'].includes(k)||seen.has(k))throw Error('unknown_or_duplicate_argument');seen.add(k);o[k]=args[i+1];}
  validateOptions(o);
  const host=hostProfile(o.host);
  const symbols=run('/usr/bin/nm',['-g',o.addon],{encoding:'utf8',maxBuffer:64*1024*1024});
  // FOCUS has a dynamic optional entry even without the translation module.
  validateTranslationPair(!o['translation-module-dir']&&!o['translation-models']?symbols.replaceAll('_TIOOpenLocalTranslation',''):symbols,o);
  const translationResources=prepareTranslationResources(o);
  const appleAI=prepareAppleAI(o['apple-ai-dylib'],symbols);
  const source=fs.realpathSync(o.app),destination=path.resolve(o.out);
  if(!symbols.includes('_TIOOTAFlashBuild')||!fs.readFileSync(o.addon).includes(Buffer.from('display extension=TMG-OTA-PHONE-01;')))throw Error('ios107_addon_marker_required');
  const firmware=o.firmware?fs.readFileSync(o.firmware):undefined;
  // Only a firmware host bundles a release; a download-only build reads no release pins.
  const release=host.firmware?releasePins(o.release):undefined;
  const stockFirmware=o['stock-firmware']?fs.readFileSync(o['stock-firmware']):undefined;
  if(host.firmware){validateResearchPair(symbols,release.name,firmware,release);if(stockPackage(release))validateStockPackage(stockFirmware,release);else if(stockFirmware)throw Error('stock_firmware_resource_required');validateReleaseAddon(fs.readFileSync(o.addon),release);}else if(firmware||stockFirmware)throw Error('download_only_host_takes_no_firmware_or_product');
  if(!host.routePatch)validateDownloadOnlyAddon(symbols,fs.readFileSync(o.addon));
  if(host.fullHost)validateFullHostAddon(host.name,symbols,fs.readFileSync(o.addon));
  const info=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(source,'Info.plist')],{encoding:'utf8'}));
  const sourceApp=fs.readFileSync(path.join(source,'Frameworks/App.framework/App'));
  validateHost(info,fs.readFileSync(path.join(source,'Runner')),sourceApp,host.name,Object.fromEntries(Object.keys(host.frameworks??{}).map(n=>[n,fs.readFileSync(path.join(source,'Frameworks',n))])));
  if(destination===source||destination.startsWith(source+path.sep))throw Error('output_must_be_separate');
  if(privateBundleNames(source).length)throw Error('source_contains_private_bootstrap');
  const profile=JSON.parse(run('python3',['-c',`import sys,plistlib,json,hashlib,subprocess
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
print(json.dumps({'entitlements':p['Entitlements'],'expires':p['ExpirationDate'].isoformat()+'Z','devices':p.get('ProvisionedDevices',[]),'certs':[hashlib.sha1(x).hexdigest().upper() for x in p['DeveloperCertificates']]}))`,o.profile],{encoding:'utf8'}));
  const entitlement=entitlementsFor(profile,o);
  fs.mkdirSync(destination,{mode:0o700});
  const app=path.join(destination,'Payload','Runner.app');
  run(process.execPath,[path.join(here,'macho-embed.mjs'),source,app,o.addon,o.bundle,...(host.stripStaleSignature?['--strip-stale-signature']:[])]);
  applyUsageDescriptions(app,translationResources);
  copyTranslationResources(translationResources,app);
  copyAppleAI(appleAI,app);
  if(translationResources){
    const plist=path.join(app,'Info.plist');
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSMicrophoneUsageDescription)run('plutil',['-insert','NSMicrophoneUsageDescription','-string','在用户主动开启英语离线字幕时使用所选麦克风；停止后结束收音。',plist]);
  }
  if(!host.routePatch){
    // Download-only: App.framework/App stays the stock bytes; no feed route, ZIP or flash marker.
    verifyStockApp(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')),host.name);
    const plist=path.join(app,'Info.plist');
    run('plutil',['-insert','TIOHostProfile','-string',host.runtimeMarker??host.name,plist]);
    run('plutil',['-insert','TIOPackagingRevision','-string',host.packagingRevision,plist]);
  }else{
    // Exact inspected data records only (each host's own offsets); no instruction/header edits or OTA grant.
    const image=path.join(app,'Frameworks/App.framework/App');
    fs.writeFileSync(image,patchOTARoute(fs.readFileSync(image),host.routeProfile).output);
    const plist=path.join(app,'Info.plist');
    if(host.hostProfileMarker)run('plutil',['-insert','TIOHostProfile','-string',host.hostProfileMarker,plist]);
    run('plutil',['-insert','TIOPackagingRevision','-string',host.packagingRevision,plist]);
    run('plutil',['-insert','TIOExperimentalOTABuild','-string',release.name,plist]);
    if(firmware)fs.writeFileSync(path.join(app,CANDIDATE_RESOURCE),firmware,{flag:'wx'});
    if(stockFirmware)fs.writeFileSync(path.join(app,STOCK_RESOURCE),stockFirmware,{flag:'wx'});
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSAppTransportSecurity)run('plutil',['-insert','NSAppTransportSecurity','-dictionary',plist]);
    if(info.NSAppTransportSecurity?.NSAllowsLocalNetworking===undefined)run('plutil',['-insert','NSAppTransportSecurity.NSAllowsLocalNetworking','-bool','YES',plist]);
    fs.cpSync(path.join(here,'tests/maps'),path.join(app,'TurboHUDMaps'),{recursive:true,errorOnExist:true,force:false});
  }
  const locationUsage=locationUsageFor(symbols);
  if(locationUsage){const plist=path.join(app,'Info.plist');const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));if(!info.NSLocationWhenInUseUsageDescription)run('plutil',['-insert','NSLocationWhenInUseUsageDescription','-string',locationUsage,plist]);}
  if(host.fullHost){
    // Full 1.0.21: this host's profile marker, the ZIP, the patched App (its pinned output) and no device-model list.
    const tag='full_host';
    const plist=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(app,'Info.plist')],{encoding:'utf8'}));
    if(plist.TIOHostProfile!==host.hostProfileMarker||plist.TIOExperimentalOTABuild!==release.name||plist.UISupportedDevices!==undefined||!fs.existsSync(path.join(app,CANDIDATE_RESOURCE)))throw Error(tag+'_bundle_mismatch');
    if(!routeProfile(host.routeProfile).outputSHA||digest(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')))!==routeProfile(host.routeProfile).outputSHA)throw Error(tag+'_route_output_mismatch');
    // Every package's ZIP is in the bundle under its fixed name with its pinned bytes, and nothing else under the stock name.
    for(const e of releasePackages(release)){const f=path.join(app,e.resource);if(!fs.existsSync(f)||digest(fs.readFileSync(f))!==e.zipSHA256)throw Error(tag+'_bundle_mismatch');}
    if(!stockPackage(release)&&fs.existsSync(path.join(app,STOCK_RESOURCE)))throw Error(tag+'_bundle_mismatch');
  }
  if(!host.routePatch){
    const plist=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(app,'Info.plist')],{encoding:'utf8'}));
    if(plist.TIOExperimentalOTABuild!==undefined||plist.UISupportedDevices!==undefined||plist.TIOHostProfile!==(host.runtimeMarker??host.name)||fs.existsSync(path.join(app,CANDIDATE_RESOURCE))||fs.existsSync(path.join(app,STOCK_RESOURCE)))throw Error('download_only_bundle_mismatch');
  }
  if(privateBundleNames(app,ALLOWED_BUNDLE_PRIVATE).length)throw Error('bundle_contains_private_file');
  const ep=path.join(destination,'signing-entitlements.plist');
  run('python3',['-c','import sys,json,plistlib; plistlib.dump(json.load(sys.stdin),open(sys.argv[1],"wb"))',ep],{input:JSON.stringify(entitlement)});fs.chmodSync(ep,0o600);
  fs.copyFileSync(o.profile,path.join(app,'embedded.mobileprovision'));
  const nested=[];function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,entry.name);if(entry.isSymbolicLink())throw Error('symlink_requires_review');if(entry.isDirectory()){walk(p);if(entry.name.endsWith('.framework'))nested.push(p);}else if(entry.name.endsWith('.dylib'))nested.push(p);}}
  walk(path.join(app,'Frameworks'));
  for(const p of nested)run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der',p]);
  run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der','--entitlements',ep,app]);
  run('codesign',['--verify','--deep','--strict',app]);
  if(host.routePatch)verifyRoute(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')),host.routeProfile);
  else verifySignedStockApp(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')),sourceApp,host.name);
  const ipa=path.join(destination,'TurboIO-local-only.ipa');
  run('/usr/bin/ditto',['-c','-k','--norsrc','--noextattr','--keepParent',path.join(destination,'Payload'),ipa]);fs.chmodSync(ipa,0o600);
  run('/usr/bin/unzip',['-tq',ipa]);
  const names=run('/usr/bin/unzip',['-Z1',ipa],{encoding:'utf8',maxBuffer:256*1024*1024}).split('\n');if(names.some(n=>n.split('/').some(x=>x==='__MACOSX'||x.startsWith('._'))))throw Error('unexpected_archive_metadata');
  if(privateArchiveNames(names).length)throw Error('archive_contains_private_file');
  const preparation=JSON.parse(fs.readFileSync(path.join(app,'TurboIOPrivatePreparation.json'),'utf8'));
  const report=host.fullHost?{appleAIModule:!!appleAI,status:'SIGNED_NOT_DEVICE_ACCEPTED',host:`${host.version} (${host.build})`,hostProfile:host.name,release:release.release,firmwareName:release.name,firmwareSHA256:release.zipSHA256,packages:releasePackages(release).map(e=>({name:e.name,kind:e.kind,resource:e.resource,zipBytes:e.zipBytes,zipSHA256:e.zipSHA256})),signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,experimentalOTA:true,flashAuthorized:false,firmwareResourceOnly:false,firmwareBundled:true,routePatched:true,routePatchedSHA256:routeProfile(host.routeProfile).outputSHA,postSigningRouteVerified:true,staleSignatureRemoved:preparation.staleSignatureRemoved===true,originalRunnerSHA256:preparation.originalExecutableSHA256,unsignedRunnerSHA256:preparation.unsignedExecutableSHA256,preparedRunnerSHA256:preparation.preparedExecutableSHA256,sourceIPASHA256:host.sourceIPASHA256,sourceNote:`Third-party decrypted IPA; SHA-256 pinned at intake, not re-hashed here. The owner approved patching App.framework and re-signing it for the full ${host.version} build.`,wireLogCapture:`Capture a wire log during every flash. The ${host.version} OTA sequence the tests replay is the one recorded during the TMG12 flash of 2026-11-15.`,ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']}:{appleAIModule:!!appleAI,status:'SIGNED_NOT_DEVICE_ACCEPTED',host:`${host.version} (${host.build})`,hostProfile:host.name,signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,experimentalOTA:false,flashAuthorized:false,firmwareBundled:false,routePatched:false,appFrameworkStockBeforeSigning:true,appFrameworkStockExceptSignature:true,staleSignatureRemoved:preparation.staleSignatureRemoved===true,originalRunnerSHA256:preparation.originalExecutableSHA256,unsignedRunnerSHA256:preparation.unsignedExecutableSHA256,preparedRunnerSHA256:preparation.preparedExecutableSHA256,sourceIPASHA256:host.sourceIPASHA256,sourceNote:'Third-party decrypted IPA; SHA-256 pinned at intake, not re-hashed here. The owner approved patching and re-signing it for this download-only build.',ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']};
  fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){try{main();}catch(e){const known=/^[a-z_]+$/.test(e.message);console.error(known?e.message:'Local packaging failed. Check compatible source, profile and signing identity. No subprocess output or credentials are printed.');process.exitCode=1;}}
