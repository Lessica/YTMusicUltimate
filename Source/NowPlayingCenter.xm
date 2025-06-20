@import Foundation;
@import MediaPlayer;

#import "Headers/YTICommand.h"
#import "Headers/YTQueueItem.h"
#import "Utils/LyricsParser.h"

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

@interface YTIKeyValuePair : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;
@end

@interface YTIServiceTrackingParams : NSObject
- (NSArray<YTIKeyValuePair *> *)paramsArray;
@end

@interface YTIResponseContext : NSObject
- (NSArray<YTIServiceTrackingParams *> *)serviceTrackingParamsArray;
@end

@interface YTIBrowseResponse : NSObject
- (YTIResponseContext *)responseContext;
@end

@interface YTITabRenderer : NSObject
- (YTICommand *)endpoint;
@end

@interface YTIRenderer : NSObject
- (NSString *)videoId;
@end

@interface YTIWatchNextTabbedResultsRenderer : NSObject
@property (retain, nonatomic) YTIRenderer *videoMetadata;
@end

static YTQueueController *gQueueController = nil;
static NSString *gNowPlayingBrowseId = nil;

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
    NSLog(@TAG "Now playing track : %@ <%@>", [self.nowPlayingMusicQueueItem.videoRenderer.title stringWithFormattingRemoved], self.nowPlayingMusicQueueItem.videoRenderer.videoId);
#endif
}

%end

%hook YTMPlayerTabViewController

- (void)updateTabs:(NSArray<YTITabRenderer *> *)tabs {
    %orig(tabs);
    NSAssert([NSThread isMainThread], @"updateTabs should be called on the main thread");
#if DEBUG
    NSLog(@TAG "YTMPlayerTabViewController updated tabs : %@", tabs);
#endif
    if (tabs.count == 3) {
        YTITabRenderer *lyricsTab = tabs[1];
        NSString *currentBrowseId = lyricsTab.endpoint.browseEndpoint.browseId;
        gNowPlayingBrowseId = currentBrowseId;
#if DEBUG
        NSLog(@TAG "Current browse_id : %@", currentBrowseId);
#endif
    }
}

%end

%hook YTIBrowseResponse

- (instancetype)initWithData:(NSData *)data extensionRegistry:(id)arg2 error:(NSError **)error {
    YTIBrowseResponse *response = %orig;
#if DEBUG
    NSLog(@TAG "YTIBrowseResponse initialized with data : <%lu bytes>", (unsigned long)data.length);
#endif
    LyricsParser *parser = [[LyricsParser alloc] initWithData:data];
    Lyrics *lyrics = [parser parseLyrics];
    if (lyrics) {
        YTIResponseContext *context = [response responseContext];
        NSArray<YTIServiceTrackingParams *> *trackingParams = [context serviceTrackingParamsArray];
        NSString *browseId = nil;
        for (YTIServiceTrackingParams *params in trackingParams) {
            for (YTIKeyValuePair *pair in [params paramsArray]) {
                if ([pair.key isEqualToString:@"browse_id"]) {
                    browseId = pair.value;
                    break;
                }
            }
            if (browseId) break;
        }
#if DEBUG
        NSLog(@TAG "Parsed lyrics : %@ <%lu lines> browse_id %@", lyrics, (unsigned long)lyrics.lines.count, browseId);
#endif
    }
    return response;
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
