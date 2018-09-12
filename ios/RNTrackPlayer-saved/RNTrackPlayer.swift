//
//  RNTrackPlayer.swift
//  rn_track_player_app
//
//  Created by ROBERT BLACKWELL on 9/8/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

import Foundation
@objc(RNTrackPlayer)
class RNTrackPlayer: NSObject {

  func constantsToExport() -> [AnyHashable : Any]! {
    return ["initialCount": 0]
  }
  
  func testFunction() {
    NSLog("Got here")
  }



}

