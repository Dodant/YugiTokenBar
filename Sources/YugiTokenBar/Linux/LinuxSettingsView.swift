#if os(Linux)
import Adwaita
import Foundation

extension AnyView {
    /// Save-file chooser shared by Settings and the unsaved-progress banner.
    @MainActor func linuxSaveExporter(_ signal: Binding<Signal>, model: LinuxModel) -> AnyView {
        fileExporter(open: signal, initialName: SaveEnvelope.fileName(Date()), title: L("세이브 내보내기"),
                     onSave: { model.export(to: $0) })
    }
}

@MainActor struct LinuxSettingsView: View {
    let snapshot: LinuxSnapshot
    let model: LinuxModel
    @State private var importer: Signal = .init()
    @State private var exporter: Signal = .init()

    var view: Body {
        VStack(spacing: 10) {
            Text(L("백업 & 이전")).style("title-3").halign(.start)
            HStack(spacing: 10) {
                Button(L("내보내기")) { exporter.signal() }.linuxSmokeID("settings-export")
                Button(L("가져오기")) { importer.signal() }.linuxSmokeID("settings-import")
            }.halign(.start)
            Text(L("지금 세이브는 먼저 자동 백업돼요")).style("dim-label").halign(.start)
            if let message = snapshot.transferMessage { Text(message).wrap().halign(.start) }
            if let error = snapshot.transferError { Text(error).wrap().halign(.start).style("error") }
        }
        .padding(20).valign(.start).vexpand()
        .linuxSaveExporter($exporter, model: model)
        .fileImporter(open: $importer, filters: [.mimeType("application/json")], title: L("세이브 가져오기"),
                      onOpen: { model.prepareImport(at: $0) })
        .dialog(visible: Binding(get: { snapshot.pendingImport != nil }, set: { if !$0 { model.cancelImport() } }),
                title: L("세이브를 바꿀까요?"), id: "import", width: 420) {
            VStack(spacing: 10) {
                if let pending = snapshot.pendingImport {
                    let current = snapshot.game.state, incoming = pending.envelope
                    Text(L("가져올 세이브: 카드 %lld종 · %@\n(%@, v%@)\n지금 세이브: 카드 %lld종 · %@\n\n지금 세이브는 세이브 폴더에 자동 백업돼요.",
                           .int(incoming.state.distinctOwned), .text(coinText(incoming.state.coins)),
                           .text(stamp(incoming.exportedAt, "yyyy-MM-dd HH:mm")), .text(incoming.appVersion),
                           .int(current.distinctOwned), .text(coinText(current.coins)))).wrap().padding()
                }
                if let error = snapshot.transferError { Text(error).wrap().style("error") }
                HStack(spacing: 10) {
                    Button(L("취소")) { model.cancelImport() }.linuxSmokeID("import-cancel")
                    Button(L("바꾸기")) { model.confirmImport() }.linuxSmokeID("import-confirm")
                }.padding()
            }
        }
    }
}
#endif
