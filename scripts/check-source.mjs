#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

// Exact, reviewed non-source files (scripts/reviewed-assets.json and scripts/ios107-reviewed-assets.json), not a blanket media exclusion.
const reviewedScreenshots = new Map();

// Values are never printed. Regex scanning is a release gate, not a guarantee.
// Hash-pinned gallery ZIPs, firmware icons, stock firmware ZIPs and README images; no blanket exemption.
const review=JSON.parse(fs.readFileSync(new URL('./reviewed-assets.json',import.meta.url),'utf8'));
for(const [p,h] of Object.entries(review.files))reviewedScreenshots.set(p,h);
const ios107Review=JSON.parse(fs.readFileSync(new URL('./ios107-reviewed-assets.json',import.meta.url),'utf8'));
for(const [p,h] of Object.entries(ios107Review.files))reviewedScreenshots.set(p,h);
export function audit(root){
  const findings=[];let files=0;
  const rules=[
    ['api-key',/sk-[A-Za-z0-9_.-]{12,}/],
    ['private-key',/-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----/],
    ['private-home',/\/Users\/(?!YOUR_|example)[^/\s]+\//],
    ['dedicated-asr-tenant',/llm-[a-z0-9-]+\.[a-z0-9.-]*aliyuncs\.com/],
    ['dedicated-weather-tenant',/[a-z0-9]+\.re\.qweatherapi\.com/],
    ['embedded-credential',/(?:api[_-]?key|password|apiToken|access_token)\s*[:=]\s*["'][a-f0-9]{32,}["']/i],
    ['temporary-public-endpoint',/https:\/\/[a-z0-9-]+\.trycloudflare\.com/],
  ];
  function walk(p){
    if(path.basename(p)==='.git')return; // Also support Git worktree pointer files.
    const s=fs.lstatSync(p),relative=path.relative(root,p);
    if(s.isSymbolicLink()){findings.push({file:relative,rule:'symlink'});return;}
    if(s.isDirectory()){
      if(['.git','.build','node_modules','build','__pycache__'].includes(path.basename(p)))return;
      if(/\.(?:app|xcframework|xcresult)$/.test(p)){findings.push({file:relative,rule:'binary-bundle'});return;}
      for(const n of fs.readdirSync(p))walk(path.join(p,n));return;
    }
    files++;
    if(reviewedScreenshots.has(relative)){
      const digest=createHash('sha256').update(fs.readFileSync(p)).digest('hex');
      if(digest!==reviewedScreenshots.get(relative))findings.push({file:relative,rule:'screenshot-needs-privacy-review'});
      return;
    }
    if(/\.(?:ipa|apk|hap|har|app|dex|jar|jks|keystore|a|o|dylib|so|p12|p7b|cer|pem|key|mobileprovision|wav|ogg|pcm|mp3|m4a|png|jpg|zip|log|jsonl)$/i.test(p)&&relative!=='ios-addon/i18n/strings.jsonl')findings.push({file:relative,rule:'non-source-artifact'});
    if(s.size>2*1024*1024){findings.push({file:relative,rule:'oversize-review'});return;}
    const b=fs.readFileSync(p);if(b.includes(0)){findings.push({file:relative,rule:'binary-content'});return;}
    b.toString('utf8').split('\n').forEach((line,i)=>{for(const [rule,re]of rules){
      if(re.test(line))findings.push({file:relative,line:i+1,rule});
    }});
  }
  walk(root);return {files,findings};
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const root=path.resolve(process.argv[2]||path.join(path.dirname(fileURLToPath(import.meta.url)),'..'));
  const result=audit(root);console.log(JSON.stringify(result,null,2));process.exitCode=result.findings.length?1:0;
}
