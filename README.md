
# react-native-track-player

This is a fork of [https://github.com/react-native-kit/react-native-track-player](https://github.com/react-native-kit/react-native-track-player).

The reason for the fork is because I had a use case that required somewhat different behaviour and a few extra facilities than the original (duh!).

Specifically I needed to be able to position an audio track with a `seek()` call before the track was played,
and to ensure that the track did not start playing until the intended seek position had been reached.

Investigating this I discovered that `seek()` before `play()` was a little less obvious than expected on IOS devices and that not `play()`ing until after `seek()` was complete even more so.

I believe (only by reading the Android code, not by testing) that there is quite a difference in behaviour on IOS devices compared to Android devices. 

Finally I found the state transitions undergone by an `RNTrackPlayer` and the interaction between those states and the interface functions was not very clear.

For more details see:

[Android IOS Differences](https://github.com/robertblackwell/react-native-track-player/wiki/android_ios_diffs)

[Player State](https://github.com/robertblackwell/react-native-track-player/wiki/player_state)

