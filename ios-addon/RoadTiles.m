#import "RoadTiles.h"
#include <math.h>
// Minimal protobuf reader for Mapbox Vector Tile 2.x. Bounds-checked; malformed input yields fewer features, never a crash.
typedef struct{const uint8_t *p,*end;} PB;
static BOOL Var(PB *b,uint64_t *v){*v=0;for(unsigned s=0;s<64&&b->p<b->end;s+=7){uint8_t c=*b->p++;*v|=(uint64_t)(c&127)<<s;if(c<128)return YES;}return NO;}
static BOOL Field(PB *b,unsigned *field,unsigned *wire,uint64_t *v,PB *sub){
 if(b->p>=b->end)return NO;uint64_t k;if(!Var(b,&k))return NO;*field=(unsigned)(k>>3);*wire=(unsigned)(k&7);
 switch(*wire){
  case 0:return Var(b,v);
  case 1:if(b->end-b->p<8)return NO;memcpy(v,b->p,8);b->p+=8;return YES;
  case 5:{if(b->end-b->p<4)return NO;uint32_t w;memcpy(&w,b->p,4);*v=w;b->p+=4;return YES;}
  case 2:if(!Var(b,v)||*v>(uint64_t)(b->end-b->p))return NO;sub->p=b->p;sub->end=b->p+*v;b->p+=*v;return YES;
 }return NO;
}
static id Value(PB b){
 unsigned f,w;uint64_t v;PB s;id out=nil;
 while(Field(&b,&f,&w,&v,&s)){
  if(f==1&&w==2)out=[[NSString alloc]initWithBytes:s.p length:s.end-s.p encoding:NSUTF8StringEncoding];
  else if(f==2&&w==5){float x;uint32_t u=(uint32_t)v;memcpy(&x,&u,4);out=@(x);}
  else if(f==3&&w==1){double x;memcpy(&x,&v,8);out=@(x);}
  else if((f==4||f==5)&&w==0)out=@((long long)v);
  else if(f==6&&w==0)out=@((long long)((v>>1)^(~(v&1)+1)));
  else if(f==7&&w==0)out=@(v!=0);
 }return out?:@"";
}
static NSString *S(id v){return [v isKindOfClass:NSString.class]?v:@"";}
// OpenMapTiles class/subclass -> the OSM highway tag RoadStyle() ranks; nil skips rail, ferry, aerialway, raceway...
static NSString *Highway(NSDictionary *t){
 NSString *c=S(t[@"class"]),*sub=S(t[@"subclass"]);
 if([@[@"motorway",@"trunk",@"primary",@"secondary",@"tertiary"] containsObject:c])return [t[@"ramp"] isEqual:@1]?[c stringByAppendingString:@"_link"]:c;
 if([c isEqual:@"minor"])return @"residential";
 if([c isEqual:@"service"]||[c isEqual:@"busway"])return @"service";
 if([c isEqual:@"track"])return @"track";
 if([c isEqual:@"path"])return [@[@"pedestrian",@"footway",@"cycleway",@"steps",@"bridleway"] containsObject:sub]?sub:@"path";
 return nil;
}
static double Lon(double tx,unsigned n){return tx/n*360-180;}
static double Lat(double ty,unsigned n){return atan(sinh(M_PI*(1-2*ty/n)))*180/M_PI;}
NSArray *TIORoadTileFeatures(NSData *tile,unsigned z,unsigned x,unsigned y,NSArray *bbox){
 NSMutableArray *out=[NSMutableArray new];if(z>22||bbox.count!=4)return out;unsigned n=1u<<z;if(x>=n||y>=n)return out;
 double minLat=[bbox[0] doubleValue],minLon=[bbox[1] doubleValue],maxLat=[bbox[2] doubleValue],maxLon=[bbox[3] doubleValue];
 PB t={tile.bytes,(const uint8_t *)tile.bytes+tile.length},l;unsigned f,w;uint64_t v;
 while(Field(&t,&f,&w,&v,&l)){if(f!=3||w!=2)continue;
  NSString *name=nil;NSMutableArray *keys=[NSMutableArray new],*values=[NSMutableArray new];NSMutableArray<NSValue *> *features=[NSMutableArray new];double extent=4096;PB b=l,s;
  while(Field(&b,&f,&w,&v,&s)){
   if(f==1&&w==2)name=[[NSString alloc]initWithBytes:s.p length:s.end-s.p encoding:NSUTF8StringEncoding];
   else if(f==2&&w==2)[features addObject:[NSValue valueWithBytes:&s objCType:@encode(PB)]];
   else if(f==3&&w==2)[keys addObject:[[NSString alloc]initWithBytes:s.p length:s.end-s.p encoding:NSUTF8StringEncoding]?:@""];
   else if(f==4&&w==2)[values addObject:Value(s)];
   else if(f==5&&w==0&&v>0&&v<=1<<16)extent=v;
  }
  BOOL roads=[name isEqual:@"transportation"],names=[name isEqual:@"transportation_name"];if(!roads&&!names)continue;
  for(NSValue *box in features){PB fb;[box getValue:&fb];PB tags={0},geom={0};uint64_t type=0;
   while(Field(&fb,&f,&w,&v,&s)){if(f==2&&w==2)tags=s;else if(f==3&&w==0)type=v;else if(f==4&&w==2)geom=s;}
   if(type!=2||!geom.p)continue; // LineStrings only: area polygons are not roads to draw
   NSMutableDictionary *tg=[NSMutableDictionary new];uint64_t a,c;
   while(tags.p&&Var(&tags,&a)&&Var(&tags,&c))if(a<keys.count&&c<values.count)tg[keys[a]]=values[c];
   NSString *highway=Highway(tg);if(!highway||[tg[@"indoor"] isEqual:@1])continue;
   NSMutableDictionary *p=[@{@"kind":@"road",@"highway":highway} mutableCopy];
   if(names){NSString *nm=S(tg[@"name"]),*en=S(tg[@"name_en"]);if(!nm.length&&!en.length)continue;p[@"labelOnly"]=@YES;if(nm.length)p[@"name"]=nm;if(en.length)p[@"name:en"]=en;}
   NSString *brunnel=S(tg[@"brunnel"]);if([brunnel isEqual:@"bridge"])p[@"bridge"]=@"yes";if([brunnel isEqual:@"tunnel"])p[@"tunnel"]=@"yes";
   if([tg[@"layer"] isKindOfClass:NSNumber.class])p[@"layer"]=tg[@"layer"];
   long long gx=0,gy=0;NSMutableArray *line=nil;NSMutableArray *lines=[NSMutableArray new];uint64_t cmd;
   BOOL bad=NO;while(!bad&&Var(&geom,&cmd)){unsigned op=cmd&7,count=(unsigned)(cmd>>3);if(op==7)continue;if((op!=1&&op!=2)||count>65536)break;
    for(unsigned i=0;i<count;i++){uint64_t dx,dy;if(!Var(&geom,&dx)||!Var(&geom,&dy)){bad=YES;break;}
     gx+=(long long)((dx>>1)^(~(dx&1)+1));gy+=(long long)((dy>>1)^(~(dy&1)+1));
     if(op==1||!line){line=[NSMutableArray new];[lines addObject:line];}
     [line addObject:@[@(Lon(x+gx/extent,n)),@(Lat(y+gy/extent,n))]];}
   }
   for(NSArray *ln in lines){if(ln.count<2)continue;double lo=INFINITY,hi=-INFINITY,lw=INFINITY,le=-INFINITY;
    for(NSArray *q in ln){double la=[q[1] doubleValue],lg=[q[0] doubleValue];lo=fmin(lo,la);hi=fmax(hi,la);lw=fmin(lw,lg);le=fmax(le,lg);}
    if(hi<minLat||lo>maxLat||le<minLon||lw>maxLon)continue;
    [out addObject:@{@"properties":p,@"geometry":@{@"type":@"LineString",@"coordinates":ln}}];}
  }
 }return out;
}
NSArray *TIORoadTilesCovering(NSArray *bbox,unsigned z,NSUInteger max){
 if(bbox.count!=4||z>22)return @[];unsigned n=1u<<z;
 double minLat=fmax(-85,[bbox[0] doubleValue]),minLon=[bbox[1] doubleValue],maxLat=fmin(85,[bbox[2] doubleValue]),maxLon=[bbox[3] doubleValue];
 if(!(minLat<=maxLat&&minLon<=maxLon&&minLon>=-180&&maxLon<=180))return @[];
 long x0=(long)floor((minLon+180)/360*n),x1=(long)floor((maxLon+180)/360*n),y0=(long)floor((1-asinh(tan(maxLat*M_PI/180))/M_PI)/2*n),y1=(long)floor((1-asinh(tan(minLat*M_PI/180))/M_PI)/2*n);
 x0=MAX(0,x0);y0=MAX(0,y0);x1=MIN((long)n-1,x1);y1=MIN((long)n-1,y1);if((NSUInteger)((x1-x0+1)*(y1-y0+1))>max)return @[];
 NSMutableArray *out=[NSMutableArray new];for(long ty=y0;ty<=y1;ty++)for(long tx=x0;tx<=x1;tx++)[out addObject:@[@(z),@(tx),@(ty)]];return out;
}
NSArray *TIORoadTilesAlongRoute(NSArray *coords,unsigned z,double radius,NSUInteger max){
 NSMutableArray *out=[NSMutableArray new];NSMutableSet *seen=[NSMutableSet new];if(coords.count<2||radius<=0)return out;
 void(^cover)(double,double)=^(double lat,double lon){double dlat=radius/111319.49,dlon=dlat/fmax(.2,cos(lat*M_PI/180));
  for(NSArray *t in TIORoadTilesCovering(@[@(lat-dlat),@(lon-dlon),@(lat+dlat),@(lon+dlon)],z,16))if(out.count<max&&![seen containsObject:t]){[seen addObject:t];[out addObject:t];}};
 double step=radius/2;
 for(NSUInteger i=0;i+1<coords.count&&out.count<max;i++){double a=[coords[i][0] doubleValue],b=[coords[i][1] doubleValue],c=[coords[i+1][0] doubleValue],d=[coords[i+1][1] doubleValue];
  if(!isfinite(a)||!isfinite(b)||!isfinite(c)||!isfinite(d))continue;
  double meters=hypot((c-a)*111319.49,(d-b)*111319.49*cos(a*M_PI/180));unsigned n=(unsigned)fmin(100000,ceil(meters/step));
  for(unsigned k=0;k<=n&&out.count<max;k++){double t=n?(double)k/n:0;cover(a+(c-a)*t,b+(d-b)*t);}}
 return out;
}
@implementation TIORoadTileStore{
 NSURL *_dir;TIORoadTileFetch _fetch;NSString *_template;BOOL _templateBusy,_retryQueued;
 NSMutableArray *_queue;NSMutableSet *_queued,*_busy;NSMutableDictionary *_failedAt;NSUInteger _saved,_downloads,_epoch;unsigned long long _bytes;
}
static NSString *Key(NSArray *t){return [NSString stringWithFormat:@"%@-%@-%@",t[0],t[1],t[2]];}
- (instancetype)initWithDirectory:(NSURL *)directory fetch:(TIORoadTileFetch)fetch{
 if(!directory||!fetch||!(self=[super init]))return nil;_dir=directory;_fetch=[fetch copy];_retryAfter=30;_queue=[NSMutableArray new];_queued=[NSMutableSet new];_busy=[NSMutableSet new];_failedAt=[NSMutableDictionary new];
 NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtURL:_dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
 // A trip that never ended normally (crash, force quit) is forgotten after a day.
 for(NSURL *u in [fm contentsOfDirectoryAtURL:_dir includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]){NSDate *m=nil;[u getResourceValue:&m forKey:NSURLContentModificationDateKey error:nil];if(m&&-m.timeIntervalSinceNow>86400)[fm removeItemAtURL:u error:nil];}
 _template=[NSString stringWithContentsOfURL:[_dir URLByAppendingPathComponent:@"template.txt"] encoding:NSUTF8StringEncoding error:nil];return self;
}
- (NSURL *)fileFor:(NSArray *)t{return [_dir URLByAppendingPathComponent:[Key(t) stringByAppendingString:@".tile"]];}
- (NSData *)tile:(NSArray *)t{if(t.count!=3)return nil;NSData *d=[NSData dataWithContentsOfURL:[self fileFor:t]];return d?[d decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil]:nil;}
- (BOOL)saved:(NSArray *)t{return [NSFileManager.defaultManager fileExistsAtPath:[self fileFor:t].path];}
- (void)want:(NSArray *)tiles urgent:(BOOL)urgent{
 NSMutableArray *add=[NSMutableArray new];for(NSArray *t in tiles){if(t.count!=3||[self saved:t])continue;BOOL queued=[_queued containsObject:Key(t)];if(urgent||!queued){if(queued)[_queue removeObject:t];[_queued addObject:Key(t)];[add addObject:t];}}
 if(urgent){[_queue insertObjects:add atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,add.count)]];for(NSArray *t in add)[_failedAt removeObjectForKey:Key(t)];}else [_queue addObjectsFromArray:add];
 [self pump];
}
- (void)pump{
 if(!_queue.count)return;NSUInteger epoch=_epoch;
 if(!_template){if(_templateBusy)return;_templateBusy=YES;
  _fetch([NSURL URLWithString:@"https://tiles.openfreemap.org/planet"],^(NSData *d){NSDictionary *j=d.length&&d.length<=256*1024?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
   NSString *t=[j isKindOfClass:NSDictionary.class]&&[j[@"tiles"] isKindOfClass:NSArray.class]&&[j[@"tiles"] count]?j[@"tiles"][0]:nil;
   BOOL ok=[t isKindOfClass:NSString.class]&&[t hasPrefix:@"https://tiles.openfreemap.org/"]&&[t hasSuffix:@"/{z}/{x}/{y}.pbf"];
   dispatch_async(dispatch_get_main_queue(),^{if(epoch!=self->_epoch)return;self->_templateBusy=NO;if(ok){self->_template=t;[t writeToURL:[self->_dir URLByAppendingPathComponent:@"template.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];[self pump];}else [self retryLater];});});
  return;}
 NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;BOOL waiting=NO;
 for(NSArray *t in [_queue copy]){if(_busy.count>=4||_downloads>=5000)break;NSString *k=Key(t);if([_busy containsObject:k])continue;
  NSNumber *failed=_failedAt[k];if(failed&&now-failed.doubleValue<_retryAfter){waiting=YES;continue;}
  [_busy addObject:k];_downloads++;NSString *u=[[[_template stringByReplacingOccurrencesOfString:@"{z}" withString:[t[0] stringValue]] stringByReplacingOccurrencesOfString:@"{x}" withString:[t[1] stringValue]] stringByReplacingOccurrencesOfString:@"{y}" withString:[t[2] stringValue]];
  _fetch([NSURL URLWithString:u],^(NSData *d){NSData *packed=d.length&&d.length<=4*1024*1024?[d compressedDataUsingAlgorithm:NSDataCompressionAlgorithmLZFSE error:nil]:nil;
   BOOL ok=packed&&[packed writeToURL:[self fileFor:t] options:NSDataWritingAtomic error:nil];
   dispatch_async(dispatch_get_main_queue(),^{if(epoch!=self->_epoch){if(ok)[NSFileManager.defaultManager removeItemAtURL:[self fileFor:t] error:nil];return;}
    [self->_busy removeObject:k];if(ok){[self->_queue removeObject:t];[self->_queued removeObject:k];[self->_failedAt removeObjectForKey:k];self->_saved++;self->_bytes+=d.length;if(self.landed)self.landed();}else self->_failedAt[k]=@(NSProcessInfo.processInfo.systemUptime);
    [self pump];});});
 }
 if(waiting&&!_busy.count)[self retryLater];
}
- (void)retryLater{if(_retryQueued)return;_retryQueued=YES;NSUInteger epoch=_epoch;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(_retryAfter*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(epoch!=self->_epoch)return;self->_retryQueued=NO;[self pump];});}
- (void)clear{_epoch++;[_queue removeAllObjects];[_queued removeAllObjects];[_busy removeAllObjects];[_failedAt removeAllObjects];_saved=0;_downloads=0;_bytes=0;_retryQueued=NO;_templateBusy=NO;
 NSFileManager *fm=NSFileManager.defaultManager;for(NSURL *u in [fm contentsOfDirectoryAtURL:_dir includingPropertiesForKeys:nil options:0 error:nil])if([u.pathExtension isEqual:@"tile"])[fm removeItemAtURL:u error:nil];}
- (NSDictionary *)status{return @{@"wanted":@(_queue.count+_saved),@"saved":@(_saved),@"failed":@(_failedAt.count),@"downloading":@(_busy.count),@"downloadedBytes":@(_bytes)};}
@end
