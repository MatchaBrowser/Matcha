import SwiftUI

/// Arc import preview and unreadable-file alert, attached to the window (task 7.1). Once the import is done,
/// the window shows the first imported Space.
struct ArcImportPresenter: ViewModifier {
    let model: WindowModel

    func body(content: Content) -> some View {
        @Bindable var arcImport = model.arcImport
        content
            .sheet(item: $arcImport.request) { request in
                ArcImportSheet(
                    sidebar: request.sidebar,
                    profiles: model.session.profiles,
                    initialProfileID: model.space.record.profile?.id,
                ) { options in
                    perform(request.sidebar, options: options)
                }
            }
            // No action: the system's OK button.
            .alert("This File Can’t Be Imported", isPresented: $arcImport.isFailurePresented) {} message: {
                Text(ArcImportModel.fileHint)
            }
    }

    private func perform(_ sidebar: ArcSidebar, options: ArcImportOptions) {
        let importer = ArcImporter(session: model.session)
        let (_, spaces) = importer.importSidebar(sidebar, options: options)
        if let first = spaces.first {
            withAnimation(.easeInOut(duration: 0.3)) { model.select(first) }
        }
    }
}
