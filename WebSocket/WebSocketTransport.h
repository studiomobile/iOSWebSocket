//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

typedef enum {
    WebSocketTransportConnecting = 0,
    WebSocketTransportOpen = 1,
    WebSocketTransportClosed = 3,
} WebSocketTransportState;

@class WebSocketTransport;

typedef void(^WSTransportListener)(WebSocketTransport *transport);
typedef void(^WSTransportData)(NSData *data);
typedef void(^WSTransportError)(NSError *error);


@interface WebSocketTransport : NSObject
@property (nonatomic, readonly, strong) NSString *host;
@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) BOOL secure;
@property (nonatomic, readonly) WebSocketTransportState state;

@property (nonatomic, copy) WSTransportListener stateListener;
@property (nonatomic, copy) WSTransportData receiver;
@property (nonatomic, copy) WSTransportError errorHandler;


- (id)initWithHost:(NSString*)host port:(NSUInteger)port secure:(BOOL)secure dispatchQueue:(dispatch_queue_t)dispatch;

- (void)open;
- (void)openInRunLoop:(NSRunLoop*)runLoop;
- (void)close;

- (void)send:(NSData*)data;

@end

