//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketTransport.h"
#import "WebSocket.h"

#define DISPATCH(queue, call) if (dispatch_get_current_queue() == queue) { call; } else dispatch_async(queue, ^{ call; })
#define CALL(call)   DISPATCH(work, call)
#define NOTIFY(call) DISPATCH(dispatch, call)

#if TARGET_OS_MAC
#undef dispatch_retain
#undef dispatch_release
#define dispatch_retain(q)
#define dispatch_release(q)
#endif

@interface WebSocketTransport () <NSStreamDelegate>
- (void)_openWithRunLoop:(NSRunLoop*)runLoop;
- (void)_writeData:(NSData*)data;
- (void)_closeWithError:(NSError*)error;
@end

@implementation WebSocketTransport {
    NSInputStream *inputStream;
    NSOutputStream *outputStream;
    NSMutableArray *pendingData;
    dispatch_queue_t dispatch;
    dispatch_queue_t work;
}
@synthesize host;
@synthesize port;
@synthesize secure;
@synthesize state = _state;
@synthesize stateListener;
@synthesize receiver;
@synthesize errorHandler;

- (id)initWithHost:(NSString*)_host port:(NSUInteger)_port secure:(BOOL)_secure dispatchQueue:(dispatch_queue_t)_dispatch
{
    if (self = [super init]) {
        host = _host;
        port = _port;
        secure = _secure;
        _state = WebSocketTransportClosed;
        dispatch = _dispatch ? _dispatch : dispatch_get_current_queue();
        dispatch_retain(dispatch);
#ifdef WEBSOCKET_TRANSPORT_PRIVATE_QUEUE
        work = dispatch_queue_create("WebSocketTransport Work Queue", DISPATCH_QUEUE_SERIAL);
#else
        work = dispatch_get_current_queue();
        dispatch_retain(work);
#endif
    }
    return self;
}

- (void)dealloc
{
    inputStream.delegate = nil;
    [inputStream close];
    outputStream.delegate = nil;
    [outputStream close];
    dispatch_release(dispatch);
    dispatch_release(work);
}

#pragma mark API

- (void)open
{
    [self openInRunLoop:[NSRunLoop currentRunLoop]];
}

- (void)openInRunLoop:(NSRunLoop *)runLoop
{
    CALL([self _openWithRunLoop:runLoop ? runLoop : [NSRunLoop mainRunLoop]]);
}

- (void)close
{
    CALL([self _closeWithError:nil]);
}

- (void)send:(NSData*)data
{
    CALL([self _writeData:data]);
}

#pragma mark Internals

- (void)_updateState:(WebSocketTransportState)state
{
    if (_state == state) return;
    _state = state;
    NOTIFY(stateListener(self));
}

- (void)_openWithRunLoop:(NSRunLoop*)runLoop
{
    NSAssert(runLoop, @"WebSocketTransport should be opened with NSRunLoop");
    if (self.state != WebSocketTransportClosed) return;

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

    inputStream = CFBridgingRelease(readStream);
    inputStream.delegate = self;
    [inputStream scheduleInRunLoop:runLoop forMode:NSRunLoopCommonModes];

    outputStream = CFBridgingRelease(writeStream);
    outputStream.delegate = self;
    [outputStream scheduleInRunLoop:runLoop forMode:NSRunLoopCommonModes];

    pendingData = [NSMutableArray new];
    [inputStream open];
    [outputStream open];
    [self _updateState:WebSocketTransportConnecting];
}

- (void)_read
{
    uint8_t buf[4096];
    while (inputStream.hasBytesAvailable) {
        NSInteger len = [inputStream read:buf maxLength:sizeof(buf)];
        if (len < 0) {
            NSError *error = WebSocketError(kWebSocketErrorTransport, @"Read Failed", nil);
            NOTIFY(errorHandler(error));
            return;
        }
        if (len > 0) {
            NSData *data = [NSData dataWithBytes:buf length:len];
            NOTIFY(receiver(data));
        }
    }
}

- (void)_write
{
    while (outputStream.hasSpaceAvailable && pendingData.count) {
        NSData *data = [pendingData objectAtIndex:0];
        NSInteger written = [outputStream write:data.bytes maxLength:data.length];
        if (written == -1) {
            NSError *error = WebSocketError(kWebSocketErrorTransport, @"Write Failed", nil);
            NOTIFY(errorHandler(error));
            return;
        }
        [pendingData removeObjectAtIndex:0];
        if (written < data.length) {
            NSData *left = [data subdataWithRange:NSMakeRange(written, data.length - written)];
            [pendingData insertObject:left atIndex:0];
            return;
        }
    }
}

- (void)_writeData:(NSData*)data
{
    [pendingData addObject:data];
    [self _write];
}

- (void)_closeWithError:(NSError*)error
{
    if (self.state == WebSocketTransportClosed) return;
    if (error) {
        errorHandler(error);
    }
    [inputStream close];
    [outputStream close];
    inputStream.delegate = nil;
    outputStream.delegate = nil;
    inputStream = nil;
    outputStream = nil;
    pendingData = nil;
    [self _updateState:WebSocketTransportClosed];
}

#pragma mark NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (stream == inputStream || stream == outputStream) {
                CALL([self _updateState:WebSocketTransportOpen]);
            }
            break;
        case NSStreamEventHasBytesAvailable:
            if (stream == inputStream) {
                CALL([self _read]);
            }
            break;
        case NSStreamEventHasSpaceAvailable:
            if (stream == outputStream) {
                CALL([self _write]);
            }
            break;
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
            if (stream == inputStream || stream == outputStream) {
                CALL([self _closeWithError:stream.streamError]);
            }
            break;
        default:
            break;
    }
}

@end
