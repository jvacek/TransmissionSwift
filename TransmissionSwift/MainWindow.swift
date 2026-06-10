import SwiftUI
import TransmissionCore

/// The S1 main window — sidebar · torrent list · optional inspector, with a
/// grouped toolbar on top and a status bar attached to the bottom safe area.
///
/// `.inspector` is attached to the outer `NavigationSplitView` (not the
/// detail) so it sits as a peer pane to the split view. That keeps the
/// toolbar's search field anchored to the detail's column and stops the
/// inspector pane from creeping under the toolbar's Liquid Glass.
struct MainWindow: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 212)
        } detail: {
            TorrentListView()
                .navigationTitle("Transmission")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBarView()
                }
                .searchable(
                    text: $store.searchQuery,
                    placement: .toolbar,
                    prompt: "Search torrents"
                )
                .toolbar {
                    MainToolbar()
                }
        }
        .inspector(isPresented: $store.inspectorVisible) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 322)
        }
        .frame(minWidth: 960, minHeight: 600)
    }
}
