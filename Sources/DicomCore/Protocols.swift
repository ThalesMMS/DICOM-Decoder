//
//  Protocols.swift
//
//  Defines lightweight abstraction layers that decouple the core
//  decoding and window/level logic from concrete UIKit views.
//

import Foundation

/// Surface capable of applying window/level settings. Concrete
/// implementations may be backed by UIKit, AppKit, Metal, or any
/// other rendering system.
public protocol DicomWindowingSurface: AnyObject {
    /// Apply window width/center in pixel space. Implementations are
    /// responsible for recomputing lookup tables and redrawing.
    func applyWindowLevel(windowWidth: Int, windowCenter: Int)
}
