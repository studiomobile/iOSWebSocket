//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "WebSocketHandshake.h"
#import "WebSocket.h"
#import <CommonCrypto/CommonDigest.h>
#import "NSData+Base64.h"

#define WS_GUID @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

static NSString *GenAccept(NSString *secKey);
static NSString *GenSecKey(NSUInteger length);

@implementation WebSocketHandshake {
    NSString *secKey;
    NSString *accept;
    CFHTTPMessageRef _resp;
}
@synthesize delegate;
@synthesize request;
@synthesize origin;
@synthesize version;

- (id)initWithRequest:(NSURLRequest*)req origin:(NSURL*)_origin version:(NSUInteger)_version
{
    if (self = [super init]) {
        request = req;
        origin = _origin;
        version = _version;
        secKey = GenSecKey(16);
        accept = GenAccept(secKey);
    }
    return self;
}

- (void)dealloc
{
    if (_resp) CFRelease(_resp);
}

- (NSData*)handshakeData
{
    NSURL *url = request.URL;
    CFHTTPMessageRef handshake = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), (__bridge CFURLRef)url, kCFHTTPVersion1_1);
    // Set host first so it defaults
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Host"), (__bridge CFStringRef)(url.port ? [NSString stringWithFormat:@"%@:%@", url.host, url.port] : url.host));
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(handshake, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
    }];
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Upgrade"), CFSTR("websocket"));
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Connection"), CFSTR("Upgrade"));
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Sec-WebSocket-Key"), (__bridge CFStringRef)secKey);
    CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Sec-WebSocket-Version"), (__bridge CFStringRef)[NSString stringWithFormat:@"%d", version]);
    if (origin) {
        CFHTTPMessageSetHeaderFieldValue(handshake, CFSTR("Origin"), (__bridge CFStringRef)origin.absoluteString);
    }
    NSData *handshakeData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(handshake));
    CFRelease(handshake);
    return handshakeData;
}

- (BOOL)handleResponse:(CFHTTPMessageRef)resp error:(NSError**)error
{
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(resp);
    if (responseCode != 101) {
        if (*error) *error = WebSocketError(kWebSocketErrorHandshake, CFBridgingRelease(CFHTTPMessageCopyResponseStatusLine(resp)), nil);
        return NO;
    }
    NSDictionary *headers = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(resp));
    BOOL accepted = [accept isEqualToString:[headers objectForKey:@"Sec-WebSocket-Accept"]];
    if (!accepted) {
        if (*error) *error = WebSocketError(kWebSocketErrorHandshake, @"Bad Sec-WebSocket-Accept header", nil);
        return NO;
    }
    return YES;
}

- (void)acceptData:(NSData*)data
{
    if (!_resp) {
        _resp = CFHTTPMessageCreateEmpty(NULL, NO);
    }
    if (!CFHTTPMessageAppendBytes(_resp, data.bytes, data.length)) {
        return;
    }
    if (!CFHTTPMessageIsHeaderComplete(_resp)) {
        return;
    }
    NSError *error = nil;
    BOOL ok = [self handleResponse:_resp error:&error];
    CFRelease(_resp);
    _resp = nil;
    if (ok) {
        //TODO: check data left
        [delegate webSocketHandshake:self didFinishedWithDataLeft:nil];
    } else {
        [delegate webSocketHandshake:self didFailedWithError:error];
    }
}

@end

static NSString *GenAccept(NSString *secKey)
{
    const char *bytes = [[secKey stringByAppendingString:WS_GUID] cStringUsingEncoding:NSASCIIStringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(bytes, strlen(bytes), digest);
    return [[NSData dataWithBytesNoCopy:digest length:sizeof(digest) freeWhenDone:NO] base64EncodedString];
}

static NSString *GenSecKey(NSUInteger length)
{
    NSMutableData *key = [[NSMutableData alloc] initWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, key.length, key.mutableBytes);
    return [key base64EncodedString];
}
