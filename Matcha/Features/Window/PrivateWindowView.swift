import SwiftUI

/// Fenêtre de navigation privée : sa propre session, en mémoire, oubliée à la fermeture de la fenêtre. Ses
/// téléchargements terminés restent dans Téléchargements, mais quittent la liste ; ceux en cours sont annulés.
struct PrivateWindowView: View {
    @State private var session = BrowserSession.makePrivate()
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        BrowserWindowView(session: session)
            .onDisappear { downloads.forgetDownloads(in: session.downloadScope) }
    }
}
