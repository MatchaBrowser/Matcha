# PLAN.md — navigateur style Arc sur WebKit

Feuille de route de développement, à suivre dans l'ordre. Les règles de travail sont dans `CLAUDE.md`.

**Légende**
- `[ ]` à faire · `[x]` fait
- **[MANUEL]** : action faite par moi (Xcode, portail Apple). Claude donne les étapes et attend.
- **[À VOIR]** : contrôle visuel ou manuel à faire avant de cocher.
- Les noms d'API sont indicatifs : vérifier les signatures exactes dans le SDK avant d'écrire le code.
- Les fonctions mises de côté sont dans `FEATURES.md` : ne pas les reprendre sans mon accord.

---

## Phase 0 — Mise en place

- [x] **0.1 [MANUEL] Créer le projet.** Xcode > Fichier > Nouveau > Projet > macOS > App. Nom `open-browser` (renommé Matcha par la suite), interface SwiftUI, langage Swift, stockage SwiftData, tests inclus (Swift Testing), case « Create Git repository » cochée. Dans la cible : déploiement minimal macOS 15.4, mode de langage Swift 6.
- [x] **0.2 [MANUEL] Permissions de l'app.** Onglet Signing & Capabilities : équipe = identifiant Apple personnel ; App Sandbox avec Outgoing Connections (Client), Downloads Folder (Read/Write), User Selected File (Read/Write), Camera, Audio Input ; Hardened Runtime activé.
- [x] **0.3 [MANUEL] Textes de permission.** Onglet Info de la cible : ajouter `NSCameraUsageDescription` et `NSMicrophoneUsageDescription` (« Un site demande l'accès à la caméra », etc.). Sans eux, l'app plante à la première visio.
- [x] **0.4 Squelette du dépôt.** Créer les dossiers décrits dans `CLAUDE.md`, un `.gitignore` (`build/`, `DerivedData/`, `xcuserdata/`, `.DS_Store`, `*.xcuserstate`), `DECISIONS.md` vide avec son en-tête, `.swiftformat` et `.swiftlint.yml` minimaux (indentation 4 espaces, longueur de ligne 140).
- [x] **0.5 Vérifier la chaîne.** Lancer les commandes de compilation et de test de `CLAUDE.md`, ouvrir l'app, faire le premier commit.

**Fini quand** la compilation et les tests passent depuis le terminal et que l'app s'ouvre.

---

## Phase 1 — Un navigateur minimal

- [x] **1.1 Configuration WebKit** (`Browser/WebConfigurationFactory.swift`). Fonction qui fabrique un `WKWebViewConfiguration` :
  - `websiteDataStore` passé en paramètre (le magasin par défaut pour l'instant) ;
  - `preferences.isElementFullscreenEnabled = true` (plein écran vidéo) ;
  - `applicationNameForUserAgent = "Version/<x> Safari/605.1.15"`, version dans une constante, pour que les sites traitent l'app comme Safari ;
  - plus tard : bloqueur, Boosts et extensions s'y brancheront.
- [x] **1.2 `BrowserTab`** (`Browser/BrowserTab.swift`). `@MainActor @Observable final class` avec `id: UUID`, le `WKWebView`, et les propriétés `title`, `url`, `isLoading`, `progress`, `canGoBack`, `canGoForward` mises à jour par observation KVO (`observe(\.title, …)`, jetons gardés dans un tableau). Méthodes `load(_:)`, `goBack()`, `goForward()`, `reload()`, `stop()`. Sur la vue web : `allowsBackForwardNavigationGestures = true`, `allowsMagnification = true`, `isInspectable = true` en Debug seulement.
- [x] **1.3 Vue SwiftUI** (`Browser/WebView.swift`). `NSViewRepresentable` qui renvoie le `WKWebView` déjà créé par l'onglet (jamais de nouvelle vue dans `makeNSView`). Changer d'onglet = afficher une autre instance, avec `.id(tab.id)`.
- [x] **1.4 Résolution URL ou recherche** (`Browser/AddressResolver.swift`, type pur + tests). Texte tapé → `URL` :
  - schéma présent (`http`, `https`, `file`, `about`) → URL telle quelle ;
  - ressemble à un hôte (contient un point et aucun espace, `localhost`, adresse IP, port ou chemin éventuels) → préfixe `https://` ;
  - sinon → URL de recherche du moteur choisi, texte encodé.
  - Tests au minimum : `apple.com`, `https://a.b/c`, `localhost:3000`, `192.168.1.1`, `comment faire du pain`, `swift 6.4` (point mais espace → recherche).
- [x] **1.5 `TabManager`** (`Browser/TabManager.swift`). `@MainActor @Observable` : liste des onglets, onglet sélectionné, `newTab(url:)`, `close(_:)`, `select(_:)`. Fermer l'onglet actif sélectionne son voisin. Tests de la logique de sélection.
- [x] **1.6 Délégués** (`Browser/NavigationCoordinator.swift`).
  - `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` : crée un `BrowserTab` **avec la configuration fournie** (obligatoire pour que `window.opener` marche), l'insère après l'onglet courant et renvoie sa vue.
  - `decidePolicyFor navigationAction` : schémas non web (`mailto:`, `tel:`, liens d'apps) → `NSWorkspace.shared.open`, puis annulation. ⌘+clic ou clic molette (`modifierFlags`, `buttonNumber`) → nouvel onglet en arrière-plan.
- [x] **1.7 Interface provisoire.** Liste d'onglets à gauche, champ d'adresse, vue web. Elle sera remplacée en phase 2 ; rester simple.
- [x] **1.8 Raccourcis** (`App/BrowserCommands.swift`, `.commands`). ⌘T nouvel onglet, ⌘W fermer, ⌘L champ d'adresse, ⌘R recharger, ⌘[ et ⌘] précédent et suivant.

**Fini quand [À VOIR]** tu navigues dans plusieurs onglets, les liens `target=_blank` ouvrent un onglet et la connexion à un compte Google fonctionne.

---

## Phase 2 — La coque Arc

- [x] **2.1 Fenêtre** (`Features/Window/`). `.windowStyle(.hiddenTitleBar)` ; un petit `WindowAccessor` (`NSViewRepresentable`) pour régler `titlebarAppearsTransparent` et `isMovableByWindowBackground`. Un fond `SpaceBackground` (dégradé, couleurs provisoires) remplit toute la fenêtre, `.ignoresSafeArea()`. Réserver la place des boutons rouge-orange-vert en haut de la barre latérale.
- [x] **2.2 Disposition** (`BrowserWindowView`). Barre latérale à gauche, carte de contenu à droite. Largeur de la barre réglable en glissant son bord (180 à 400 pt, mémorisée). Carte : marge de 8 pt en haut, à droite et en bas, coins arrondis 10 pt, bordure fine, ombre légère.
- [x] **2.3 Barre latérale** (`Features/Sidebar/`), de haut en bas :
  - ligne des boutons de fenêtre + boutons précédent, suivant, recharger ;
  - `AddressPill` : affiche le domaine ; un clic ou ⌘L passe en édition de l'URL complète ;
  - `FavoritesGrid` : grille de tuiles d'icônes (4 colonnes) ;
  - `PinnedSection` : dossiers et onglets épinglés ;
  - séparateur avec bouton « + Nouvel onglet » ;
  - `TodaySection` : onglets du jour, bouton « Effacer » ;
  - pied : `SpaceSwitcher` (une icône par Space) et bouton +.
  - En phase 2, la place d'un onglet (favori, épinglé, du jour) est une simple propriété en mémoire ; la persistance arrive en phase 3.
- [x] **2.4 Masquer la barre** avec ⌘S. Masquée, la carte prend toute la largeur ; le survol des 8 pt du bord gauche la fait apparaître par-dessus, et elle repart quand le pointeur s'éloigne.
- [x] **2.5 Favicons** (`Services/FaviconService.swift`). Après chargement, lire en JavaScript la meilleure icône (`link rel="icon"`, `apple-touch-icon`, la plus grande), sinon `/favicon.ico`. Téléchargement `URLSession`, cache mémoire (`NSCache`) et disque (`Caches/Favicons/`). À défaut, une pastille colorée avec l'initiale du site.
- [x] **2.6 Glisser-déposer.** Réordonner dans une section ; déplacer entre favoris, épinglés et onglets du jour ; déposer dans un dossier. Type `Transferable` qui ne transporte que l'identifiant de l'onglet.
- [x] **2.7 Dossiers épinglés.** Créer, renommer, replier, imbriquer.
- [x] **2.8 Menu contextuel des lignes.** Dupliquer, Copier le lien, Épingler ou Désépingler, Ajouter aux favoris, Fermer, Fermer les autres. Bouton × au survol de chaque ligne.
- [x] **2.9 Comportement d'Arc pour les épinglés.** ⌘W sur un onglet épinglé ne le supprime pas : il revient à son URL d'origine et se décharge.
- [x] **2.10 Icône du site dans la barre d'adresse.** Afficher l'icône du site (ou sa pastille) devant le domaine. Fiabiliser les icônes : une icône qui n'a pas pu être chargée est réessayée au chargement suivant.
- [x] **2.11 Réglages** (`App/Settings/`, ⌘,). Fenêtre de réglages en onglets, valeurs dans `UserDefaults` décrites par un type `BrowserSettings` : moteur de recherche ; apparence (système, clair, sombre) ; alerte avant de quitter ; effacer les cookies et données des sites (avec confirmation). Laisser la place des profils (3.6) et des thèmes de Space (3.4).
- [x] **2.12 Page d'accueil et bouton Accueil.** Réglages : adresse d'accueil, bouton Accueil affiché ou non, nouveaux onglets ouverts sur la page d'accueil ou vides. Raccourci ⌘⇧H.
- [x] **2.13 Position de la barre d'adresse.** Réglage : dans la barre latérale (comme Arc) ou pleine largeur au-dessus de la page, dans la carte, avec précédent, suivant, recharger, icône du site et Accueil. Réglage : afficher ou masquer les boutons de navigation.

**Fini quand [À VOIR]** une capture côte à côte avec Arc te convainc.

---

## Phase 3 — Spaces, profils et persistance

- [x] **3.1 Modèles SwiftData** (`Models/`), compatibles CloudKit (voir `CLAUDE.md`) :
  - `ProfileRecord` : id, nom ;
  - `SpaceRecord` : id, nom, symbole d'icône, thème (couleurs encodées), ordre, profil ;
  - `FolderRecord` : id, nom, ordre, replié ou non, Space, dossier parent ;
  - `TabRecord` : id, URL, titre, place (`favorite`, `pinned`, `today`, `archived`), ordre, dernière activité, URL d'origine (épinglés), `interactionState` (Data optionnel), Space, dossier.
  - Les favoris appartiennent au profil (communs aux Spaces de ce profil) ; épinglés et onglets du jour appartiennent au Space.
- [x] **3.2 Lien enregistrements ↔ onglets.** Au lancement, `TabManager` charge les `TabRecord` et ne crée la vue web d'un onglet qu'à son premier affichage. Les changements sont réécrits avec un délai d'une seconde.
- [x] **3.3 Premier lancement.** Créer un profil par défaut et un Space « Perso ».
- [x] **3.4 Thèmes** (`Features/Spaces/SpaceTheme.swift`). 2 ou 3 couleurs, angle du dégradé, variantes clair et sombre : c'est la couleur de la barre latérale et du fond. Éditeur en popover : couleurs prédéfinies et sélecteur libre. Le fond s'anime au changement de Space.
- [x] **3.5 Changer de Space.** ⌃1 à ⌃9. Glissement horizontal à deux doigts sur la barre latérale : sous-classe de `NSView` qui lit `scrollWheel(with:)` (`phase`, `scrollingDeltaX`), seuil d'environ 80 pt, ignoré si le geste est surtout vertical. Le contenu de la barre glisse comme des pages.
- [x] **3.6 Profils isolés.** Un `WKWebsiteDataStore(forIdentifier: profile.id)` par profil ; chaque onglet est créé avec le magasin du profil de son Space. Déplacer un onglet vers un Space d'un autre profil recrée sa vue web à partir de l'URL. Écran de gestion, dans un onglet « Profils » des réglages (2.11) : créer, renommer, supprimer un profil (`WKWebsiteDataStore.remove(forIdentifier:)`).
- [x] **3.7 Restauration de session.** Sauvegarder `webView.interactionState` (converti en `Data`) quand un onglet quitte l'écran, avant déchargement et à la fermeture de l'app ; à la recréation, affecter cet état au lieu de recharger l'URL, pour garder l'historique précédent/suivant.
- [x] **3.8 Fenêtre privée** (⌘⇧N). `WindowGroup` séparé, `WKWebsiteDataStore.nonPersistent()`, thème sombre fixe, rien d'enregistré, pas d'historique.

**Fini quand [À VOIR]** deux Spaces restent connectés à deux comptes Google différents après redémarrage, et le bouton précédent fonctionne sur les onglets restaurés.

---

## Phase 4 — Les fonctions signature

- [x] **4.0 Langues** (`Resources/Localizable.xcstrings`). Catalogue de chaînes de Xcode, avec l'anglais comme langue source (c'est déjà la `developmentRegion` du projet). Les textes du code passent en anglais et le français devient une traduction complète. Langues de l'app : anglais (langue source : ce sont les textes du code, soignés comme une traduction), français, allemand, espagnol, italien. Les langues sont ajoutées aux `knownRegions` du projet.
  - Tous les textes passent par le catalogue. Pour `Text`, `Button`, `Label` et les menus SwiftUI, c'est automatique. Ailleurs (AppKit, textes calculés, paramètres des vues) : `String(localized:)` ou `LocalizedStringResource`. Pluriels par les variantes du catalogue ; dates et nombres par `FormatStyle`, jamais assemblés à la main.
  - Les noms créés au premier lancement (profil « Personnel », Space « Perso ») sont traduits à leur création, puis traités comme des données de l'utilisateur.
  - Réglages > Général : l'app suit la langue de macOS ; un bouton « Changer la langue… » ouvre Réglages Système > Langue et région (langue par app).
  - Les tests d'interface lancent l'app en français (`-AppleLanguages (fr)`). Un test vérifie que chaque langue du bundle traduit toutes les clés.
  - Dans `CLAUDE.md`, la règle « Textes de l'interface en français » devient : textes en anglais dans le code, traduits dans toutes les langues au sein de la même tâche.
- [x] **4.1 Barre de commande** (`Features/CommandBar/`). Panneau centré par-dessus la fenêtre (≈ 640 pt de large, matériau flouté), deux modes : nouvel onglet (⌘T) et édition de l'onglet courant (⌘L).
  - Protocole `CommandProvider` (résultats asynchrones pour une requête) avec : onglets ouverts, épinglés et favoris, historique (préfixe puis approximatif, classé par fréquence et récence), suggestions du moteur de recherche (délai de 150 ms, requête précédente annulée), actions (« Nouveau Space », « Copier l'URL », « Réglages »).
  - Première ligne : ouvrir l'URL ou lancer la recherche exacte. Clavier : ↑ ↓ ⏎ ⎋.
  - Tests du classement des résultats.
- **4.2 Archivage automatique** : reportée, voir `FEATURES.md`.
- [x] **4.3 Split view.** Groupe de 2 à 4 onglets côte à côte dans la carte, séparateurs réglables. Création en déposant un onglet sur le bord gauche ou droit de la carte, ou par le menu « Ouvrir en split ». Dans la barre latérale, le groupe tient sur une ligne. Le panneau actif est marqué et le champ d'adresse le suit.
- [x] **4.4 Peek** (`Features/Peek/`). Maj+clic sur un lien : navigation annulée, page ouverte dans un aperçu flottant (≈ 85 % de la carte, fond assombri, même profil). Boutons « Ouvrir en onglet » (la même vue web passe dans un nouvel onglet, sans recharger) et « Fermer » (⎋ ou clic à côté). Option : les liens d'un épinglé vers un autre domaine s'ouvrent aussi en aperçu.
- [x] **4.5 Mini-fenêtre** (`Features/MiniWindow/`, l'équivalent de Little Arc). `NSPanel` flottant d'environ 520 × 680 pt, barre minimale : domaine, « Ouvrir dans le Space », fermer. Raccourci global réglable avec KeyboardShortcuts (défaut ⌥⌘N). Les liens venus d'autres apps y arriveront en phase 8.
- [x] **4.6 Copier l'URL** avec ⌘⇧C et une petite confirmation « URL copiée ».
- **4.7 Boosts** : reportée, voir `FEATURES.md`.
- [x] **4.8 Raccourcis supplémentaires.** ⌘1 à ⌘8 pour les premiers favoris puis épinglés, ⌘9 pour le dernier onglet ; ⌃Tab et ⌃⇧Tab pour l'onglet suivant et précédent dans l'ordre de la barre.

**Fini quand [À VOIR]** tu passes une journée entière sans ouvrir Arc.

---

## Phase 5 — Fiabilité du quotidien

- [x] **5.1 Téléchargements** (`Features/Downloads/`). Dans `decidePolicyFor navigationResponse`, renvoyer `.download` si `canShowMIMEType` est faux ou si la réponse est une pièce jointe ; gérer aussi `shouldPerformDownload` côté action. Implémenter les méthodes « didBecome download » et `WKDownloadDelegate` : destination dans Téléchargements, nom unique, progression via `download.progress`, liste en popover dans le pied de la barre, « Afficher dans le Finder ». Vérifier que les fichiers téléchargés portent l'attribut de quarantaine.
- [x] **5.2 Permissions par site.** `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)` : feuille « Autoriser une fois / Toujours / Refuser », décision mémorisée dans un `SitePermissionRecord`. Popover de réglages du site depuis le champ d'adresse : permissions, bloqueur actif ou non, effacer les cookies. Localisation et notifications : vérifier ce que l'API publique permet ; si rien, le noter dans `DECISIONS.md` et reporter.
- [x] **5.3 Recherche dans la page** (⌘F, ⌘G, ⌘⇧G). Barre en haut de la carte, `webView.find(_:configuration:)` avec `WKFindConfiguration`, message « Introuvable ». Agit sur `TabManager.frontTab`.
- [x] **5.4 Impression, PDF, zoom.** ⌘P via `webView.printOperation(with:)` ; export PDF via `createPDF` ; ⌘+, ⌘- et ⌘0 via `pageZoom`, mémorisé par domaine. Agit sur `TabManager.frontTab`.
- [x] **5.5 Historique** (`Features/History/`). `HistoryRecord` (URL, titre, date, Space) écrit à chaque fin de chargement, jamais en fenêtre privée. Vue ⌘Y avec recherche, suppression d'une entrée ou d'une période. Branché sur la barre de commande par `HistorySource` (prévu en 4.1). Les pages des mini-fenêtres passent par le même `NavigationCoordinator` (profil de la mini-fenêtre, sans Space) ; donner aussi la source à `MiniCommandBarModel(history:)`.
- [x] **5.6 Mémoire** (`Services/TabLifecycleService.swift`). Un onglet invisible depuis plus de 30 minutes (réglable) : capture (`takeSnapshot`), sauvegarde de l'`interactionState`, libération de la vue ; il reste affiché normalement dans la barre et se recrée au clic. En cas d'alerte mémoire (`DispatchSource.makeMemoryPressureSource`), décharger d'abord les plus anciens. Ne jamais décharger un onglet qui joue du son (`requestMediaPlaybackState`).
- [x] **5.7 Plantage d'une page.** `webViewWebContentProcessDidTerminate` : recharger si l'onglet est visible, sinon recharger à sa prochaine sélection. Une page d'aperçu plantée est visible : elle se recharge.
- [x] **5.8 Fenêtres de connexion.** Dans `createWebViewWith`, si `windowFeatures` donne une taille (fenêtre de connexion Google, Apple, banque), ouvrir une petite `NSWindow` dédiée au lieu d'un onglet ; `webViewDidClose` la ferme. Depuis un aperçu, la fenêtre de connexion s'ouvre sans faire de l'aperçu un onglet. Valable aussi dans une mini-fenêtre (`TabHost.openWindow` de `MiniWindowManager`).
- [x] **5.9 Menu contextuel des pages.** Sous-classe `BrowserWebView: WKWebView`, surcharge de `willOpenMenu(_:with:)` : « Ouvrir dans un nouvel onglet » à la place de « nouvelle fenêtre », ajout de « Ouvrir dans Peek » et « Copier le lien ». Les identifiants des éléments du menu ne sont pas documentés : code défensif, on garde le menu d'origine si un identifiant manque. « Ouvrir dans Peek » (libellé « Open in Peek », « Ouvrir dans un aperçu ») appelle `TabManager.openPeek(_:from:openingPoint:)`. Depuis un aperçu, « Ouvrir dans un nouvel onglet » crée un onglet en arrière-plan après l'onglet d'origine, sans faire de l'aperçu un onglet.
- [x] **5.10 Son.** Icône haut-parleur sur les onglets qui jouent du son ; clic = pause (`pauseAllMediaPlayback`).

**Fini quand [À VOIR]** une semaine complète sans revenir à Arc ni à Safari, sans plantage.

---

## Phase 6 — Bloqueur, extensions, mots de passe

- **6.1 Listes de blocage** : reportée, voir `FEATURES.md`.
- **6.2 Bloqueur natif** : reportée (code gardé, interface cachée), voir `FEATURES.md`.
- [x] **6.3 Infrastructure des extensions** (`Services/ExtensionManager.swift`). Un `WKWebExtensionController` unique, branché sur la configuration de toutes les vues (`webExtensionController`). Implémenter `WKWebExtensionControllerDelegate` : fenêtres ouvertes, fenêtre active, ouverture d'onglet et de fenêtre, popup d'action, demande de permissions. `BrowserTab` adopte `WKWebExtensionTab`, le modèle de fenêtre adopte `WKWebExtensionWindow` ; prévenir le contrôleur à chaque ouverture, activation, fermeture et changement d'onglet ou de fenêtre. Modèle de référence : le dépôt open source zer0.
- [x] **6.4 Installation.** Depuis une extension Safari d'une app installée (App Store, chargée sur place), ou un dossier décompressé, un `.crx` (Chrome), un `.xpi` (Firefox) ou un `.zip` choisi par l'utilisateur : retirer l'en-tête CRX, décompresser dans `Application Support/Extensions/<id>/`, charger le contexte. Écran des permissions demandées, décisions mémorisées. Réglages > Extensions.
- [x] **6.5 Boutons d'extensions.** Rangée d'icônes sous le champ d'adresse ; clic = popup de l'action dans un `NSPopover` ; badge de texte. Bouton masquable par extension (Réglages > Extensions, menu du bouton).
- [x] **6.6 [À VOIR] Tests réels.** Ton gestionnaire de mots de passe (Bitwarden ou 1Password), un bloqueur (uBlock Origin Lite), Dark Reader. Noter dans `DECISIONS.md` ce qui ne marche pas.

**Fini quand [À VOIR]** tes mots de passe se remplissent par l'extension et les pubs ne s'affichent plus.

---

## Phase 7 — Import et synchro

- [x] **7.1 Import depuis Arc** (`Services/ArcImporter.swift`). La sandbox empêche de lire le fichier directement : ouvrir un `NSOpenPanel` placé dans `~/Library/Application Support/Arc/` pour que je choisisse `StorableSidebar.json`. Le format n'est pas documenté : explorer d'abord le fichier que je fournis (version anonymisée pour les tests), puis écrire un analyseur tolérant. Correspondances : Spaces → Spaces (noms, couleurs si possible), épinglés → épinglés, dossiers → dossiers, favoris → favoris. Écran d'aperçu avant import. Tests sur l'exemple.
- [ ] **7.2 Import de favoris HTML** (format Netscape, exporté de Safari ou Chrome) vers des dossiers d'un Space choisi.
- **7.3 [MANUEL] iCloud** : reportée, voir `FEATURES.md`.
- [x] **7.4 Moteur de synchro** (`Services/Sync/`). Un seul moteur pour les trois modes (iCloud, serveur privé, serveur public) ; seul le transport change. La spécification est dans `SYNC.md`.
  - Synchronisés (`SYNC.md`, § 2) : profils, Spaces, dossiers, onglets (favoris et épinglés avec leur adresse d'origine, onglets du jour avec leur adresse courante, envois regroupés), extensions (liste, réglages, permissions, et paquet chiffré pour celles installées depuis un fichier ; une extension venue d'un autre Mac attend l'accord de l'utilisateur), réglages de l'app et décisions par site (permissions, zoom), et les Boosts s'ils voient le jour (`FEATURES.md`). Restent sur le Mac : historique, états de navigation, split views, données des sites et des extensions, téléchargements, ce qui dépend du Mac (fenêtres, raccourci global, langue).
  - Un seul magasin SwiftData, sans magasin synchronisé à part. Les changements locaux viennent d'une comparaison de l'état de ce Mac avec celui de sa dernière synchro, pour tous les types (`DECISIONS.md`, 2026-10-18 : à la place de l'historique de SwiftData).
  - Types purs : conversion entre enregistrement et contenu JSON versionné, identifiants tirés d'une clé (UUID v5 : réglages, zoom, décisions de site, extensions), horloge hybride, règle de conflit (la modification la plus récente gagne), application dans l'ordre profils → Spaces → dossiers → onglets → extensions → réglages → décisions de site, avec mise en attente des références manquantes. Changements locaux : comparaison avec le dernier état synchronisé.
  - Réglages > Extensions : section « Depuis vos autres Mac » (ajouter après l'écran des permissions, ou ignorer ; lien App Store pour une extension Safari dont l'app manque).
  - Protocole `SyncTransport` : envoyer un lot, lire les changements depuis un curseur, être prévenu des nouveaux changements. L'état (curseur, changements en attente) est conservé d'un lancement à l'autre.
  - Tests avec un transport en mémoire et deux appareils simulés : création, modification, suppression, conflit, référence manquante, première synchro (fusion, remplacement, Mac qui n'a que les données du premier lancement).
- [x] **7.5 Chiffrement** (`Services/Sync/SyncCrypto.swift`), pour les serveurs. Un mot de passe maître donne la clé maître (PBKDF2-SHA256, 600 000 itérations). Une clé de compte aléatoire, enveloppée par la clé maître et par une clé de secours, chiffre chaque enregistrement en AES-256-GCM, lié à son identifiant. Détails au § 3 de `SYNC.md`. CryptoKit et CommonCrypto, sans dépendance. Le mot de passe maître n'est jamais enregistré ; la clé de compte reste dans le trousseau de ce Mac. Kit de secours (adresse du serveur, identifiant, clé de secours) à enregistrer en PDF ou à imprimer : son écran vient avec la création du compte (7.9). Tests avec des vecteurs fixes ; tout contenu modifié ou déplacé doit être refusé.
- **7.6 Transport iCloud** : reportée, voir `FEATURES.md`.
- [ ] **7.7 Transport serveur** (`Services/Sync/ServerTransport.swift`). Client de l'API v1 de `SYNC.md` avec `URLSession` : préconnexion, connexion, renouvellement des jetons, envoi et lecture des changements, paquets d'extension (§ 4.7). Flux d'événements (`text/event-stream`), avec repli sur une lecture toutes les 15 minutes. Respect de `Retry-After`. HTTPS obligatoire, sauf pour `localhost`. Tests contre un faux serveur (`URLProtocol`).
- [ ] **7.8 Serveur de référence** (dépôt séparé `github.com/matchabrowser/syncserver`, en Go, routes sous `/api/v1`). Implémente l'API v1 de `SYNC.md` : comptes, appareils, jetons, enregistrements chiffrés, paquets d'extension, flux d'événements, invitations. SQLite, image Docker, une commande d'administration (créer une invitation, lister et supprimer des comptes). Il ne voit jamais de donnée en clair. Tests de conformité de l'API, réutilisables pour le serveur public. L'hébergement reste à choisir avec moi.
- [ ] **7.9 Réglages « Synchronisation ».** Choix : Désactivée, Serveur privé, Serveur public (grisé, « Bientôt disponible ») ; iCloud viendra avec sa reprise (`FEATURES.md`).
  - Serveur privé : adresse vérifiée par `GET /v1/server` ; créer un compte ou se connecter ; mot de passe maître saisi deux fois, avec jauge de solidité et l'avertissement « Matcha ne peut pas le récupérer » ; kit de secours à enregistrer avant de continuer ; liste des appareils (révoquer) ; changer le mot de passe maître ; mot de passe oublié (clé de secours) ; se déconnecter ; supprimer le compte.
  - État affiché (« Synchronisé il y a 2 min », erreurs compréhensibles) et bouton « Synchroniser maintenant ».
  - Premier envoi vers un mode qui contient déjà des données : Fusionner (par défaut), Remplacer les données de ce Mac, Remplacer les données synchronisées.

**2026-10-18 :** l'utilisateur fera le serveur de synchro plus tard (7.7 à 7.9) ; la phase 8 commence avant la fin de la phase 7 (7.2 aussi reste à faire).

Le serveur public (même API, hébergé par nous) n'a pas encore de tâche. Il attend les décisions sur l'hébergement, les quotas et les conditions d'utilisation (`SYNC.md`, § 7).

**Fini quand [À VOIR]** un second Mac retrouve tes Spaces, dossiers, favoris, épinglés, onglets du jour, extensions (après ton accord) et réglages par ton serveur privé, et la base du serveur ne contient aucune donnée lisible.

---

## Phase 8 — Navigateur par défaut et distribution

- [ ] **8.1 [MANUEL] Déclarer l'app comme navigateur.** Onglet Info : types d'URL `http` et `https`, types de documents HTML (`public.html`).
- [ ] **8.2 Liens entrants.** `application(_:open:)` ou `.onOpenURL` : ouvrir dans la mini-fenêtre par défaut ; réglage pour les ouvrir plutôt dans le Space courant. Point d'entrée prêt : `MiniWindowManager.openNew(loading:source: .link)`.
- [ ] **8.3 Bouton « Définir par défaut »** dans les réglages : `NSWorkspace.shared.setDefaultApplication(at:toOpenURLsWithScheme:)` pour `http` et `https` (macOS demande confirmation).
- [ ] **8.4 Mises à jour Sparkle.** Ajouter le paquet, `SPUStandardUpdaterController`, menu « Rechercher des mises à jour… », clés `SUFeedURL` et `SUPublicEDKey`. Suivre la documentation de Sparkle pour une app sandboxée (services d'installation).
- [ ] **8.5 Script de publication** (`scripts/release.sh`). Numéro de version, `xcodebuild archive`, `xcodebuild -exportArchive` (méthode Developer ID), `xcrun notarytool submit --wait`, `xcrun stapler staple`, image disque avec `create-dmg`, signature Sparkle (`sign_update`), mise à jour de `appcast.xml`. **[MANUEL]** Créer une fois le profil d'identifiants de notarisation (`xcrun notarytool store-credentials`).
- [ ] **8.6 [MANUEL] Passkeys.** Demander à Apple le droit `com.apple.developer.web-browser.public-key-credential` via son formulaire dédié ; une fois accordé, l'ajouter aux entitlements et au profil.

**Fini quand [À VOIR]** un lien cliqué dans Mail ouvre l'app et une mise à jour Sparkle s'installe.

---

## Contrôle de fin de phase

À refaire à la fin de chaque phase, résultats notés dans `DECISIONS.md` :

| Type de site | Exemples | À vérifier |
| --- | --- | --- |
| Comptes | Google, compte Apple, ta banque | Connexion, cookies séparés par profil |
| Visio | Google Meet, Zoom en ligne | Caméra, micro, partage d'écran |
| Vidéo | YouTube, Netflix | Plein écran, contenus protégés |
| Apps web lourdes | Figma, Google Docs, Notion | Fluidité, raccourcis, copier-coller |
| Messagerie | WhatsApp Web, Slack | Fonctionnement général |
| Actualité | Ton journal habituel | Bloqueur, mise en page |
| Fichiers | Un PDF, un téléchargement | Téléchargement, lecture, impression |

Mesure mémoire : les mêmes 20 onglets dans l'app, Safari et Arc, comparés dans le Moniteur d'activité.
