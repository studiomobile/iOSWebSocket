//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

typedef void (^WSHandshakeError)(NSError *error);
typedef void (^WSHandshakeData)(NSData *leftData);

NSString* WebSocketHandshakeSecKey(void);
NSString* WebSocketHandshakeAccept(NSString *secKey);
NSData*   WebSocketHandshakeData(NSURLRequest *req, NSURL *origin, NSString *secKey, NSUInteger version);

id WebSocketHandshakeAcceptData(NSData *data, id state, NSString *accept, WSHandshakeError handler, WSHandshakeData completion);