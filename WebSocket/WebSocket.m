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
@property (nonatomic, unsafe_unretained) id<WebSocketDelegate> delegate;
@property (nonatomic, readonly) WebSocketState state;
@property (nonatomic, copy) WSSocketNotifier notifier;
@property (nonatomic, copy) WSProtocolError errorHandler;
@property (nonatomic, copy) WSProtocolFrame frameReceiver;
@property (nonatomic, copy) WSHandshakeData handshakeComplete;
@property (nonatomic, strong) id handshake;
@property (nonatomic, strong) NSString *accept;
@property (nonatomic, strong) WebSocketFrame *frame;
@property (nonatomic, strong, readonly) NSMutableData *cache;
- (void)update:(WebSocketState)state;
@end

@implementation WebSocket {
    WebSocketStateHolder *state;
    WebSocketTransport *transport;
}
@synthesize request;
@synthesize origin;
@synthesize version;
@synthesize secure;

+ (NSArray*)supportedSchemes { return [NSArray arrayWithObjects:@"ws", @"wss", @"http", @"https", nil]; }
+ (NSArray*)secureSchemes { return [NSArray arrayWithObjects:@"wss", @"https", nil]; }

- (id)initWithRequest:(NSURLRequest*)_request origin:(NSURL*)_origin
{
    NSURL *url = _request.URL;
    if (![self.class.supportedSchemes containsObject:url.scheme]) return nil;
    if (self = [super init]) {
        request = _request;
        origin = _origin;
        secure = [self.class.secureSchemes containsObject:url.scheme];
        NSUInteger port = url.port ? [url.port unsignedIntegerValue] : secure ? 443 : 80;
        NSUInteger _version = version = 13;

        WebSocketStateHolder *_state = state = [WebSocketStateHolder new];
        WebSocketTransport *_transport = transport = [[WebSocketTransport alloc] initWithHost:url.host port:port secure:secure];

        __unsafe_unretained WebSocket *_me = self;
        WSSocketNotifier _notify = state.notifier = ^(WSSocketNotifierCallback callback) {
            id<WebSocketDelegate> _delegate = _state.delegate;
            if (_delegate) {
                callback(_me, _delegate);
            }
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
                        [delegate webSocket:socket didReceiveData:frame.data];
                    });
                }   break;
                case WebSocketPong: {
                    NSData *data = frame.data;
                    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
                    if (data.length != sizeof(time)) return;
                    CFAbsoluteTime was = *(CFAbsoluteTime*)data.bytes;
                    _notify(^(WebSocket *socket, id<WebSocketDelegate> delegate) {
                        [delegate webSocket:socket didReceivePongAfterDelay:time - was];
                    });
                }   break;
                case WebSocketPing: {
                    NSArray *packet = WebSocketPacket(frame.data, WebSocketPong, YES);
                    [_transport send:packet];
                }   break;
                case WebSocketConnectionClose:
                    //TODO: check close code
                    _errorHandler(nil);
                    break;
                default:
                    break;
            }
        };

        WSHandshakeData _handshakeComplete = state.handshakeComplete = ^(NSData *data) {
            WSTransportData _receiver = _transport.receiver = ^(NSData *data) {
                _state.frame = WebSocketReceive(data, _state.frame, _state.cache, _frameReceiver, _errorHandler);
            };
            [_state update:WebSocketOpen];
            if (data) {
                _receiver(data);
            }
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
                    tr.receiver = ^(NSData *data) {
                        _state.handshake = WebSocketHandshakeAcceptData(data, _state.handshake, _state.accept, _errorHandler, _handshakeComplete);
                    };
                    NSData *data = WebSocketHandshakeData(_request, _origin, secKey, _version);
                    [tr send:[NSArray arrayWithObject:data]];
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

- (void)dealloc
{
    state.notifier = ^(WSSocketNotifierCallback _) {};
    [transport close];
}

#pragma mark API

- (id<WebSocketDelegate>)delegate
{
    return state.delegate;
}

- (void)setDelegate:(id<WebSocketDelegate>)delegate
{
    state.delegate = delegate;
}

- (WebSocketState)state
{
    return state.state;
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
    NSArray *packet = WebSocketPacket(data, WebSocketConnectionClose, YES);
    [transport send:packet];
    [state update:WebSocketClosing];
}

- (void)sendString:(NSString*)string
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *packet = WebSocketPacket(data, WebSocketTextFrame, YES);
    [transport send:packet];
}

- (void)sendData:(NSData*)data
{
    NSArray *packet = WebSocketPacket(data, WebSocketBinaryFrame, YES);
    [transport send:packet];
}

- (void)ping
{
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    NSData *data = [NSData dataWithBytes:&time length:sizeof(time)];
    NSArray *packet = WebSocketPacket(data, WebSocketPing, YES);
    [transport send:packet];
}

@end


@implementation WebSocketStateHolder
@synthesize delegate=_delegate;
@synthesize state;
@synthesize notifier;
@synthesize errorHandler;
@synthesize frameReceiver;
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
