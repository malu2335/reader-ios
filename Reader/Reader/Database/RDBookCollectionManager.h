//
//  RDBookCollectionManager.h
//  Reader
//
//  书架合集:多本书合并为一个书架项,点开像「话列表」看每本书;可继续导入。
//

#import <Foundation/Foundation.h>
@class RDBookDetailModel;

NS_ASSUME_NONNULL_BEGIN

/// 合集变更后发出,object 为合集壳 RDBookDetailModel(可为 nil)
extern NSString * const RDBookCollectionDidChangeNotification;

@interface RDBookCollectionManager : NSObject

/// 将 ≥2 本书合并为新合集;返回合集壳,失败返回 nil
+ (nullable RDBookDetailModel *)createCollectionWithTitle:(NSString *)title
                                                    books:(NSArray <RDBookDetailModel *>*)books
                                             errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

/// 合集内成员。排序:同名/同系列按末尾序号 1·2·3;不同书名按首拼/首字母。
+ (NSArray <RDBookDetailModel *>*)membersOfCollectionId:(NSInteger)collectionId;

/// 书名智能比较(供合集排序与单测)
+ (NSComparisonResult)compareBookTitles:(NSString *)titleA to:(NSString *)titleB;

/// 全部合集壳(书架顶层 collection 项)
+ (NSArray <RDBookDetailModel *>*)allCollections;

/// 把书加入已有合集(若已在其他合集则先移出)
+ (BOOL)addBookId:(NSInteger)bookId
 toCollectionId:(NSInteger)collectionId
   errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

/// 从合集移出,恢复为书架独立项
+ (BOOL)removeBookId:(NSInteger)bookId fromCollection:(NSInteger)collectionId;

/// 解散合集:成员回顶层,删除合集壳
+ (BOOL)dissolveCollectionId:(NSInteger)collectionId;

/// 重命名合集壳
+ (BOOL)renameCollectionId:(NSInteger)collectionId title:(NSString *)title;

/// 刷新合集壳的 author/封面/readTime 摘要
+ (void)refreshCollectionSummary:(NSInteger)collectionId;

/// 生成不冲突的本地合集 bookId(<0)
+ (NSInteger)newCollectionBookId;

@end

NS_ASSUME_NONNULL_END
