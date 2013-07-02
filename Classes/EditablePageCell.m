// EditablePageCell.m
//
// Kraftstoff


#import "EditablePageCell.h"
#import "FuelCalculatorController.h"
#import "AppDelegate.h"


static CGFloat const margin = 8.0;


@implementation EditablePageCell


@synthesize textField;
@synthesize valueIdentifier;
@synthesize delegate;


- (void)finishConstruction
{
    BOOL useOldStyle = ([AppDelegate systemMajorVersion] < 7);

	[super finishConstruction];

    // Create textfield
    textField = [[EditablePageCellTextField alloc] initWithFrame: CGRectZero];

	textField.font                     = (useOldStyle) ? [UIFont systemFontOfSize: 15.0] : [UIFont fontWithName:@"HelveticaNeue-Light" size: 17.0];
	textField.textAlignment            = NSTextAlignmentRight;
	textField.autocapitalizationType   = UITextAutocapitalizationTypeNone;
	textField.autocorrectionType       = UITextAutocorrectionTypeNo;
	textField.backgroundColor          = [UIColor clearColor];
	textField.clearButtonMode          = UITextFieldViewModeWhileEditing;
	textField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	textField.autoresizingMask         = UIViewAutoresizingFlexibleWidth;
	textField.userInteractionEnabled   = NO;

	[self.contentView addSubview: textField];


    // Configure the default textlabel
    UILabel *label = self.textLabel;

	label.textAlignment        = NSTextAlignmentLeft;
	label.font                 = (useOldStyle) ? [UIFont boldSystemFontOfSize: 17.0] : [UIFont fontWithName:@"HelveticaNeue" size: 17.0];
	label.highlightedTextColor = [UIColor blackColor];
	label.textColor            = [UIColor blackColor];

    if (useOldStyle)
    {
        label.shadowColor      = [UIColor whiteColor];
        label.shadowOffset     = CGSizeMake (0, 1);
    }
}


- (NSString*)accessibilityLabel
{
	return [NSString stringWithFormat: @"%@ %@", self.textLabel.text, textField.text];
}


- (void)configureForData: (id)dataObject
          viewController: (id)viewController
               tableView: (UITableView*)tableView
               indexPath: (NSIndexPath*)indexPath
{
	[super configureForData: dataObject viewController: viewController tableView: tableView indexPath: indexPath];

	self.textLabel.text   = ((NSDictionary*)dataObject)[@"label"];
    self.delegate         = viewController;
    self.valueIdentifier  = ((NSDictionary*)dataObject)[@"valueIdentifier"];

	textField.placeholder = ((NSDictionary*)dataObject)[@"placeholder"];
	textField.delegate    = self;
}


- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGFloat leftOffset = ([AppDelegate systemMajorVersion] >= 7) ? 6.0 : 0.0;
    CGFloat labelWidth = [self.textLabel.text sizeWithFont: self.textLabel.font].width;
    CGFloat height     = self.contentView.bounds.size.height;
	CGFloat width      = self.contentView.bounds.size.width;

    self.textLabel.frame = CGRectMake (leftOffset + margin, 0.0, labelWidth,                    height - 1);
    self.textField.frame = CGRectMake (leftOffset + margin, 0.0, width - 2*margin - leftOffset, height - 1);
}


- (UIColor*)invalidTextColor
{
    if ([AppDelegate systemMajorVersion] < 7)
        return [UIColor colorWithRed: 0.42 green: 0.0 blue: 0.0 alpha: 1.0];
    else
        // FIXME: when editing a field with inline picker, this should be black
        return self.tintColor;    //[UIColor colorWithRed: 1.0 green: 0.4 blue: 0.4 alpha: 1.0];
}



#pragma mark -
#pragma mark UITextFieldDelegate



- (void)textFieldDidEndEditing: (UITextField*)aTextField
{
    aTextField.userInteractionEnabled = NO;
}

@end
