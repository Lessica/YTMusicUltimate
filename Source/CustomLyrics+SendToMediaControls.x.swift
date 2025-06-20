import Orion
import MediaPlayer

fileprivate let TAG = "EeveeSpotifyLyrics"

class MPNowPlayingInfoCenterHook: ClassHook<MPNowPlayingInfoCenter> {
    typealias Group = LyricsGroup

    static let targetName: String = "MPNowPlayingInfoCenter"

    fileprivate static var currentTrackId: String?
    
    fileprivate static let lyricsLoadingQueue = DispatchQueue(label: "com.eevee.spotify.nowPlayingLyricsLoadingQueue", qos: .utility)
    fileprivate static let lyricsQueue = DispatchQueue(label: "com.eevee.spotify.nowPlayingLyricsQueue", qos: .userInitiated)
    fileprivate static var lyricsTrackId: String?
    fileprivate static var lyrics: Lyrics?

    @Property(.nonatomic) var updateTimer: Timer? = nil

    func setNowPlayingInfo(_ info: [String: Any]?) {

        guard UserDefaults.lyricsSource != .notReplaced,
              UserDefaults.lyricsOptions.sendToMediaControls,
              let info = info,
              let title = info[MPMediaItemPropertyTitle] as? String,
              let subtitle = info[MPMediaItemPropertyArtist] as? String else {
            orig.setNowPlayingInfo(info)
            return
        }

        var newInfo = info
        if let skipComb = info["SkipSubtitleCombination"] as? Bool, skipComb {
        } else {
            let newSubtitle = "\(title) — \(subtitle)"
            newInfo[MPMediaItemPropertyArtist] = newSubtitle
        }

        let trackId = info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String
        let elapsedPlaybackTime = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval ?? 0

        Self.lyricsQueue.async { [weak self] in
            Self.currentTrackId = trackId
            try? self?.reloadLyricsIfNeeded(trackId: trackId, info: newInfo)
        }

        var nextInterval: TimeInterval?
        var nextInfo: [String: Any]?

        Self.lyricsQueue.sync { [weak self] in
            guard let self = self else { return }

            let currentLyricsText: String
            var nextLineOffsetMs: Int32? = nil

            if trackId == Self.lyricsTrackId, let lyrics = Self.lyrics, lyrics.data.lines.count > 0 {
                let currentMs = Int32(elapsedPlaybackTime * 1000)
                let lines = lyrics.data.lines
                let currentLine = lines.last(where: { $0.offsetMs <= currentMs })
                currentLyricsText = currentLine?.content ?? ""
                
                if let currentLine = currentLine,
                   let idx = lines.lastIndex(where: { $0.offsetMs == currentLine.offsetMs }),
                   idx + 1 < lines.count
                {
                    nextLineOffsetMs = lines[idx + 1].offsetMs
                }
                else if nextLineOffsetMs == nil, currentLine == nil, let firstLine = lines.first, currentMs < firstLine.offsetMs {
                    nextLineOffsetMs = firstLine.offsetMs
                }
            } else {
                currentLyricsText = ""
            }

            #if DEBUG
                NSLog("\(TAG): \(currentLyricsText.isEmpty ? "(empty)" : currentLyricsText), next offset: \(nextLineOffsetMs.map { String($0) } ?? "nil")")
            #endif

            let playbackDuration = info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval ?? 0
            let playbackRate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1.0

            if let nextOffset = nextLineOffsetMs, playbackRate > 1e-6 {
                let currentMs = Int32(elapsedPlaybackTime * 1000)
                let deltaMs = Int(nextOffset) - Int(currentMs)
                let interval = Double(deltaMs) / 1000.0 / playbackRate
                if interval > 0, elapsedPlaybackTime + interval <= playbackDuration {
                    nextInterval = max(interval, 0.2 /* important! */)
                    nextInfo = newInfo
                    nextInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(nextOffset + 50 /* important! */) / 1000.0
                }
            }

            if !currentLyricsText.isEmpty {
                newInfo[MPMediaItemPropertyTitle] = currentLyricsText
            }
        }

        updateTimer?.invalidate()
        updateTimer = nil

        if let nextInterval = nextInterval, let nextInfo = nextInfo {
            updateTimer = Timer.scheduledTimer(timeInterval: nextInterval, target: self, selector: #selector(updateTimerFired(_:)), userInfo: nextInfo, repeats: false)
            #if DEBUG
                NSLog("\(TAG): Scheduled update timer for \(nextInterval) seconds")
            #endif
        }

        orig.setNowPlayingInfo(newInfo)
    }

    @objc fileprivate func updateTimerFired(_ timer: Timer?) {
        #if DEBUG
            NSLog("\(TAG): updateTimerFired(_:)")
        #endif
        guard var info = timer?.userInfo as? [String: Any] else { return }
        info["SkipSubtitleCombination"] = true
        setNowPlayingInfo(info)
    }

    fileprivate func reloadLyricsIfNeeded(trackId: String?, info: [String: Any]?) throws {

        guard let trackId = trackId, trackId.hasPrefix("spotify:track:") else {
            return
        }

        let startedAt = Date()
        Self.lyricsLoadingQueue.async {
            if Self.lyricsTrackId == trackId {
                return
            }

            let spotifyTrackId = String(trackId.dropFirst("spotify:track:".count))
            guard let loadedLyrics = try? loadCustomLyricsInBackgroundForCurrentTrack(expectTrackId: spotifyTrackId) else {
                return
            }

            Self.lyricsQueue.sync { [weak self] in
                guard let self = self else { return }

                if Self.currentTrackId == trackId {
                    Self.lyrics = loadedLyrics
                    Self.lyricsTrackId = trackId
                    #if DEBUG
                        NSLog("\(TAG): Lyrics loaded for track \(spotifyTrackId)")
                    #endif

                    if let info = info {
                        let endedAt = Date()
                        let delta = max(0, endedAt.timeIntervalSince(startedAt))

                        var newInfo = info
                        let elapsedPlaybackTime = info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval ?? 0
                        let playbackDuration = info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval ?? 0
                        let playbackRate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1.0

                        let newElapsedPlaybackTime: TimeInterval
                        newElapsedPlaybackTime = min(elapsedPlaybackTime + delta * playbackRate, playbackDuration)
                        newInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = newElapsedPlaybackTime
                        newInfo["SkipSubtitleCombination"] = true

                        DispatchQueue.main.async {
                            self.setNowPlayingInfo(newInfo)
                        }
                    }
                }
            }
        }
    }
}