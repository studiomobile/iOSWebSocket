//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

@protocol WebSocketHandshakeDelegate;


@interface WebSocketHandshake : NSObject
@property (nonatomic, unsafe_unretained) id<WebSocketHandshakeDelegate> delegate;
@property (nonatomic, strong, readonly) NSURLRequest *request;
@property (nonatomic, strong, readonly) NSURL *origin;
@property (nonatomic, readonly) NSUInteger version;
@property (nonatomic, strong, readonly) NSData *handshakeData;

- (id)initWithRequest:(NSURLRequest*)req origin:(NSURL*)origin version:(NSUInteger)version;

- (void)acceptData:(NSData*)data;

@end


@protocol WebSocketHandshakeDelegate

- (void)webSocketHandshake:(WebSocketHandshake*)handshake didFinishedWithDataLeft:(NSData*)data;

- (void)webSocketHandshake:(WebSocketHandshake*)handshake didFailedWithError:(NSError*)error;

@end
