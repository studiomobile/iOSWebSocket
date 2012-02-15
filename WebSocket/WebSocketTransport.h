//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

typedef enum {
    WebSocketTransportConnecting = 0,
    WebSocketTransportOpen = 1,
    WebSocketTransportClosed = 3,
} WebSocketTransportState;


typedef void(^WSTransportData)(NSData *data);


@protocol WebSocketTransportDelegate;


@interface WebSocketTransport : NSObject
@property (unsafe_unretained) id<WebSocketTransportDelegate> delegate;
@property (nonatomic, strong, readonly) NSString *host;
@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) BOOL secure;
@property (nonatomic, readonly) WebSocketTransportState state;

@property (nonatomic, copy, readonly) WSTransportData sender;
@property (nonatomic, copy) WSTransportData receiver;


- (id)initWithHost:(NSString*)host port:(NSUInteger)port secure:(BOOL)secure dispatchQueue:(dispatch_queue_t)dispatch;

- (void)open;
- (void)openInRunLoop:(NSRunLoop*)runLoop;
- (void)close;

@end


@protocol WebSocketTransportDelegate

- (void)webSocketTransport:(WebSocketTransport*)transport didChangeState:(WebSocketTransportState)state;

- (void)webSocketTransport:(WebSocketTransport*)transport didFailedWithError:(NSError*)error;

@end
