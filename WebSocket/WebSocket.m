//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocket.h"
#import "WebSocketTransport.h"
#import "WebSocketProtocol.h"
#import "WebSocketHandshake.h"

NSString *kWebSocketErrorDomain = @"WebSocketErrorDomain";

@interface WebSocket () <WebSocketTransportDelegate, WebSocketHandshakeDelegate>
@property (nonatomic, strong) WebSocketFrame *partial;
@property (nonatomic, strong) NSMutableData *cache;
- (void)_handleFrame:(WebSocketFrame*)frame;
- (void)_closeWithError:(NSError*)error;
@end

#define CALL(call) dispatch_async(work, ^{ call; })
#define NOTIFY(call) dispatch_async(dispatch, ^{ call; })

@implementation WebSocket {
    WebSocketTransport *transport;
    WSProtocolData sender;
    WSProtocolData receiver;
    dispatch_queue_t work;
    dispatch_queue_t dispatch;
}
@synthesize delegate;
@synthesize request;
@synthesize origin;
@synthesize state;
@synthesize version;
@synthesize secure;
@synthesize partial;
@synthesize cache;

+ (NSArray*)supportedSchemes { return [NSArray arrayWithObjects:@"ws", @"wss", @"http", @"https", nil]; }
+ (NSArray*)secureSchemes { return [NSArray arrayWithObjects:@"wss", @"https", nil]; }

- (id)initWithRequest:(NSURLRequest*)_request origin:(NSURL*)_origin dispatchQueue:(dispatch_queue_t)_dispatch
{
    NSURL *url = _request.URL;
    if (![self.class.supportedSchemes containsObject:url.scheme]) return nil;
    if (self = [super init]) {
        request = _request;
        origin = _origin;
        state = WebSocketClosed;
        version = 13;
        secure = [self.class.secureSchemes containsObject:url.scheme];
        work = dispatch_queue_create("WebSocket Work Queue", DISPATCH_QUEUE_SERIAL);
        dispatch = _dispatch ? _dispatch : dispatch_get_current_queue();
        dispatch_retain(dispatch);
        cache = [NSMutableData new];
        NSUInteger port = url.port ? [url.port unsignedIntegerValue] : secure ? 443 : 80;
        transport = [[WebSocketTransport alloc] initWithHost:url.host port:port secure:secure dispatchQueue:work];
        transport.delegate = self;
        sender = transport.sender;
        __block __typeof__(self) me = self;
        receiver = ^(NSData *data) {
            me.partial = WebSocketReceive(data, me.partial, me.cache, ^(WebSocketFrame *frame) {
                [me _handleFrame:frame];
            }, ^(NSError *error) {
                [me _closeWithError:error];
            });
        };
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest*)_request
{
    return [self initWithRequest:_request origin:nil dispatchQueue:nil];
}

- (id)initWithRequest:(NSURLRequest*)_request origin:(NSURL*)_origin
{
    return [self initWithRequest:_request origin:_origin dispatchQueue:nil];
}

- (void)dealloc
{
    dispatch_release(work);
    dispatch_release(dispatch);
}

#pragma mark API

- (void)open
{
    [transport open];
}

- (void)openInRunLoop:(NSRunLoop*)runLoop
{
    [transport openInRunLoop:runLoop];
}

- (void)close
{
    [transport close];
}

- (void)sendString:(NSString*)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    CALL(WebSocketSend(data, WebSocketTextFrame, YES, sender));
}

- (void)sendData:(NSData*)data
{
    CALL(WebSocketSend(data, WebSocketBinaryFrame, YES, sender));
}

- (void)sendClose:(NSString*)message code:(uint16_t)code
{
    code = htons(code);
    NSMutableData *data = [NSMutableData dataWithBytes:&code length:sizeof(code)];
    if (message.length) {
        [data appendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    }
    WebSocketSend(data, WebSocketConnectionClose, YES, sender);
}

- (void)ping
{
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    NSData *data = [NSData dataWithBytes:&time length:sizeof(time)];
    CALL(WebSocketSend(data, WebSocketPing, YES, sender));
}

#pragma mark Internals

- (void)_updateState:(WebSocketState)_state
{
    if (state == _state) return;
    state = _state;
    if (state == WebSocketClosed) {
        partial = nil;
        [cache setLength:0];
    }
    NOTIFY([delegate webSocket:self didChangeState:state]);
}

- (void)_closeWithError:(NSError*)error
{
    if (error) {
        NOTIFY([delegate webSocket:self didFailedWithError:error]);
    }
    transport.receiver = nil;
    [transport close];
}

- (void)_handleFrame:(WebSocketFrame*)frame
{
    switch (frame.opCode) {
        case WebSocketTextFrame: {
            NOTIFY([delegate webSocket:self didReceiveStringData:frame.data]);
        }   break;
        case WebSocketBinaryFrame: {
            NOTIFY([delegate webSocket:self didReceiveData:frame.data]);
        }   break;
        case WebSocketPong: {
            NSData *data = frame.data;
            CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
            if (data.length != sizeof(time)) return;
            CFAbsoluteTime was = *(CFAbsoluteTime*)data.bytes;
            NOTIFY([delegate webSocket:self didReceivePongAfterDelay:time - was]);
        }   break;
        case WebSocketConnectionClose:
            //TODO: check close code
            [self _closeWithError:nil];
            break;
        default:
            break;
    }
}

- (void)_startHandshake
{
    WebSocketHandshake * handshake = [[WebSocketHandshake alloc] initWithRequest:request origin:origin version:version];
    handshake.delegate = self;
    transport.receiver = ^(NSData *data) {
        [handshake acceptData:data];
    };
    sender(handshake.handshakeData);
}

#pragma mark WebSocketHandshakeDelegate

- (void)webSocketHandshake:(WebSocketHandshake*)_handshake didFinishedWithDataLeft:(NSData*)data
{
    transport.receiver = receiver;
    [self _updateState:WebSocketOpen];
    if (data) {
        receiver(data);
    }
}

- (void)webSocketHandshake:(WebSocketHandshake*)handshake didFailedWithError:(NSError*)error
{
    [self _closeWithError:error];
}

#pragma mark WebSocketTransportDelegate

- (void)webSocketTransport:(WebSocketTransport*)_transport didChangeState:(WebSocketTransportState)_state
{
    switch (_state) {
        case WebSocketTransportConnecting:
            [self _updateState:WebSocketConnecting];
            break;
        case WebSocketTransportOpen:
            [self _startHandshake];
            break;
        case WebSocketTransportClosed:
            [self _updateState:WebSocketClosed];
            break;
    }
}

- (void)webSocketTransport:(WebSocketTransport*)transport didFailedWithError:(NSError*)error
{
    [self _closeWithError:error];
}

@end

NSError* WebSocketError(NSInteger code, NSString *message, NSString *reason)
{
    NSMutableDictionary *info = [NSMutableDictionary new];
    if (message) {
        [info setObject:message forKey:NSLocalizedDescriptionKey];
    }
    if (reason) {
        [info setObject:reason forKey:NSLocalizedFailureReasonErrorKey];
    }
    return [NSError errorWithDomain:kWebSocketErrorDomain code:code userInfo:info];
}
