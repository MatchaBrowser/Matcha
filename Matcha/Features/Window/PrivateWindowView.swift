import SwiftUI

/// Fenêtre de navigation privée : sa propre session, en mémoire, oubliée à la fermeture de la fenêtre.
struct PrivateWindowView: View {
    @State private var session = BrowserSession.makePrivate()

    var body: some View {
        BrowserWindowView(session: session)
    }
}
