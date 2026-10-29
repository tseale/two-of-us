import Foundation
import Observation
import UIKit
import os

/// State behind the interactive drop-off card: the whiteboard rows plus what
/// the parent has done on the card (dropped off, copied, added a note).
/// Owned by the view controller so a typed note arriving through the system
/// action row refreshes the same card instead of rebuilding it.
///
/// Writes go through `QuickLogger` (the App Group store) exactly like the
/// widget buttons — the extension can't reach the sync engine, so the
/// check-in / note sync to the co-parent when the app is next opened; the
/// geofence crossing itself already told their phone someone's at daycare.
@MainActor
@Observable
final class DropoffCardModel {
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "dropoffcard")

    private(set) var board: DropoffBoardInfo?
    /// When the Dropped off button landed the marker (shown in place of the button).
    private(set) var droppedOffAt: Date?
    /// Set when the store refused the write (no participant identity in the
    /// App Group yet) — the card says to open the app instead of lying.
    private(set) var dropOffFailed = false
    private(set) var copied = false
    private(set) var noteAdded = false

    /// Rows the notification carried, for when the store won't open.
    private let fallback: DropoffBoardInfo?

    init(userInfo: [AnyHashable: Any]) {
        fallback = DropoffBoardInfo(userInfo: userInfo)
        reload()
    }

    /// Live rows when the App Group store opens (a bottle logged in the car
    /// after the prompt fired still shows), else what the banner showed.
    func reload() {
        if let logger = QuickLogger.make() {
            board = DropoffBoard.load(from: logger.context)
        } else {
            board = fallback
        }
    }

    func dropOff() {
        guard droppedOffAt == nil else { return }
        if let event = QuickLogger.make()?.logCheck(.checkIn) {
            droppedOffAt = event.timestamp
            dropOffFailed = false
        } else {
            Self.log.error("Drop-off from the notification card refused")
            dropOffFailed = true
        }
    }

    func copyToClipboard() {
        guard let board else { return }
        UIPasteboard.general.string = board.clipboardText
        copied = true
    }

    /// A note typed into the system "Add a note" action, kept on the card:
    /// writes it, then re-reads the rows so the Notes row shows it.
    func addNote(_ text: String) {
        guard QuickLogger.make()?.logNote(text) != nil else {
            Self.log.error("Note from the notification card refused")
            return
        }
        noteAdded = true
        reload()
    }
}
