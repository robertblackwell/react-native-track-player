##Issues

This note explores a couple of issues that have come to light while using `react-native-track-player` on a recent project.

The usecase that exposed these issues is one where there was a need to position a track to a specific point __before__ allowing the track to start playing.

### The `add()` function 

The `add()` function, and the other related functions like `remove()`, `skipToNext` and `skipToPrevious`   deliver quite different results on Android and IOS.

#### Android
Following an `add()` call the the Android version of the library puts the underlying Android player object into a `prepared` state (with the current track item `loaded`) and is able to accept and respond to a `play()` or `seek()` call successfully. Further the readiness of the player (that is it being in a `prepared` state) is signalled to the caller by the resolving of the promise that the `add()` call returned. 
####IOS
On the other hand in the IOS version of the library an `add()` call does nothing to prepare the player and if a `seek()` call is issued at this point nothing will happen, the call will just drop through a series of Swift `guard` statements and be quietly ignored. 

The necessary setup work of allocating and initializing `AVPlayerItem` and `AVPLayer` is not initiated until a `play()` call is issued. 

The readiness of an `AVPlayer` to receive further instructions is signalled by the `AVPlayer.status` becoming `readyToPlay` which can be observed via KVO. However this information is not passed to the caller of the `play()` function and the resolving of the promise returned by the `play()` call __does not__ mean that the underlying AVPlayer is ready for business. 

Hence there is a period of time after a `play()` call when a `seek()` call will still be quietly ignored, namely the period while thee `AVPLayer` is buffering and before it issues `readyToPlay`.

In order to be sure that, that following a `play()` call, the underlying `AVPlayer` is ready to accept `seek()` calls the caller must wait to see a `playback-state` event where the new state is either `playing` or `paused`. A step that is not necessary for the Android implementation. 

####IOS Solution/Workaround

1.	In a fork of this project I have added a function `load()` to the underlying AudioPlayer and modified the `MediaWrapper.add()` to call `load()` whenever `currentItem` changes. This emulates the actions within the Android library.
	
	The `load()` signals via callback to `MediaWrapper` and thence via promiose to `RNTrackPlayer` when the AVPlayer is `readyToPlay`. 
	
	More specifically `load()` initializes an `AVPLayerItem`,  and an `AVplayer`, waits using KVO for the `AVPLayer` to become `readyToPlay`, then calls `play();pause()` to put the RNPTrackPlayer into `paused` state and finally signals completion of this sequence to `MediaWrapper` via a delegate function call.
	
2. A more immediate solution is for the react js application in IOS-only code to issue a `pause()` call immediately after `add();play()`. This will have the effect of putting the `RNTrackPlayer` into `pause` state eventually. The js application can determine when this `pause` state comes about by monitoring `playback-state` events looking for a new state value of `pause`.  

### The `seek()` function

The interface as represented in the `RNTrackPlayer` has no mechanism for signalling when a `seek()` has completed nor indeed whether it was successful.

In our case therefore we could not tell when the track was correctly positioned to the required starting point and hence could not determine when to start the trach `play()` ing.

####IOS Solution

The solution to this was to make use of the capability of the `seek()` function the underlying `AudioPlayer` and `AVPlayer` which accept an optional callback which is used to signal success or failure of the operation.

The callback was used to pass completion notifications back to `MediaWrapper` from where it was sent to the js application as a new event type called `playback-seek-completion`.

####Android Solution

Yet to be implemented. Android MediaPlayer certainly provides a means of listening for seek complete events.