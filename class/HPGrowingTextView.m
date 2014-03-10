//
//  HPTextView.m
//
//  Created by Hans Pinckaers on 29-06-10.
//
//	MIT License
//
//	Copyright (c) 2011 Hans Pinckaers
//
//	Permission is hereby granted, free of charge, to any person obtaining a copy
//	of this software and associated documentation files (the "Software"), to deal
//	in the Software without restriction, including without limitation the rights
//	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//	copies of the Software, and to permit persons to whom the Software is
//	furnished to do so, subject to the following conditions:
//
//	The above copyright notice and this permission notice shall be included in
//	all copies or substantial portions of the Software.
//
//	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//	THE SOFTWARE.

#import "HPGrowingTextView.h"
#import "HPTextViewInternal.h"

CGFloat const HPAccessoryViewLeftPadding = 5.0f;
CGFloat const HPAccessoryViewRightPadding = 8.0f;
CGFloat const HPTruncationInsetiOS7 = 5.0f;
CGFloat const HPTruncationInsetiOS6 = 8.0f;

#if !__has_feature(objc_arc)
#error HPGrowingTextView must be built with ARC.
// You can turn on ARC for only HPGrowingTextView by adding -fobjc-arc to the build phase for HPGrowingTextView.m.
#endif

@interface HPGrowingTextView () < HPTextViewInternalDelegate>
@property (copy, nonatomic) NSString *realText;

-(void)commonInitialiser;
-(void)resizeTextView:(NSInteger)newSizeH;
-(void)growDidStop;
@end

@interface NSString (Layout)
// Truncate a given string to fit in rect with the truncationString, inset and font
- (NSString *)stringByTruncatingToSize:(CGRect)rect
                    truncateWithString:(NSString *)truncationString
                             withInset:(CGFloat)inset
                             usingFont:(UIFont *)font;
@end

@implementation HPGrowingTextView
@synthesize internalTextView;
@synthesize delegate;
@synthesize maxHeight;
@synthesize minHeight;
@synthesize font;
@synthesize textColor;
@synthesize textAlignment; 
@synthesize selectedRange;
@synthesize editable;
@synthesize dataDetectorTypes;
@synthesize animateHeightChange;
@synthesize animationDuration;
@synthesize returnKeyType;
@dynamic placeholder;
@dynamic placeholderColor;

// having initwithcoder allows us to use HPGrowingTextView in a Nib. -- aob, 9/2011
- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder])) {
        [self commonInitialiser];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInitialiser];
    }
    return self;
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
- (id)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)textContainer {
    if ((self = [super initWithFrame:frame])) {
        [self commonInitialiser:textContainer];
    }
    return self;
}

-(void)commonInitialiser {
    [self commonInitialiser:nil];
}

-(void)commonInitialiser:(NSTextContainer *)textContainer
#else
-(void)commonInitialiser
#endif
{
    // Initialization code
    CGRect r = self.frame;
    r.origin.y = 0;
    r.origin.x = 0;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
    internalTextView = [[HPTextViewInternal alloc] initWithFrame:r textContainer:textContainer];
#else
    internalTextView = [[HPTextViewInternal alloc] initWithFrame:r];
#endif
    internalTextView.delegate = self;
    internalTextView.scrollEnabled = NO;
    internalTextView.font = [UIFont systemFontOfSize:13.0];
    internalTextView.contentInset = UIEdgeInsetsZero;		
    internalTextView.showsHorizontalScrollIndicator = NO;
    internalTextView.text = @"-";
    internalTextView.contentMode = UIViewContentModeRedraw;
    [self addSubview:internalTextView];
    
    minHeight = internalTextView.frame.size.height;
    minNumberOfLines = 1;
    
    animateHeightChange = YES;
    animationDuration = 0.1f;
    
    internalTextView.text = @"";
    
    [self setMaxNumberOfLines:3];

    [self setPlaceholderColor:[UIColor lightGrayColor]];
    internalTextView.displayPlaceHolder = YES;
}

-(CGSize)sizeThatFits:(CGSize)size
{
    if (self.text.length == 0) {
        size.height = minHeight;
    }
    return size;
}

- (void)getAccessoryViewFrame:(CGRect *)frame textViewRightInsets:(CGFloat *)rightInset
{
	if (frame == NULL && rightInset == NULL)
	{
		return;
	}
	
	if (!self.accessoryView)
	{
		if (frame != NULL)
		{
			*frame = CGRectZero;
		}
		
		if (rightInset != NULL)
		{
			*rightInset = 0;
		}
		
		return;
	}
	
	CGRect accessoryViewFrame = self.accessoryView.frame;
	
	accessoryViewFrame.origin.x =
	CGRectGetWidth(self.bounds) -
	CGRectGetWidth(accessoryViewFrame) -
	HPAccessoryViewRightPadding;
	
	accessoryViewFrame.origin.y =
	(CGRectGetHeight(self.bounds) - CGRectGetHeight(accessoryViewFrame)) / 2;
	
	if (frame != NULL)
	{
		*frame = CGRectIntegral(accessoryViewFrame);
	}
	
	if (rightInset != NULL)
	{
		*rightInset =
		(HPAccessoryViewLeftPadding +
		 HPAccessoryViewRightPadding +
		 CGRectGetWidth(accessoryViewFrame));
	}
}

- (void)ios6_hideAccessoryViewIfOverlapsWithText:(NSString *)theText animate:(BOOL)animate
{
	if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
	{
		// iOS 7 or later
		// Not needed for iOS 6, accessory view can co-exist
		return;
	}
	
	if (!self.accessoryView || !self.superview)
	{
		// No accessory view, not added to superview, not needed
		return;
	}
	
	CGFloat maxWidthToAccessoryView = CGRectGetMinX(self.accessoryView.frame) - 10;
	
	// Just make it twice as large so it can compute properly
	CGSize textViewSize =
	[theText sizeWithFont:internalTextView.font
				 forWidth:internalTextView.contentSize.width * 2
			lineBreakMode:NSLineBreakByClipping];
	
	BOOL textOverlapsAccessoryView =
	(textViewSize.width >= maxWidthToAccessoryView);
	
	BOOL shouldHide = textOverlapsAccessoryView;
	
	if (shouldHide != self.accessoryView.hidden)
	{
		[UIView animateWithDuration:animate ? 0.3 : 0.0
							  delay:0.0
							options:UIViewAnimationCurveEaseInOut
						 animations:^{
							 self.accessoryView.alpha = shouldHide ? 0 : 1;
							 self.accessoryView.hidden = shouldHide;
						 }
						 completion:nil];
	}
}

-(void)layoutSubviews
{
    [super layoutSubviews];
	
	CGRect r = self.bounds;
	r.origin.y = 0;
	r.origin.x = contentInset.left;
    r.size.width -= contentInset.left + contentInset.right;

	if (self.accessoryView)
	{
		CGRect accessoryViewFrame;
		CGFloat rightInsets;
		
		[self getAccessoryViewFrame:&accessoryViewFrame textViewRightInsets:&rightInsets];
		
		self.accessoryView.frame = accessoryViewFrame;
		
		if ([self.internalTextView respondsToSelector:@selector(setTextContainerInset:)])
		{
			UIEdgeInsets internalInsets = self.internalTextView.textContainerInset;
			internalInsets.right = rightInsets;
			self.internalTextView.textContainerInset = internalInsets;
		}

		[self ios6_hideAccessoryViewIfOverlapsWithText:self.text animate:NO];
	}

    internalTextView.frame = r;
}

-(void)setContentInset:(UIEdgeInsets)inset
{
    contentInset = inset;
    
    CGRect r = self.frame;
    r.origin.y = inset.top - inset.bottom;
    r.origin.x = inset.left;
    r.size.width -= inset.left + inset.right;
    
    internalTextView.frame = r;
    
    [self setMaxNumberOfLines:maxNumberOfLines];
    [self setMinNumberOfLines:minNumberOfLines];
}

-(UIEdgeInsets)contentInset
{
    return contentInset;
}

-(void)setMaxNumberOfLines:(int)n
{
    if(n == 0 && maxHeight > 0) return; // the user specified a maxHeight themselves.
    
    // Use internalTextView for height calculations, thanks to Gwynne <http://blog.darkrainfall.org/>
    NSString *saveText = internalTextView.text, *newText = @"-";
    
    internalTextView.delegate = nil;
    internalTextView.hidden = YES;
    
    for (int i = 1; i < n; ++i)
        newText = [newText stringByAppendingString:@"\n|W|"];
    
    internalTextView.text = newText;
    
    maxHeight = [self measureHeight];
    
    internalTextView.text = saveText;
    internalTextView.hidden = NO;
    internalTextView.delegate = self;
    
    [self sizeToFit];
    
    maxNumberOfLines = n;
}

-(int)maxNumberOfLines
{
    return maxNumberOfLines;
}

- (void)setMaxHeight:(int)height
{
    maxHeight = height;
    maxNumberOfLines = 0;
}

-(void)setMinNumberOfLines:(int)m
{
    if(m == 0 && minHeight > 0) return; // the user specified a minHeight themselves.

	// Use internalTextView for height calculations, thanks to Gwynne <http://blog.darkrainfall.org/>
    NSString *saveText = internalTextView.text, *newText = @"-";
    
    internalTextView.delegate = nil;
    internalTextView.hidden = YES;
    
    for (int i = 1; i < m; ++i)
        newText = [newText stringByAppendingString:@"\n|W|"];
    
    internalTextView.text = newText;
    
    minHeight = [self measureHeight];
    
    internalTextView.text = saveText;
    internalTextView.hidden = NO;
    internalTextView.delegate = self;
    
    [self sizeToFit];
    
    minNumberOfLines = m;
}

-(int)minNumberOfLines
{
    return minNumberOfLines;
}

- (void)setMinHeight:(int)height
{
    minHeight = height;
    minNumberOfLines = 0;
}

- (NSString *)placeholder
{
    return internalTextView.placeholder;
}

- (void)setPlaceholder:(NSString *)placeholder
{
    [internalTextView setPlaceholder:placeholder];
    [internalTextView setNeedsDisplay];
}

- (UIColor *)placeholderColor
{
    return internalTextView.placeholderColor;
}

- (void)setPlaceholderColor:(UIColor *)placeholderColor 
{
    [internalTextView setPlaceholderColor:placeholderColor];
}

- (void)setAccessoryView:(UIView *)accessoryView
{
	if (_accessoryView != accessoryView)
	{
		if (_accessoryView)
		{
			[_accessoryView removeFromSuperview];
		}
		
		if (accessoryView)
		{
			[self addSubview:accessoryView];
		}
		
		_accessoryView = accessoryView;
		
		[self truncateStringToFitSingleLine];
		
		[self ios6_hideAccessoryViewIfOverlapsWithText:self.text animate:NO];
	}
}

- (void)textViewDidChange:(UITextView *)textView
{
	self.realText = textView.text;
    [self refreshHeight];
}

- (void)refreshHeight
{
	[self refreshHeightAlongWithAnimation:NULL completion:NULL];
}

- (void)refreshHeightAlongWithAnimation:(void (^)(void))otherAnimations
							 completion:(void (^)(NSUInteger, NSUInteger))completion
{
	NSUInteger oldHeight = CGRectGetHeight(internalTextView.frame);
	
	//size of content, so we can set the frame of self
	NSInteger newSizeH = [self measureHeight];
	if (newSizeH < minHeight || !internalTextView.hasText) {
        newSizeH = minHeight; //not smalles than minHeight
    }
    else if (maxHeight && newSizeH > maxHeight) {
        newSizeH = maxHeight; // not taller than maxHeight
    }
    
	if (internalTextView.frame.size.height != newSizeH)
	{
        // if our new height is greater than the maxHeight
        // sets not set the height or move things
        // around and enable scrolling
        if (newSizeH >= maxHeight)
        {
            if(!internalTextView.scrollEnabled){
                internalTextView.scrollEnabled = YES;
                [internalTextView flashScrollIndicators];
            }
            
        } else {
            internalTextView.scrollEnabled = NO;
        }
        
        // [fixed] Pasting too much text into the view failed to fire the height change,
        // thanks to Gwynne <http://blog.darkrainfall.org/>
		if (newSizeH <= maxHeight)
		{
			[UIView animateWithDuration:animateHeightChange ? animationDuration : 0
								  delay:0
								options:(UIViewAnimationOptionAllowUserInteraction|
										 UIViewAnimationOptionBeginFromCurrentState)
							 animations:^(void) {
								 [self resizeTextView:newSizeH];
								 if (otherAnimations != NULL)
								 {
									 otherAnimations();
								 }
							 }
							 completion:^(BOOL finished) {
								 if (completion != NULL)
								 {
									 completion(oldHeight, newSizeH);
								 }
								 
								 if ([delegate respondsToSelector:@selector(growingTextView:didChangeHeight:)]) {
									 [delegate growingTextView:self didChangeHeight:newSizeH];
								 }
							 }];
		}
	}
    // Display (or not) the placeholder string
    
    BOOL wasDisplayingPlaceholder = internalTextView.displayPlaceHolder;
    internalTextView.displayPlaceHolder = self.internalTextView.text.length == 0;
	
    if (wasDisplayingPlaceholder != internalTextView.displayPlaceHolder) {
        [internalTextView setNeedsDisplay];
    }
    
//    // scroll to caret (needed on iOS7)
//	[self performSelector:@selector(ios7_scrollToCaret) withObject:nil afterDelay:0.1f];

    // Tell the delegate that the text view changed
    if ([delegate respondsToSelector:@selector(growingTextViewDidChange:)]) {
		[delegate growingTextViewDidChange:self];
	}
}

// Code from apple developer forum - @Steve Krulewitz, @Mark Marszal, @Eric Silverberg
- (CGFloat)measureHeight
{
	if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1)
	{
		// iOS 6.1 or earlier
		return self.internalTextView.contentSize.height;
	}
	else
	{
		// iOS 7 or later
		return ceilf([self.internalTextView sizeThatFits:self.internalTextView.frame.size].height);
	}	
}

- (void)ios7_scrollToCaret
{
	[self ios7_scrollToCaretAnimated:NO];
}

- (void)ios7_scrollToCaretAnimated:(BOOL)animated
{
	if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1)
	{
		// iOS 6.1 or earlier, return
		return;
	}
	
    CGRect r = [internalTextView caretRectForPosition:internalTextView.selectedTextRange.end];
    CGFloat caretY =  MAX(r.origin.y - internalTextView.frame.size.height + r.size.height + 8, 0);
    if (internalTextView.contentOffset.y < caretY && r.origin.y != INFINITY)
	{
		[internalTextView setContentOffset:CGPointMake(0, caretY) animated:animated];
	}
}

-(void)resizeTextView:(NSInteger)newSizeH
{
    if ([delegate respondsToSelector:@selector(growingTextView:willChangeHeight:)]) {
        [delegate growingTextView:self willChangeHeight:newSizeH];
    }
    
    CGRect internalTextViewFrame = self.frame;
    internalTextViewFrame.size.height = newSizeH; // + padding
    self.frame = internalTextViewFrame;
    
    internalTextViewFrame.origin.y = contentInset.top - contentInset.bottom;
    internalTextViewFrame.origin.x = contentInset.left;
    
    if (!CGRectEqualToRect(internalTextView.frame, internalTextViewFrame))
	{
		internalTextView.frame = internalTextViewFrame;
		
		// Fix iOS 7 bug where when internal text frame is increased, it ends up
		// sitting below because of a negative content offset applied that cannot
		// be reset without setting the text of the text view.
		if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
		{
			// iOS 7 or later
			CGPoint offset = internalTextView.contentOffset;
			
			if (offset.y < 0)
			{
				NSRange originalSelectedRange = internalTextView.selectedRange;
				[internalTextView setText:internalTextView.text];
				
				// Restore selected range
				[internalTextView setSelectedRange:originalSelectedRange];
			}
		}
	}
		
	if (self.resizeTextViewBlock != NULL)
	{
		self.resizeTextViewBlock(self, newSizeH);
	}	
}

- (void)growDidStop
{
    // scroll to caret (needed on iOS7)
	[self ios7_scrollToCaretAnimated:NO];
    
	if ([delegate respondsToSelector:@selector(growingTextView:didChangeHeight:)]) {
		[delegate growingTextView:self didChangeHeight:self.frame.size.height];
	}
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [internalTextView becomeFirstResponder];
}

- (BOOL)becomeFirstResponder
{
    [super becomeFirstResponder];
    return [self.internalTextView becomeFirstResponder];
}

-(BOOL)resignFirstResponder
{
	[super resignFirstResponder];
	return [internalTextView resignFirstResponder];
}

-(BOOL)isFirstResponder
{
  return [self.internalTextView isFirstResponder];
}



///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITextView properties
///////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setText:(NSString *)newText selectedTextRange:(NSRange)range
{
	self.realText = newText;
    internalTextView.text = newText;
	
	if (range.location != NSNotFound && NSMaxRange(range) <= [newText length])
	{
		internalTextView.selectedRange = range;
	}
	
	[self ios6_hideAccessoryViewIfOverlapsWithText:newText animate:NO];
	
	if (![self isFirstResponder])
	{
        [self truncateStringToFitSingleLine];
    }
	
    // include this line to analyze the height of the textview.
    // fix from Ankit Thakur
    [self performSelector:@selector(refreshHeight) withObject:nil];
}

-(void)setText:(NSString *)newText
{
	[self setText:newText selectedTextRange:NSMakeRange(NSNotFound, 0)];
}

-(NSString*) text
{
    return self.realText;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setFont:(UIFont *)afont
{
	internalTextView.font= afont;
	
	[self setMaxNumberOfLines:maxNumberOfLines];
	[self setMinNumberOfLines:minNumberOfLines];
}

-(UIFont *)font
{
	return internalTextView.font;
}	

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setTextColor:(UIColor *)color
{
	internalTextView.textColor = color;
}

-(UIColor*)textColor{
	return internalTextView.textColor;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setBackgroundColor:(UIColor *)backgroundColor
{
  [super setBackgroundColor:backgroundColor];
	internalTextView.backgroundColor = backgroundColor;
}

-(UIColor*)backgroundColor
{
  return internalTextView.backgroundColor;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setTextAlignment:(NSTextAlignment)aligment
{
	internalTextView.textAlignment = aligment;
}

-(NSTextAlignment)textAlignment
{
	return internalTextView.textAlignment;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setSelectedRange:(NSRange)range
{
	internalTextView.selectedRange = range;
}

-(NSRange)selectedRange
{
	return internalTextView.selectedRange;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setIsScrollable:(BOOL)isScrollable
{
    internalTextView.scrollEnabled = isScrollable;
}

- (BOOL)isScrollable
{
    return internalTextView.scrollEnabled;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setEditable:(BOOL)beditable
{
	internalTextView.editable = beditable;
}

-(BOOL)isEditable
{
	return internalTextView.editable;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setReturnKeyType:(UIReturnKeyType)keyType
{
	internalTextView.returnKeyType = keyType;
}

-(UIReturnKeyType)returnKeyType
{
	return internalTextView.returnKeyType;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setKeyboardType:(UIKeyboardType)keyType
{
	internalTextView.keyboardType = keyType;
}

- (UIKeyboardType)keyboardType
{
	return internalTextView.keyboardType;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setEnablesReturnKeyAutomatically:(BOOL)enablesReturnKeyAutomatically
{
  internalTextView.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically;
}

- (BOOL)enablesReturnKeyAutomatically
{
  return internalTextView.enablesReturnKeyAutomatically;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

-(void)setDataDetectorTypes:(UIDataDetectorTypes)datadetector
{
	internalTextView.dataDetectorTypes = datadetector;
}

-(UIDataDetectorTypes)dataDetectorTypes
{
	return internalTextView.dataDetectorTypes;
}

///////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)hasText{
	return [internalTextView hasText];
}

- (void)scrollRangeToVisible:(NSRange)range
{
	[internalTextView scrollRangeToVisible:range];
}

- (void)scrollTextViewToCaret
{
	[self scrollRangeToVisible:internalTextView.selectedRange];
}

#pragma mark - Truncation

- (NSString *)_truncatedStringFittingASingleLineFromString:(NSString *)originalString
{
	CGRect frame = internalTextView.frame;
	frame.size.height = internalTextView.font.lineHeight;
	
	if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
	{
		// iOS 7 or later	
		CGFloat rightInsets;
		[self getAccessoryViewFrame:NULL textViewRightInsets:&rightInsets];
		
		if (rightInsets > 0)
		{
			frame.size.width -= rightInsets;
		}
	}

	NSString* truncatedString = nil;
	
	if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1)
	{
		// iOS 6.1
		truncatedString =
		[originalString stringByTruncatingToSize:frame
							  truncateWithString:@"…"
									   withInset:HPTruncationInsetiOS6
									   usingFont:internalTextView.font];
	}
	else
	{
		// iOS 7 or later
		truncatedString =
		[originalString stringByTruncatingToSize:frame
							  truncateWithString:@"…"
									   withInset:HPTruncationInsetiOS7
									   usingFont:internalTextView.font];
	}
	
	return truncatedString;
}

- (void)truncateStringToFitSingleLine
{
    NSString* originalString = [NSString stringWithString:internalTextView.text];
    
    // Truncate the string if needed
    NSString* truncatedString =
	[self _truncatedStringFittingASingleLineFromString:originalString];
	
    internalTextView.text = truncatedString;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UITextViewDelegate


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)textViewShouldBeginEditing:(UITextView *)textView {
	if ([delegate respondsToSelector:@selector(growingTextViewShouldBeginEditing:)]) {
		return [delegate growingTextViewShouldBeginEditing:self];
		
	} else {
		return YES;
	}
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)textViewShouldEndEditing:(UITextView *)textView {
	if ([delegate respondsToSelector:@selector(growingTextViewShouldEndEditing:)]) {
		return [delegate growingTextViewShouldEndEditing:self];
		
	} else {
		return YES;
	}
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)textViewDidBeginEditing:(UITextView *)textView {
    internalTextView.text = self.realText;
	if ([delegate respondsToSelector:@selector(growingTextViewDidBeginEditing:)]) {
		[delegate growingTextViewDidBeginEditing:self];
	}
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)textViewDidEndEditing:(UITextView *)textView {		
	if ([delegate respondsToSelector:@selector(growingTextViewDidEndEditing:)]) {
		[delegate growingTextViewDidEndEditing:self];
	}
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range
 replacementText:(NSString *)atext {
	
	//weird 1 pixel bug when clicking backspace when textView is empty
	if(![textView hasText] && [atext isEqualToString:@""]) return NO;
	
	//Added by bretdabaker: sometimes we want to handle this ourselves
	if ([delegate respondsToSelector:@selector(growingTextView:shouldChangeTextInRange:replacementText:)])
	{
		BOOL shouldChange = [delegate growingTextView:self shouldChangeTextInRange:range replacementText:atext];
		
		if (shouldChange)
		{
			NSString* textAfterReplacement =
			[textView.text stringByReplacingCharactersInRange:range withString:atext];
			[self ios6_hideAccessoryViewIfOverlapsWithText:textAfterReplacement animate:NO];
		}
		
		// Scroll to the end of the text
		if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1)
		{
			// iOS 6.1 or earlier
			[self performSelector:@selector(scrollTextViewToCaret) withObject:nil afterDelay:0];
		}
		
		return shouldChange;
	}
	
	BOOL shouldChange = YES;
	
	if ([atext isEqualToString:@"\n"])
	{
		if ([delegate respondsToSelector:@selector(growingTextViewShouldReturn:)])
		{
			BOOL shouldReturn = [delegate growingTextViewShouldReturn:self];
			
			if (shouldReturn)
			{
				[textView resignFirstResponder];
				shouldChange = NO;
			}
		}
	}
	
	if (shouldChange)
	{
		NSString* textAfterReplacement =
		[textView.text stringByReplacingCharactersInRange:range withString:atext];
		[self ios6_hideAccessoryViewIfOverlapsWithText:textAfterReplacement animate:atext.length <= 1];
	}
	
	return shouldChange;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)textViewDidChangeSelection:(UITextView *)textView {
	if ([delegate respondsToSelector:@selector(growingTextViewDidChangeSelection:)]) {
		[delegate growingTextViewDidChangeSelection:self];
	}
}

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement
{
	return NO;
}

#pragma mark - HPTextViewInternalDelegate

- (NSString *)textViewAccessibilityLabel:(UITextView *)textView
{
	if (textView == internalTextView)
	{
		return self.placeholder;
	}
	return nil;
}

- (NSString *)textViewAccessibilityValue:(UITextView *)textView
{
	if (textView == internalTextView)
	{
		return self.realText;
	}
	return nil;
}

@end


@implementation NSString (Layout)

- (NSString *)truncateString:(NSString *)originalString
				  withString:(NSString *)truncationString
						font:(UIFont *)font
		   constrainedToSize:(CGSize)maxSize
			   fittingHeight:(CGFloat)fittingHeight
		  enumerationOptions:(NSStringEnumerationOptions)enumerationOptions
{
	
	__block NSMutableString* truncatedText = [NSMutableString stringWithString:originalString];
	
	[self enumerateSubstringsInRange:NSMakeRange(0, self.length)
							 options:enumerationOptions
						  usingBlock:
	 ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
		 
		 NSRange rangeToDelete = enclosingRange;
		 rangeToDelete.length = truncatedText.length - rangeToDelete.location;
		 
		 [truncatedText replaceCharactersInRange:rangeToDelete withString:truncationString];
		 
		 CGSize newSize = [truncatedText sizeWithFont:font
									constrainedToSize:maxSize
										lineBreakMode:NSLineBreakByWordWrapping];
		 
		 //		 DDLogInfo(@"Truncated text: %@ (%@)", truncatedText, NSStringFromCGSize(newSize));
		 
		 if (fittingHeight >= newSize.height)
			 *stop = YES;
	 }];
	
	return [NSString stringWithString:truncatedText];
	
}


// http://stackoverflow.com/a/7829803/401329
// http://stackoverflow.com/questions/7099604/ellipsis-at-the-end-of-uitextview
- (NSString *)stringByTruncatingToSize:(CGRect)rect
                    truncateWithString:(NSString *)truncationString
                             withInset:(CGFloat)inset
                             usingFont:(UIFont *)font
{
    
    CGSize maxSize = CGSizeMake(rect.size.width  - (inset * 2), FLT_MAX);
    CGSize curSize = [self sizeWithFont:font constrainedToSize:maxSize lineBreakMode:NSLineBreakByWordWrapping];
    NSString *truncatedText = [NSString stringWithString:self];
    
    if (rect.size.height < curSize.height) {
        
		NSStringEnumerationOptions enumerateByWords =
		NSStringEnumerationByWords | NSStringEnumerationReverse |
		NSStringEnumerationLocalized;
		
		truncatedText =
		[self truncateString:self
				  withString:truncationString
						font:font
		   constrainedToSize:maxSize
			   fittingHeight:rect.size.height
		  enumerationOptions:enumerateByWords];
		
		// Ooops, the only word was truncated. Truncate by characters now...
		if ([truncatedText isEqualToString:truncationString]) {
			
			NSStringEnumerationOptions enumerateByCharacters =
			NSStringEnumerationByComposedCharacterSequences |
			NSStringEnumerationReverse | NSStringEnumerationLocalized;
			
			truncatedText =
			[self truncateString:self
					  withString:truncationString
							font:font
			   constrainedToSize:maxSize
				   fittingHeight:rect.size.height
			  enumerationOptions:enumerateByCharacters];
			
		}
        
    }
    
    return truncatedText;
}

@end