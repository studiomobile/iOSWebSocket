//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

typedef enum {
    WebSocketClosed = 0,
    WebSocketClosing = 1,
    WebSocketConnecting = 2,
    WebSocketOpen = 3,
} WebSocketState;

typedef enum {
    WebSocketCloseNormal     = 1000,
    WebSocketCloseAway       = 1001,
    WebSocketCloseError      = 1002,
    WebSocketCloseTypeError  = 1003,
    WebSocketCloseNoStatus   = 1005,
    WebSocketCloseAbnormally = 1006,
    WebSocketCloseBadData    = 1007,
    WebSocketClosePolicy     = 1008,
    WebSocketCloseTooBig     = 1009,
    WebSocketCloseExtensions = 1010,
    WebSocketCloseUnexpected = 1011,
    WebSocketCloseTLS        = 1015,
} WebSocketCloseCode;


extern NSString *kWebSocketErrorDomain;

enum {
    kWebSocketErrorHandshake = 100,
    kWebSocketErrorTransport = 101,
    kWebSocketErrorProtocol  = 102,
};

NSError* WebSocketError(NSInteger code, NSString *message, NSString *reason);

@protocol WebSocketDelegate;

@interface WebSocket : NSObject
@property (nonatomic, strong, readonly) NSURLRequest *request;
@property (nonatomic, strong, readonly) NSURL *origin;
@property (nonatomic, readonly) WebSocketState state;
@property (nonatomic, readonly) NSUInteger version;
@property (nonatomic, readonly) BOOL secure;

+ (NSArray*)supportedSchemes;
+ (NSArray*)secureSchemes;

- (id)initWithRequest:(NSURLRequest*)request delegate:(id<WebSocketDelegate>)delegate;
- (id)initWithRequest:(NSURLRequest*)request origin:(NSURL*)origin delegate:(id<WebSocketDelegate>)delegate;
- (id)initWithRequest:(NSURLRequest*)request origin:(NSURL*)origin delegate:(id<WebSocketDelegate>)delegate dispatchQueue:(dispatch_queue_t)dispatch;

- (void)open;
- (void)openInRunLoop:(NSRunLoop*)runLoop;
- (void)close;
- (void)closeWithMessage:(NSString*)message code:(WebSocketCloseCode)code;

- (void)sendString:(NSString*)string;
- (void)sendData:(NSData*)data;

- (void)ping;

@end


@protocol WebSocketDelegate
- (void)webSocket:(WebSocket*)webSocket didChangeState:(WebSocketState)state;
- (void)webSocket:(WebSocket*)webSocket didReceiveData:(NSData*)data;
- (void)webSocket:(WebSocket*)webSocket didReceiveStringData:(NSData*)data;
- (void)webSocket:(WebSocket*)webSocket didReceivePongAfterDelay:(CFTimeInterval)delay;
- (void)webSocket:(WebSocket*)webSocket didFailedWithError:(NSError*)error;
@end
