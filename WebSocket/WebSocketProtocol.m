//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketProtocol.h"
#import "WebSocket.h"
#import <CommonCrypto/CommonDigest.h>

inline static uint32_t _mask(uint8_t *dst, NSUInteger len, uint8_t mask[4], uint32_t off);

@implementation WebSocketFrame {
    NSData *_chunk;
    NSMutableData *data;
    uint32_t mask;
    uint64_t left;
    BOOL final;
}
@synthesize opCode;

- (id)initWithOpCode:(WebSocketOpCode)_opCode payload:(uint64_t)size mask:(uint32_t)_mask final:(BOOL)_final
{
    if (self = [super init]) {
        opCode = _opCode;
        left = size;
        mask = _mask;
        final = _final;
    }
    return self;
}

- (BOOL)complete { return final && !left; }

- (void)continuePayload:(uint64_t)size final:(BOOL)_final { left += size; final = _final; }

- (NSData*)data { return data ? data : _chunk; }

- (NSString*)description
{
    return [NSString stringWithFormat:@"<%@:%d data:%d left:%d final:%d>", NSStringFromClass(self.class), opCode, (uint32_t)self.data.length, (uint32_t)left, final];
}

- (NSData*)appendData:(NSData*)_data
{
    NSUInteger len = _data.length;
    if (!len) return nil;

    NSData *chunk = _data;
    if (len > left) {
        chunk = [_data subdataWithRange:NSMakeRange(0, left)];
        _data = [_data subdataWithRange:NSMakeRange(left, len - left)];
    } else {
        _data = nil;
    }
    left -= chunk.length;

    if (!_chunk && !data && !mask) {
        _chunk = chunk;
        return _data;
    }

    NSUInteger offset = data.length;
    if (!data) {
        data = [_chunk mutableCopy];
    }
    if (!data) {
        data = [chunk mutableCopy];
    } else {
        [data appendData:chunk];
    }
    _chunk = nil;

    if (mask) {
        _mask(data.mutableBytes + offset, chunk.length, (uint8_t*)&mask, offset % sizeof(mask));
    }

    return _data;
}

@end

static const uint8_t SignBitMask = 0x80;
static const uint8_t DataBitMask = 0x7F;
static const uint8_t OpCodeMask  = 0x0F;

#define CHECK_LENGTH(len) if (data.length < len) { [cache appendData:data]; break; } else { [cache setLength:0]; }

WebSocketFrame* WebSocketReceive(NSData *data, WebSocketFrame *partial, NSMutableData *cache, WSProtocolFrame receiver, WSProtocolError handler)
{
    while (data) {
        if (partial) {
            data = [partial appendData:data];
            if (partial.complete) {
                receiver(partial);
                partial = nil;
            }
        }
        if (!data.length) break;
        
        NSUInteger headerSize = 2;
        CHECK_LENGTH(headerSize);
        
        uint8_t *buf = (uint8_t*)data.bytes;
        uint64_t payload = buf[1] & DataBitMask;
        
        switch (payload) {
            case 126: headerSize += sizeof(uint16_t); break;
            case 127: headerSize += sizeof(uint64_t); break;
        }
        
        CHECK_LENGTH(headerSize);
        
        switch (payload) {
            case 126: payload = OSSwapBigToHostInt16(*(uint16_t*)(buf + 2)); break;
            case 127: payload = OSSwapBigToHostInt64(*(uint64_t*)(buf + 2)); break;
        }
        
        uint32_t mask = 0;
        BOOL masked = buf[1] &SignBitMask;
        if (masked) {
            CHECK_LENGTH(headerSize + sizeof(mask));
            memcpy(&mask, buf + headerSize, sizeof(mask));
            headerSize += sizeof(mask);
        }
        
        BOOL fin = buf[0] & SignBitMask;
        uint8_t rsv = (buf[0] >> 4) & 0x7;
        WebSocketOpCode opcode = buf[0] & OpCodeMask;
        
        if (rsv != 0) {
            handler(WebSocketError(kWebSocketErrorProtocol, @"Bad RSV", nil));
            return nil;
        }
        
        switch (opcode) {
            case WebSocketPing:
            case WebSocketPong:
            case WebSocketTextFrame:
            case WebSocketBinaryFrame:
            case WebSocketConnectionClose:
                partial = [[WebSocketFrame alloc] initWithOpCode:opcode payload:payload mask:mask final:fin];
                break;
            case WebSocketContinuation:
                [partial continuePayload:payload final:fin];
                break;
            default: {
                handler(WebSocketError(kWebSocketErrorProtocol, @"Bad OpCode", nil));
                return nil;
            }
        }
        data = [data subdataWithRange:NSMakeRange(headerSize, data.length - headerSize)];
    }
    return partial;
}


NSMutableArray* WebSocketPacket(NSData *data, WebSocketOpCode opCode, BOOL masked)
{
    NSUInteger headerSize = 2;
    NSUInteger dataSize = data.length;
    
    if (dataSize > UINT16_MAX) {
        headerSize += sizeof(uint64_t);
    } else if (data.length > 125) {
        headerSize += sizeof(uint16_t);
    }
    
    uint8_t mask[4];
    if (masked) {
        headerSize += sizeof(mask);
    }
    
    NSMutableData *header = [[NSMutableData alloc] initWithLength:headerSize + (masked ? dataSize : 0)];
    uint8_t *hbuf = header.mutableBytes;
    uint8_t *hptr = hbuf;

    *hptr++ = SignBitMask | (opCode & OpCodeMask);

    if (dataSize > UINT16_MAX) {
        *hptr++ = 127;
        *(uint64_t*)hptr = OSSwapHostToBigInt64(dataSize);
        hptr += sizeof(uint64_t);
    } else if (dataSize > 125) {
        *hptr++ = 126;
        *(uint16_t*)hptr = OSSwapHostToBigInt16(dataSize);
        hptr += sizeof(uint16_t);
    } else {
        *hptr++ = (uint8_t)dataSize;
    }

    if (masked) {
        hbuf[1] |= SignBitMask;
#if TARGET_OS_IPHONE
        int statusCode = SecRandomCopyBytes(kSecRandomDefault, sizeof(mask), (uint8_t *) &mask);
        NSCAssert(statusCode == 0, @"Unable to generate a mask: %d", statusCode);
#else
        NSData *random = [[NSFileHandle fileHandleForReadingAtPath:@"/dev/random"] readDataOfLength:sizeof(mask)];
        memcpy(&mask, random.bytes, sizeof(mask));
#endif
        memcpy(hptr, mask, sizeof(mask));
        hptr += sizeof(mask);
        memcpy(hptr, data.bytes, dataSize);
        _mask(hptr, dataSize, mask, 0);
        return [NSMutableArray arrayWithObject:header];
    } else {
        return [NSMutableArray arrayWithObjects:header, data, nil];
    }
}

inline static uint32_t _mask(uint8_t *dst, NSUInteger len, uint8_t mask[4], uint32_t off)
{
    for (; len; --len, ++dst, off = (off + 1) % sizeof(uint32_t)) {
        *dst ^= mask[off];
    }
    return off;
}
