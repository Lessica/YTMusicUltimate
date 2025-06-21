@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface LyricLine : NSObject <NSSecureCoding>
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) uint64_t startTime;
@property (nonatomic, assign) uint64_t endTime;
@end

@interface Lyrics : NSObject <NSSecureCoding>
@property (nonatomic, strong) NSArray<LyricLine *> *lines;
@end

@interface LyricsParser : NSObject
- (instancetype)initWithData:(NSData *)data;
- (Lyrics *_Nullable)parseLyrics;
@end

NS_ASSUME_NONNULL_END
