//
//  RDReadSpeechBar.h
//  Reader
//
//  听书悬浮控制条:播放/暂停、语速、切换语音、退出
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDReadSpeechBar : UIView

@property (nonatomic,copy,nullable) void (^onPlayPause)(void);
@property (nonatomic,copy,nullable) void (^onRate)(void);
@property (nonatomic,copy,nullable) void (^onVoice)(void);
@property (nonatomic,copy,nullable) void (^onExit)(void);

- (void)updatePlaying:(BOOL)playing rate:(CGFloat)rate;
- (void)updateVoiceName:(nullable NSString *)name;
- (void)showInView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
