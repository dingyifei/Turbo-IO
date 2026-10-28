#!/usr/bin/env node
// Local-only source-release packager. Does not download, decrypt or upload apps.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync as exec } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {validateTranslationPair,prepareTranslationResources,copyTranslationResources} from './local-translation/package-resources.mjs';
import {prepareAppleAI,copyAppleAI} from './apple-ai/package-resources.mjs';
import {inspectMachO} from './macho-embed.mjs';
import {patch as patchOTARoute,verifyRoute} from './patch-route.mjs';
export const CANDIDATE_RESOURCE='TurboWeReadCandidate.zip';
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
const pins=JSON.parse(fs.readFileSync(new URL('./firmware-pins.json',import.meta.url),'utf8'));
const digest=b=>createHash('sha256').update(b).digest('hex');
export function validateHost(info,runner,appImage){
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleShortVersionString!=='1.0.7'||String(info.CFBundleVersion)!=='230'||Object.keys(info).some(k=>k.startsWith('TIO')))throw Error('requires_original_ios107_230');
  const h=inspectMachO(runner);
  const acceptedPairs=[
    ['c416d939c90745b170027171844e3275faf5e502306746176375dee5837aadcf','fd83c578708e929d732d06a97c2b8e3dd4dd665d0ec72ea16420fcbcca4bae3e'],
    ['765715adebb3b6132a1870d9b500e861e028cdaecc2f6485296a428c1812e0b3','041dc97ad3a864ac322e92a49d3b1ebbd466d371dc427591b0b82c8c56b5090d'],
  ];
  if(h.encrypted||h.uuid!=='410defdbf93739eaacf2f616abff9d0b'||!acceptedPairs.some(([r,a])=>digest(runner)===r&&digest(appImage)===a))throw Error('host_image_identity_mismatch');
}
export function validateOptions(o) {
  for(const k of ['app','addon','profile','out'])if(typeof o[k]!=='string'||!path.isAbsolute(o[k]))throw Error('absolute_paths_required');
  if(!o.app.endsWith('.app')||o.out.endsWith('.app'))throw Error('use_app_input_and_new_output_directory');
  if(!/^[a-f0-9]{40}$/i.test(o.identity||'')||!/^[a-z0-9-]{8,80}$/i.test(o.device||''))throw Error('explicit_identity_and_device_required');
  if(!/^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z0-9.-]+$/.test(o.bundle||''))throw Error('invalid_bundle');
  if(o.product&&!/^iPhone\d+,\d+$/.test(o.product))throw Error('invalid_explicit_product');
  if(fs.existsSync(o.out))throw Error('output_must_not_exist');
  if(o['experimental-ota']!==undefined&&o['experimental-ota']!==pins.name)throw Error('only_exact_'+pins.name.toLowerCase()+'_supported');
  if(o.bundle!=='com.rayneo.venus.pub'||typeof o.firmware!=='string'||!path.isAbsolute(o.firmware))throw Error('exact_host_and_firmware_resource_required');
}
export function validateResearchPair(symbols, kind, firmware) {
  if(kind!==pins.name||!symbols.includes('_TIOMenuLayoutController')||!symbols.includes('OBJC_CLASS_$_TIORoadMap'))throw Error('ios107_addon_required');
  if(!Buffer.isBuffer(firmware)||firmware.length!==pins.zipBytes||createHash('sha256').update(firmware).digest('hex')!==pins.zipSHA256)throw Error('navs3_firmware_identity_mismatch');

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
  if(process.argv.includes('--help'))console.log(`iOS 1.0.7/230 APP107: exact ${pins.name} OTA candidate included by default. Installation does NOT grant flash permission; manual one-shot authorization required.`);
  if(process.argv.includes('--help'))console.log('Optional Apple AI: --apple-ai-dylib /absolute/TurboAppleAI.dylib (requires TIO_APPLE_AI=1 addon)');
  if(process.argv.includes('--help'))console.log('Optional local translation: --translation-module-dir /absolute/module --translation-models /absolute/models (requires TIO_LOCAL_TRANSLATION=1 addon; see official-addon/ios107-edition/local-translation/README.md)');
  if(process.argv.includes('--help')){console.log(`node official-addon/ios107-edition/package.mjs --app /absolute/Runner.app --addon /absolute/TurboIOPrivateAddon.dylib --profile /absolute/profile.mobileprovision --identity CERTIFICATE_SHA1 --device YOUR_DEVICE_ID --out /absolute/new-private-output --bundle com.rayneo.venus.pub --firmware /absolute/exact-${pins.name}-CANDIDATE-NOT-APPROVED.zip [--product iPhone18,2]`);return;}
  const o={bundle:'com.rayneo.venus.pub'};const args=process.argv.slice(2);
  if(args.length%2)throw Error('expected_named_arguments');
  const seen=new Set();for(let i=0;i<args.length;i+=2){const k=args[i].slice(2);if(!args[i].startsWith('--')||!['app','addon','profile','identity','device','out','bundle','product','experimental-ota','firmware','translation-module-dir','translation-models','apple-ai-dylib'].includes(k)||seen.has(k))throw Error('unknown_or_duplicate_argument');seen.add(k);o[k]=args[i+1];}
  validateOptions(o);
  const symbols=run('/usr/bin/nm',['-g',o.addon],{encoding:'utf8',maxBuffer:64*1024*1024});
  // FOCUS has a dynamic optional entry even without the translation module.
  validateTranslationPair(!o['translation-module-dir']&&!o['translation-models']?symbols.replaceAll('_TIOOpenLocalTranslation',''):symbols,o);
  const translationResources=prepareTranslationResources(o);
  const appleAI=prepareAppleAI(o['apple-ai-dylib'],symbols);
  const source=fs.realpathSync(o.app),destination=path.resolve(o.out);
  if(!symbols.includes('_TIOOTAFlashBuild')||!fs.readFileSync(o.addon).includes(Buffer.from('display extension=APP107-OTA-PHONE-01;')))throw Error('ios107_addon_marker_required');
  const firmware=o.firmware?fs.readFileSync(o.firmware):undefined;
  validateResearchPair(symbols,pins.name,firmware);
  const info=JSON.parse(run('plutil',['-convert','json','-o','-',path.join(source,'Info.plist')],{encoding:'utf8'}));
  validateHost(info,fs.readFileSync(path.join(source,'Runner')),fs.readFileSync(path.join(source,'Frameworks/App.framework/App')));
  if(destination===source||destination.startsWith(source+path.sep))throw Error('output_must_be_separate');
  if(privateBundleNames(source).length)throw Error('source_contains_private_bootstrap');
  const profile=JSON.parse(run('python3',['-c',`import sys,plistlib,json,hashlib,subprocess
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',sys.argv[1]],stderr=subprocess.DEVNULL))
print(json.dumps({'entitlements':p['Entitlements'],'expires':p['ExpirationDate'].isoformat()+'Z','devices':p.get('ProvisionedDevices',[]),'certs':[hashlib.sha1(x).hexdigest().upper() for x in p['DeveloperCertificates']]}))`,o.profile],{encoding:'utf8'}));
  const entitlement=entitlementsFor(profile,o);
  fs.mkdirSync(destination,{mode:0o700});
  const app=path.join(destination,'Payload','Runner.app');
  run(process.execPath,[path.join(here,'macho-embed.mjs'),source,app,o.addon,o.bundle]);
  applyUsageDescriptions(app,translationResources);
  copyTranslationResources(translationResources,app);
  copyAppleAI(appleAI,app);
  if(translationResources){
    const plist=path.join(app,'Info.plist');
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSMicrophoneUsageDescription)run('plutil',['-insert','NSMicrophoneUsageDescription','-string','在用户主动开启英语离线字幕时使用所选麦克风；停止后结束收音。',plist]);
  }
  {
    // Exact inspected 1.0.7 data records only; no instruction/header edits or OTA grant.
    const image=path.join(app,'Frameworks/App.framework/App');
    fs.writeFileSync(image,patchOTARoute(fs.readFileSync(image)).output);
    const plist=path.join(app,'Info.plist');
    run('plutil',['-insert','TIOExperimentalOTAQueryRouting','-string','ios107-tmg2-loopback-flash-gated',plist]);
    run('plutil',['-insert','TIOPackagingRevision','-string','APP107-OTA-PUBLIC-SOURCE-01',plist]);
    run('plutil',['-insert','TIOExperimentalOTABuild','-string',pins.name,plist]);
    if(firmware)fs.writeFileSync(path.join(app,CANDIDATE_RESOURCE),firmware,{flag:'wx'});
    const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));
    if(!info.NSAppTransportSecurity)run('plutil',['-insert','NSAppTransportSecurity','-dictionary',plist]);
    if(info.NSAppTransportSecurity?.NSAllowsLocalNetworking===undefined)run('plutil',['-insert','NSAppTransportSecurity.NSAllowsLocalNetworking','-bool','YES',plist]);
    fs.cpSync(path.join(here,'tests/maps'),path.join(app,'TurboHUDMaps'),{recursive:true,errorOnExist:true,force:false});
  }
  const locationUsage=locationUsageFor(symbols);
  if(locationUsage){const plist=path.join(app,'Info.plist');const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));if(!info.NSLocationWhenInUseUsageDescription)run('plutil',['-insert','NSLocationWhenInUseUsageDescription','-string',locationUsage,plist]);}
  if(o.product){const plist=path.join(app,'Info.plist');const info=JSON.parse(run('plutil',['-convert','json','-o','-',plist],{encoding:'utf8'}));if(Array.isArray(info.UISupportedDevices)&&!info.UISupportedDevices.includes(o.product))run('plutil',['-insert','UISupportedDevices.0','-string',o.product,plist]);}
  if(privateBundleNames(app,ALLOWED_BUNDLE_PRIVATE).length)throw Error('bundle_contains_private_file');
  const ep=path.join(destination,'signing-entitlements.plist');
  run('python3',['-c','import sys,json,plistlib; plistlib.dump(json.load(sys.stdin),open(sys.argv[1],"wb"))',ep],{input:JSON.stringify(entitlement)});fs.chmodSync(ep,0o600);
  fs.copyFileSync(o.profile,path.join(app,'embedded.mobileprovision'));
  const nested=[];function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,entry.name);if(entry.isSymbolicLink())throw Error('symlink_requires_review');if(entry.isDirectory()){walk(p);if(entry.name.endsWith('.framework'))nested.push(p);}else if(entry.name.endsWith('.dylib'))nested.push(p);}}
  walk(path.join(app,'Frameworks'));
  for(const p of nested)run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der',p]);
  run('codesign',['--force','--sign',o.identity,'--timestamp=none','--generate-entitlement-der','--entitlements',ep,app]);
  run('codesign',['--verify','--deep','--strict',app]);
  verifyRoute(fs.readFileSync(path.join(app,'Frameworks/App.framework/App')));
  const ipa=path.join(destination,'TurboIO-local-only.ipa');
  run('/usr/bin/ditto',['-c','-k','--norsrc','--noextattr','--keepParent',path.join(destination,'Payload'),ipa]);fs.chmodSync(ipa,0o600);
  run('/usr/bin/unzip',['-tq',ipa]);
  const names=run('/usr/bin/unzip',['-Z1',ipa],{encoding:'utf8'}).split('\n');if(names.some(n=>n.split('/').some(x=>x==='__MACOSX'||x.startsWith('._'))))throw Error('unexpected_archive_metadata');
  if(privateArchiveNames(names).length)throw Error('archive_contains_private_file');
  const report={appleAIModule:!!appleAI,status:'SIGNED_NOT_DEVICE_ACCEPTED',host:'1.0.7 (230)',signatureVerified:true,officialSourceUploaded:false,privateBootstrapIncluded:false,experimentalOTA:true,flashAuthorized:false,firmwareResourceOnly:false,postSigningRouteVerified:true,ipaSHA256:createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),pushEntitled:!!entitlement['aps-environment'],appleSignInEntitled:!!entitlement['com.apple.developer.applesignin']};
  fs.writeFileSync(path.join(destination,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});console.log(JSON.stringify(report,null,2));
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){try{main();}catch(e){const known=/^[a-z_]+$/.test(e.message);console.error(known?e.message:'Local packaging failed. Check compatible source, profile and signing identity. No subprocess output or credentials are printed.');process.exitCode=1;}}
