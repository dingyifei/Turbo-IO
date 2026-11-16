// The one inspected host image (version/build/UUID) the packager prepares. The native runtime checks the same
// image independently (HostCompatibility.h). Any other app, older versions included, is refused.
export const inspectedHosts = Object.freeze([
  // The 1.0.21 image: download-only (C19) without the packager's TIOHostProfile=ios1021
  // marker; with it, the full host (package.mjs ios1021). The decrypted input carries a
  // stale Apple signature, which macho-embed strips for both builds.
  Object.freeze({version:'1.0.21',build:'1',uuid:'74da0780dcf0384f9e841ac12f56cdf5',profile:'ios1021-download',downloadOnly:true,staleSignature:true}),
]);
export function inspectedHost(info, uuid) {
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleExecutable!=='Runner')return null;
  return inspectedHosts.find(h=>h.version===info.CFBundleShortVersionString&&h.build===String(info.CFBundleVersion)&&h.uuid===uuid)??null;
}
