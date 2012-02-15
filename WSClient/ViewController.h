//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) IBOutlet UIToolbar *headerBar;
@property (nonatomic, strong) IBOutlet UIView *containerView;
@property (nonatomic, strong) IBOutlet UITextField *inputField;
@property (nonatomic, strong) IBOutlet UITextView *outputView;

- (IBAction)cancelInput:(id)sender;

@end
