//
//  MediaWrapper.swift
//  RNTrackPlayer
//
//  Created by David Chavez on 11.08.17.
//  Copyright © 2017 David Chavez. All rights reserved.
//

import Foundation
import MediaPlayer

protocol MediaWrapperDelegate: class {
    func playerUpdatedState()
    func playerSwitchedTracks(trackId: String?, time: TimeInterval?, nextTrackId: String?)
    func playerExhaustedQueue(trackId: String?, time: TimeInterval?)
    func playbackFailed(error: Error)
    // RB addition
    func playbackSeekCompleted(success: Bool)
    
}

class MediaWrapper: AudioPlayerDelegate {
    private(set) var queue: [Track]
    private var currentIndex: Int
    private let player: AudioPlayer
    private var trackImageTask: URLSessionDataTask?
    
    var loadUnderway : Bool
    var loadCompletion : ((_ success: Bool, _ task: Track ) -> Void)?
    
    weak var delegate: MediaWrapperDelegate?
    
    enum PlaybackState: String {
        case playing, paused, stopped, buffering, none
    }
    
    var volume: Float {
        get {
            return player.getVolume()
        }
        set {
            player.volume = newValue
        }
    }
    var rate: Float {
        get {
            return player.getRate()
        }
        set {
            player.rate = newValue
        }
    }
    
    var currentTrack: Track? {
        return queue[safe: currentIndex]
    }
    
    var bufferedPosition: Double {
        return player.currentItemLoadedRange?.latest ?? 0
    }
    
    var currentTrackDuration: Double {
        return player.currentItemDuration ?? 0
    }
    
    var currentTrackProgression: Double {
        return player.currentItemProgression ?? 0
    }
    
    var mappedState: PlaybackState {
        switch player.state {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        case .buffering:
            return .buffering
        default:
            return .none
        }
    }
    
    func getPlayer() -> AudioPlayer {
        return player;
    }
    
    // MARK: - Init/Deinit
    
    init() {
        self.queue = []
        self.currentIndex = -1
        self.player = AudioPlayer()
        self.loadUnderway = false
        
        self.player.delegate = self
        self.player.bufferingStrategy = .playWhenBufferNotEmpty
        
        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        }
    }
    
    ///
    /// updateTrack
    /// Updates the current track to the given index. If the given index is outside the range in the queue
    /// do the best you can .. take the first or last. Update the value of currentIndex
    ///
    /// Having determined the 'new' current index - if its different to before -- load that track into the player
    /// by calling the players load() fuunc
    ///
    ///     If fails the callback is called with (false, a message to describe the issue).
    ///     If succeeds the callback is called with (true, "") and at this time the player is 'readyToPlay'
    ///
    ///
    func updateCurrentTrack( track index: Int, callback: @escaping (Bool, String) -> Void )
    {
    	var oldId = ""
    	if currentIndex >= 0 && currentIndex < queue.count {
        	oldId = queue[currentIndex].id
        }
		let oldState = mappedState
        var i = index
        if queue.count <= i {
            i = queue.count - 1
        } else if i < 0 {
            i = 0
        }
        currentIndex = index
        let currentId = queue[index].id
        if currentId == oldId {
        	// the current track has not changed, that track must be loaded
         	callback(true, "")
          	return
        }
        // notify track change
        let cTrack = queue[i]
        player.load(track: cTrack, callback: {[self, oldState, callback](success: Bool, errorMsg: String) -> Void in
        	print("updateCurrentTrack callback oldState: \(oldState) \n")
        	if success && (
         	   (oldState != PlaybackState.paused)
                && (oldState != PlaybackState.stopped)
            ) {
         		self.play()
            }
            callback(success, errorMsg)
        })
    }
    func fixCurrentIndex(curIndex : Int) -> Int
    {
        if( queue.count == 0) {return -1}
        if( curIndex < 0 && queue.count > 0) {return 0}
        if( curIndex > queue.count) {return queue.count - 1}
        return curIndex
    }
    
    
    // MARK: - Public API
    
    func queueContainsTrack(trackId: String) -> Bool {
        return queue.contains(where: { $0.id == trackId })
    }
    
    func addTracks(_ tracks: [Track]) {
        queue.append(contentsOf: tracks)
    }
    
    ///
    /// Add a set of tracks to the queue before the given track id.
    /// -	tracks, an array of tracks to add
    ///	-	trackId, string - the id of the track before which to add. If this is null or is not in the queue add the new tracks at the end
    /// -	cb, a callback using node style that will indicate success after the tracks are added AND if the current track has changed
    ///				the new current track will be loaded and put into either play or pause state
    ///
    /// see updateCurrentTrack for more details
    ///
    func addTracks(_ tracks: [Track], before trackId: String?, callback cb : @escaping (_ success:Bool, _ errorMsg: String) -> Void)
    {
        var currIndex = currentIndex
        if let trackIndex = queue.index(where: { $0.id == trackId }) {
            // the id was found which also means the queue was not empty and currentIndex was already initialized
            queue.insert(contentsOf: tracks, at: trackIndex)
            if (currIndex >= trackIndex) {
                currIndex = currIndex + tracks.count
            }
        } else if queue.count > 0 {
            // queue was not empty so add the new tracks at the end and the currentIndex must have already been initialized
            addTracks(tracks)
        } else {
            // the queue was empty so need to initialize currentIndex
            addTracks(tracks)
            currIndex = 0
        }
        // this will set currentIndex correctly and load the current track ready for play
        updateCurrentTrack(track: currIndex, callback: cb)
    }
    
    //
    // TODO - not sure this one works - needs testing - and certainly the interface is not good
    //
    func removeTracks(ids: [String]) {
        var actionAfterRemovals = "none"
        // records whether the current item is the same of different after all removals
        var currentItemChanged = false
        for id in ids {
            if let trackIndex = queue.index(where: { $0.id == id })
            {
                if trackIndex > currentIndex {
                    queue.remove(at: trackIndex)
                    //
                } else if trackIndex < currentIndex {
                    currentIndex = currentIndex - 1
                    currentItemChanged = true
                    queue.remove(at: trackIndex)
                } else {
                    if id == queue.last?.id {
                        actionAfterRemovals = "stop"
                        // currentIndex is the last one and it is being removed - so stay pointing at last after removal
                        currentIndex = currentIndex - 1
                        currentItemChanged = true
                    } else if trackIndex == currentIndex {
                        // current index is NOT the last one and it is being removed. So dont change currentIndex and it will point at the nextt one
                        actionAfterRemovals = "play"
                        currentItemChanged = true
                    }
                    queue.remove(at: trackIndex)
                }
                if(currentItemChanged) {
                    updateCurrentTrack(track: currentIndex, callback: {[](_ success: Bool, _ errorMsg: String ) -> Void in
                        print("TODO - something better has to happen here")
                    })
                }
            }
        }
        switch actionAfterRemovals {
        case "play": play()
        case "stop": stop()
        default: break;
        }
    }
    
    func removeUpcomingTracks() {
        queue = queue.filter { $0.0 <= currentIndex }
    }
    
    ///
    /// Skip to the track whose id is given, make it the current track
    ///
    /// if the target track is not already the current track load that track and either play it or pause it
    /// depending on what state the currentItem is in at the start of the call
    ///
    /// If the id is not in the queue (or the queue is empty) the callback will signal an error
    ///
    func skipToTrack(id: String, callback cb: @escaping (_ success: Bool, _ errorMsg: String) -> Void) {
    	
        if let trackIndex = queue.index(where: { $0.id == id }) {
            currentTrack?.skipped = true
            updateCurrentTrack(track: trackIndex, callback: {[](_ success: Bool, _ errorMsg: String ) -> Void in
                cb(success, errorMsg)
            })
        } else {
        	cb(false, "requested track not found")
        }
    }
    
    ///
    /// Attempt to skip to the next track and either play or pause depending on what the current track is doing
    /// Success is signalled by the callback with true for the first argument
    ///	Failure is signalled by the callback with false as the first arg and an error message as the second
    ///
    func skipToNext(callback cb: @escaping (_ success: Bool, _ errorMsg: String) -> Void)
    {
    	if queue.indices.contains(currentIndex + 1) {
     		updateCurrentTrack(track: currentIndex + 1, callback: {[](_ success: Bool, _ errorMsg: String ) -> Void in
                cb(success, errorMsg)
            })
        } else {
        	stop()
         	cb(false, "queue exhausted")
        	// what to do here
        }
    }
    ///
    /// Attempt to skip to the previous track and either play or pause depending on what the current track is doing
    /// Success is signalled by the callback with true for the first argument
    /// Failure is signalled by the callback with false as the first arg and an error message as the second
    ///
    func skipToPrevious(callback cb: @escaping (_ success: Bool, _ errorMsg: String) -> Void)
    {
        if queue.indices.contains(currentIndex - 1) {
             updateCurrentTrack(track: currentIndex - 1, callback: {[](_ success: Bool, _ errorMsg: String ) -> Void in
                cb(success, errorMsg)
            })
        } else {
        	stop()
         	cb(false, "queue exhausted")
        }
    }


    func playNext() -> Bool {
        if queue.indices.contains(currentIndex + 1) {
            updateCurrentTrack(track: currentIndex+1, callback: {[self](_ success: Bool, _ errorMsg: String ) -> Void in
                // the interface does not allow for a better action then simply do nothing
                print("TODO - something better has to happen here")
                self.play()
            })
            return true
        }
        
        stop()
        return false
    }
    
    func playPrevious() -> Bool {
        if queue.indices.contains(currentIndex - 1) {
            currentIndex = currentIndex - 1
            play()
            return true
        }
        
        stop()
        return false
    }
    
    func play() {
        guard queue.count > 0 else { return }
        if (currentIndex == -1) { currentIndex = 0 }
        
        // resume playback if it was paused and check currentIndex wasn't changed by a skip/previous
        if player.state == .paused && currentTrack?.id == queue[currentIndex].id {
            player.resume()
            return
        }
        return // TODO - this is a hack
        let track = queue[currentIndex]
        player.play(track: track)
        
        setPitchAlgorithm(for: track)
        
        // fetch artwork and cancel any previous requests
        trackImageTask?.cancel()
        if let artworkURL = track.artworkURL?.value {
            trackImageTask = URLSession.shared.dataTask(with: artworkURL, completionHandler: { (data, _, error) in
                if let data = data, let artwork = UIImage(data: data), error == nil {
                    track.artwork = MPMediaItemArtwork(image: artwork)
                }
            })
        }
        
        trackImageTask?.resume()
    }
    
    func setPitchAlgorithm(for track: Track) {
        if let pitchAlgorithm = track.pitchAlgorithm {
            switch pitchAlgorithm {
            case PitchAlgorithm.linear.rawValue:
                player.player?.currentItem?.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmVarispeed
            case PitchAlgorithm.music.rawValue:
                player.player?.currentItem?.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmSpectral
            case PitchAlgorithm.voice.rawValue:
                player.player?.currentItem?.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmTimeDomain
            default:
                player.player?.currentItem?.audioTimePitchAlgorithm = AVAudioTimePitchAlgorithmLowQualityZeroLatency
            }
        }
    }
    
    func pause() {
        player.pause()
    }
    
    func stop() {
        currentIndex = -1
        self.queue = []
        player.stop()
    }
    
    // Kick off a seek operation. Will get an event when it is complete
    func seek(to time: Double) {
        self.player.seek(to: time)
    }
    
    func reset() {
        rate = 1
        queue.removeAll()
        stop()
    }
    
    // MARK: - AudioPlayerDelegate
    
    func audioPlayer(_ audioPlayer: AudioPlayer, willChangeTrackFrom from: Track?, at position: TimeInterval?, to track: Track?) {
        guard from?.id != track?.id else { return }
        delegate?.playerSwitchedTracks(trackId: from?.id, time: position, nextTrackId: track?.id)
    }
    
    func audioPlayer(_ audioPlayer: AudioPlayer, didFinishPlaying item: Track, at position: TimeInterval?) {
        print(String(format: "MediaWrapper didFinishPlaying %@\n", item.id))
        if item.skipped { return }
        if (!playNext()) {
            delegate?.playerExhaustedQueue(trackId: item.id, time: position)
        }
    }
    
    func audioPlayer(_ audioPlayer: AudioPlayer, didChangeStateFrom from: AudioPlayerState, to state: AudioPlayerState)
    {
        print("didChangeState from \(from) to \(state) \n")
        switch state {
        case .failed(let error):
            delegate?.playbackFailed(error: error)
        default:
            delegate?.playerUpdatedState()
        }
    }
    func audioPlayer(_ audioPlayer: AudioPlayer, didCompleteSeekWithOutcome success: Bool)
    {
        print("seek outcome \n")
        delegate?.playbackSeekCompleted(success: success)
    }
    
    func audioPlayer(_ audioPlayer: AudioPlayer, didBecomeReadyToPlayFor item: Track)
    {
        let trackId = item.id
        let state = player.state
        print("ready to play track with ID: \(trackId) state : \(state)\n")
    }
    func audioPlayer(_ audioPlayer: AudioPlayer)
    {
        print("ready to play \n")
    }
    
}
