//
//  RDLibraryMutationCoordinator.m
//  Reader
//

#import "RDLibraryMutationCoordinator.h"
#import "RDLocalBookManager.h"

static void *kRDLibraryMutationQueueKey = &kRDLibraryMutationQueueKey;

@implementation RDLibraryMutationCoordinator

+ (dispatch_queue_t)queue
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.reader.library.mutation", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue,
                                    kRDLibraryMutationQueueKey,
                                    kRDLibraryMutationQueueKey,
                                    NULL);
    });
    return queue;
}

+ (BOOL)isOnQueue
{
    return dispatch_get_specific(kRDLibraryMutationQueueKey) == kRDLibraryMutationQueueKey;
}

+ (void)performSync:(dispatch_block_t)block
{
    if (!block) {
        return;
    }
    if ([self isOnQueue]) {
        block();
        return;
    }
    dispatch_sync([self queue], block);
}

+ (void)performAsync:(dispatch_block_t)block
{
    if (!block) {
        return;
    }
    dispatch_async([self queue], block);
}

+ (void)postLibraryChanged:(id)object
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RDLocalBookImportedNotification
                                                            object:object];
    });
}

@end
