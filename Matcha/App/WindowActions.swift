/// Actions que la fenêtre active offre aux commandes de menu.
struct WindowActions {
    /// Ouvre la barre de commande (nouvel onglet), ou un onglet sur la page d'accueil si les réglages le demandent.
    let newTab: () -> Void
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché (⌘L).
    let editAddress: () -> Void
    /// Barre de commande ouverte : ⌘W la ferme au lieu de fermer l'onglet.
    let isCommandBarPresented: Bool
    /// Ferme la barre de commande et rend le clavier à la page.
    let closeCommandBar: () -> Void
    /// Masque ou affiche la barre latérale.
    let toggleSidebar: () -> Void
    let isSidebarVisible: Bool
    /// Ouvre ou ferme le panneau des téléchargements (⌥⌘L) ; barre masquée, elle s'affiche d'abord.
    let toggleDownloads: () -> Void
    /// Panneau des téléchargements visible (ouvert, dans une barre affichée) : le menu propose de le masquer.
    let isDownloadsPanelShown: Bool
    /// Copie l'adresse de l'onglet affiché et confirme « URL copiée » (⇧⌘C), comme l'action de la
    /// barre de commande ; nil si l'onglet affiché n'a pas d'adresse.
    let copyURL: (() -> Void)?
    /// Charge la page d'accueil ; nil sans page d'accueil réglée.
    let goHome: (() -> Void)?
    /// Noms des Spaces, dans l'ordre de la barre.
    let spaceNames: [String]
    let currentSpaceIndex: Int
    let selectSpace: (Int) -> Void
    let newSpace: () -> Void
    /// Affiche un onglet de la fenêtre comme un clic sur sa ligne (⌘1 à ⌘9, ⌃⇥) : la barre de commande et
    /// l'aperçu se ferment, la page prend le clavier.
    let showTab: (BrowserTab) -> Void
    /// Fenêtre privée : « Afficher tout l'historique » (⌘Y) y est grisé, elle n'a pas d'historique.
    let isPrivate: Bool
}
