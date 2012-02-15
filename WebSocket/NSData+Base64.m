//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "NSData+Base64.h"

#define XX 65
#define UNITS(arr) (sizeof(arr)/sizeof(arr[0]))

static const uint8_t encodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static const uint8_t decodingTable[256] =
{
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 62, XX, XX, XX, 63, 
    52, 53, 54, 55, 56, 57, 58, 59, 60, 61, XX, XX, XX, XX, XX, XX, 
    XX,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 
    15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, XX, XX, XX, XX, XX, 
    XX, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
    XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, XX, 
};


@implementation NSData (Base64)


+ (NSData*)dataWithBase64EncodedString:(NSString*)string
{
    if (string.length == 0) return [NSData new];

    const char *input = [string cStringUsingEncoding:NSASCIIStringEncoding];
    if (!input) return nil;
    const NSUInteger length = strlen(input);
    
    uint8_t *output = malloc(((length + 3) / 4) * 3);
    if (!output) return nil;
    
    NSUInteger in_p = 0;
    NSUInteger out_p = 0;

    uint8_t buf[4];
    NSUInteger len;
    
    while (TRUE) {
        for (len = 0; len < UNITS(buf) && in_p < length; ++in_p) {
            if (isspace(input[in_p]) || input[in_p] == '=')
                continue;
            
            buf[len] = decodingTable[input[in_p]];
            if (buf[len] == XX) { //  Illegal character!
                goto error;
            }
            ++len;
        }

        if (len == 0) break;

        if (len == 1) { //  At least two characters are needed to produce one byte!
            goto error;
        }
            
        //  Decode the characters in the buffer to bytes.
                     output[out_p++] = (buf[0] << 2) | (buf[1] >> 4);
        if (len > 2) output[out_p++] = (buf[1] << 4) | (buf[2] >> 2);
        if (len > 3) output[out_p++] = (buf[2] << 6) | buf[3];
    }
        
    return [NSData dataWithBytesNoCopy:output length:out_p freeWhenDone:YES];

error:
    free(output);
    return nil;
}
    

- (NSString *)base64EncodedString
{
    const uint8_t const *input = (uint8_t*)self.bytes;
    const NSUInteger length = self.length;
	if (!length) return @"";
    
    uint8_t *output = malloc(((length + 2) / 3) * 4);
	if (!output) return nil;
    
	NSUInteger in_p = 0;
	NSUInteger out_p = 0;
    
	while (in_p < length) {
        uint8_t buf[3] = {0, 0, 0};
        NSUInteger len = MIN(3, length - in_p);
        memcpy(buf, input + in_p, len);
        in_p += len;
		
		output[out_p++] = encodingTable[(buf[0] & 0xFC) >> 2];
		output[out_p++] = encodingTable[((buf[0] & 0x03) << 4) | ((buf[1] & 0xF0) >> 4)];
        
		if (len > 1) {
			output[out_p++] = encodingTable[((buf[1] & 0x0F) << 2) | ((buf[2] & 0xC0) >> 6)];
        } else {
            output[out_p++] = '=';
        }
        
		if (len > 2) {
			output[out_p++] = encodingTable[buf[2] & 0x3F];
        } else {
            output[out_p++] = '=';	
        }
	}
	
	return [[NSString alloc] initWithBytesNoCopy:output length:out_p encoding:NSASCIIStringEncoding freeWhenDone:YES];
}


@end
