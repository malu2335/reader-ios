//
//  RDAIProfileEditController.h
//  Reader
//

#import "RDBaseViewController.h"
@class RDAIConfigProfile;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RDAIProfileEditMode) {
    /// 翻译服务配置(OpenAI / Anthropic / Gemini 等)
    RDAIProfileEditModeTranslate = 0,
    /// AI 朗读引擎(OpenAI TTS / 小米 MiMo 等)
    RDAIProfileEditModeTTS = 1,
};

@interface RDAIProfileEditController : RDBaseViewController
/// nil 表示新建
@property (nonatomic, strong, nullable) RDAIConfigProfile *profile;
/// 编辑用途;默认翻译。新建 TTS 时传 RDAIProfileEditModeTTS
@property (nonatomic, assign) RDAIProfileEditMode editMode;
@end

NS_ASSUME_NONNULL_END
