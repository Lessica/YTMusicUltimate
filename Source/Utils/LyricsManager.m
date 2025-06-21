#import "LyricsManager.h"
#import "LyricsParser.h"

@interface LyricsManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, Lyrics *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSString *cacheDirectory;
@end

@implementation LyricsManager

+ (instancetype)sharedManager {
    static LyricsManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        _memoryCache = [NSMutableDictionary dictionary];
        _queue = dispatch_queue_create("com.ginsu.ytmusicultimate.lyricsmanager", DISPATCH_QUEUE_CONCURRENT_WITH_AUTORELEASE_POOL);
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        _cacheDirectory = [[paths firstObject] stringByAppendingPathComponent:@"YTMusicUltimate/LyricsCache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return self;
}

- (NSString *)filePathForKey:(NSString *)key {
    NSString *safeKey = [NSString stringWithFormat:@"%@.lyric", key];
    return [self.cacheDirectory stringByAppendingPathComponent:safeKey];
}

- (void)setLyrics:(Lyrics *)lyrics forKey:(NSString *)key {
    if (!key || !lyrics) return;
    dispatch_barrier_async(self.queue, ^{
        self.memoryCache[key] = lyrics;
        NSString *filePath = [self filePathForKey:key];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:lyrics requiringSecureCoding:YES error:nil];
        if (data) {
            [data writeToFile:filePath atomically:YES];
        }
    });
}

- (Lyrics *)lyricsForKey:(NSString *)key {
    if (!key) return nil;
    __block Lyrics *lyrics = nil;
    dispatch_sync(self.queue, ^{
        lyrics = self.memoryCache[key];
        if (!lyrics) {
            NSString *filePath = [self filePathForKey:key];
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data) {
                lyrics = [NSKeyedUnarchiver unarchivedObjectOfClass:[Lyrics class] fromData:data error:nil];
                if (lyrics) {
                    self.memoryCache[key] = lyrics;
                }
            }
        }
    });
    return lyrics;
}

@end
