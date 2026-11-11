import AppKit
import Testing

@testable import TransmissionSwift

@Suite("FileListSelection")
struct FileListSelectionTests {
    private let none: NSEvent.ModifierFlags = []
    private let command: NSEvent.ModifierFlags = .command
    private let shift: NSEvent.ModifierFlags = .shift
    private let commandShift: NSEvent.ModifierFlags = [.command, .shift]
    private let visible = [0, 1, 2, 3, 4]

    @Test("a plain click replaces the selection")
    func plainClick() {
        var selection = FileListSelection()
        selection.click(2, visible: visible, modifiers: none)
        #expect(selection.ids == [2])
        #expect(selection.anchor == 2)

        selection.click(4, visible: visible, modifiers: none)
        #expect(selection.ids == [4])
        #expect(selection.anchor == 4)
    }

    @Test("Command-click toggles a row and moves the anchor")
    func commandClick() {
        var selection = FileListSelection()
        selection.click(1, visible: visible, modifiers: none)
        selection.click(3, visible: visible, modifiers: command)
        #expect(selection.ids == [1, 3])
        #expect(selection.anchor == 3)

        selection.click(1, visible: visible, modifiers: command)
        #expect(selection.ids == [3])
        #expect(selection.anchor == 1)
    }

    @Test("Shift-click selects the range from the anchor")
    func shiftClick() {
        var selection = FileListSelection()
        selection.click(1, visible: visible, modifiers: none)
        selection.click(4, visible: visible, modifiers: shift)

        #expect(selection.ids == [1, 2, 3, 4])
        #expect(selection.anchor == 1)
    }

    @Test("Shift-click works upwards too")
    func shiftClickUpwards() {
        var selection = FileListSelection()
        selection.click(4, visible: visible, modifiers: none)
        selection.click(2, visible: visible, modifiers: shift)

        #expect(selection.ids == [2, 3, 4])
    }

    @Test("Command-Shift adds the range to the existing selection")
    func commandShiftClick() {
        var selection = FileListSelection()
        selection.click(0, visible: visible, modifiers: none)
        selection.click(4, visible: visible, modifiers: command)
        selection.click(2, visible: visible, modifiers: commandShift)

        #expect(selection.ids == [0, 2, 3, 4])
    }

    @Test("a hidden anchor falls back to a plain click")
    func hiddenAnchor() {
        var selection = FileListSelection()
        selection.click(1, visible: visible, modifiers: none)
        selection.click(3, visible: [0, 2, 3], modifiers: shift)

        #expect(selection.ids == [3])
        #expect(selection.anchor == 3)
    }

    @Test("ranges follow the visible order")
    func visibleOrder() {
        var selection = FileListSelection()
        selection.click(0, visible: [0, 2, 3], modifiers: none)
        selection.click(3, visible: [0, 2, 3], modifiers: shift)

        #expect(selection.ids == [0, 2, 3])
    }

    @Test("select all covers the visible rows and anchors the first")
    func selectAll() {
        var selection = FileListSelection()
        selection.selectAll(visible: [1, 3, 4])

        #expect(selection.ids == [1, 3, 4])
        #expect(selection.anchor == 1)
    }

    @Test("clear empties the ids and anchor")
    func clear() {
        var selection = FileListSelection()
        selection.selectAll(visible: visible)
        selection.clear()

        #expect(selection.ids.isEmpty)
        #expect(selection.anchor == nil)
        #expect(selection.isEmpty)
    }
}
