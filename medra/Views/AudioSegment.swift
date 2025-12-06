//
//  AudioSegment.swift
//  medra
//
//  Audio segment model for audio editing
//

import Foundation

/// Represents a segment of audio in the editor
struct AudioSegment: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double       // Start time in seconds
    var endTime: Double         // End time in seconds
    var isSelected: Bool = false
    
    /// Duration of this segment in seconds
    var duration: Double {
        endTime - startTime
    }
    
    /// Returns true if this segment contains the given time
    func contains(time: Double) -> Bool {
        time >= startTime && time <= endTime
    }
    
    static func == (lhs: AudioSegment, rhs: AudioSegment) -> Bool {
        lhs.id == rhs.id
    }
}

/// Edit history item for undo/redo support
struct AudioEditAction {
    enum ActionType {
        case split(segmentId: UUID, splitTime: Double)
        case delete(segments: [AudioSegment])
        case merge(segments: [AudioSegment], resultSegment: AudioSegment)
        case rangeChange(oldStart: Double, oldEnd: Double, newStart: Double, newEnd: Double)
    }
    
    let type: ActionType
    let timestamp: Date = Date()
}
