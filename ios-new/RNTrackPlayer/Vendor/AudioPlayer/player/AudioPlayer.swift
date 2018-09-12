//
//  AudioPlayer.swift
//  AudioPlayer
//
//  Created by Kevin DELANNOY on 26/04/15.
//  Copyright (c) 2015 Kevin Delannoy. All rights reserved.
//

import AVFoundation
#if os(iOS) || os(tvOS)
import MediaPlayer
#endif

/// An `AudioPlayer` instance is used to play `AudioPlayerItem`. It's an easy to use AVPlayer with simple methods to
/// handle the whole playing audio process.
///
/// You can get events (such as state change or time observation) by registering a delegate.
public class AudioPlayer: NSObject {
    // MARK: Handlers
    
    /// The background handler.
    let backgroundHandler = BackgroundHandler()
    
    /// Reachability for network connection.
    let reachability = Reachability()
    
    // MARK: Event producers
    
    /// The network event producer.
    lazy var networkEventProducer: NetworkEventProducer = {
        NetworkEventProducer(reachability: self.reachability)
    }()
    
    /// The player event producer.
    let playerEventProducer = PlayerEventProducer()
    
    /// The seek event producer.
    let seekEventProducer = SeekEventProducer()
    
    /// The quality adjustment event producer.
    var qualityAdjustmentEventProducer = QualityAdjustmentEventProducer()
    
    /// The audio item event producer.
    var trackEventProducer = TrackEventProducer()
    
    /// The retry event producer.
    var retryEventProducer = RetryEventProducer()
    
    ///a flag and property to be used in new style loading of track
    var isLoadingTrack : Bool
    var loadingTrackCompletionCallback : ((Bool, String) -> Void)?
    //    var trackBeingLoaded : Track?
    
    // MARK: Player
    
    #if NO_DIDSET_CURRENT_ITEM
    var player: AVPlayer?
    #else
    /// The audio player.
    var player: AVPlayer? {
        didSet {
            if #available(OSX 10.11, *) {
                player?.allowsExternalPlayback = false
            }
            player?.volume = volume
            //            player?.rate = rate // RB change
            updatePlayerForBufferingStrategy()
            
            if let player = player {
                playerEventProducer.player = player
                trackEventProducer.item = currentItem
                playerEventProducer.startProducingEvents()
                trackEventProducer.startProducingEvents()
                qualityAdjustmentEventProducer.startProducingEvents()
                
                // Start producing network events if not already doing so
                networkEventProducer.startProducingEvents()
            } else {
                playerEventProducer.player = nil
                trackEventProducer.item = nil
                playerEventProducer.stopProducingEvents()
                trackEventProducer.stopProducingEvents()
                qualityAdjustmentEventProducer.stopProducingEvents()
            }
        }
    }
    #endif
    #if NO_DIDSET_CURRENT_ITEM
    var currentItem : Track?
    #else
    /// The current item being played.
    internal(set) var currentItem: Track? {
        didSet {
            // Save previous item's progression
            guard let t = currentItem else {
                //                assertionFailure("currentItem set did not unwrap")
                // legitimatelt gets here when a stop() call has been issued
                return
            }
            let trackId = t.id
            print("currentItem.set starting id : \(trackId)\n")
            let oldProgression = currentItemProgression
            
            if let currentItem = currentItem {
                // Stops the current player
                player?.rate = 0
                player = nil
                
                // signal new style loading
                isLoadingTrack = true
                //                trackBeingLoaded = currentItem
                
                // Ensures the audio session got started
                setAudioSession(active: true)
                
                // Sets new state
                if isOnline || currentItem.url.isLocal {
                    state = .buffering
                    backgroundHandler.beginBackgroundTask()
                } else {
                    stateWhenConnectionLost = .buffering
                    state = .waitingForConnection
                    backgroundHandler.beginBackgroundTask()
                    return
                }
                
                // Reset special state flags
                pausedForInterruption = false
                
                // Create new AVPlayerItem
                let playerItem = AVPlayerItem(url: currentItem.url.value)
                
                if #available(iOS 10.0, tvOS 10.0, OSX 10.12, *) {
                    playerItem.preferredForwardBufferDuration = self.preferredForwardBufferDuration
                }
                
                // Creates new player
                player = AVPlayer(playerItem: playerItem)
                
                // Updates information on the lock screen
                updateNowPlayingInfoCenter()
                
                // Calls delegate
                if oldValue != currentItem {
                    delegate?.audioPlayer(self, willChangeTrackFrom: oldValue, at: oldProgression, to: currentItem)
                    if let x = player?.rate {
                        print(String(format:"AudioPlayer.play about to set rate rate is : %f", x))
                    } else {
                        print(String(format:"AudioPlayer.play about to set rate rate is unwrappable optional"))
                    }
                    pause()
                    //                    player?.rate = 0
                }
            } else {
                delegate?.audioPlayer(self, willChangeTrackFrom: oldValue, at: oldProgression, to: nil)
                pause()
            }
        }
    }
    
    #endif
    
    // MARK: Public properties
    
    /// The delegate that will be called upon events.
    weak var delegate: AudioPlayerDelegate?
    
    /// Defines the maximum to wait after a connection loss before putting the player to Stopped mode and cancelling
    /// the resume. Default value is 60 seconds.
    var maximumConnectionLossTime = TimeInterval(60)
    
    /// Defines whether the player should automatically adjust sound quality based on the number of interruption before
    /// a delay and the maximum number of interruption whithin this delay. Default value is `true`.
    var adjustQualityAutomatically = true
    
    /// Defines the delay within which the player wait for an interruption before upgrading the quality. Default value
    /// is 10 minutes.
    var adjustQualityTimeInternal: TimeInterval {
        get {
            return qualityAdjustmentEventProducer.adjustQualityTimeInternal
        }
        set {
            qualityAdjustmentEventProducer.adjustQualityTimeInternal = newValue
        }
    }
    
    /// Defines the maximum number of interruption to have within the `adjustQualityTimeInterval` delay before
    /// downgrading the quality. Default value is 5.
    var adjustQualityAfterInterruptionCount: Int {
        get {
            return qualityAdjustmentEventProducer.adjustQualityAfterInterruptionCount
        }
        set {
            qualityAdjustmentEventProducer.adjustQualityAfterInterruptionCount = newValue
        }
    }
    
    /// The maximum number of interruption before putting the player to Stopped mode. Default value is 10.
    var maximumRetryCount: Int {
        get {
            return retryEventProducer.maximumRetryCount
        }
        set {
            retryEventProducer.maximumRetryCount = newValue
        }
    }
    
    /// The delay to wait before cancelling last retry and retrying. Default value is 10 seconds.
    var retryTimeout: TimeInterval {
        get {
            return retryEventProducer.retryTimeout
        }
        set {
            retryEventProducer.retryTimeout = newValue
        }
    }
    
    /// Defines whether the player should resume after a system interruption or not. Default value is `true`.
    var resumeAfterInterruption = true
    
    /// Defines whether the player should resume after a connection loss or not. Default value is `true`.
    var resumeAfterConnectionLoss = true
    
    /// Defines the volume of the player. `1.0` means 100% and `0.0` is 0%.
    var volume = Float(1) {
        didSet {
            player?.volume = volume
        }
    }
    
    func getVolume() -> Float {
        return player?.volume ?? 1
    }
    
    /// Defines the rate of the player. Default value is 1.
    var rate = Float(1) {
        didSet {
            print("rate.didSet \n")
            if case .playing = state {
                player?.rate = rate
                updateNowPlayingInfoCenter()
            }
        }
    }
    
    func getRate() -> Float {
        return player?.rate ?? 0
    }
    
    /// Defines the buffering strategy used to determine how much to buffer before starting playback
    var bufferingStrategy: AudioPlayerBufferingStrategy = .defaultBuffering {
        didSet {
            updatePlayerForBufferingStrategy()
        }
    }
    
    /// Defines the preferred buffer duration in seconds before playback begins. Defaults to 60.
    /// Works on iOS/tvOS 10+ when `bufferingStrategy` is `.playWhenPreferredBufferDurationFull`.
    var preferredBufferDurationBeforePlayback = TimeInterval(60)
    
    /// Defines the preferred size of the forward buffer for the underlying `AVPlayerItem`.
    /// Works on iOS/tvOS 10+, default is 0, which lets `AVPlayer` decide.
    var preferredForwardBufferDuration = TimeInterval(0)
    
    /// Defines how to behave when the user is seeking through the lockscreen or the control center.
    ///
    /// - multiplyRate: Multiples the rate by a factor.
    /// - changeTime:   Changes the current position by adding/substracting a time interval.
    enum SeekingBehavior {
        case multiplyRate(Float)
        case changeTime(every: TimeInterval, delta: TimeInterval)
        
        func handleSeekingStart(player: AudioPlayer, forward: Bool) {
            switch self {
            case .multiplyRate(let rateMultiplier):
                if forward {
                    player.rate = player.rate * rateMultiplier
                } else {
                    player.rate = -(player.rate * rateMultiplier)
                }
                
            case .changeTime:
                player.seekEventProducer.isBackward = !forward
                player.seekEventProducer.startProducingEvents()
            }
        }
        
        func handleSeekingEnd(player: AudioPlayer, forward: Bool) {
            switch self {
            case .multiplyRate(let rateMultiplier):
                if forward {
                    player.rate = player.rate / rateMultiplier
                } else {
                    player.rate = -(player.rate / rateMultiplier)
                }
                
            case .changeTime:
                player.seekEventProducer.stopProducingEvents()
            }
        }
    }
    
    /// Defines the rate behavior of the player when the backward/forward buttons are pressed. Default value
    /// is `multiplyRate(2)`.
    var seekingBehavior = SeekingBehavior.multiplyRate(2) {
        didSet {
            if case .changeTime(let timerInterval, _) = seekingBehavior {
                seekEventProducer.intervalBetweenEvents = timerInterval
            }
        }
    }
    
    func makeNewAVPlayer(playerItem : AVPlayerItem)
    {
        // Creates new player
        let tmpPlayer = AVPlayer(playerItem: playerItem)
        player = tmpPlayer
        
        if #available(OSX 10.11, *) {
            tmpPlayer.allowsExternalPlayback = false
        }
        player?.volume = volume
        //            player?.rate = rate // RB change
        updatePlayerForBufferingStrategy()
        
        playerEventProducer.player = player
        trackEventProducer.item = currentItem
        playerEventProducer.startProducingEvents()
        trackEventProducer.startProducingEvents()
        qualityAdjustmentEventProducer.startProducingEvents()
        // Start producing network events if not already doing so
        networkEventProducer.startProducingEvents()
        
    }
    func invalidateCurrentAVPlayer()
    {
        player?.rate = 0.0
        player = nil
        playerEventProducer.player = nil
        trackEventProducer.item = nil
        playerEventProducer.stopProducingEvents()
        trackEventProducer.stopProducingEvents()
        qualityAdjustmentEventProducer.stopProducingEvents()
        
    }
    // MARK: Public Methods
    ///
    /// loadTrack - gets a track ready for playing. Creates AVPlayer and AVPlayerItem and puts them into paused state
    /// which is actually that the status of the AVPlayer/AVPlayerItem is 'readyToPlay'/AVPlayerStatus.readyToPlay and the
    /// players timeControlStatus is AVPLayerTimeControlStatus.paused.
    ///
    /// These combined represent AudioPlayer state = AudioPlayerState.paused
    ///
    /// Finally saves the AVPlayer and AVPLayerItem in self.player and self.currentItem
    ///
    func _loadTrackAsCurrent(track: Track?)
    {
        // Save previous item's value
        let oldItemValue = self.currentItem
        self.currentItem = track
        let oldProgression = currentItemProgression
        
        if let newItem = track {
            invalidateCurrentAVPlayer()
            isLoadingTrack = true
            // Ensures the audio session got started
            setAudioSession(active: true)
            // Sets new state
            if isOnline || newItem.url.isLocal {
                state = .buffering
                backgroundHandler.beginBackgroundTask()
            } else {
                stateWhenConnectionLost = .buffering
                state = .waitingForConnection
                backgroundHandler.beginBackgroundTask()
                return
            }
            // Reset special state flags
            pausedForInterruption = false
            let playerItem = AVPlayerItem(url: newItem.url.value)
            if #available(iOS 10.0, tvOS 10.0, OSX 10.12, *) {
                playerItem.preferredForwardBufferDuration = self.preferredForwardBufferDuration
            }
            
            makeNewAVPlayer(playerItem: playerItem)
            updateNowPlayingInfoCenter()
            
            // Calls delegate
            if oldItemValue != newItem
            {
                delegate?.audioPlayer(self, willChangeTrackFrom: oldItemValue, at: oldProgression, to: newItem)
                if let x = player?.rate {
                    print(String(format:"AudioPlayer.play about to set rate rate is : %f", x))
                } else {
                    print(String(format:"AudioPlayer.play about to set rate rate is unwrappable optional"))
                }
                pause() // need to have all the state setting stuff with it
            }
        } else {
            delegate?.audioPlayer(self, willChangeTrackFrom: oldItemValue, at: oldProgression, to: nil)
            pause()
        }
    }
    
    ///
    /// loads a track into a new AVPlayer and new AVPlayerItem and calls the callback
    ///     (true, "") when the AVPlayer achieves status = AVPLayerStatus.readyToPlay
    ///     (false, "some error message " if an error occurs
    ///
    func load(track: Track, callback : @escaping (Bool, String) -> Void)
    {
        if isLoadingTrack {
            callback(false, "Cannot have two loading operations at the same time")
        }
        loadingTrackCompletionCallback = callback
        #if NO_DIDSET_CURRENT_ITEM
        _loadTrackAsCurrent(track: track)
        #else
        currentItem = track
        #endif
    }
    func play(track: Track)
    {
        assert(false)
        currentItem = track
    }
    
    // MARK: Readonly properties
    
    /// The current state of the player.
    internal(set) var state = AudioPlayerState.stopped {
        didSet {
            updateNowPlayingInfoCenter()
            
            if state != oldValue {
                if case .buffering = state {
                    backgroundHandler.beginBackgroundTask()
                } else if case .buffering = oldValue {
                    backgroundHandler.endBackgroundTask()
                }
                
                delegate?.audioPlayer(self, didChangeStateFrom: oldValue, to: state)
            }
        }
    }
    
    // MARK: Private properties
    
    /// A boolean value indicating whether the player has been paused because of a system interruption.
    var pausedForInterruption = false
    
    /// A boolean value indicating if quality is being changed. It's necessary for the interruption count to not be
    /// incremented while new quality is buffering.
    var qualityIsBeingChanged = false
    
    /// The state before the player went into .Buffering. It helps to know whether to restart or not the player.
    var stateBeforeBuffering: AudioPlayerState?
    
    /// The state of the player when the connection was lost
    var stateWhenConnectionLost: AudioPlayerState?
    
    /// Convenience for checking if platform is currently online
    var isOnline: Bool {
        get {
            return reachability?.isReachable ?? false
        }
    }
    
    // MARK: Initialization
    
    /// Initializes a new AudioPlayer.
    override init() {
        isLoadingTrack = false
        loadingTrackCompletionCallback = nil
        super.init()
        
        playerEventProducer.eventListener = self
        networkEventProducer.eventListener = self
        trackEventProducer.eventListener = self
        qualityAdjustmentEventProducer.eventListener = self
    }
    
    /// Deinitializes the AudioPlayer. On deinit, the player will simply stop playing anything it was previously
    /// playing.
    deinit {
        networkEventProducer.stopProducingEvents()
        stop()
    }
    
    // MARK: Utility methods
    
    /// Updates the MPNowPlayingInfoCenter with current item's info.
    func updateNowPlayingInfoCenter() {
        #if os(iOS) || os(tvOS)
        if let item = currentItem {
            MPNowPlayingInfoCenter.default().ap_update(
                with: item,
                duration: currentItemDuration,
                progression: currentItemProgression,
                playbackRate: player?.rate ?? 0)
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        #endif
    }
    
    /// Enables or disables the `AVAudioSession` and sets the right category.
    ///
    /// - Parameter active: A boolean value indicating whether the audio session should be set to active or not.
    func setAudioSession(active: Bool) {
        #if os(iOS) || os(tvOS)
        _ = try? AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
        _ = try? AVAudioSession.sharedInstance().setActive(active)
        #endif
    }
    
    // MARK: Public computed properties
    
    /// Boolean value indicating whether the player should resume playing (after buffering)
    var shouldResumePlaying: Bool {
        if isLoadingTrack {
            return false
        }
        let x = !state.isPaused &&
            (stateWhenConnectionLost.map { !$0.isPaused } ?? true) &&
            (stateBeforeBuffering.map { !$0.isPaused } ?? true)
        return x
    }
    
    // MARK: Retrying
    
    /// This will retry to play current item and seek back at the correct position if possible (or enabled). If not,
    /// it'll just play the next item in queue.
    func retryOrPlayNext() {
        guard !state.isPlaying else {
            retryEventProducer.stopProducingEvents()
            return
        }
        
        let cip = currentItemProgression
        let ci = currentItem
        currentItem = ci
        if let cip = cip {
            //We can't call self.seek(to:) in here since the player is new
            //and `cip` is probably not in the seekableTimeRanges.
            player?.seek(to: CMTime(timeInterval: cip))
        }
    }
    
    /// Updates the current player based on the current buffering strategy.
    /// Only has an effect on iOS 10+, tvOS 10+ and macOS 10.12+
    func updatePlayerForBufferingStrategy() {
        if #available(iOS 10.0, tvOS 10.0, OSX 10.12, *) {
            player?.automaticallyWaitsToMinimizeStalling = self.bufferingStrategy != .playWhenBufferNotEmpty
        }
    }
    
    /// Updates a given player item based on the `preferredForwardBufferDuration` set.
    /// Only has an effect on iOS 10+, tvOS 10+ and macOS 10.12+
    func updatePlayerItemForBufferingStrategy(_ playerItem: AVPlayerItem) {
        //Nothing strategy-specific yet
        if #available(iOS 10.0, tvOS 10.0, OSX 10.12, *) {
            playerItem.preferredForwardBufferDuration = self.preferredForwardBufferDuration
        }
    }
}

//
// This is a hack to get AVPLayer.status becoming readyToPlay up to the higher levels
//
extension AudioPlayer {
    
    func reportAVPlayerReady()
    {
        guard let track = self.currentItem else {
            assertionFailure("reportAVPlayerReady no currentItem ")
            return
        }
        delegate?.audioPlayer(self, didBecomeReadyToPlayFor: track)
        delegate?.audioPlayer(self)
        
    }
    func reportSeekCompleted(_ finished: Bool)
    {
        delegate?.audioPlayer(self, didCompleteSeekWithOutcome: finished)
    }
    
}

extension AudioPlayer: EventListener {
    /// The implementation of `EventListener`. It handles network events, player events, audio item events, quality
    /// adjustment events, retry events and seek events.
    ///
    /// - Parameters:
    ///   - event: The event.
    ///   - eventProducer: The producer of the event.
    func onEvent(_ event: Event, generetedBy eventProducer: EventProducer) {
        if let event = event as? NetworkEventProducer.NetworkEvent {
            handleNetworkEvent(from: eventProducer, with: event)
        } else if let event = event as? PlayerEventProducer.PlayerEvent {
            handlePlayerEvent(from: eventProducer, with: event)
        } else if let event = event as? TrackEventProducer.TrackEvent {
            handleTrackEvent(from: eventProducer, with: event)
        } else if let event = event as? RetryEventProducer.RetryEvent {
            handleRetryEvent(from: eventProducer, with: event)
        } else if let event = event as? SeekEventProducer.SeekEvent {
            handleSeekEvent(from: eventProducer, with: event)
        }
    }
}
