//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

typedef enum  {
    WebSocketContinuation = 0x0,
    WebSocketTextFrame = 0x1,
    WebSocketBinaryFrame = 0x2,
    WebSocketConnectionClose = 0x8,
    WebSocketPing = 0x9,
    WebSocketPong = 0xA,
} WebSocketOpCode;


@interface WebSocketFrame : NSObject
@property (nonatomic, readonly) WebSocketOpCode opCode;
@property (nonatomic, strong, readonly) NSData *data;
@end


typedef void(^WSProtocolData)(NSData *data);
typedef void(^WSProtocolFrame)(WebSocketFrame *frame);
typedef void(^WSProtocolError)(NSError *error);


void WebSocketSend(NSData *data, WebSocketOpCode opCode, BOOL masked, WSProtocolData sender);

WebSocketFrame* WebSocketReceive(NSData *data, WebSocketFrame *partial, NSMutableData *cache, WSProtocolFrame receiver, WSProtocolError handler);
