//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <Foundation/Foundation.h>

@interface NSData (Base64)

+ (NSData*)dataWithBase64EncodedString:(NSString*)string;

- (NSString*)base64EncodedString;

@end
