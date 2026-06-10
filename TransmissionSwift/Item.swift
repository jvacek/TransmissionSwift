//
//  Item.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
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
