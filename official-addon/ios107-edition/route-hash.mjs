// The loopback route strings for patch-route.mjs. Does not install, serve or flash.
// Preserve Dart string size AND cached noncryptographic hash, so the existing
// canonical hash-table placement is not changed. Not a firmware MD5 bypass.
// Host pins and record offsets live in patch-route.mjs ROUTE_PROFILES.
export const originals=['/xrlauncherapi/v1/signApi/gray/upgrade','/xrlauncherhwapi/v1/signApi/gray/upgrade'];
const assert=(v,s)=>{if(!v)throw Error(s);};
const combine=(h,c)=>{h=(h+c)>>>0;h=Math.imul(h,1025)>>>0;return (h^(h>>>6))>>>0;};
function accumulate(s){let h=0;for(const c of Buffer.from(s))h=combine(h,c);return h;}
function finalize(h){h=Math.imul(h,9)>>>0;h=(h^(h>>>11))>>>0;h=Math.imul(h,32769)>>>0;return (h&0x3fffffff)||1;}
export const stringHash=s=>finalize(accumulate(s));
function inverseOdd(n){let x=1n;for(let i=0;i<6;i++)x=(x*(2n-BigInt(n)*x))&0xffffffffn;return Number(x);}
function undoXor(n,shift){let x=n;for(let s=shift;s<32;s+=shift)x^=n>>>s;return x>>>0;}
const inv1025=inverseOdd(1025),inv9=inverseOdd(9),inv32769=inverseOdd(32769);
const uncombine=(h,c)=>(Math.imul(undoXor(h,6),inv1025)-c)>>>0;
const unfinalize=h=>Math.imul(undoXor(Math.imul(h,inv32769)>>>0,11),inv9)>>>0;
const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
export function makeRoute(original){
  const base='http://127.0.0.1:18794/g/';
  const prefix=base+'x'.repeat(Buffer.byteLength(original)-base.length-6);
  const target=stringHash(original);assert(target>1,'Unsupported degenerate hash');
  const forward=new Map(),initial=accumulate(prefix);
  for(let a=0;a<64;a++)for(let b=0;b<64;b++)for(let c=0;c<64;c++){
    const h=combine(combine(combine(initial,alphabet.charCodeAt(a)),alphabet.charCodeAt(b)),alphabet.charCodeAt(c));
    if(!forward.has(h))forward.set(h,a*4096+b*64+c);
  }
  for(let hi=0;hi<4;hi++){
    const end=unfinalize((target+hi*0x40000000)>>>0);
    for(let c=0;c<64;c++)for(let b=0;b<64;b++)for(let a=0;a<64;a++){
      const h=uncombine(uncombine(uncombine(end,alphabet.charCodeAt(c)),alphabet.charCodeAt(b)),alphabet.charCodeAt(a));
      const first=forward.get(h);if(first===undefined)continue;
      const result=prefix+alphabet[first>>>12]+alphabet[(first>>>6)&63]+alphabet[first&63]+alphabet[a]+alphabet[b]+alphabet[c];
      assert(result.length===original.length&&stringHash(result)===target,'Hash construction failed');
      return result;
    }
  }
  throw Error('No compatible route found; do not patch');
}
