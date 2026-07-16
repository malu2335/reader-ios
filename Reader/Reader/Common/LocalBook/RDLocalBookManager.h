//
//  RDLocalBookManager.h
//  Reader
//
//  本地书籍导入与管理:文件拷贝、格式调度、封面、入库。
//  本地书 bookId 恒为负数,不参与任何网络请求。
//

#import <UIKit/UIKit.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

//导入完成后发出,书架监听刷新
extern NSString * const RDLocalBookImportedNotification;
//请求打开导入文件选择器(空书架等入口发出,书架控制器响应)
extern NSString * const RDLocalBookImportRequestNotification;

/// book:成功或重复时返回书籍; errorMessage:失败原因; isDuplicate:内容哈希已存在于书架
typedef void(^RDLocalBookImportCompletion)(RDBookDetailModel * _Nullable book, NSString * _Nullable errorMessage, BOOL isDuplicate);

@interface RDLocalBookManager : NSObject

+ (NSArray <NSString *>*)supportedExtensions;   //txt/epub/mobi/pdf/azw

+ (BOOL)isSupportedFileURL:(NSURL *)url;

/// 异步导入(后台解析,主线程回调)。按文件内容 MD5 去重:同一文件不重复入库。
+ (void)importBookAtURL:(NSURL *)url complete:(nullable RDLocalBookImportCompletion)complete;

/// 本地书的绝对文件路径
+ (nullable NSString *)absolutePathForBook:(RDBookDetailModel *)book;

/// 本地书封面(内嵌封面文件,或按标题生成的纸质风格封面)
+ (nullable UIImage *)coverForBook:(RDBookDetailModel *)book;

/// 删除本地书:阅读记录、章节与文件
+ (void)removeLocalBook:(RDBookDetailModel *)book;

/// 重新解析书籍文件并重建章节库(恢复备份用),同步执行,在后台队列调用
+ (BOOL)rebuildChaptersForBook:(RDBookDetailModel *)book errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

+ (NSString *)booksDirectory;

@end

NS_ASSUME_NONNULL_END
