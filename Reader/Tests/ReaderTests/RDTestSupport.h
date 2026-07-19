//
//  RDTestSupport.h
//  ReaderTests
//
//  用例共用的环境搭建。
//
//  说明:PATH_DOCUMENT 是直接取 NSSearchPathForDirectories 的宏,无法重定向,
//  而单元测试是注入宿主 app 进程内跑的,因此所有用例共用模拟器 app 容器里的
//  同一个 Documents 与同一个 WCDB 单例。隔离靠两件事:
//    1. 每个用例开始前用应用自己的删除接口清空书库(clean slate);
//    2. fixture 内容带唯一后缀,bookId 由内容 MD5 派生,不同用例天然不撞。
//

#import <XCTest/XCTest.h>

@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

@interface RDTestSupport : NSObject

/// 清空书库:删除全部记录行、章节、书签、历史与 LocalBooks 下的文件。
/// 同步返回时保证已删干净(内部等待变更队列排空)。
+ (void)resetLibrary;

/// 造一本 chapterCount 章的 TXT(内容带唯一后缀),返回临时目录里的文件 URL
+ (NSURL *)makeTxtBookWithTitle:(NSString *)title chapters:(NSInteger)chapterCount;

/// 造一个约 byteSize 字节的 TXT(用于预算/超限用例)
+ (NSURL *)makeTxtBookWithTitle:(NSString *)title byteSize:(NSUInteger)byteSize;

/// 同步导入一本书;返回导入结果(失败时 book 为 nil,message 为错误文案)
+ (RDBookDetailModel *_Nullable)importBookAtURL:(NSURL *)url
                                        message:(NSString *_Nullable *_Nullable)message
                                    isDuplicate:(BOOL *_Nullable)isDuplicate;

/// 让 LocalBooks 目录暂时不可写,用于文件落盘失败的故障注入
+ (BOOL)setBooksDirectoryWritable:(BOOL)writable;

/// 等待书库变更串行队列排空(删除的章节清理等异步收尾)
+ (void)waitForLibraryQueue;

/// 同步等待一个异步回调;超时返回 NO
+ (BOOL)waitFor:(void (^)(dispatch_block_t done))block timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
