#include <Foundation/Foundation.h>
@import Foundation;
@import MediaPlayer;

#import "Headers/YTIBrowseResponse.h"
#import "Headers/YTICommand.h"
#import "Headers/YTIKeyValuePair.h"
#import "Headers/YTIServiceTrackingParams.h"
#import "Headers/YTIRenderer.h"
#import "Headers/YTIResponseContext.h"
#import "Headers/YTITabRenderer.h"
#import "Headers/YTIWatchNextTabbedResultsRenderer.h"
#import "Headers/YTQueueController.h"
#import "Headers/YTQueueItem.h"
#import "Headers/YTQueueItemsController.h"
#import "Headers/MPNowPlayingInfoCenter+YTMusicUltimate.h"
#import "Utils/LyricsParser.h"
#import "Utils/LyricsManager.h"

#define TAG "YTMusicUltimate+NowPlayingCenter : "

static BOOL YTMU(NSString *key) {
    NSDictionary *YTMUltimateDict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [YTMUltimateDict[key] boolValue];
}

@interface MDCTabBarView : UIView
- (NSArray<UITabBarItem *> *)items;
- (void)setSelectedItem:(UITabBarItem *)item;
@end

@interface YTMPlayerTabView : UIView
- (MDCTabBarView *)tabBar;
@end

@interface YTMPlayerTabViewController : UIViewController
@property (nonatomic, strong) YTMPlayerTabView *view;
- (void)tabBarView:(MDCTabBarView *)view didSelectItem:(UITabBarItem *)item;
@end

static BOOL gIsEnabled = NO;
static dispatch_queue_t gLyricsQueue = nil;
static YTQueueController *gQueueController = nil;
static NSString *gNowPlayingBrowseId = nil;
static MPNowPlayingInfoCenter *gNowPlayingInfoCenter = nil;
static NSDictionary *gLastNowPlayingInfo = nil;
static NSDate *gLastNowPlayingInfoReportedAt = nil;

%hook YTQueueController

- (void)commonInit {
    %orig;
    if (!gIsEnabled) {
        return;
    }
    gQueueController = self;
#if DEBUG
    NSLog(@TAG "YTQueueController initialized : %@", self);
#endif
    [self ytmu_nowPlayingItemChanged];
}

- (void)setNowPlayingIndex:(NSUInteger)index {
    %orig;
    if (!gIsEnabled) {
        return;
    }
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
    %orig;
    if (!gIsEnabled) {
        return;
    }
    NSAssert([NSThread isMainThread], @"updateTabs should be called on the main thread");
#if DEBUG
    NSLog(@TAG "YTMPlayerTabViewController updated tabs : %@", tabs);
#endif
    if (tabs.count == 3) {
        YTITabRenderer *lyricsTab = tabs[1];
        NSString *currentBrowseId = lyricsTab.endpoint.browseEndpoint.browseId;
        dispatch_async(gLyricsQueue, ^{
            gNowPlayingBrowseId = [currentBrowseId copy];
        });
#if DEBUG
        NSLog(@TAG "Current browse_id : %@", currentBrowseId);
#endif
        /* trigger the load of lyrics */
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<UITabBarItem *> *items = [self.view.tabBar items];
            if (items.count == 3) {
                UITabBarItem *lyricsItem = items[1];
                [self.view.tabBar setSelectedItem:lyricsItem];
            }
        });
    }
}

- (void)tabBarView:(MDCTabBarView *)view didSelectItem:(UITabBarItem *)item {
    %orig;
    if (!gIsEnabled) {
        return;
    }
#if DEBUG
    NSLog(@TAG "YTMPlayerTabViewController tabBarView : %@ didSelectItem : %@", view, item);
#endif
}

%end

%hook YTIBrowseResponse

- (instancetype)initWithData:(NSData *)data extensionRegistry:(id)arg2 error:(NSError **)error {
    YTIBrowseResponse *response = %orig;
#if DEBUG
    NSLog(@TAG "YTIBrowseResponse initialized with data : <%lu bytes>", (unsigned long)data.length);
#endif
    
    if (!gIsEnabled || !data || !response) {
        return response;
    }

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

        [[LyricsManager sharedManager] setLyrics:lyrics forKey:browseId];
#if DEBUG
        NSLog(@TAG "Parsed lyrics : %@ <%lu lines> browse_id %@", lyrics, (unsigned long)lyrics.lines.count, browseId);
#endif

        dispatch_async(gLyricsQueue, ^{
            if (![gNowPlayingBrowseId isEqualToString:browseId]) {
                return;
            }
            
            if (!gNowPlayingInfoCenter || !gLastNowPlayingInfo || !gLastNowPlayingInfoReportedAt) {
                return;
            }

            NSDate *startedAt = gLastNowPlayingInfoReportedAt;
            NSDate *endedAt = [NSDate date];
            NSTimeInterval delta = MAX(0, [endedAt timeIntervalSinceDate:startedAt]);

            NSMutableDictionary *newInfo = [gLastNowPlayingInfo mutableCopy];
            NSTimeInterval elapsedPlaybackTime = [newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
            NSTimeInterval playbackDuration = [newInfo[MPMediaItemPropertyPlaybackDuration] doubleValue];
            NSTimeInterval playbackRate = newInfo[MPNowPlayingInfoPropertyPlaybackRate] ? [newInfo[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] : 1.0;

            NSTimeInterval newElapsedPlaybackTime = MIN(elapsedPlaybackTime + delta * playbackRate, playbackDuration);
            newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(newElapsedPlaybackTime);
            newInfo[@"SkipSubtitleCombination"] = @YES;

            dispatch_async(dispatch_get_main_queue(), ^{
                [gNowPlayingInfoCenter setNowPlayingInfo:newInfo];
            });
        });
    }
    return response;
}

%end

%hook MPNowPlayingInfoCenter

%property (nonatomic, strong) NSTimer *ytmu_updateTimer;

- (void)setNowPlayingInfo:(NSDictionary *)info {

    if (!gIsEnabled || !info ||
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

    dispatch_async(gLyricsQueue, ^{
        gNowPlayingInfoCenter = self;
        gLastNowPlayingInfo = newInfo;
        gLastNowPlayingInfoReportedAt = [NSDate date];
    });

    NSTimeInterval elapsedPlaybackTime = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
    NSTimeInterval playbackDuration = [info[MPMediaItemPropertyPlaybackDuration] doubleValue];
    NSTimeInterval playbackRate = info[MPNowPlayingInfoPropertyPlaybackRate] ? [info[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] : 1.0;

    __block NSMutableDictionary *nextInfo = nil;
    __block NSTimeInterval nextInterval = 0;

    dispatch_sync(gLyricsQueue, ^{
        NSString *trackId = [gNowPlayingBrowseId copy];
        Lyrics *lyrics = [[LyricsManager sharedManager] lyricsForKey:trackId];

        NSString *currentLyricsText = @"";
        NSUInteger nextLineStartTime = 0;

        if (lyrics && lyrics.lines.count > 0) {
            uint64_t currentMs = (uint64_t)(elapsedPlaybackTime * 1000);
            NSArray<LyricLine *> *lines = lyrics.lines;
            LyricLine *currentLine = nil;
            for (NSInteger i = lines.count - 1; i >= 0; i--) {
                LyricLine *line = lines[i];
                if (line.startTime <= currentMs) {
                    currentLine = line;
                    break;
                }
            }
            if (currentLine) {
                currentLyricsText = currentLine.text;
                NSUInteger idx = [lines indexOfObject:currentLine];
                if (idx != NSNotFound && idx + 1 < lines.count) {
                    nextLineStartTime = ((LyricLine *)lines[idx + 1]).startTime;
                }
            }
            else if (lines.count > 0 && currentMs < ((LyricLine *)lines[0]).startTime) {
                nextLineStartTime = ((LyricLine *)lines[0]).startTime;
            }
        }

#if DEBUG
        NSLog(@TAG "%@, next offset: %@", currentLyricsText.length > 0 ? currentLyricsText : @"(empty)", nextLineStartTime > 0 ? [@(nextLineStartTime) stringValue] : @"nil");
#endif

        if (nextLineStartTime > 0 && playbackRate > 1e-6) {
            uint64_t currentMs = (uint64_t)(elapsedPlaybackTime * 1000);
            NSInteger deltaMs = (NSInteger)nextLineStartTime - (NSInteger)currentMs;
            NSTimeInterval interval = (NSTimeInterval)deltaMs / 1000.0 / playbackRate;
            if (interval > 0 && elapsedPlaybackTime + interval <= playbackDuration) {
                nextInfo = [newInfo mutableCopy];
                nextInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @((nextLineStartTime + 50 /* important! */) / 1000.0);
                nextInterval = MAX(interval, 0.2 /* important! */);
            }
        }

        if (currentLyricsText.length > 0) {
            newInfo[MPMediaItemPropertyTitle] = currentLyricsText;
        }
    });

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;

        if ([strongSelf ytmu_updateTimer]) {
            [[strongSelf ytmu_updateTimer] invalidate];
            strongSelf.ytmu_updateTimer = nil;
        }

        if (nextInfo && nextInterval > 0) {
            strongSelf.ytmu_updateTimer = [NSTimer scheduledTimerWithTimeInterval:nextInterval target:self selector:@selector(ytmu_updateTimerFired:) userInfo:nextInfo repeats:NO];
#if DEBUG
            NSLog(@TAG "Scheduled update timer for %.3f seconds", nextInterval);
#endif
        }
    });

    %orig(newInfo);
}

%new
- (void)ytmu_updateTimerFired:(NSTimer *)timer {
#if DEBUG
    NSLog(@TAG "ytmu_updateTimerFired:");
#endif
    
    NSDictionary *userInfo = timer.userInfo;
    if (!userInfo) {
        return;
    }
    
    NSMutableDictionary *mUserInfo = [userInfo mutableCopy];
    mUserInfo[@"SkipSubtitleCombination"] = @YES;
    
    [self setNowPlayingInfo:mUserInfo];
}

%end

%ctor {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gIsEnabled = YTMU(@"sendLyricsToMediaControls");
        gLyricsQueue = dispatch_queue_create("com.ginsu.ytmusicultimate.now-playing", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
    });
}
