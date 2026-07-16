//
//  RDAIProfileEditController.h
//  Reader
//

#import "RDBaseViewController.h"
@class RDAIConfigProfile;

NS_ASSUME_NONNULL_BEGIN

@interface RDAIProfileEditController : RDBaseViewController
/// nil 表示新建
@property (nonatomic, strong, nullable) RDAIConfigProfile *profile;
@end

NS_ASSUME_NONNULL_END
