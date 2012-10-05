//
//  This content is released under the MIT License: http://www.opensource.org/licenses/mit-license.html
//

#import "ViewController.h"
#import "WebSocket.h"

#define SERVER_URL @"ws://localhost:9000"

@interface ViewController () <WebSocketDelegate>
@end

@implementation ViewController {
    WebSocket *socket;
}
@synthesize headerBar;
@synthesize containerView;
@synthesize inputField;
@synthesize outputView;

- (NSString*)stateText
{
    switch (socket.state) {
        case WebSocketOpen: return @"Connected";
        case WebSocketConnecting: return @"Connecting";
        case WebSocketClosed: return @"Disconnected";
        case WebSocketClosing: return @"Disconnecting";
    }
    return nil;
}

- (void)updateView
{
    NSMutableArray *items = [NSMutableArray new];
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:[self stateText] style:UIBarButtonItemStyleBordered target:self action:@selector(switchState)]];
    [items addObject:[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    if (socket.state == WebSocketOpen) {
        [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Ping" style:UIBarButtonItemStyleBordered target:self action:@selector(ping)]];
    }
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStyleBordered target:self action:@selector(clear)]];
    headerBar.items = items;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [self updateView];
}

#pragma mark Actions

- (void)switchState
{
    if (!socket) {
        socket = [[WebSocket alloc] initWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:SERVER_URL]]];
        socket.delegate = self;
    }
    if (socket.state == WebSocketOpen) {
        [socket close];
        socket = nil;
    } else
    if (socket.state == WebSocketClosed) {
        [socket open];
    }
}

- (void)ping
{
    [socket ping];
}

- (void)clear
{
    outputView.text = nil;
}

- (IBAction)cancelInput:(id)sender
{
    [inputField resignFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [socket sendString:textField.text];
    return YES;
}

- (void)appendText:(NSString*)text
{
    if (!outputView.text.length) {
        outputView.text = text;
    } else {
        outputView.text = [outputView.text stringByAppendingFormat:@"\n%@", text];
    }
}

#pragma mark WebSocketDelegate

- (void)webSocket:(WebSocket*)webSocket didChangeState:(WebSocketState)state
{
    [self updateView];
}

- (void)webSocket:(WebSocket*)webSocket didReceiveData:(NSData*)data
{
    [self appendText:[NSString stringWithFormat:@"Received %d bytes: %@", data.length, data]];
}

- (void)webSocket:(WebSocket*)webSocket didReceiveStringData:(NSData*)data
{
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self appendText:string];
}

- (void)webSocket:(WebSocket*)webSocket didReceivePongAfterDelay:(CFTimeInterval)delay
{
    [self appendText:[NSString stringWithFormat:@"Ping/pong (millis): %0.1f", delay * 1000]];
}

- (void)webSocket:(WebSocket*)webSocket didFailedWithError:(NSError*)error
{
    [[[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)webSocket:(WebSocket *)webSocket didCloseWithCode:(WebSocketCloseCode)code data:(NSData *)data
{
}

#pragma mark - Keyboard handling

- (void)animateFromKeyboardNotification:(NSNotification*)n
{
    [UIView beginAnimations:nil context:nil];
    [UIView setAnimationDuration:[[n.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[[n.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue]];
    CGRect frame = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view convertRect:frame fromView:self.view.window];
    CGRect containerFrame = containerView.frame;
    containerFrame.size.height = frame.origin.y - containerFrame.origin.y;
    containerView.frame = containerFrame;
    [UIView commitAnimations];
}

- (void)keyboardWillShow:(NSNotification*)n
{
    [self animateFromKeyboardNotification:n];
}

- (void)keyboardWillHide:(NSNotification*)n
{
    [self animateFromKeyboardNotification:n];
}

@end
