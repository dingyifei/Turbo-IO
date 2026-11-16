#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT UIViewController *_Nullable TIOTopController(void);
FOUNDATION_EXPORT void TIONotice(UIViewController *_Nullable from, NSString *title, NSString *_Nullable message);
FOUNDATION_EXPORT void TIOConfirm(UIViewController *_Nullable from, NSString *title, NSString *_Nullable message,
                                  NSString *action, BOOL destructive, void(^confirmed)(void));
FOUNDATION_EXPORT void TIOChoose(UIViewController *_Nullable from, NSString *title, NSString *_Nullable message,
                                 NSArray<NSString *> *options, NSInteger selected, NSIndexSet *_Nullable destructive,
                                 void(^chosen)(NSInteger index));
FOUNDATION_EXPORT void TIOAttachInfo(UIViewController *vc, NSString *title, NSString *body);
NS_ASSUME_NONNULL_END
