//
//  RDHarnessSelfTests.m
//  ReaderTests
//
//  自检:先证明等待工具本身可靠,再谈业务用例的成败。
//

#import "RDTestSupport.h"
#import "RDLibraryMutationCoordinator.h"

@interface RDHarnessSelfTests : XCTestCase
@end

@implementation RDHarnessSelfTests

/// waitFor: 能收到主队列上的异步回调
- (void)testWaitForCatchesMainQueueCallback
{
    __block BOOL called = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        dispatch_async(dispatch_get_main_queue(), ^{
            called = YES;
            done();
        });
    } timeout:5];
    XCTAssertTrue(finished, @"waitFor: 必须能等到主队列回调");
    XCTAssertTrue(called);
}

/// waitFor: 能收到后台线程转主队列的回调(导入用的正是这个形状)
- (void)testWaitForCatchesBackgroundThenMainCallback
{
    __block BOOL called = NO;
    BOOL finished = [RDTestSupport waitFor:^(dispatch_block_t done) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSThread sleepForTimeInterval:0.2];
            dispatch_async(dispatch_get_main_queue(), ^{
                called = YES;
                done();
            });
        });
    } timeout:10];
    XCTAssertTrue(finished, @"waitFor: 必须能等到后台转主队列的回调");
    XCTAssertTrue(called);
}

/// 变更队列可用且不会把主线程堵死
- (void)testLibraryQueueDrains
{
    __block BOOL ran = NO;
    [RDLibraryMutationCoordinator performAsync:^{
        ran = YES;
    }];
    [RDTestSupport waitForLibraryQueue];
    XCTAssertTrue(ran, @"变更队列应能正常排空");
}

@end
