//
//  Item.swift
//  closet
//
//  Created by 赵建华 on 2026/3/10.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
