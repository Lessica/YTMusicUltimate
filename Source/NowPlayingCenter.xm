@import Foundation;
@import MediaPlayer;

#import "Headers/YTQueueItem.h"

#define TAG "YTMusicUltimate+NowPlayingCenter : "

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface YTQueueItemsController : NSObject
@property (nonatomic, strong) NSArray *queueItems;
@end

@interface YTQueueController : NSObject
@property (nonatomic, assign) NSUInteger nowPlayingIndex;
@property (nonatomic, strong) YTQueueItemsController *queueItemsController;
@property (nonatomic, strong) YTQueueItem *nowPlayingMusicQueueItem;
- (void)ytmu_nowPlayingItemChanged;
@end

@interface MPNowPlayingInfoCenter (YTMusicUltimate)

@property (nonatomic, strong) NSTimer *ytmu_updateTimer;

- (void)ytmu_updateTimerFired:(NSTimer *)timer;
- (void)reloadLyricsIfNeededWithTrackId:(NSString *)trackId userInfo:(NSDictionary *)userInfo;

@end

static YTQueueController *gQueueController = nil;

%hook YTQueueController

- (void)commonInit {
    %orig;
    gQueueController = self;
#if DEBUG
    NSLog(@TAG "YTQueueController initialized : %@", self);
#endif
    [self ytmu_nowPlayingItemChanged];
}

- (void)setNowPlayingIndex:(NSUInteger)index {
    %orig(index);
    [self ytmu_nowPlayingItemChanged];
}

%new
- (void)ytmu_nowPlayingItemChanged {
#if DEBUG
    NSLog(@TAG "Now playing track : %@ <%@>", [self.nowPlayingMusicQueueItem.videoRenderer.title stringWithFormattingRemoved], self.nowPlayingMusicQueueItem.localID);
#endif
}

%end

%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)info {

    if (!YTMU(@"sendLyricsToMediaControls") ||
        !info ||
        !info[MPMediaItemPropertyTitle] ||
        !info[MPMediaItemPropertyArtist]
    ) {
        %orig;
        return;
    }

#if DEBUG
    // NSLog(@TAG "Now playing info: %@", info);
#endif

    NSString *title = info[MPMediaItemPropertyTitle];
    NSString *subtitle = info[MPMediaItemPropertyArtist];

    NSMutableDictionary *newInfo = [info mutableCopy];
    if ([info[@"SkipSubtitleCombination"] boolValue] || [subtitle hasPrefix:[NSString stringWithFormat:@"%@ — ", title]]) {
    } else {
        NSString *newSubtitle = [NSString stringWithFormat:@"%@ — %@", title, subtitle];
        newInfo[MPMediaItemPropertyArtist] = newSubtitle;
    }

    %orig(newInfo);
}

%new
- (void)ytmu_updateTimerFired:(NSTimer *)timer {

}

%new
- (void)reloadLyricsIfNeededWithTrackId:(NSString *)trackId userInfo:(NSDictionary *)userInfo {

}

%end
