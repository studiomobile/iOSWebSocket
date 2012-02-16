//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocket.h"
#import "WebSocketTransport.h"
#import "WebSocketProtocol.h"
#import "WebSocketHandshake.h"

NSString *kWebSocketErrorDomain = @"WebSocketErrorDomain";

typedef void(^WSSocketNotifierCallback)(WebSocket *socket, id<WebSocketDelegate> delegate);
typedef void(^WSSocketNotifier)(WSSocketNotifierCallback callback);

@interface WebSocketStateHolder : NSObject
@property (nonatomic, readonly) WebSocketState state;
@property (nonatomic, copy) WSSocketNotifier notifier;
@property (nonatomic, copy) WSProtocolData sender;
@property (nonatomic, copy) WSProtocolData receiver;
@property (nonatomic, copy) WSProtocolError errorHandler;
@property (nonatomic, copy) WSProtocolFrame frameReceiver;
@property (nonatomic, copy) WSHandshakeData receiveHandshake;
@property (nonatomic, copy) WSHandshakeData handshakeComplete;
@property (nonatomic, strong) id handshake;
@property (nonatomic, strong) NSString *accept;
@property (nonatomic, strong) WebSocketFrame *frame;
@property (nonatomic, strong, readonly) NSMutableData *cache;
- (void)update:(WebSocketState)state;
@end

#define CALL(call) dispatch_async(work, ^{ call; })

@implementation WebSocket {
    WebSocketStateHolder *state;
    WebSocketTransport *transport;
    WSProtocolData sender;
    dispatch_queue_t work;
    dispatch_queue_t dispatch;
}
@synthesize request;
@synthesize origin;
@synthesize version;
@synthesize secure;

+ (NSArray*)supportedSchemes { return [NSArray arrayWithObjects:@"ws", @"wss", @"http", @"https", nil]; }
+ (NSArray*)secureSchemes { return [NSArray arrayWithObjects:@"wss", @"https", nil]; }

- (id)initWithRequest:(NSURLRequest*)_request origin:(NSURL*)_origin delegate:(id<WebSocketDelegate>)__delegate dispatchQueue:(dispatch_queue_t)_dispatch
{
    NSURL *url = _request.URL;
    if (![self.class.supportedSchemes containsObject:url.scheme]) return nil;
    if (self = [super init]) {
        request = _request;
        origin = _origin;
        secure = [self.class.secureSchemes containsObject:url.scheme];
        NSUInteger port = url.port ? [url.port unsignedIntegerValue] : secure ? 443 : 80;
        NSUInteger _version = version = 13;

        work = dispatch_queue_create("WebSocket Work Queue", DISPATCH_QUEUE_SERIAL);
        if (!_dispatch) _dispatch = dispatch_get_main_queue();
        dispatch = _dispatch;
        dispatch_retain(dispatch);

        __unsafe_unretained WebSocket *me = self;
        __unsafe_unretained id<WebSocketDelegate> _delegate = __delegate;

        WebSocketStateHolder *_state = state = [WebSocketStateHolder new];
        WebSocketTransport *_transport = transport = [[WebSocketTransport alloc] initWithHost:url.host port:port secure:secure dispatchQueue:work];

        WSSocketNotifier _notify = state.notifier = ^(WSSocketNotifierCallback callback) {
            dispatch_async(_dispatch, ^{
                callback(me, _delegate);
            });
        };

        WSProtocolData _sender = sender = state.sender = ^(NSData *data) {
            [_transport send:data];
        };

        WSProtocolError _errorHandler = state.errorHandler = ^(NSError *error) {
            if (error) {
                _notify(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
                    [delegate webSocket:socket didFailedWithError:error];
                });
            }
            [_transport close];
        };

        WSProtocolFrame _frameReceiver = state.frameReceiver = ^(WebSocketFrame *frame) {
            switch (frame.opCode) {
                case WebSocketTextFrame: {
                    _notify(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
                        [delegate webSocket:socket didReceiveStringData:frame.data];
                    });
                }   break;
                case WebSocketBinaryFrame: {
                    _notify(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
                        [delegate webSocket:me didReceiveData:frame.data];
                    });
                }   break;
                case WebSocketPong: {
                    NSData *data = frame.data;
                    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
                    if (data.length != sizeof(time)) return;
                    CFAbsoluteTime was = *(CFAbsoluteTime*)data.bytes;
                    _notify(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
                        [_delegate webSocket:me didReceivePongAfterDelay:time - was];
                    });
                }   break;
                case WebSocketPing:
                    WebSocketSend(frame.data, WebSocketPong, YES, _sender);
                    break;
                case WebSocketConnectionClose:
                    //TODO: check close code
                    _errorHandler(nil);
                    break;
                default:
                    break;
            }
        };

        WSProtocolData _receiver = state.receiver = ^(NSData *data) {
            _state.frame = WebSocketReceive(data, _state.frame, _state.cache, _frameReceiver, _errorHandler);
        };

        WSHandshakeData _handshakeComplete = state.handshakeComplete = ^(NSData *data) {
            _transport.receiver = _receiver;
            [_state update:WebSocketOpen];
            if (data) {
                _receiver(data);
            }
        };

        WSHandshakeData _receiveHandshake = state.receiveHandshake = ^(NSData *data) {
            _state.handshake = WebSocketHandshakeAcceptData(data, _state.handshake, _state.accept, _errorHandler, _handshakeComplete);
        };

        transport.errorHandler = _errorHandler;
        transport.stateListener = ^(WebSocketTransport *tr) {
            switch (tr.state) {
                case WebSocketTransportConnecting:
                    [_state update:WebSocketConnecting];
                    break;
                case WebSocketTransportOpen: {
                    NSString *secKey = WebSocketHandshakeSecKey();
                    _state.accept = WebSocketHandshakeAccept(secKey);
                    tr.receiver = _receiveHandshake;
                    _sender(WebSocketHandshakeData(_request, _origin, secKey, _version));
                }   break;
                case WebSocketTransportClosed:
                    tr.receiver = nil;
                    [_state update:WebSocketClosed];
                    break;
            }
        };
    }
    return self;
}

- (id)initWithRequest:(NSURLRequest*)_request delegate:(id<WebSocketDelegate>)_delegate
{
    return [self initWithRequest:_request origin:nil delegate:_delegate dispatchQueue:nil];
}

- (id)initWithRequest:(NSURLRequest*)_request origin:(NSURL*)_origin delegate:(id<WebSocketDelegate>)_delegate
{
    return [self initWithRequest:_request origin:_origin delegate:_delegate dispatchQueue:nil];
}

- (void)dealloc
{
    state.notifier = ^(WSSocketNotifierCallback _) {};
    [transport close];
    dispatch_sync(work, ^{}); // wait for completion
    dispatch_release(work);
    dispatch_release(dispatch);
}

#pragma mark API

- (WebSocketState)state
{
    return state.state;
}

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
    [self closeWithMessage:nil code:WebSocketCloseNormal];
}

- (void)closeWithMessage:(NSString*)message code:(WebSocketCloseCode)_code
{
    uint16_t code = OSSwapHostToBigInt16(_code);
    NSMutableData *data = [NSMutableData dataWithBytes:&code length:sizeof(code)];
    if (message.length) {
        [data appendData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    }
    CALL(WebSocketSend(data, WebSocketConnectionClose, YES, sender));
    CALL([state update:WebSocketClosing]);
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

- (void)ping
{
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    NSData *data = [NSData dataWithBytes:&time length:sizeof(time)];
    CALL(WebSocketSend(data, WebSocketPing, YES, sender));
}

@end


@implementation WebSocketStateHolder
@synthesize state;
@synthesize notifier;
@synthesize sender;
@synthesize receiver;
@synthesize errorHandler;
@synthesize frameReceiver;
@synthesize receiveHandshake;
@synthesize handshakeComplete;
@synthesize handshake;
@synthesize accept;
@synthesize frame;
@synthesize cache;

- (id)init
{
    if (self = [super init]) {
        state = WebSocketClosed;
        cache = [NSMutableData new];
    }
    return self;
}

- (void)update:(WebSocketState)_state
{
    if (state == _state) return;
    state = _state;
    if (state == WebSocketClosed) {
        frame = nil;
        [cache setLength:0];
    }
    notifier(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
        [delegate webSocket:socket didChangeState:_state];
    });
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
