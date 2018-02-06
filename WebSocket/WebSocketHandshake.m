//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketHandshake.h"
#import "WebSocket.h"
#import <CommonCrypto/CommonDigest.h>
#import "NSData+Base64.h"

#define SEC_KEY_SIZE 16
#define WEB_SOCKET_GUID @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

NSString* WebSocketHandshakeSecKey(void)
{
#if TARGET_OS_IPHONE
    NSMutableData *key = [[NSMutableData alloc] initWithLength:SEC_KEY_SIZE];
    int statusCode = SecRandomCopyBytes(kSecRandomDefault, key.length, key.mutableBytes);
    NSCAssert(statusCode == 0, @"Unable to generate a handshake key: %d", statusCode);
#else
    NSData *key = [[NSFileHandle fileHandleForReadingAtPath:@"/dev/random"] readDataOfLength:SEC_KEY_SIZE];
#endif
    return [key base64EncodedString];
}

NSString* WebSocketHandshakeAccept(NSString *secKey)
{
    const char *bytes = [[secKey stringByAppendingString:WEB_SOCKET_GUID] cStringUsingEncoding:NSASCIIStringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(bytes, (CC_LONG)strlen(bytes), digest);
    return [[NSData dataWithBytesNoCopy:digest length:sizeof(digest) freeWhenDone:NO] base64EncodedString];
}

NSData* WebSocketHandshakeData(NSURLRequest *req, NSURL *origin, NSString *secKey, NSUInteger version)
{
    NSURL *url = req.URL;
    CFHTTPMessageRef handshake = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), (__bridge CFURLRef)url, kCFHTTPVersion1_1);
    // Set host first so it defaults
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Host"), (__bridge CFStringRef)(url.port ? [NSString stringWithFormat:@"%@:%@", url.host, url.port] : url.host));
    [req.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(handshake, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
    }];
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Upgrade"), CFSTR("websocket"));
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Connection"), CFSTR("Upgrade"));
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Sec-WebSocket-Key"), (__bridge CFStringRef)secKey);
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Sec-WebSocket-Version"), (__bridge CFStringRef)[NSString stringWithFormat:@"%d", (uint32_t)version]);
    if (origin) {
        CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Origin"), (__bridge CFStringRef)origin.absoluteString);
    }
    NSData *handshakeData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(handshake));
    CFRelease(handshake);
    return handshakeData;
}

id WebSocketHandshakeAcceptData(NSData *data, id state, NSString *accept, WSHandshakeError handler, WSHandshakeData completion)
{
    CFHTTPMessageRef resp = (__bridge CFHTTPMessageRef)state;
    if (!resp) {
        resp = CFHTTPMessageCreateEmpty(NULL, NO);
        state = (__bridge id)resp;
    }
    if (!CFHTTPMessageAppendBytes(resp, data.bytes, data.length)) {
        return state;
    }
    if (!CFHTTPMessageIsHeaderComplete(resp)) {
        return state;
    }
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(resp);
    if (responseCode != 101) {
        handler(WebSocketError(kWebSocketErrorHandshake, CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(resp)), nil));
        return nil;
    }
    NSDictionary *headers = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(resp));
    NSString *acceptHeader = [headers objectForKey:@"Sec-WebSocket-Accept"];
    if (!acceptHeader) {
        for (NSString *h in headers.allKeys) {
            if ([[h lowercaseString] isEqualToString:@"sec-websocket-accept"]) {
                acceptHeader = [headers objectForKey:h];
                break;
            }
        }
    }
    BOOL accepted = [accept isEqualToString:acceptHeader];
    if (!accepted) {
        handler(WebSocketError(kWebSocketErrorHandshake, @"Bad Sec-WebSocket-Accept header", nil));
        return nil;
    }
    NSData *left = CFBridgingRelease(CFHTTPMessageCopyBody(resp));
    completion(left);
    return nil;
}
