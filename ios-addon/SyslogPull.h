#import <Foundation/Foundation.h>
// Sensor log: ask the glasses for their syslog once (biz 0x10, A1 00 00 12), read the
// completion notices and the file-share bytes passively, lz4-decode and grep probe lines.
// Everything here is pure; the hook and the hub row live elsewhere. Nothing leaves the phone.

// {businessId:@16, payload:A1 00 00 12}
NSDictionary *TIOSyslogRequest(void);
// biz 0x10 payload -> {sub:@0x13,size:@N,name:@"..."} | {sub:@0x14,raw:NSData} | nil
NSDictionary *TIOSyslogParseNotice(NSData *payload);

// Collects the file-share bytes. Fed either with raw biz 0x11 TransferMessage payloads
// (FileInfoSync / FileChunk placed by chunk_start) or with already-decoded chunk bytes
// (the stock receiver's fileShareProgress chunkData, appended in order).
@interface TIOSyslogAssembler : NSObject
@property(nonatomic,readonly) NSData *data;
@property(nonatomic,readonly) uint64_t expectedSize; // from the 0x13 notice or FileInfoSync; 0 = unknown
@property(nonatomic,readonly,copy) NSString *fileName,*advertisedMD5;
@property(nonatomic,readonly) BOOL complete;         // expectedSize known and bytes >= expectedSize
- (void)expectSize:(uint64_t)size name:(NSString *)name;
- (BOOL)feedTransferMessage:(NSData *)payload;       // NO if not a usable FileInfoSync/FileChunk
- (BOOL)appendChunk:(NSData *)bytes;                 // NO when over the cap
@end

// lz4 frame (magic 0x184D2204); block and content checksums are skipped, not verified.
NSData *TIOLZ4DecodeFrame(NSData *frame,NSUInteger maxOutput);
// Raw lz4 block appended to `out`; matches may reach into earlier output (linked frame blocks).
BOOL TIOLZ4DecodeBlock(const uint8_t *src,NSUInteger n,NSMutableData *out,NSUInteger maxOutput);

// Lines of decoded text that contain any probe needle (see the .m); capped.
NSArray<NSString *> *TIOSyslogProbeLines(NSData *text);
