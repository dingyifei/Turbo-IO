// Exact pinned inputs only, one row per host profile. Two data strings, no instruction/header edits.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {makeRoute,stringHash,originals} from './route-hash.mjs';
// One row per host profile: the input pins, the record offsets and the pinned output. The replacement strings and
// the Dart hash rule are the same for every row. OTAHost.h TIOOTARouteOffsets holds the same offsets.
export const ROUTE_PROFILES=Object.freeze({
  // Full 1.0.21/1 (C20): the stock App of the download-only row (package.mjs ios1021-download),
  // the same two stock strings at the 1.0.21 offsets, with the same Dart lengths and cached hashes.
  ios1021:Object.freeze({host:'1.0.21',build:1,inputs:Object.freeze(['0a78cf75acdaf7b9d999cf27edd4ba7424640811e77cd309fc4c27fcb8c49273']),offsets:Object.freeze([46796656,37435136]),
    outputSHA:'cd8be91e82bdbc1c98b5dda4fa0d358b91a2187ea4571200760fac0c53cb7852'}),
});
// The profile must be named; there is no default host.
export function routeProfile(name){if(!Object.hasOwn(ROUTE_PROFILES,name))throw Error('Unknown route profile');return ROUTE_PROFILES[name];}
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const check=(v,m)=>{if(!v)throw Error(m);};
// Signing may change the signature blob; verify the exact two records afterwards.
export function verifyRoute(input,profile){
  const offsets=routeProfile(profile).offsets;
  for(let i=0;i<originals.length;i++){
    const offset=offsets[i],original=originals[i],replacement=makeRoute(original);
    check(input.length>=offset+original.length,'Truncated route image');
    check(input.readBigUInt64LE(offset-8)===BigInt(original.length*2),'Dart length mismatch');
    check(input.readUInt32LE(offset-12)===stringHash(original),'Cached hash mismatch');
    check(input.subarray(offset,offset+original.length).equals(Buffer.from(replacement)),'Route record mismatch');
  }
  return true;
}
export function patch(input,profile){
  const p=routeProfile(profile),offsets=p.offsets;
  check(p.inputs.includes(sha(input)),`Wrong host image: requires pinned ${p.host}/${p.build}`);
  const output=Buffer.from(input),changes=[];
  for(let i=0;i<originals.length;i++){
    const original=originals[i],offset=offsets[i];
    check(input.indexOf(original)===offset&&input.indexOf(original,offset+1)===-1,'Unexpected query record');
    check(input.readBigUInt64LE(offset-8)===BigInt(original.length*2),'Dart length mismatch');
    check(input.readUInt32LE(offset-12)===stringHash(original),'Cached hash mismatch');
    const replacement=makeRoute(original);output.write(replacement,offset,'ascii');
    check(output.subarray(offset-16,offset).equals(input.subarray(offset-16,offset)),'Header changed');
    changes.push({offset,bytes:original.length,original,replacement});
  }
  for(let i=0;i<input.length;i++)if(input[i]!==output[i])check(changes.some(c=>i>=c.offset&&i<c.offset+c.bytes),'Unexpected edit');
  check(sha(output)===p.outputSHA,'Patched image does not match the pinned output');
  return {output,report:{host:p.host,build:p.build,profile,inputSHA:sha(input),outputSHA:sha(output),changes,instructionsChanged:false,deviceIO:false,runtimeValidated:false}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const [source,out,profile]=process.argv.slice(2);check(source&&out&&profile&&!fs.existsSync(out),'Usage: patch-route.mjs INPUT_APP NEW_OUTPUT_DIRECTORY PROFILE (ios1021)');
  const {output,report}=patch(fs.readFileSync(source),profile);fs.mkdirSync(out,{mode:0o700});
  fs.writeFileSync(path.join(out,'App'),output,{flag:'wx',mode:0o600});
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx',mode:0o600});
  console.log(JSON.stringify(report));
}
