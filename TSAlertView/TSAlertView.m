//
//  TSAlertView.m
//
//  Created by Nick Hodapp aka Tom Swift on 1/19/11.
//

#import "TSAlertView.h"
#import <QuartzCore/QuartzCore.h>

@interface TSAlertOverlayWindow : UIWindow
{
}
@property (nonatomic,retain) UIWindow* oldKeyWindow;
@end

@implementation  TSAlertOverlayWindow
@synthesize oldKeyWindow;

- (void) makeKeyAndVisible
{
	self.oldKeyWindow = [[UIApplication sharedApplication] keyWindow];
	self.windowLevel = UIWindowLevelAlert;
	[super makeKeyAndVisible];
}

- (void) resignKeyWindow
{
	[super resignKeyWindow];
	[self.oldKeyWindow makeKeyWindow];
}

- (void) drawRect: (CGRect) rect
{
	// render the radial gradient behind the alertview
	
	CGFloat width			= self.frame.size.width;
	CGFloat height			= self.frame.size.height;
	CGFloat locations[3]	= { 0.0, 0.5, 1.0 	};
	CGFloat components[12]	= {	1, 1, 1, 0.5,
		0, 0, 0, 0.5,
		0, 0, 0, 0.7	};
	
	CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
	CGGradientRef backgroundGradient = CGGradientCreateWithColorComponents(colorspace, components, locations, 3);
	CGColorSpaceRelease(colorspace);
	
	CGContextDrawRadialGradient(UIGraphicsGetCurrentContext(), 
								backgroundGradient, 
								CGPointMake(width/2, height/2), 0,
								CGPointMake(width/2, height/2), width,
								0);
	
	CGGradientRelease(backgroundGradient);
}

- (void) dealloc
{
	self.oldKeyWindow = nil;
	
	NSLog( @"TSAlertView: TSAlertOverlayWindow dealloc" );
}

@end

@interface TSAlertView (private)
@property (nonatomic, readonly) NSMutableArray* buttons;
@property (nonatomic, readonly) UILabel* titleLabel;
@property (nonatomic, readonly) UILabel* messageLabel;
@property (nonatomic, readonly) UITextView* messageTextView;
- (void) TSAlertView_commonInit;
- (void) releaseWindow: (int) buttonIndex;
- (void) pulse;
- (CGSize) titleLabelSize;
- (CGSize) messageLabelSize;
- (CGSize) inputTextFieldSize;
- (CGSize) buttonsAreaSize_Stacked;
- (CGSize) buttonsAreaSize_SideBySide;
- (CGSize) recalcSizeAndLayout: (BOOL) layout;
@end

@interface TSAlertViewController : UIViewController
{
}
@end

@implementation TSAlertViewController

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
	return YES;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
	TSAlertView* av = [self.view.subviews lastObject];
	if (!av || ![av isKindOfClass:[TSAlertView class]])
		return;
	// resize the alertview if it wants to make use of any extra space (or needs to contract)
	[UIView animateWithDuration:duration 
					 animations:^{
						 [av sizeToFit];
						 av.center = CGPointMake( CGRectGetMidX( self.view.bounds ), CGRectGetMidY( self.view.bounds ) );;
						 av.frame = CGRectIntegral( av.frame );
					 }];
}

- (void) dealloc
{
	NSLog( @"TSAlertView: TSAlertViewController dealloc" );
}

@end


@implementation TSAlertView

@synthesize delegate;
@synthesize cancelButtonIndex;
@synthesize firstOtherButtonIndex;
@synthesize buttonLayout;
@synthesize width;
@synthesize maxHeight;
@synthesize usesMessageTextView;
@synthesize backgroundImage = _backgroundImage;
@synthesize style;
@synthesize resourceBundle = _res;
@synthesize hasButtons = _hasButtons;
@synthesize alertViewController = _alertViewController;
@synthesize overlayWindow = _overlayWindow;

@synthesize messageFont = _messageFont;
@synthesize messageShadowOffset = _messageShadowOffset;
@synthesize buttonsTextShadowOffset = _buttonsTextShadowOffset;
@synthesize messageShadowColor = _messageShadowColor;
@synthesize buttonsTextColor = _buttonsTextColor;
@synthesize buttonsTextShadowColor = _buttonsShadowColor;

const CGFloat kTSAlertView_LeftMargin	= 18.0;
const CGFloat kTSAlertView_TopMargin	= 16.0;
const CGFloat kTSAlertView_BottomMargin = 22.0;
const CGFloat kTSAlertView_RowMargin	= 8.0;
const CGFloat kTSAlertView_ColumnMargin = 10.0;

#pragma mark --Init block

- (id) init
{
	if ( ( self = [super init] ) )
	{
		[self TSAlertView_commonInit];
	}
	return self;
}

-(id) initWithResBundleName:(NSString *)bundleName {
    if (self=[self init]) {
        self.resourceBundle = [NSBundle bundleWithPath:[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:  [bundleName stringByAppendingString:@".bundle"]]];
        if (!self.resourceBundle)  self.resourceBundle = [NSBundle mainBundle];
    }
    
    return self;
}

- (id) initWithFrame:(CGRect)frame
{
	if ( ( self = [super initWithFrame: frame] ) )
	{
		[self TSAlertView_commonInit];
		
		if ( !CGRectIsEmpty( frame ) )
		{
			width = frame.size.width;
			maxHeight = frame.size.height;
		}
	}
	return self;
}

- (id) initWithTitle: (NSString *) t message: (NSString *) m delegate: (id) d cancelButtonTitle: (NSString *) cancelButtonTitle otherButtonTitles: (NSString *) otherButtonTitles, ...
{
	if ( (self = [super init] ) ) // will call into initWithFrame, thus TSAlertView_commonInit is called
	{
		self.title = t;
		self.message = m;
		self.delegate = d;
		
		if ( nil != cancelButtonTitle )
		{
			[self addButtonWithTitle: cancelButtonTitle ];
			self.cancelButtonIndex = 0;
		}
		
		if ( nil != otherButtonTitles )
		{
			firstOtherButtonIndex = [self.buttons count];
			[self addButtonWithTitle: otherButtonTitles ];
			
			va_list args;
			va_start(args, otherButtonTitles);
			
			id arg;
			while ( nil != ( arg = va_arg( args, id ) ) ) 
			{
				if ( ![arg isKindOfClass: [NSString class] ] )
					return nil;
				
				[self addButtonWithTitle: (NSString*)arg ];
			}
		}
	}
	
	return self;
}

- (void) TSAlertView_commonInit
{
	self.backgroundColor = [UIColor clearColor];
	self.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
	
	// defaults:
	style = TSAlertViewStyleNormal;
	self.width = 0; // set to default
	self.maxHeight = 0; // set to default
	buttonLayout = TSAlertViewButtonLayoutNormal;
	cancelButtonIndex = -1;
	firstOtherButtonIndex = -1;
    [self setMessageFont:[UIFont systemFontOfSize:14]];

    [self.buttons addObject:[[UIButton alloc] initWithFrame:CGRectMake(0, 0, 0, 0)]];
    self.hasButtons = NO;
}

#pragma mark --Deallocate

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self ];
	
	NSLog( @"TSAlertView: TSAlertOverlayWindow dealloc" );
}

#pragma mark --Overloaded parent methods
- (CGSize) sizeThatFits: (CGSize) unused 
{
	CGSize s = [self recalcSizeAndLayout: NO];
	return s;
}

- (void) layoutSubviews
{
	[self recalcSizeAndLayout: YES];
}

//Gloss effecr starts here
- (void) drawRect:(CGRect)rect
{
	[self.backgroundImage drawInRect: rect];
    drawGloss(self.bounds);
}

#pragma mark --Setters and Getters
- (void) setWidth:(CGFloat) w
{
	if ( w <= 0 )
		w = 284;
	
	width = MAX( w, self.backgroundImage.size.width );
}

- (CGFloat) width
{
	if ( nil == self.superview )
		return width;
	
	CGFloat maxWidth = self.superview.bounds.size.width - 20;
	
	return MIN( width, maxWidth );
}

- (void) setMaxHeight:(CGFloat) h
{
	if ( h <= 0 )
		h = 358;
	
	maxHeight = MAX( h, self.backgroundImage.size.height );
}

- (CGFloat) maxHeight
{
	if ( nil == self.superview )
		return maxHeight;
	
	return MIN( maxHeight, self.superview.bounds.size.height - 20 );
}

- (void) setStyle:(TSAlertViewStyle)newStyle
{
	if ( style != newStyle )
	{
		style = newStyle;
		
		if ( style == TSAlertViewStyleInput )
		{
			// need to watch for keyboard
			[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector( onKeyboardWillShow:) name: UIKeyboardWillShowNotification object: nil];
			[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector( onKeyboardWillHide:) name: UIKeyboardWillHideNotification object: nil];
		}
	}
}

- (NSMutableArray*) buttons
{
	if ( _buttons == nil )
	{
		_buttons = [NSMutableArray arrayWithCapacity:4];
	}
	
	return _buttons;
}

- (UILabel*) titleLabel
{
	if ( _titleLabel == nil )
	{
		_titleLabel = [[UILabel alloc] init];
		_titleLabel.font = [UIFont boldSystemFontOfSize: 18];
		_titleLabel.backgroundColor = [UIColor clearColor];
		_titleLabel.textColor = [UIColor whiteColor];
		_titleLabel.textAlignment = UITextAlignmentCenter;
		_titleLabel.lineBreakMode = UILineBreakModeWordWrap;
		_titleLabel.numberOfLines = 0;
	}
	
	return _titleLabel;
}

- (UILabel*) messageLabel
{
	if ( _messageLabel == nil )
	{
		_messageLabel = [[UILabel alloc] init];
		_messageLabel.font = self.messageFont;
		_messageLabel.backgroundColor = [UIColor clearColor];
		_messageLabel.textColor = [UIColor whiteColor];
		_messageLabel.textAlignment = UITextAlignmentCenter;
		_messageLabel.lineBreakMode = UILineBreakModeWordWrap;
		_messageLabel.numberOfLines = 0;
	}
	
	return _messageLabel;
}

- (UITextView*) messageTextView
{
	if ( _messageTextView == nil )
	{
		_messageTextView = [[UITextView alloc] init];
		_messageTextView.editable = NO;
        _messageTextView.font = self.messageFont;
		_messageTextView.backgroundColor = [UIColor whiteColor];
		_messageTextView.textColor = [UIColor darkTextColor];
		_messageTextView.textAlignment = UITextAlignmentLeft;
		_messageTextView.bounces = YES;
		_messageTextView.alwaysBounceVertical = YES;
		_messageTextView.layer.cornerRadius = 5;
	}
	
	return _messageTextView;
}

- (UIImageView*) messageTextViewMaskView
{
	if ( _messageTextViewMaskImageView == nil )
	{
		UIImage* shadowImage = [[UIImage imageWithContentsOfFile:[self.resourceBundle pathForResource:@"TSAlertViewMessageListViewShadow" ofType:@"png"]] stretchableImageWithLeftCapWidth:6 topCapHeight:7];
		
		_messageTextViewMaskImageView = [[UIImageView alloc] initWithImage: shadowImage];
		_messageTextViewMaskImageView.userInteractionEnabled = NO;
		_messageTextViewMaskImageView.layer.masksToBounds = YES;
		_messageTextViewMaskImageView.layer.cornerRadius = 6;
	}
	return _messageTextViewMaskImageView;
}

- (UITextField*) inputTextField
{
	if ( _inputTextField == nil )
	{
		_inputTextField = [[UITextField alloc] init];
		_inputTextField.borderStyle = UITextBorderStyleRoundedRect;
	}
	
	return _inputTextField;
}

- (UIImage*) backgroundImage
{
	if ( _backgroundImage == nil )
	{
        NSString *path = [self.resourceBundle pathForResource:@"bg_alert" ofType:@"png"];
        self.backgroundImage = [[[UIImage alloc] initWithContentsOfFile:path] stretchableImageWithLeftCapWidth:20 topCapHeight:25];
	}
	
	return _backgroundImage;
}

- (void) setTitle:(NSString *)t
{
	self.titleLabel.text = t;
}

- (NSString*) title 
{
	return self.titleLabel.text;
}

- (void) setMessage:(NSString *)t
{
	self.messageLabel.text = t;
	self.messageTextView.text = t;
}

- (NSString*) message  
{
	return self.messageLabel.text;
}

-(void) setMessageFont:(UIFont *)font {
    _messageFont = font;
}

-(void) setMessageShadowOffset:(CGSize)shadowOffset {
    self.messageLabel.shadowOffset = CGSizeMake(shadowOffset.width/self.contentScaleFactor, shadowOffset.height/self.contentScaleFactor);
}

-(void)setMessageShadowColor:(UIColor *)color {
    self.messageLabel.shadowColor = color;
}

- (NSInteger) numberOfButtons
{
	return [self.buttons count];
}

- (void) setCancelButtonIndex:(NSInteger)buttonIndex
{
	// avoid a NSRange exception
	if ( buttonIndex < 0 || buttonIndex >= [self.buttons count] )
		return;
	
	cancelButtonIndex = buttonIndex;
	
	UIButton* b = [self.buttons objectAtIndex: buttonIndex];
	
	UIImage* buttonBgNormal = [UIImage imageWithContentsOfFile:[self.resourceBundle pathForResource:@"TSAlertViewCancelButtonBackground" ofType:@"png"]];
	buttonBgNormal = [buttonBgNormal stretchableImageWithLeftCapWidth: buttonBgNormal.size.width / 2.0 topCapHeight: buttonBgNormal.size.height / 2.0];
	[b setBackgroundImage: buttonBgNormal forState: UIControlStateNormal];
	
	UIImage* buttonBgPressed = [UIImage imageWithContentsOfFile:[self.resourceBundle pathForResource:@"TSAlertViewButtonBackground_Highlighted" ofType:@"png"]];
	buttonBgPressed = [buttonBgPressed stretchableImageWithLeftCapWidth: buttonBgPressed.size.width / 2.0 topCapHeight: buttonBgPressed.size.height / 2.0];
	[b setBackgroundImage: buttonBgPressed forState: UIControlStateHighlighted];
}

-(void)setButtonsTextShadowOffset:(CGSize)shadowOffset {
    for (UIButton *b in self.buttons) b.titleLabel.shadowOffset =
        CGSizeMake(shadowOffset.width/self.contentScaleFactor, shadowOffset.height/self.contentScaleFactor);
}

-(void)setButtonsTextShadowColor:(UIColor *)color {
    for (UIButton  *b in self.buttons) [b setTitleShadowColor:color forState:UIControlStateNormal];
}

-(void)setButtonsTextColor:(UIColor *)color {
    for (UIButton *b in self.buttons) [b setTitleColor:color forState:UIControlStateNormal];
}

#pragma mark --Show view

- (void) show
{
	[[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate:[NSDate date]];
	
	self.alertViewController = [[TSAlertViewController alloc] init];
	self.alertViewController.view.backgroundColor = [UIColor clearColor];
	
	// $important - the window is released only when the user clicks an alert view button
	self.overlayWindow = [[TSAlertOverlayWindow alloc] initWithFrame: [UIScreen mainScreen].bounds];
	self.overlayWindow.alpha = 0.0;
	self.overlayWindow.backgroundColor = [UIColor clearColor];
	self.overlayWindow.rootViewController = self.alertViewController;
	[self.overlayWindow makeKeyAndVisible];
	
	// fade in the window
	[UIView animateWithDuration: 0.2 animations: ^{
		self.overlayWindow.alpha = 1;
	}];
	
	// add and pulse the alertview
	// add the alertview
	[self.alertViewController.view addSubview: self];
	[self sizeToFit];
	self.center = CGPointMake( CGRectGetMidX( self.alertViewController.view.bounds ), CGRectGetMidY( self.alertViewController.view.bounds ) );
	self.frame = CGRectIntegral( self.frame );
	[self pulse];
	
	if ( self.style == TSAlertViewStyleInput )
	{
		[self layoutSubviews];
		[self.inputTextField becomeFirstResponder];
	}
}

#pragma mark --Animation of appearing
- (void) pulse
{
	// pulse animation thanks to:  http://delackner.com/blog/2009/12/mimicking-uialertviews-animated-transition/
    self.transform = CGAffineTransformMakeScale(0.6, 0.6);
	[UIView animateWithDuration: 0.2 
					 animations: ^{
						 self.transform = CGAffineTransformMakeScale(1.1, 1.1);
					 }
					 completion: ^(BOOL finished){
						 [UIView animateWithDuration:1.0/15.0
										  animations: ^{
											  self.transform = CGAffineTransformMakeScale(0.9, 0.9);
										  }
										  completion: ^(BOOL finished){
											  [UIView animateWithDuration:1.0/7.5
															   animations: ^{
																   self.transform = CGAffineTransformIdentity;
															   }];
										  }];
					 }];
	
}

#pragma mark --Actions block

- (void) onButtonPress: (id) sender
{
	int buttonIndex = [_buttons indexOfObjectIdenticalTo: sender];
	
	if ( [self.delegate respondsToSelector: @selector(alertView:clickedButtonAtIndex:)] )
	{
		[self.delegate alertView: self clickedButtonAtIndex: buttonIndex ];
	}
	
	if ( buttonIndex == self.cancelButtonIndex )
	{
		if ( [self.delegate respondsToSelector: @selector(alertViewCancel:)] )
		{
			[self.delegate alertViewCancel: self ];
		}	
	}
	
	[self dismissWithClickedButtonIndex: buttonIndex  animated: YES];
}

- (void) onKeyboardWillShow: (NSNotification*) note
{
	NSValue* v = [note.userInfo objectForKey: UIKeyboardFrameEndUserInfoKey];
	CGRect kbframe = [v CGRectValue];
	kbframe = [self.superview convertRect: kbframe fromView: nil];
	
	if ( CGRectIntersectsRect( self.frame, kbframe) )
	{
		CGPoint c = self.center;
		
		if ( self.frame.size.height > kbframe.origin.y - 20 )
		{
			self.maxHeight = kbframe.origin.y - 20;
			[self sizeToFit];
			[self layoutSubviews];
		}
		
		c.y = kbframe.origin.y / 2;
		
		[UIView animateWithDuration: 0.2
						 animations: ^{
							 self.center = c;
							 self.frame = CGRectIntegral(self.frame);
						 }];
	}
}

- (void) onKeyboardWillHide: (NSNotification*) note
{
	[UIView animateWithDuration: 0.2
					 animations: ^{
						 self.center = CGPointMake( CGRectGetMidX( self.superview.bounds ), CGRectGetMidY( self.superview.bounds ));
						 self.frame = CGRectIntegral(self.frame);
					 }];
}

#pragma mark --Layout methods

- (CGSize) recalcSizeAndLayout: (BOOL) layout
{
	BOOL	stacked = !(self.buttonLayout == TSAlertViewButtonLayoutNormal && [self.buttons count] == 2 );
	
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	
	CGSize  titleLabelSize = [self titleLabelSize];
	CGSize  messageViewSize = [self messageLabelSize];
	CGSize  inputTextFieldSize = [self inputTextFieldSize];
	CGSize  buttonsAreaSize = stacked ? [self buttonsAreaSize_Stacked] : [self buttonsAreaSize_SideBySide];
	
	CGFloat inputRowHeight = self.style == TSAlertViewStyleInput ? inputTextFieldSize.height + kTSAlertView_RowMargin : 0;
	
	CGFloat totalHeight = kTSAlertView_TopMargin + titleLabelSize.height + kTSAlertView_RowMargin + messageViewSize.height + inputRowHeight + kTSAlertView_RowMargin + buttonsAreaSize.height + kTSAlertView_BottomMargin;
	
	if ( totalHeight > self.maxHeight )
	{
		// too tall - we'll condense by using a textView (with scrolling) for the message
		
		totalHeight -= messageViewSize.height;
		//$$what if it's still too tall?
		messageViewSize.height = self.maxHeight - totalHeight;
		
		totalHeight = self.maxHeight;
		
		self.usesMessageTextView = YES;
	}
	
	if ( layout )
	{
		// title
		CGFloat y = kTSAlertView_TopMargin;
		if ( self.title != nil )
		{
			self.titleLabel.frame = CGRectMake( kTSAlertView_LeftMargin, y, titleLabelSize.width, titleLabelSize.height );
			[self addSubview: self.titleLabel];
			y += titleLabelSize.height + kTSAlertView_RowMargin;
		}
		
		// message
		if ( self.message != nil )
		{
			if ( self.usesMessageTextView )
			{
				self.messageTextView.frame = CGRectMake( kTSAlertView_LeftMargin, y, messageViewSize.width, messageViewSize.height );
				[self addSubview: self.messageTextView];
				y += messageViewSize.height + kTSAlertView_RowMargin;
				
				UIImageView* maskImageView = [self messageTextViewMaskView];
				maskImageView.frame = self.messageTextView.frame;
				[self addSubview: maskImageView];
			}
			else
			{
				self.messageLabel.frame = CGRectMake( kTSAlertView_LeftMargin, y, messageViewSize.width, messageViewSize.height );
				[self addSubview: self.messageLabel];
				y += messageViewSize.height + kTSAlertView_RowMargin;
			}
		}
		
		// input
		if ( self.style == TSAlertViewStyleInput )
		{
			self.inputTextField.frame = CGRectMake( kTSAlertView_LeftMargin, y, inputTextFieldSize.width, inputTextFieldSize.height );
			[self addSubview: self.inputTextField];
			y += inputTextFieldSize.height + kTSAlertView_RowMargin;
		}
		
		// buttons
		CGFloat buttonHeight = [[self.buttons objectAtIndex:0] sizeThatFits: CGSizeZero].height;
		if ( stacked )
		{
			CGFloat buttonWidth = maxWidth;
			for ( UIButton* b in self.buttons )
			{
				b.frame = CGRectMake( kTSAlertView_LeftMargin, y, buttonWidth, buttonHeight );
				[self addSubview: b];
				y += buttonHeight + kTSAlertView_RowMargin;
			}
		}
		else
		{
			CGFloat buttonWidth = (maxWidth - kTSAlertView_ColumnMargin) / 2.0;
			CGFloat x = kTSAlertView_LeftMargin;
			for ( UIButton* b in self.buttons )
			{
				b.frame = CGRectMake( x, y, buttonWidth, buttonHeight );
				[self addSubview: b];
				x += buttonWidth + kTSAlertView_ColumnMargin;
			}
		}
		
	}
	
	return CGSizeMake( self.width, totalHeight );
}

- (CGSize) titleLabelSize
{
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	CGSize s = [self.titleLabel.text sizeWithFont: self.titleLabel.font constrainedToSize: CGSizeMake(maxWidth, 1000) lineBreakMode: self.titleLabel.lineBreakMode];
	if ( s.width < maxWidth )
		s.width = maxWidth;
	
	return s;
}

- (CGSize) messageLabelSize
{
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	CGSize s = [self.messageLabel.text sizeWithFont: self.messageLabel.font constrainedToSize: CGSizeMake(maxWidth, 1000) lineBreakMode: self.messageLabel.lineBreakMode];
	if ( s.width < maxWidth )
		s.width = maxWidth;
	
	return s;
}

- (CGSize) inputTextFieldSize
{
	if ( self.style == TSAlertViewStyleNormal)
		return CGSizeZero;
	
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	
	CGSize s = [self.inputTextField sizeThatFits: CGSizeZero];
	
	return CGSizeMake( maxWidth, s.height );
}

- (CGSize) buttonsAreaSize_SideBySide
{
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	
	CGSize bs = [[self.buttons objectAtIndex:0] sizeThatFits: CGSizeZero];
	
	bs.width = maxWidth;
	
	return bs;
}

- (CGSize) buttonsAreaSize_Stacked
{
	CGFloat maxWidth = self.width - (kTSAlertView_LeftMargin * 2);
	int buttonCount = [self.buttons count];
	
	CGSize bs = [[self.buttons objectAtIndex:0] sizeThatFits: CGSizeZero];
	
	bs.width = maxWidth;
	
	bs.height = (bs.height * buttonCount) + (kTSAlertView_RowMargin * (buttonCount-1));
	
	return bs;
}

#pragma mark --Other

- (void) releaseWindow: (int) buttonIndex
{
	if ( [self.delegate respondsToSelector: @selector(alertView:didDismissWithButtonIndex:)] )
	{
		[self.delegate alertView: self didDismissWithButtonIndex: buttonIndex ];
	}
	
	// the one place we release the window we allocated in "show"
	// this will propogate releases to us (TSAlertView), and our TSAlertViewController
}

- (BOOL) isVisible
{
	return self.superview != nil;
}

- (NSInteger) addButtonWithTitle: (NSString *) t
{
	NSInteger i = [self addButtonWithTitle:t font:[UIFont fontWithName:@"Arial-bold" size:14]];
    return i;
}

- (NSInteger) addButtonWithTitle: (NSString *) t font:(UIFont *)font
{
    UIButton* b = [UIButton buttonWithType: UIButtonTypeCustom];
	[b setTitle: t forState: UIControlStateNormal];
    [b.titleLabel setFont:font];
	
    NSString *path = [self.resourceBundle pathForResource:@"btn_alert" ofType:@"png"];
	UIImage* buttonBgNormal = [[UIImage alloc] initWithContentsOfFile:path];
	buttonBgNormal = [buttonBgNormal stretchableImageWithLeftCapWidth: buttonBgNormal.size.width / 2.0 topCapHeight: buttonBgNormal.size.height / 2.0];
	[b setBackgroundImage: buttonBgNormal forState: UIControlStateNormal];
	
    //	UIImage* buttonBgPressed = [UIImage imageNamed: @"TSAlertViewButtonBackground_Highlighted.png"];
    //	buttonBgPressed = [buttonBgPressed stretchableImageWithLeftCapWidth: buttonBgPressed.size.width / 2.0 topCapHeight: buttonBgPressed.size.height / 2.0];
    //	[b setBackgroundImage: buttonBgPressed forState: UIControlStateHighlighted];
	
	[b addTarget: self action: @selector(onButtonPress:) forControlEvents: UIControlEventTouchUpInside];
	
    if (!self.hasButtons) {
        [self.buttons removeAllObjects];
        self.hasButtons = YES;
    }
	[self.buttons addObject: b];
	
	[self setNeedsLayout];
	
	return self.buttons.count-1;
}

- (NSString *) buttonTitleAtIndex:(NSInteger)buttonIndex
{
	// avoid a NSRange exception
	if ( buttonIndex < 0 || buttonIndex >= [self.buttons count] )
		return nil;
	
	UIButton* b = [self.buttons objectAtIndex: buttonIndex];
	
	return [b titleForState: UIControlStateNormal];
}

- (void) dismissWithClickedButtonIndex: (NSInteger)buttonIndex animated: (BOOL) animated
{
	if ( self.style == TSAlertViewStyleInput && [self.inputTextField isFirstResponder] )
	{
		[self.inputTextField resignFirstResponder];
	}
	
	if ( [self.delegate respondsToSelector: @selector(alertView:willDismissWithButtonIndex:)] )
	{
		[self.delegate alertView: self willDismissWithButtonIndex: buttonIndex ];
	}
	
	if ( animated )
	{
		self.window.backgroundColor = [UIColor clearColor];
		self.window.alpha = 1;
		
		[UIView animateWithDuration: 0.2
						 animations: ^{
							 [self.window resignKeyWindow];
							 self.window.alpha = 0;
						 }
						 completion: ^(BOOL finished) {
							 [self releaseWindow: buttonIndex];
						 }];
		
		[UIView commitAnimations];
	}
	else
	{
		[self.window resignKeyWindow];
		
		[self releaseWindow: buttonIndex];
	}
}

#pragma mark --Gloss functions

static void addRoundedRectToPath (CGContextRef context, CGRect rect, CGFloat ovalWidth, CGFloat ovalHeight) {
    float fw, fh;
    if (ovalWidth<=0 || ovalHeight<=0)  {
        CGContextAddRect(context, rect);
        return;
    }
    CGContextSaveGState(context);
    CGContextTranslateCTM (context, CGRectGetMinX(rect), CGRectGetMinY(rect));
    CGContextScaleCTM (context, ovalWidth, ovalHeight);
    fw = CGRectGetWidth (rect) / ovalWidth;
    fh = CGRectGetHeight (rect) / ovalHeight;
    CGContextMoveToPoint(context, fw, fh/2);
    CGContextAddArcToPoint(context, fw, fh, fw/2, fh, 1);
    CGContextAddArcToPoint(context, 0, fh, 0, fh/2, 1);
    CGContextAddArcToPoint(context, 0, 0, fw/2, 0, 1);
    CGContextAddArcToPoint(context, fw, 0, fw, fh/2, 1);
    CGContextClosePath(context);
    CGContextRestoreGState(context);
}

static void addGlossPath(CGContextRef context, CGRect rect) {
    CGFloat quarterHeight = CGRectGetMidY(rect) / 3;
    CGContextSaveGState(context);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, -20, 0);
    
    CGContextAddLineToPoint(context, -20, quarterHeight);
    CGContextAddQuadCurveToPoint(context, CGRectGetMidX(rect), quarterHeight*2, CGRectGetMaxX(rect) + 20, quarterHeight);
    CGContextAddLineToPoint(context, CGRectGetMaxX(rect) +20, 0);
    
    CGContextClosePath(context);
    CGContextRestoreGState(context);
}

void drawGloss(CGRect bounds) {
    CGFloat locations[2] = {0.0, 1.0};
    CGFloat components[8] = {1.0, 1.0, 1.0, 0.1, 1.0, 1.0, 1.0, .01};
    CGGradientRef glossGradient;
    CGColorSpaceRef rgbColorspace;
    CGPoint topCenter = CGPointMake(CGRectGetMidX(bounds), 0.0f);
    CGPoint midCenter = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    UIGraphicsPushContext(context);
    
    addRoundedRectToPath(context, CGRectInset(bounds, 9.0f, 13.0f), 10, 10);
    CGContextClosePath(context);
    CGContextClip(context);
    
    addGlossPath(context, bounds);
    CGContextClip(context);
    
    rgbColorspace = CGColorSpaceCreateDeviceRGB();
    glossGradient = CGGradientCreateWithColorComponents(rgbColorspace, components, locations, 2);
    
    CGContextDrawLinearGradient(context, glossGradient, topCenter, midCenter, 0);
    
    UIGraphicsPopContext();
    
    CGGradientRelease(glossGradient);
    CGColorSpaceRelease(rgbColorspace);
}

@end




