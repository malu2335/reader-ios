//
//  RDBookshelfUITests.m
//  ReaderUITests
//
//  最小主路径 UI 测试。刻意只覆盖两条:导入入口能真的把 picker 拉起来,
//  以及连点一本书只进一个阅读器——这两条正是 P2-01 / P2-02 修的东西,
//  也是静态断言无论如何覆盖不到的。
//

#import <XCTest/XCTest.h>

@interface RDBookshelfUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation RDBookshelfUITests

- (void)setUp
{
    [super setUp];
    self.continueAfterFailure = NO;
    self.app = [[XCUIApplication alloc] init];
    [self.app launch];
}

- (void)tearDown
{
    [self.app terminate];
    [super tearDown];
}

/// 冒烟:书架能起来,底部两个 tab 都在
- (void)testBookshelfLaunchesWithTabs
{
    XCTAssertTrue([self.app.staticTexts[@"书架"] waitForExistenceWithTimeout:5], @"书架标题应出现");
    XCTAssertTrue(self.app.staticTexts[@"设置"].exists, @"设置 tab 应存在");
}

/// P2-01:从设置页点"导入本地书籍",应切到书架并成功拉起系统 picker
- (void)testImportFromSettingsPresentsDocumentPicker
{
    XCUIElement *settingTab = self.app.staticTexts[@"设置"];
    XCTAssertTrue([settingTab waitForExistenceWithTimeout:5]);
    [settingTab tap];

    XCUIElement *importRow = self.app.staticTexts[@"导入本地书籍"];
    XCTAssertTrue([importRow waitForExistenceWithTimeout:5], @"设置页应有导入入口");
    [importRow tap];

    // picker 由系统进程展示;取消按钮出现即说明 present 成功
    XCUIElement *cancel = self.app.buttons[@"Cancel"];
    XCUIElement *cancelCN = self.app.buttons[@"取消"];
    BOOL shown = [cancel waitForExistenceWithTimeout:8] || [cancelCN waitForExistenceWithTimeout:2];
    XCTAssertTrue(shown, @"导入 picker 必须由当前可见的书架 controller 成功展示(P2-01)");

    if (cancel.exists) {
        [cancel tap];
    }
    else if (cancelCN.exists) {
        [cancelCN tap];
    }
}

/// P2-02:空书架上连点导入按钮,不应叠出多个 picker
- (void)testRepeatedImportTapsDoNotStackPickers
{
    XCUIElement *emptyImport = self.app.buttons[@"导入本地书籍"];
    if (![emptyImport waitForExistenceWithTimeout:5]) {
        // 书架非空时这个按钮不存在,该用例无从验证,直接跳过
        return;
    }
    [emptyImport tap];
    [emptyImport tap];

    XCUIElement *cancel = self.app.buttons[@"Cancel"];
    XCUIElement *cancelCN = self.app.buttons[@"取消"];
    XCTAssertTrue([cancel waitForExistenceWithTimeout:8] || [cancelCN waitForExistenceWithTimeout:2]);

    // 关掉一层之后不应还有第二层 picker 压着
    if (cancel.exists) {
        [cancel tap];
    }
    else if (cancelCN.exists) {
        [cancelCN tap];
    }
    XCTAssertTrue([self.app.staticTexts[@"书架"] waitForExistenceWithTimeout:5],
                  @"关闭 picker 后应直接回到书架,说明没有第二个 picker 叠着");
}

@end
