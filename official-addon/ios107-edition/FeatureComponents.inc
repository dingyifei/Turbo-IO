void TIOStyleAction(UIButton *button,BOOL primary,BOOL destructive){
 NSString *title=[button titleForState:UIControlStateNormal];UIButtonConfiguration *c=primary?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;
 c.title=title;c.cornerStyle=UIButtonConfigurationCornerStyleLarge;c.contentInsets=NSDirectionalEdgeInsetsMake(14,18,14,18);
 c.baseBackgroundColor=destructive?UIColor.systemRedColor:TIOAccent();c.baseForegroundColor=primary?(destructive?UIColor.whiteColor:TIOPaper()):(destructive?UIColor.systemRedColor:TIOAccent());
 button.configuration=c;button.titleLabel.adjustsFontForContentSizeCategory=YES;
}
UIView *TIOEmptyState(NSString *symbol,NSString *title,NSString *detail){
 UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:symbol]];icon.tintColor=TIOAccent();icon.contentMode=UIViewContentModeScaleAspectFit;[icon.heightAnchor constraintEqualToConstant:38].active=YES;
 UILabel *name=Label(title,18,UIFontWeightMedium),*text=Label(detail,14,UIFontWeightRegular);name.textAlignment=text.textAlignment=NSTextAlignmentCenter;text.textColor=UIColor.secondaryLabelColor;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[icon,name,text]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=14;stack.layoutMarginsRelativeArrangement=YES;stack.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(24,22,24,22);return stack;
}
// Normalize only standard system surfaces in our navigation subtree. Preview
// canvases, maps, status colors and custom image rendering remain untouched.
static void TIOStyleFeatureSurface(UIView *view){
 UIColor *bg=view.backgroundColor;
 if([bg isEqual:UIColor.systemBackgroundColor]||[bg isEqual:UIColor.systemGroupedBackgroundColor])view.backgroundColor=TIOPaper();
 else if([bg isEqual:UIColor.secondarySystemGroupedBackgroundColor])view.backgroundColor=[TIOInk()colorWithAlphaComponent:.05];
 if([view isKindOfClass:UITextView.class]){UITextView *text=(id)view;text.tintColor=TIOAccent();text.adjustsFontForContentSizeCategory=YES;}
 if([view isKindOfClass:UITextField.class]){UITextField *field=(id)view;field.tintColor=TIOAccent();field.textColor=TIOInk();}
 if([view isKindOfClass:UIButton.class]){UIButton *button=(id)view;UIButtonConfiguration *c=button.configuration;if([c.baseBackgroundColor isEqual:UIColor.systemIndigoColor]||[c.baseBackgroundColor isEqual:UIColor.systemBlueColor]){c.baseBackgroundColor=TIOAccent();c.baseForegroundColor=TIOPaper();button.configuration=c;}}
 for(UIView *child in view.subviews)TIOStyleFeatureSurface(child);
}
