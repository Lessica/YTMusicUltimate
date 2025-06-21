@import Foundation;
@class Lyrics;

NS_ASSUME_NONNULL_BEGIN

@interface LyricsManager : NSObject
+ (instancetype)sharedManager;
- (void)setLyrics:(Lyrics *)lyrics forKey:(NSString *)key;
- (Lyrics *_Nullable)lyricsForKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
