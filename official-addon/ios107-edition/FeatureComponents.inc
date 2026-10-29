/* Forwarding shims over TIODesign; new code calls TIODesign directly. */
void TIOStyleAction(UIButton *button,BOOL primary,BOOL destructive){
 TIODesignStyleButton(button,destructive?(primary?TIODesignButtonDestructiveFilled:TIODesignButtonDestructive):(primary?TIODesignButtonPrimary:TIODesignButtonSecondary));
}
UIView *TIOEmptyState(NSString *symbol,NSString *title,NSString *detail){return TIODesignEmptyState(symbol,title,detail,nil,nil);}
static void TIOStyleFeatureSurface(UIView *view){TIODesignStyleSurface(view);}
