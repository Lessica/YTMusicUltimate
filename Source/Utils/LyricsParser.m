#import "LyricsParser.h"

#define TAG "YTMusicUltimate+LyricsParser : "

@implementation LyricLine
@end
@implementation Lyrics
@end

@implementation LyricsParser {
    NSData *_data;
    const uint8_t *_bytes;
    NSUInteger _length;
}

- (instancetype)initWithData:(NSData *)data {
    if (self = [super init]) {
        _data = data;
        _bytes = (const uint8_t *)[data bytes];
        _length = [data length];
    }
    return self;
}

- (BOOL)parseVarintAt:(NSUInteger)offset maxLen:(NSUInteger)maxLen value:(uint64_t *)value usedBytes:(NSUInteger *)used {
    uint64_t result = 0;
    NSUInteger shift = 0, i = 0;
    while (i < maxLen) {
        uint8_t byte = _bytes[offset + i];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;
        i++;
        if ((byte & 0x80) == 0) {
            *value = result;
            *used = i;
            return YES;
        }
    }
    return NO;
}

- (NSUInteger)findTarget:(const char *)target {
    NSUInteger targetLen = strlen(target);
    if (targetLen == 0 || targetLen > _length) return NSNotFound;
    // Boyer-Moore-Horspool
    uint8_t badCharSkip[256] = {0};
    for (NSUInteger i = 0; i < 256; i++) badCharSkip[i] = targetLen;
    for (NSUInteger i = 0; i < targetLen - 1; i++) {
        badCharSkip[(uint8_t)target[i]] = targetLen - 1 - i;
    }
    NSUInteger i = 0;
    while (i <= _length - targetLen) {
        if (memcmp(_bytes + i, target, targetLen) == 0) {
            return i;
        }
        i += badCharSkip[_bytes[i + targetLen - 1]];
    }
    return NSNotFound;
}

- (Lyrics *)parseLyrics {
    NSMutableArray<LyricLine *> *result = [NSMutableArray array];
    const char *target = "timed_lyrics.eml-js-canary";
    NSUInteger foundIndex = [self findTarget:target];
    if (foundIndex == NSNotFound || foundIndex == 0) {
#if DEBUG
        NSLog(@TAG "Target marker not found or data is invalid");
#endif
        return nil;
    }
    uint8_t prevByte = _bytes[foundIndex - 1];
    NSUInteger cursor = foundIndex;
    if (cursor + prevByte > _length) {
#if DEBUG
        NSLog(@TAG "Pre-parse area out of range");
#endif
        return nil;
    }
    cursor += prevByte;
    if (cursor + 16 > _length) {
#if DEBUG
        NSLog(@TAG "Header area out of range");
#endif
        return nil;
    }
    cursor += 16;
    if (cursor >= _length || _bytes[cursor] != 0x0A) {
#if DEBUG
        NSLog(@TAG "Missing lyric block start marker 0x0A");
#endif
        return nil;
    }
    int blockIndex = 0;
    while (cursor < _length) {
        @autoreleasepool {
            if (cursor + 1 >= _length) break;
            if (_bytes[cursor] != 0x0A) break;
            uint8_t blockLen = _bytes[cursor + 1];
            if (cursor + 2 + blockLen > _length) break;
            NSUInteger blockStart = cursor + 2;
            NSUInteger blockEnd = blockStart + blockLen;
            if (blockLen < 2) break;
            uint8_t strLen = _bytes[blockStart + 1];
            if (blockLen < 2 + strLen) break;
            NSData *strData = [_data subdataWithRange:NSMakeRange(blockStart + 2, strLen)];
            NSString *lyric = [[NSString alloc] initWithData:strData encoding:NSUTF8StringEncoding];
            if (!lyric) break;
            NSUInteger remainOffset = blockStart + 2 + strLen;
            if (remainOffset + 2 > blockEnd) break;
            if (_bytes[remainOffset] != 0x12) break;
            uint8_t remainLen = _bytes[remainOffset + 1];
            if (remainOffset + 2 + remainLen > blockEnd) break;
            const uint8_t *remainPtr = _bytes + remainOffset + 2;
            if (remainLen < 1 || remainPtr[0] != 0x08) break;
            uint64_t ts1 = 0, ts2 = 0;
            NSUInteger ts1Len = 0, ts2Len = 0;
            if (![self parseVarintAt:(remainOffset + 3) maxLen:(remainLen - 2) value:&ts1 usedBytes:&ts1Len]) break;
            if (ts1Len + 1 >= remainLen - 1) break;
            if (remainPtr[ts1Len + 1] != 0x10) break;
            if (![self parseVarintAt:(remainOffset + 3 + ts1Len + 1) maxLen:(remainLen - 2 - ts1Len - 1) value:&ts2 usedBytes:&ts2Len]) break;
            if (ts1Len + ts2Len + 2 >= remainLen - 1) break;
            if (remainPtr[ts1Len + ts2Len + 2] != 0x1A) break;
            LyricLine *line = [LyricLine new];
            line.text = lyric;
            line.startTime = ts1;
            line.endTime = ts2;
            [result addObject:line];
#if DEBUG
            NSLog(@TAG "Block %d: '%@' [%llu, %llu]", blockIndex, lyric, ts1, ts2);
#endif
            cursor = blockEnd;
            blockIndex++;
        }
    }
    Lyrics *lyrics = [Lyrics new];
    lyrics.lines = result;
    return lyrics;
}

@end
