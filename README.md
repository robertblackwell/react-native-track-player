
# react-native-track-player

This is a fork of [https://github.com/react-native-kit/react-native-track-player](https://github.com/react-native-kit/react-native-track-player).

The reason for the fork is because I had a use case that required somewhat different behaviour and a few extra facilities than the original (duh!).

Specifically I needed to be able to position an audio track with a `seek()` call before the track was played,
and to ensure that the track did not start playing until the intended seek position had been reached.

Investigating this I discovered that `seek()` before `play()` was a little less obvious than expected on IOS devices and that not `play()`ing until after `seek()` was even more so.

I believe (only by reading the Android code, not by testing) that there is quite a difference in behaviour on IOS devices compared to Android devices. 

Finally I found the state transitions undergone by an `RNTrackPlayer` and the interaction between those states and the interface functions was not very clear.

For more details see:

[Android IOS Differences](https://github.com/robertblackwell/react-native-track-player/wiki/android_ios_diffs)

[Player State](https://github.com/robertblackwell/react-native-track-player/wiki/player_state)

## Changes

The following changes have been made to the IOS code in this fork.

### `add()`

The `add()` function returns a `Promise`. 

When that promise `resolves` the player has loaded the `currentItem` (usually the first in the array of tracks), performed all initialization of the track and has the track in `paused` state. The track is ready for `play()` or either flavour of `seek()` (see below for new flacour of seek).

### `seekTo()`

The standard behaviour of this function is to return immediately it has initiated a seek operation, and provide no indicatio of when or if that seek operation completes.

A new event has been added to the `TrackPlayer` interface called `playbck-seek-complete` that fires when the underlying player objects detect completion of a seek operation.

### `seekToPromise()`

This is a new interface function; it returns a Promise.

When the promise `resolves` the seek operation is complete. If the seek operation fails (according to the AVFoundation documentation this can happen if another seek is issued before the first one is complete) the promise will be `rejected`.

This type of seek operation __ALSO__ fire the `player-seek-complete` event.