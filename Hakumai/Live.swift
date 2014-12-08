//
//  Live.swift
//  Hakumai
//
//  Created by Hiroyuki Onishi on 11/19/14.
//  Copyright (c) 2014 Hiroyuki Onishi. All rights reserved.
//

import Foundation

class Live: Printable {
    var liveId: String?
    var title: String?
    var community: Community = Community()
    var baseTime: NSDate?
    var openTime: NSDate?
    var startTime: NSDate?
    
    var description: String {
        return (
            "Live: liveId[\(self.liveId)] title[\(self.title)] community[\(self.community)] " +
            "baseTime[\(self.baseTime)] openTime[\(self.openTime)] startTime[\(self.startTime)]"
        )
    }
    
    // MARK: - Object Lifecycle
    init() {
        // nop
    }
}