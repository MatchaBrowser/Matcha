import SwiftUI

/// Aperçu de l'import d'Arc et alerte d'un fichier illisible, attachés à la fenêtre (tâche 7.1). L'import fait,
/// la fenêtre affiche le premier Space importé.
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
            // Sans action : le bouton OK du système.
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
