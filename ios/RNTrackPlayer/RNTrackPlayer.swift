//
//  RNTrackPlayer.swift
//  RNTrackPlayer
//
//  Created by David Chavez on 13.08.17.
//  Copyright © 2017 David Chavez. All rights reserved.
//

import Foundation
import MediaPlayer
import AVFoundation

@objc(RNTrackPlayer)
class RNTrackPlayer: RCTEventEmitter, MediaWrapperDelegate {
  
    private lazy var mediaWrapper: MediaWrapper = {
        let wrapper = MediaWrapper()
        wrapper.delegate = self
        
        return wrapper
    }()
    
    // MARK: - MediaWrapperDelegate Methods
    
    func playerUpdatedState() {
        guard !isTesting else { return }
        sendEvent(withName: "playback-state", body: ["state": mediaWrapper.mappedState.rawValue])
    }
    
    func playerSwitchedTracks(trackId: String?, time: TimeInterval?, nextTrackId: String?) {
        guard !isTesting else { return }
        sendEvent(withName: "playback-track-changed", body: [
            "track": trackId,
            "position": time,
            "nextTrack": nextTrackId
        ])
    }
    
    func playerExhaustedQueue(trackId: String?, time: TimeInterval?) {
        guard !isTesting else { return }
        sendEvent(withName: "playback-queue-ended", body: [
            "track": trackId,
            "position": time,
        ])
    }
    
    func playbackFailed(error: Error) {
        guard !isTesting else { return }
        sendEvent(withName: "playback-error", body: ["error": error.localizedDescription])
    }
    
    // RB signals seek completion with the same bool value that AVPlayer returned
    func playerSeekCompleted(success : Bool) {
        sendEvent(withName: "playback-seek-complete", body : ["finished" : success])
    }

    private let isTesting = { () -> Bool in
        if let _ = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] {
            return true
        } else if let testingEnv = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
            return testingEnv.contains("libXCTTargetBootstrapInject.dylib")
        } else {
            return false
        }
    }()
    
    
    // MARK: - Required Methods
    
    override open static func requiresMainQueueSetup() -> Bool {
        return true;
    }
    
    @objc(constantsToExport)
    override public func constantsToExport() -> [AnyHashable: Any] {
        return [
            "STATE_NONE": MediaWrapper.PlaybackState.none.rawValue,
            "STATE_PLAYING": MediaWrapper.PlaybackState.playing.rawValue,
            "STATE_PAUSED": MediaWrapper.PlaybackState.paused.rawValue,
            "STATE_STOPPED": MediaWrapper.PlaybackState.stopped.rawValue,
            "STATE_BUFFERING": MediaWrapper.PlaybackState.buffering.rawValue,
            
            "PITCH_ALGORITHM_LINEAR": PitchAlgorithm.linear.rawValue,
            "PITCH_ALGORITHM_MUSIC": PitchAlgorithm.music.rawValue,
            "PITCH_ALGORITHM_VOICE": PitchAlgorithm.voice.rawValue,

            "CAPABILITY_PLAY": Capability.play.rawValue,
            "CAPABILITY_PAUSE": Capability.pause.rawValue,
            "CAPABILITY_STOP": Capability.stop.rawValue,
            "CAPABILITY_SKIP_TO_NEXT": Capability.next.rawValue,
            "CAPABILITY_SKIP_TO_PREVIOUS": Capability.previous.rawValue,
            "CAPABILITY_JUMP_FORWARD": Capability.jumpForward.rawValue,
            "CAPABILITY_JUMP_BACKWARD": Capability.jumpBackward.rawValue
        ]
    }
    
    @objc(supportedEvents)
    override public func supportedEvents() -> [String] {
        return [
            "playback-queue-ended",
            "playback-state",
            "playback-error",
            "playback-track-changed",
            
            "playback-seek-complete",

            "remote-stop",
            "remote-pause",
            "remote-play",
            "remote-next",
            "remote-previous",
            "remote-jump-forward",
            "remote-jump-backward",
        ]
    }
    
    
    // MARK: - Bridged Methods
    
    @objc(setupPlayer:resolver:rejecter:)
    public func setupPlayer(config: [String: Any], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
    	print("\n\nYYYUUUU Just to see we got here \n\n")
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            reject("setup_audio_session_failed", "Failed to setup audio session", error)
        }
        
        resolve(NSNull())
    }
    
    @objc(destroy)
    public func destroy() {
        print("Destroying player")
    }
    
    @objc(updateOptions:)
    public func update(options: [String: Any]) {
        let remoteCenter = MPRemoteCommandCenter.shared()
        let castedCapabilities = (options["capabilities"] as? [String])
        let capabilities = castedCapabilities?.flatMap { Capability(rawValue: $0) } ?? []
        
        let enableStop = capabilities.contains(.stop)
        let enablePause = capabilities.contains(.pause)
        let enablePlay = capabilities.contains(.play)
        let enablePlayNext = capabilities.contains(.next)
        let enablePlayPrevious = capabilities.contains(.previous)
        let enableSkipForward = capabilities.contains(.jumpForward)
        let enableSkipBackward = capabilities.contains(.jumpBackward)
        
        toggleRemoteHandler(command: remoteCenter.stopCommand, selector: #selector(remoteSentStop), enabled: enableStop)
        toggleRemoteHandler(command: remoteCenter.pauseCommand, selector: #selector(remoteSentPause), enabled: enablePause)
        toggleRemoteHandler(command: remoteCenter.playCommand, selector: #selector(remoteSentPlay), enabled: enablePlay)
        toggleRemoteHandler(command: remoteCenter.togglePlayPauseCommand, selector: #selector(remoteSentPlayPause), enabled: enablePause && enablePlay)
        toggleRemoteHandler(command: remoteCenter.nextTrackCommand, selector: #selector(remoteSentNext), enabled: enablePlayNext)
        toggleRemoteHandler(command: remoteCenter.previousTrackCommand, selector: #selector(remoteSentPrevious), enabled: enablePlayPrevious)
        
        
        remoteCenter.skipForwardCommand.preferredIntervals = [options["jumpInterval"] as? NSNumber ?? 15]
        remoteCenter.skipBackwardCommand.preferredIntervals = [options["jumpInterval"] as? NSNumber ?? 15]
        toggleRemoteHandler(command: remoteCenter.skipForwardCommand, selector: #selector(remoteSendSkipForward), enabled: enableSkipForward)
        toggleRemoteHandler(command: remoteCenter.skipBackwardCommand, selector: #selector(remoteSendSkipBackward), enabled: enableSkipBackward)
    }
    
    @objc(add:before:resolver:rejecter:)
    public func add(trackDicts: [[String: Any]], before trackId: String?, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if let trackId = trackId, !mediaWrapper.queueContainsTrack(trackId: trackId) {
            reject("track_not_in_queue", "Given track ID was not found in queue", nil)
            return
        }
        
        var tracks = [Track]()
        for trackDict in trackDicts {
            guard let track = Track(dictionary: trackDict) else {
                reject("invalid_track_object", "Track is missing a required key", nil)
                return
            }
            
            tracks.append(track)
        }
        
        print("Adding tracks:", tracks)
        mediaWrapper.addTracks(tracks, before: trackId, callback: {[resolve, reject] (success: Bool, errorMsg: String) ->Void  in
          if(success) {
            resolve(NSNull.self)
          } else {
            reject("call to add TRack failed", errorMsg, nil)
          }
        })
//        resolve(NSNull())
    }
    
    @objc(remove:resolver:rejecter:)
    public func remove(tracks ids: [String], resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Removing tracks:", ids)
        mediaWrapper.removeTracks(ids: ids)
        
        resolve(NSNull())
    }
    
    @objc(removeUpcomingTracks)
    public func removeUpcomingTracks() {
        print("Removing upcoming tracks")
        mediaWrapper.removeUpcomingTracks()
    }
    
    @objc(skip:resolver:rejecter:)
    public func skip(to trackId: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        if !mediaWrapper.queueContainsTrack(trackId: trackId) {
            reject("track_not_in_queue", "Given track ID was not found in queue", nil)
            return
        }
        
        print("Skipping to track:", trackId)
        mediaWrapper.skipToTrack(id: trackId, callback: {[resolve, reject](_ success:Bool, _ errorMsg )->Void in
            if(success) {
                resolve(NSNull())
            } else {
                reject("skip_error", errorMsg, nil)
            }
        })
    }
    
    ///
    /// Skip to the next track in the queue and either play it or pause it depending on what the current track is doing.
    /// If there is no current track it will be paused.
    ///
    /// when resolve is called the new track is ready to play
    /// rejectr will be called with three args (errCode, errMsg, errorObj or nil) if the request fails
    ///		and this includes if there is no next track - that is if we are at the end of the queue
    @objc(skipToNext:rejecter:)
    public func skipToNext(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        print("Skipping to next track")
        mediaWrapper.skipToNext(callback: {[resolve, reject](_ success:Bool, _ errorMsg )->Void in
            if(success) {
                resolve(NSNull())
            } else {
                reject("skip_to_next_error", errorMsg, nil)
            }
        })
    }
    
    ///
    /// Skip to the previous track in the queue and either play it or pause it depending on what the current track is doing.
    /// If there is no current track it will be paused.
    ///
    /// when resolve is called the new track is ready to play
    /// rejectr will be called with three args (errCode, errMsg, errorObj or nil) if the request fails
    ///        and this includes if there is no previous track - that is if we are at the beginning of the queue
    @objc(skipToPrevious:rejecter:)
    public func skipToPrevious(resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        print("Skipping to next track")
        mediaWrapper.skipToPrevious(callback: {[resolve, reject](_ success:Bool, _ errorMsg )->Void in
            if(success) {
                resolve(NSNull())
            } else {
                reject("skip_to_next_error", errorMsg, nil)
            }
        })
    }

    @objc(reset:rejecter:)
    public func reset(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Resetting player.")
        mediaWrapper.reset()
        resolve(NSNull())
    }

    @objc(play:rejecter:)
    public func play(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Starting/Resuming playback")
        mediaWrapper.play()
        resolve(NSNull())
    }

    @objc(pause:rejecter:)
    public func pause(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Pausing playback")
        mediaWrapper.pause()
        resolve(NSNull())
    }

    @objc(stop:rejecter:)
    public func stop(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Stopping playback")
        mediaWrapper.stop()
        resolve(NSNull())
    }

    @objc(seekTo:)
    public func seek(to time: Double) {
        print("Seeking to \(time) seconds")
        mediaWrapper.seek(to: time)
    }

    @objc(setVolume:)
    public func setVolume(level: Float) {
        print("Setting volume to \(level)")
        mediaWrapper.volume = level
    }

    @objc(getVolume:rejecter:)
    public func getVolume(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting current volume")
        resolve(mediaWrapper.volume)
    }

    @objc(setRate:)
    public func setRate(rate: Float) {
        guard [.playing].contains(mediaWrapper.mappedState) else { return }
        print("Setting rate to \(rate)")
        mediaWrapper.rate = rate
    }

    @objc(getRate:rejecter:)
    public func getRate(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        print("Getting current rate")
        resolve(mediaWrapper.rate)
    }

    @objc(getTrack:resolver:rejecter:)
    public func getTrack(id: String, resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        if !mediaWrapper.queueContainsTrack(trackId: id) {
            reject("track_not_in_queue", "Given track ID was not found in queue", nil)
            return
        }

        let track = mediaWrapper.queue.first(where: { $0.id == id })
        resolve(track!.toObject())
    }

    @objc(getQueue:rejecter:)
    public func getQueue(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        let queue = mediaWrapper.queue.map { $0.toObject() }
        resolve(queue)
    }

    @objc(getCurrentTrack:rejecter:)
    public func getCurrentTrack(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mediaWrapper.currentTrack?.id)
    }

    @objc(getDuration:rejecter:)
    public func getDuration(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mediaWrapper.currentTrackDuration)
    }

    @objc(getBufferedPosition:rejecter:)
    public func getBufferedPosition(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mediaWrapper.bufferedPosition)
    }

    @objc(getPosition:rejecter:)
    public func getPosition(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mediaWrapper.currentTrackProgression)
    }

    @objc(getState:rejecter:)
    public func getState(resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(mediaWrapper.mappedState.rawValue)
    }


    // MARK: - Private Helpers
    
    func toggleRemoteHandler(command: MPRemoteCommand, selector: Selector, enabled: Bool) {
        command.removeTarget(self, action: selector)
        command.addTarget(self, action: selector)
        command.isEnabled = enabled
    }
    
    
    // MARK: - Remote Dynamic Methods
    
    func remoteSentStop() {
        sendEvent(withName: "remote-stop", body: nil)
    }
    
    func remoteSentPause() {
        sendEvent(withName: "remote-pause", body: nil)
    }
    
    func remoteSentPlay() {
        sendEvent(withName: "remote-play", body: nil)
    }
    
    func remoteSentNext() {
        sendEvent(withName: "remote-next", body: nil)
    }
    
    func remoteSentPrevious() {
        sendEvent(withName: "remote-previous", body: nil)
    }
    
    func remoteSendSkipForward(event: MPSkipIntervalCommandEvent) {
        sendEvent(withName: "remote-jump-forward", body: ["interval": event.interval])
    }
    
    func remoteSendSkipBackward(event: MPSkipIntervalCommandEvent) {
        sendEvent(withName: "remote-jump-backward", body: ["interval": event.interval])
    }
    
    func remoteSentPlayPause() {
        if mediaWrapper.mappedState == .paused {
            sendEvent(withName: "remote-play", body: nil)
            return
        }
        
        sendEvent(withName: "remote-pause", body: nil)
    }
// MARK: - additions for seek complete event

    func playbackSeekCompleted(success: Bool) {
      NSLog("got here")
      sendEvent(withName : "playback-seek-complete", body: nil)
    }

// MARK:: - additional interface functions

    @objc(jumpTo:)
    public func jumpTo(to time: Double) {
        print("Jump to \(time) seconds")
    }


    @objc(seekToPromise:resolver:rejecter:)
    public func seekPromise(to time: Double, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        print("Seeking to \(time) seconds")
        mediaWrapper.seekPromise(to: time, callback: {[resolve, reject] (success: Bool, errorMsg: String) ->Void  in
          if(success) {
            resolve(NSNull.self)
          } else {
            reject("seek failed", errorMsg, nil)
          }
        })
    }


}
