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

+ (NSArray <NSString *>*)supportedExtensions;   //txt/epub/mobi/pdf/azw/zip/cbz

+ (BOOL)isSupportedFileURL:(NSURL *)url;        //含图片文件夹

/// 异步导入(后台解析,主线程回调)。按文件内容 MD5 去重:同一文件不重复入库。
/// 支持 zip/cbz 图集与「含图片的文件夹」(文件夹会打包为 cbz 再入库)。
+ (void)importBookAtURL:(NSURL *)url complete:(nullable RDLocalBookImportCompletion)complete;

/// 本地书的绝对文件路径
+ (nullable NSString *)absolutePathForBook:(RDBookDetailModel *)book;

/// 本地书封面(内嵌封面文件,或按标题生成的纸质风格封面)
+ (nullable UIImage *)coverForBook:(RDBookDetailModel *)book;

/// 同步串行回填旧 PDF 的首页封面;内部在导入队列执行,请从后台队列调用。
+ (void)preparePDFCoversForBooks:(NSArray <RDBookDetailModel *>*)books;

/// 手动封面独立于 coverImg,正数在线书与负数本地书均可使用。
+ (nullable NSString *)customCoverPathForBook:(RDBookDetailModel *)book;
+ (nullable UIImage *)customCoverForBook:(RDBookDetailModel *)book;
+ (NSUInteger)beginCustomCoverRequestForBook:(RDBookDetailModel *)book;
+ (BOOL)isCustomCoverRequestCurrent:(NSUInteger)requestVersion
                            forBook:(RDBookDetailModel *)book;
+ (BOOL)saveCustomCover:(UIImage *)cover
                forBook:(RDBookDetailModel *)book
         requestVersion:(NSUInteger)requestVersion
           errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
+ (nullable NSData *)customCoverDataForBook:(RDBookDetailModel *)book;
+ (BOOL)restoreCustomCoverData:(nullable NSData *)data forBook:(RDBookDetailModel *)book;
+ (void)removeCustomCoverForBook:(RDBookDetailModel *)book;

/// 删除本地书:阅读记录、章节与文件
+ (void)removeLocalBook:(RDBookDetailModel *)book;

/// 重新解析书籍文件得到章节(恢复备份用),同步执行,在后台队列调用。
/// 只解析不写库:章节与读记录由 RDLibraryTransaction 一次性原子提交;
/// 同时把 book.charpterModel 归位到解析结果里的对应章节。
/// 返回 nil 表示失败(errorMessage 有值);PDF/漫画返回空数组。
+ (nullable NSArray *)parseChaptersForBook:(RDBookDetailModel *)book errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

/// 同上,但从指定路径解析(恢复备份时源文件还在 staging 目录里,尚未进正式路径)
+ (nullable NSArray *)parseChaptersForBook:(RDBookDetailModel *)book
                                    atPath:(nullable NSString *)path
                              errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

+ (NSString *)booksDirectory;

@end

NS_ASSUME_NONNULL_END
