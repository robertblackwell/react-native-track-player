//
//  AudioPlayerDelegate.swift
//  AudioPlayer
//
//  Created by Kevin DELANNOY on 09/03/16.
//  Copyright © 2016 Kevin Delannoy. All rights reserved.
//

import AVFoundation

/// This typealias only serves the purpose of saving user to `import AVFoundation`.
typealias Metadata = [AVMetadataItem]

/// This protocol contains helpful methods to alert you of specific events. If you want to be notified about those
/// events, you will have to set a delegate to your `audioPlayer` instance.
protocol AudioPlayerDelegate: class {
    /// This method is called when the audio player changes its state. A fresh created audioPlayer starts in `.stopped`
    /// mode.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - from: The state before any changes.
    ///   - state: The new state.
    func audioPlayer(_ audioPlayer: AudioPlayer, didChangeStateFrom from: AudioPlayerState, to state: AudioPlayerState)

    /// This method is called when the audio player is about to start playing a new item.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - from: The item that is about to be replaced.
    ///   - position: The position item that is going to be replaced was at.
    ///   - track: The item that is about to start being played.
    func audioPlayer(_ audioPlayer: AudioPlayer, willChangeTrackFrom from: Track?, at position: TimeInterval?, to track: Track?)
    
    /// This method is called when the audio player finishes playing an item.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - item: The item that it just finished playing.
    func audioPlayer(_ audioPlayer: AudioPlayer, didFinishPlaying item: Track, at position: TimeInterval?)

    /// This method is called a regular time interval while playing. It notifies the delegate that the current playing
    /// progression changed.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - time: The current progression.
    ///   - percentageRead: The percentage of the file that has been read. It's a Float value between 0 & 100 so that
    ///         you can easily update an `UISlider` for example.
    func audioPlayer(_ audioPlayer: AudioPlayer, didUpdateProgressionTo time: TimeInterval, percentageRead: Float)

    /// This method gets called when the current item duration has been found.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - duration: Current item's duration.
    ///   - item: Current item.
    func audioPlayer(_ audioPlayer: AudioPlayer, didFindDuration duration: TimeInterval, for item: Track)

    /// This methods gets called before duration gets updated with discovered metadata.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - item: Current item.
    ///   - data: Found metadata.
    func audioPlayer(_ audioPlayer: AudioPlayer, didUpdateEmptyMetadataOn item: Track, withData data: Metadata)

    /// This method gets called while the audio player is loading the file (over the network or locally). It lets the
    /// delegate know what time range has already been loaded.
    ///
    /// - Parameters:
    ///   - audioPlayer: The audio player.
    ///   - range: The time range that the audio player loaded.
    ///   - item: Current item.
    func audioPlayer(_ audioPlayer: AudioPlayer, didLoad range: TimeRange, for item: Track)

    /// Fix for brendons bug
    /// This method gets called at the successful conclusion of establishing a new track as the currentItem
    /// which is signalled by AVPlayer.status == readyToPlay. I would like to call this action "loadingAtrack"
    /// and report the completion of the action as didFinishLoadingTrack track:Track.
    ///
    /// But not ready to go there yet
    ///
    /// This is not really captured in the PlayerEventPeoducer.PlayerEvent repetoire so this is being handled
    /// "outside normal channels"
    ///
    ///
    func audioPlayer(_ audioPlayer: AudioPlayer, didBecomeReadyToPlayFor item: Track)
    func audioPlayer(_ audioPlayer: AudioPlayer)
    func audioPlayer(_ audioPlayer: AudioPlayer, didCompleteSeekWithOutcome success: Bool)
}

extension AudioPlayerDelegate {
    func audioPlayer(_ audioPlayer: AudioPlayer, didChangeStateFrom from: AudioPlayerState,
                     to state: AudioPlayerState) {}

    func audioPlayer(_ audioPlayer: AudioPlayer, willChangeTrackFrom from: Track?, at position: TimeInterval?, to track: Track?) {}
    
    func audioPlayer(_ audioPlayer: AudioPlayer, didUpdateProgressionTo time: TimeInterval, percentageRead: Float) {}

    func audioPlayer(_ audioPlayer: AudioPlayer, didFindDuration duration: TimeInterval, for item: Track) {}

    func audioPlayer(_ audioPlayer: AudioPlayer, didUpdateEmptyMetadataOn item: Track, withData data: Metadata) {}

    func audioPlayer(_ audioPlayer: AudioPlayer, didLoad range: TimeRange, for item: Track) {}

//    func audioPlayer(_ audioPlayer: AudioPlayer, didBecomeReadyToPlayFor item: Track) {}

}
