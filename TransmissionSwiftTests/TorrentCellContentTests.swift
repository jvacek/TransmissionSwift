import AppKit
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The display-value builder that feeds one table cell. `TorrentCellContent` is
/// the seam the AppKit cell renders, so its output is what the row shows.
@Suite("TorrentCellContent.make")
struct TorrentCellContentTests {
    @Test func cellContent_nameCarriesStatusDotAndTagDots() {
        let torrent = makeTableTorrent(labels: ["A", "B"])
        let content = TorrentCellContent.make(
            for: .name, row: TorrentRowDisplay(torrent), downloadDirectoryBase: nil,
            tagColors: ["A": .red])
        #expect(content.shape == .dotAndText)
        #expect(content.text == torrent.name)
        #expect(content.dotColor == torrent.status.nsDisplayColor)
        // A coloured tag uses its colour; an uncoloured tag falls back to grey.
        #expect(content.trailingDotColors == [TagColor.red.nsColor, .tertiaryLabelColor])
    }

    @Test func cellContent_progressExposesValuePercentAndTint() {
        let torrent = makeTableTorrent(progress: 0.42)
        let content = TorrentCellContent.make(
            for: .progress, row: TorrentRowDisplay(torrent), downloadDirectoryBase: nil)
        #expect(content.shape == .progress)
        #expect(content.progressValue == 0.42)
        #expect(content.percentText == "42%")
        #expect(content.accessibilityLabel == "42 percent")
        #expect(content.progressTint == torrent.status.nsDisplayColor)
    }

    @Test func cellContent_labelWithoutTagsIsAnEmDash() {
        let content = TorrentCellContent.make(
            for: .label, row: TorrentRowDisplay(makeTableTorrent()), downloadDirectoryBase: nil)
        #expect(content.shape == .text)
        #expect(content.text == "\u{2014}")
    }

    @Test func cellContent_labelWithTagsUsesPillsAndColours() {
        let torrent = makeTableTorrent(labels: ["A", "B"])
        let content = TorrentCellContent.make(
            for: .label, row: TorrentRowDisplay(torrent), downloadDirectoryBase: nil,
            tagColors: ["A": .blue])
        #expect(content.shape == .pills)
        #expect(content.pillTexts == ["A", "B"])
        #expect(content.pillBackgroundColors?.first == TagColor.blue.nsColor)
        #expect(content.pillForegroundColors?.first == TagColor.blue.nsPillForeground)
    }

    @Test func cellContent_priorityCarriesSymbolAndLabel() {
        let content = TorrentCellContent.make(
            for: .priority, row: TorrentRowDisplay(makeTableTorrent(priority: .high)),
            downloadDirectoryBase: nil)
        #expect(content.shape == .symbolAndText)
        #expect(content.text == TorrentPriority.high.displayLabel)
        #expect(content.symbolName == TorrentPriority.high.systemImage)
        #expect(content.accessibilityLabel == "high priority")
    }

    @Test func cellContent_queuePositionNilIsAnEmDash() {
        let content = TorrentCellContent.make(
            for: .queuePosition, row: TorrentRowDisplay(makeTableTorrent()),
            downloadDirectoryBase: nil)
        #expect(content.text == "\u{2014}")
        #expect(content.color == .tertiaryLabelColor)
    }

    @Test func cellContent_queuePositionRendersHashPrefix() {
        let content = TorrentCellContent.make(
            for: .queuePosition, row: TorrentRowDisplay(makeTableTorrent(queuePosition: 3)),
            downloadDirectoryBase: nil)
        #expect(content.text == "#3")
    }

    @Test func cellContent_errorMessagePresentIsRed() {
        let content = TorrentCellContent.make(
            for: .errorMessage,
            row: TorrentRowDisplay(makeTableTorrent(errorMessage: "tracker down")),
            downloadDirectoryBase: nil)
        #expect(content.text == "tracker down")
        #expect(content.color == .systemRed)
    }

    @Test func cellContent_downloadFolderKeepsFullPathInToolTip() {
        let torrent = makeTableTorrent()
        let content = TorrentCellContent.make(
            for: .downloadFolder, row: TorrentRowDisplay(torrent),
            downloadDirectoryBase: "/downloads")
        #expect(content.toolTip == torrent.downloadFolder)
        #expect(content.accessibilityLabel == torrent.downloadFolder)
    }
}
