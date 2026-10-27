import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
export const REQUIRED=['TIOAppleAIProbe','TIOAppleLLM','TIOAppleLLMTask','TIOAppleSpeech','TIOAppleSpeechTask','TIOAppleCaptionPanel','TIOAppleCaptionHost'];
export function prepareAppleAI(dylib,addonSymbols,{nm}={}) {
  if(dylib===undefined||dylib===null)return null;
  if(typeof dylib!=='string'||!path.isAbsolute(dylib))throw Error('apple_ai_absolute_path_required');
  let info;try{info=JSON.parse(fs.readFileSync(path.join(path.dirname(dylib),'build-info.json')));}catch{throw Error('apple_ai_build_info_mismatch');}
  if(info.version!=='APPLE-AI-01')throw Error('apple_ai_build_info_mismatch');
  if(!addonSymbols.includes('_TIOAppleAILoaded'))throw Error('apple_ai_addon_mismatch');
  const symbols=nm?nm(dylib):execFileSync('nm',[dylib],{encoding:'utf8',maxBuffer:64*1024*1024});
  if(!REQUIRED.every(name=>String(symbols).split('\n').some(line=>line.trimEnd().endsWith('_OBJC_CLASS_$_'+name))))throw Error('apple_ai_symbols_missing');
  return {dylib};
}
export function copyAppleAI(resources,app) {
  if(!resources)return;
  const target=path.join(app,'Frameworks','TurboAppleAI.dylib');
  if(fs.existsSync(target))throw Error('apple_ai_already_present');
  fs.copyFileSync(resources.dylib,target,fs.constants.COPYFILE_EXCL);
}
