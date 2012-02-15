//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        @try {
            return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
        }
        @catch (NSException *exception) {
            NSLog(@"%@", exception);
            @throw exception;
        }
    }
    return 0;
}
