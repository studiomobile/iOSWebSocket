//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketTransport.h"
#import "WebSocket.h"

#ifdef WEBSOCKET_TRANSPORT_PRIVATE_QUEUE

#define CALL(call)   dispatch_async(work, ^{ call; })
#define HANDLE(call) dispatch_async(work, ^{ call; })
#define NOTIFY(call) dispatch_async(dispatch, ^{ call; })

#else

#define CALL(call)   call
#define HANDLE(call) dispatch_async(dispatch, ^{ call; })
#define NOTIFY(call) call

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
#ifdef WEBSOCKET_TRANSPORT_PRIVATE_QUEUE
    dispatch_queue_t work;
#endif
}
@synthesize delegate;
@synthesize host;
@synthesize port;
@synthesize secure;
@synthesize state = _state;
@synthesize receiver;

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
#ifdef WEBSOCKET_TRANSPORT_PRIVATE_QUEUE
    dispatch_release(work);
#endif
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

- (WSTransportData)sender
{
    return ^(NSData *data) {
        CALL([self _writeData:[data copy]]);
    };
}

#pragma mark Internals

- (void)_updateState:(WebSocketTransportState)state
{
    if (_state == state) return;
    _state = state;
    NOTIFY([self.delegate webSocketTransport:self didChangeState:_state]);
}

- (void)_openWithRunLoop:(NSRunLoop*)runLoop
{
    NSAssert(runLoop, @"WebSocketTransport should be opened with NSRunLoop");
    if (self.state != WebSocketTransportClosed) return;

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, port, &readStream, &writeStream);

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
            NOTIFY([delegate webSocketTransport:self didFailedWithError:error]);
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
            NOTIFY([delegate webSocketTransport:self didFailedWithError:error]);
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
        [self.delegate webSocketTransport:self didFailedWithError:error];
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
                HANDLE([self _updateState:WebSocketTransportOpen]);
            }
            break;
        case NSStreamEventHasBytesAvailable:
            if (stream == inputStream) {
                HANDLE([self _read]);
            }
            break;
        case NSStreamEventHasSpaceAvailable:
            if (stream == outputStream) {
                HANDLE([self _write]);
            }
            break;
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
            if (stream == inputStream || stream == outputStream) {
                HANDLE([self _closeWithError:stream.streamError]);
            }
            break;
    }
}

@end
