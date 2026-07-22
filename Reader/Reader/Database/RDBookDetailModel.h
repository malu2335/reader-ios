//
//  RDBookDetailModel.h
//  Reader
//
//  Created by yuenov on 2019/11/21.
//  Copyright © 2019 yuenov. All rights reserved.
//

#import <Foundation/Foundation.h>
@class RDCharpterModel;
@class RDLibraryDetailModel;
@class RDShareModel;

@interface RDBookDetailModel : RDModel

@property (nonatomic,assign) NSInteger bookId;
@property (nonatomic,strong) NSString *title;
@property (nonatomic,strong) NSString *coverImg;
@property (nonatomic,strong) NSString *author;
@property (nonatomic,strong) NSString *category;
@property (nonatomic,strong) NSString *word;
@property (nonatomic,strong) NSString *charpter;    //最近更新的章节
@property (nonatomic,strong) NSString *desc;
@property (nonatomic,assign) NSTimeInterval time;   //更新时间
@property (nonatomic,assign) BOOL end;          //是否连载
@property (nonatomic,assign) BOOL updateEnd;    //是否连载
@property (nonatomic,assign) NSInteger updateCharpterId;  //更新的章节
@property (nonatomic,assign) NSInteger total;   //总章节数
/// 在线书城残留字段(本地书不使用);保留以兼容旧归档/YYModel
@property (nonatomic,strong) NSArray *recommend;
@property (nonatomic,strong) RDShareModel *share;


//添加到书架时的阅读进度
@property (nonatomic,assign) BOOL bookUpdate;   //书架上的书是否有更新
@property (nonatomic,strong) RDCharpterModel *charpterModel;  //当前阅读的章节
@property (nonatomic,assign) NSInteger page;        //当前阅读的进度(页码,字体变化时仅作参考)
@property (nonatomic,assign) NSInteger charOffset;  //章节内字符偏移(阅读记忆主坐标,字体变化后恢复用)
/// 最近阅读章节名(书架列表轻量展示,避免反序列化 charpterModel 大字段)
@property (nonatomic,strong) NSString *readChapterName;
@property (nonatomic,assign) NSTimeInterval readTime;   //阅读的最后时间
@property (nonatomic,assign) BOOL onBookshelf;      //是否在书架上

//本地导入书籍(bookId 为负数,不参与任何网络请求)
@property (nonatomic,strong) NSString *localPath;   //Documents/LocalBooks 下的相对文件名
@property (nonatomic,strong) NSString *fileType;    //txt / epub / mobi / pdf / cbz / collection(合集壳)
/// 所属合集 bookId;0 表示顶层独立书或合集壳本身
@property (nonatomic,assign) NSInteger collectionId;
/// 合集内排序
@property (nonatomic,assign) NSInteger collectionOrder;

-(BOOL)isLocalBook;
/// 书架合集壳(fileType=collection),点开进成员目录而非阅读器
-(BOOL)isCollection;
@end
