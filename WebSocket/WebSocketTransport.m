//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketTransport.h"
#import "WebSocket.h"

@interface _WSTransportState : NSObject
@property (nonatomic, strong) NSRunLoop *runLoop;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableArray *queue;
@property (atomic, assign) BOOL connected;
- (id)read;
- (id)write:(NSArray*)datas;
@end


@interface WebSocketTransport () <NSStreamDelegate>
@property (atomic, strong) _WSTransportState *_state;
@end

@implementation WebSocketTransport
@synthesize host;
@synthesize port;
@synthesize secure;
@synthesize stateListener;
@synthesize receiver;
@synthesize errorHandler;
@synthesize _state = __state;

- (id)initWithHost:(NSString*)_host port:(NSUInteger)_port secure:(BOOL)_secure
{
    if (self = [super init]) {
        host = _host;
        port = _port;
        secure = _secure;
    }
    return self;
}

#pragma mark API

- (WebSocketTransportState)state
{
    _WSTransportState *st = self._state;
    return st ? st.connected ? WebSocketTransportOpen : WebSocketTransportConnecting : WebSocketTransportClosed;
}

- (void)openInRunLoop:(NSRunLoop *)runLoop
{
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, (UInt32)port, &readStream, &writeStream);

    if (secure) {
        CFReadStreamSetProperty(readStream, kCFStreamPropertySocketSecurityLevel, kCFStreamSocketSecurityLevelNegotiatedSSL);
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertySocketSecurityLevel, kCFStreamSocketSecurityLevelNegotiatedSSL);
#ifdef TARGET_IPHONE_SIMULATOR
        NSLog(@"WebSocketTransport: In debug mode. Allowing connection to any root cert");
        NSDictionary *sslOpt = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:(__bridge NSString*)kCFStreamSSLAllowsAnyRoot];
        CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, (__bridge CFDictionaryRef)sslOpt);
        CFWriteStreamSetProperty(writeStream, kCFStreamPropertySSLSettings, (__bridge CFDictionaryRef)sslOpt);
#endif
    }

    _WSTransportState *st = [_WSTransportState new];
    st.runLoop = runLoop;
    st.queue = [NSMutableArray new];
    st.inputStream = CFBridgingRelease(readStream);
    st.outputStream = CFBridgingRelease(writeStream);
    st.inputStream.delegate = self;
    st.outputStream.delegate = self;
    [st.inputStream scheduleInRunLoop:runLoop forMode:NSRunLoopCommonModes];
    [st.outputStream scheduleInRunLoop:runLoop forMode:NSRunLoopCommonModes];
    [st.inputStream open];
    [st.outputStream open];

    self._state = st;
    stateListener(self);
}

- (void)close
{
    self._state = nil;
    stateListener(self);
}

- (void)send:(NSArray*)datas
{
    _WSTransportState *st = self._state;
    if (!st) return;
    if ([NSRunLoop currentRunLoop] == st.runLoop) {
        [st write:datas];
    } else {
        CFRunLoopPerformBlock((__bridge CFRunLoopRef)st.runLoop, kCFRunLoopDefaultMode, ^{
            [st write:datas];
        });
    }
}

#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    _WSTransportState *st = self._state;
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (stream == st.inputStream || stream == st.outputStream) {
                BOOL notify = !st.connected;
                st.connected = YES;
                if (notify) {
                    stateListener(self);
                }
            }
            break;
        case NSStreamEventHasBytesAvailable:
            if (stream == st.inputStream) {
                id res = [st read];
                if ([res isKindOfClass:[NSData class]]) {
                    receiver(res);
                }
                if ([res isKindOfClass:[NSError class]]) {
                    errorHandler(res);
                }
            }
            break;
        case NSStreamEventHasSpaceAvailable:
            if (stream == st.outputStream) {
                id error = [st write:nil];
                if ([error isKindOfClass:[NSError class]]) {
                    errorHandler(error);
                }
            }
            break;
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
            if (stream == st.inputStream || stream == st.outputStream) {
                NSError *error = stream.streamError;
                if (error) {
                    errorHandler(error);
                }
                self._state = nil;
                stateListener(self);
            }
            break;
        default:
            break;
    }
}

@end


@implementation _WSTransportState
@synthesize runLoop;
@synthesize inputStream;
@synthesize outputStream;
@synthesize queue;
@synthesize connected;

- (id)read
{
    uint8_t buf[4096];
    NSInteger len = sizeof(buf);
    NSMutableData *data = [NSMutableData new];
    while (inputStream.hasBytesAvailable && len == sizeof(buf)) {
        NSInteger len = [inputStream read:buf maxLength:sizeof(buf)];
        if (len < 0) {
            return WebSocketError(kWebSocketErrorTransport, @"Read Failed", nil);
        }
        if (len > 0) {
            [data appendBytes:buf length:len];
        }
    }
    return data.length > 0 ? data : nil;
}

- (id)write:(NSArray*)datas
{
    if (datas) {
        [queue addObjectsFromArray:datas];
    }
    while (outputStream.hasSpaceAvailable && queue.count) {
        NSData *data = [queue objectAtIndex:0];
        NSInteger written = [outputStream write:data.bytes maxLength:data.length];
        if (written == -1) {
            return WebSocketError(kWebSocketErrorTransport, @"Write Failed", nil);
        }
        if (written < data.length) {
            NSData *left = [data subdataWithRange:NSMakeRange(written, data.length - written)];
            [queue replaceObjectAtIndex:0 withObject:left];
        } else {
            [queue removeObjectAtIndex:0];
        }
    }
    return nil;
}

- (void)dealloc
{
    [inputStream close];
    [outputStream close];
    inputStream.delegate = nil;
    outputStream.delegate = nil;
}

@end
