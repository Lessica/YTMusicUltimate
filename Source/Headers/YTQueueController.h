#import "YTQueueItem.h"
#import "YTQueueItemsController.h"
#import <Foundation/Foundation.h>

@interface YTQueueController : NSObject
@property (nonatomic, assign) NSUInteger nowPlayingIndex;
@property (nonatomic, strong) YTQueueItemsController *queueItemsController;
@property (nonatomic, strong) YTQueueItem *nowPlayingMusicQueueItem;
@property (nonatomic) NSTimeInterval nowPlayingVideoMediaTime;
- (void)ytmu_nowPlayingItemChanged;
@end