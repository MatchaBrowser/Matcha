import Foundation
import OSLog

/// Catégories de journalisation, une par module.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.matchabrowser.matcha"

    /// Application, réglages.
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Onglets, navigation et WebKit.
    static let browser = Logger(subsystem: subsystem, category: "Browser")
    /// Icônes des sites.
    static let favicons = Logger(subsystem: subsystem, category: "Favicons")
    /// Barre de commande et suggestions de recherche.
    static let commandBar = Logger(subsystem: subsystem, category: "CommandBar")
    /// Aperçu des liens (Maj+clic).
    static let peek = Logger(subsystem: subsystem, category: "Peek")
    /// Mini-fenêtres et leur raccourci global ; jamais d'adresse ni de texte tapé.
    static let miniWindow = Logger(subsystem: subsystem, category: "MiniWindow")
    /// Téléchargements ; jamais d'adresse complète ni de nom de fichier, seulement l'hôte.
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    /// Permissions des sites (caméra, micro) et données d'un site ; jamais d'adresse complète, seulement l'hôte.
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
}
