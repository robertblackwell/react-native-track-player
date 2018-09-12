# IOS Player States

The IOS implementation of RNTrackPlayer, like its Android and Windows counterparts, exposes a set of state values through which the player transitions during operation. Those states are listed below for completeness,
together with the brief documentation provided in the `react-native-track-player` wiki..

The purpose of this document is to give a more complete description of the meaning of these states, the transitions between them that take place during the operation of the player and how the available interface functions interact with these states.

The perspective of this document is __purely__ the IOS implementation, which is at least a bit different to that of the Android and Windows implementations. 


## States
| State          | Description                                           |
|:--------------:|:-----------------------------------------------------:|
|`STATE_NONE` | State indicating that no media is currently loaded |
|`STATE_PLAYING` |State indicating that the player is currently playing |
|`STATE_PAUSED` | State indicating that the player is currently paused |
|`STATE_STOPPED` |State indicating that the player is currently stopped |
|`STATE_BUFFERING` | State indicating that the player is currently buffering |

## More detail

A little bit of architecture will help with this discussion.

The `RNTrackPlayer` object implements the `react-native` interface to this native module. It in turn
has a property which is an instance of `AudioPlayer`, this  instance of `AudioPlayer` stays in existence for the life time of RNTrackPlayer and is the object that does most of the work of playing and controlling media.

`AudioPlayer` in its turn creates instances of `AVPlayerItem` and `AVPlayer` in order to play and control media via IOS; th `AV` objects are part of Apples `AVFoundation`.

`AudioPlayer` has a state variable whose value is determined by a number of attributes and properties of the `AVPLayerItem` and `AVPlayer` instances.

The `state` value reported by `RNTrackPlayer` is actually the value of the `state` variable maintained by the instance of `AudioPlayer`

### STATE_NONE

As far as I can tell the IOS implementation does not use this state.

### STATE_STOPPED

`AudioPlayer` sets its state to `STATE_STOPPED` during `init`. 

It can only be moved out of this state by a call to `add(tracks tracks:[Tracks], resolve, reject)`.

The only functions that should be called in this state are:

-	`setupPlayer()`, `updateOptions()` or `add(...)`

Calls to :

-	`getQueue()`, `getVol()`, `getTrack()`, `getCurrentTrack()`, `getDuration()`, `getBufferedPosition()`, `getPosition()`  are probably harmless but the results meaningless.

-	calls to the corresponding `setXX()` functions will have unpredictable results.

Calls to :

-	`play()`, `pause()`, `resume()`, `seek()` generally do nothing as there is no machinery at the lower level to take any action. In some circumstances these calls may crash.

Calls to :

-	`skip(to:)`, `skipToNext()`, `skipToPrevious()` are meaningless as no tracks have been added to the queue in this state.

-	similarly for `remove(tracks : [String])` and `removeUpcomingTracks()`.

### STATE_PAUSED

This is the first "active" state. A call to the function `add(tracks tracks:[Track], resolve, reject)` initiates the transition from `STATE_STOPPED` to `STATE_PAUSED`.

It does this by loading some tracks into the track queue, selecting the current track, and loading the current track into the lower level player objects.

Down inside the istance of `AudioPlayer` an instance of `AVPlayerItem` is initialized with the `url` of the current track and that `AVPlayerItem` used to initialize an iinstance of `AVPlayer`.

Successive calls to `add()` may result in the loading of a number of different tracks as the `current track` possibly changes with each set of track additions.

After the `add()` call resolves it promise, and the state is `STATE_PAUSED`, all of the `seek()`, `play()`, `pause()`, `resume()` `seekXXX()`, `remove...()` may be employed.

### STATE_BUFFERING 

This is usually a transitory state that the player goes into when it is acquiring additional data from the media data source. There are a number of siruations that give rise to this situation but at the `RNTrackPlayer` level they all get lumped together.

Probably the primary purpose of this state is to allow the UI to show a `loading data` icon while the buffering is happening.

A call to `add(tracks tracks:[Track] ....)` almost always causes a transition from `STATE_STOPPED`, to `STATE_BUFFERING` to `STATE_PAUSED`. But the buffering state is only transitionary and the `add()` is not complete until `STATE_PAUSED` is reached and its promise resolved. 

### STATE_PLAYING

This state is reached from the `PAUSED_STATE` via a call to `play()` or `resume()`.

Obviously a call to `pause()` from this state will take the player back to `STATE_PAUSED`.

As media plays there may/will be periods where the player temporarily transitions into `STATE_BUFFERING`

### A NOTE ON SEEK

`seek()` can be called in either `STATE_PAUSED` or `STATE_PLAYING`



### Back to STATE_STOPPED

From `STATE_PAUSED` or `STATE_PLAYING` a player returns to `STATE_STOPPED` by anyone of the following:

-	a call to `stop()`
- 	a call to `skipToNext()` or `skipToPrevious()` where `next` or `previous` respectively do not exist. 

On arriving in `STATE_STOPPED` the player empties the queue of tracks and the `AVPlayer/AVPlayerItem` instances are deallocated. In order to continue more tracks have to be `add()`ed and the processes started again.

### Transitioning between Tracks

Once in `STATE_PLAYING` the player will move through the tracks in the queue one afer the other. During the transition from one track to the next, the `AudioPlayer` instance must allocate new instances of `AVPlayerItem` and `AVPlayer`. Thus there will be a short transition of :

	`playing` -> `stopped` -> paused(new track)` -> `playing(new track)`
	
What happens when the last track in the queue is complete ?

As things stand the player transitions into `STATE_STOPPED` in which the queue is emptied and the `AVPlayer/AVPlayerItem` instances are deallocated. In order to continue more tracks have to be `add()`ed 