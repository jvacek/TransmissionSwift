import Testing
import TransmissionCore

@testable import TransmissionSwift

@Suite("AddTorrentFileNode tree")
struct AddTorrentFileTreeTests {
    private func file(
        _ index: Int,
        _ path: String,
        length: Int64 = 1,
        wanted: Bool = true,
        priority: TorrentPriority = .normal
    ) -> TorrentAddFile {
        TorrentAddFile(
            index: index,
            path: path.split(separator: "/").map(String.init),
            length: length,
            wanted: wanted,
            priority: priority)
    }

    @Test("flat files become file nodes sorted by name")
    func flatFiles() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "b.txt"),
            file(1, "a.txt"),
        ])

        #expect(tree.map(\.name) == ["a.txt", "b.txt"])
        #expect(tree.allSatisfy { !$0.isFolder })
        #expect(tree.map(\.fileIndices) == [[1], [0]])
    }

    @Test("folders nest and collect every descendant index")
    func nestedFolders() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "Season 01/Episode 01.mkv"),
            file(1, "Season 01/Episode 02.mkv"),
            file(2, "Season 01/Subs/English.srt"),
            file(3, "README.nfo"),
        ])

        #expect(tree.map(\.name) == ["Season 01", "README.nfo"])
        let season = tree[0]
        #expect(season.isFolder)
        #expect(season.fileIndices == [0, 1, 2])
        #expect(
            season.children?.map(\.name) == ["Subs", "Episode 01.mkv", "Episode 02.mkv"])
        #expect(season.children?.first?.fileIndices == [2])
    }

    @Test("a file at the root and a folder are both kept")
    func rootFileAndFolder() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "README.nfo"),
            file(1, "Season 01/Episode 01.mkv"),
        ])

        #expect(tree.map(\.name) == ["Season 01", "README.nfo"])
        #expect(tree[0].fileIndices == [1])
        #expect(tree[1].fileIndices == [0])
    }

    @Test("a filtered subset keeps only its ancestors")
    func filteredSubset() {
        let tree = AddTorrentFileNode.tree(from: [
            file(2, "Season 01/Subs/English.srt")
        ])

        #expect(tree.count == 1)
        #expect(tree[0].name == "Season 01")
        #expect(tree[0].children?.map(\.name) == ["Subs"])
        #expect(tree[0].children?.first?.children?.map(\.name) == ["English.srt"])
        #expect(tree[0].fileIndices == [2])
    }

    @Test("node count includes folders and files")
    func nodeCount() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "Season 01/Episode 01.mkv"),
            file(1, "README.nfo"),
        ])

        #expect(tree.reduce(0) { $0 + $1.nodeCount } == 3)
    }

    @Test("folder ids cover every folder for the default expansion")
    func folderIDs() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "Season 01/Subs/English.srt"),
            file(1, "README.nfo"),
        ])

        #expect(tree.flatMap(\.folderIDs) == ["folder:Season 01", "folder:Season 01/Subs"])
    }

    @Test("node ids include the folder and all of its descendants")
    func nodeIDs() {
        let tree = AddTorrentFileNode.tree(from: [
            file(0, "Season 01/Subs/English.srt")
        ])

        #expect(
            tree[0].nodeIDs == [
                "folder:Season 01",
                "folder:Season 01/Subs",
                "file:0",
            ])
    }
}
