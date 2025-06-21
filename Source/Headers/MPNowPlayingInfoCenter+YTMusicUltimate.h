#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface MPNowPlayingInfoCenter (YTMusicUltimate)
@property (nonatomic, strong) NSTimer *ytmu_updateTimer;
- (void)ytmu_updateTimerFired:(NSTimer *)timer;
- (void)reloadLyricsIfNeededWithTrackId:(NSString *)trackId userInfo:(NSDictionary *)userInfo;
@end