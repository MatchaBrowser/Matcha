# Audit de Matcha : sécurité, architecture, conformité Apple

Date : 2026-10-19, sur le commit `a94cf2e`. Audit en lecture seule : 9 analyses, puis revérification des points graves dans le code, les en-têtes du SDK et par un test temporaire (retiré).

**Gravité** :
- **Critique** : exploitable, plantage ou perte de données aujourd'hui.
- **Élevé**, **Moyen**, **Faible**.

**État** :
- **actif** : touche l'app actuelle.
- **latent** : code pas encore branché (synchro).
- **vérifié** : revérifié moi-même. Les autres constats viennent des analyses, avec leurs références dans le code.

## Verdict

- **La base est saine** :
  - bac à sable et runtime renforcé, sans exception ;
  - concurrence stricte propre ;
  - logique pure bien testée (~1 300 tests) ;
  - chiffrement conforme à `SYNC.md` ;
  - fenêtres privées bien isolées ;
  - téléchargements mis en quarantaine.
- **Ce qui ne va pas aujourd'hui** :
  - 3 failles web actives : `matcha-source:`, apps lancées sans accord, pop-ups sans clic ;
  - 5 manques WebKit qui cassent des sites courants : dialogues JavaScript, envoi de fichiers, sites protégés par mot de passe, sites `http://`, erreurs de chargement invisibles ;
  - 1 plantage atteignable depuis l'interface ;
  - identité des extensions usurpable.
- **Synchro** : la conception a des défauts à corriger dans `SYNC.md` avant la 7.7. Un serveur peut tout effacer, les mises à jour d'extensions sont silencieuses, et les identifiants révèlent les sites.
- **App Store** : Matcha n'est pas soumissible en l'état (Sparkle, API privée, catégorie, manifeste de confidentialité). Tout se règle avec une cible App Store séparée.

---

## 1. Sécurité du contenu web

**✅ W1. Toute page peut utiliser `matcha-source:`** (Critique, actif, vérifié) — corrigé : seulement les afficheurs ouverts par l'app, en cadre principal, par profil ; fichiers ordinaires, 32 Mo au plus, hors du fil principal (la relecture du site reste : l'archive web donne le DOM modifié, pas le code reçu).
- **Problème** : le gestionnaire est enregistré sur toutes les pages et sert n'importe quelle requête. Cela inclut celles d'une page web : `<img src="matcha-source:https://banque/…">`, une iframe, `location=` ou `window.open`.
  - Il refait la requête hors de WebKit avec **tous les cookies du profil**. Les cookies `SameSite=Strict` passent, et la protection contre le pistage est contournée.
  - Il lit les fichiers `file:` sur le fil principal, sans limite. `matcha-source:file:///dev/zero` gèle l'app.
  - Les réponses sont gardées en mémoire, quelle que soit leur taille.
- **Où** : `PageSourceSchemeHandler.swift`, `PageSource.swift:9`, `WebConfigurationFactory.swift:29`, `NavigationCoordinator.handles`.
- **Correction** :
  - Ne plus refaire la requête : lire le code reçu dans `createWebArchiveData()` de la page affichée. Ce sont les octets exacts, sans réseau, et sans rejouer un lien à usage unique.
  - N'accepter que les adresses d'afficheur émises par l'app (jeton par onglet), et seulement en cadre principal.
  - Dans `decidePolicyFor`, annuler toute navigation vers ce schéma lancée par une page.
  - Retirer `file:`.

**✅ W2. Une page lance d'autres apps sans clic ni accord** (Élevé, actif, vérifié) — corrigé : bandeau Annuler / Ouvrir / Toujours ouvrir pour tout lien vers une app, `mailto:` compris ; « Toujours » retenu par site et listé dans les Réglages.
- **Problème** : toute navigation du cadre principal vers un schéma inconnu lance l'app associée. Exemples : `zoommtg:`, `smb:` (montage dans le Finder), `vnc:`, `ssh:`, `x-apple.systempreferences:`.
  - Cela vaut aussi pour une redirection JavaScript, un meta refresh ou une réponse 302.
  - Un `window.open` lancé depuis une iframe publicitaire compte comme « cadre principal » (`targetFrame?.isMainFrame ?? true`).
  - Safari, Chrome et Firefox demandent avant. C'est aussi contraire à « rien ne s'ouvre seul ».
- **Où** : `NavigationPolicy.swift:67-70` et `NavigationCoordinator.swift:34, 55-62`. L'entrée de `DECISIONS.md` du 2026-10-16 (« sans confirmation ») est à réviser.
- **Correction** :
  - Un panneau « Autoriser ‹site› à ouvrir ‹App› ? », avec le nom de l'app via `NSWorkspace.urlForApplication(toOpen:)`. Le choix se mémorise par site et par schéma, comme les autorisations.
  - Cadre d'origine lu dans `sourceFrame`.
  - Fermer l'onglet vide créé pour l'occasion.
  - Refus d'office pour `smb`, `afp`, `nfs`, `vnc`, `ssh`, `telnet` et `ftp`.

**✅ W3. Aucun blocage des pop-ups** (Élevé, actif, vérifié) — corrigé : `javaScriptCanOpenWindowsAutomatically = false` ; reste à faire : indicateur « Pop-up bloquée ».
- **Problème** : `javaScriptCanOpenWindowsAutomatically` vaut YES par défaut sur macOS (en-tête `WKPreferences.h`), et Matcha ne le change pas.
  - Une page ouvre autant d'onglets et de fenêtres qu'elle veut, sans clic.
  - Une fenêtre de connexion ouverte par un onglet en arrière-plan prend le focus clavier : la frappe d'un mot de passe peut atterrir dedans.
  - W1 et W2 deviennent ainsi possibles sans aucun clic.
- **Correction** :
  - Mettre la propriété à `false`. WebKit laisse passer les ouvertures qui suivent un clic, donc les vraies fenêtres de connexion fonctionnent toujours.
  - Ne pas donner le focus à une fenêtre de connexion si la fenêtre d'origine ne l'a pas.
  - Afficher un indicateur « Pop-up bloquée ».

**✅ W4. L'adresse affichée est celle en cours de chargement** (Moyen, actif, confirmé par un test) — corrigé : `displayedURL` (document affiché, ou chargement demandé par l'utilisateur).
- **Problème** : `tab.url` recopie `webView.url`, qui prend l'adresse demandée avant que la page ne change.
  - Une page lance `location = "https://accounts.google.com:81/"`, un port qui ne répond pas (~75 s d'attente).
  - Sa fausse page reste affichée sous l'adresse de Google. Dans une fenêtre de connexion, elle a même le cadenas.
- **Correction** :
  - Ajouter une `committedURL`, mise à jour dans `didCommit` et lors des changements dans le même document, puis rétablie après un échec.
  - Afficher l'adresse en attente seulement pour les chargements lancés par l'utilisateur.

**✅ W5. Pas d'indicateur HTTP/HTTPS** (Moyen, actif) — corrigé : cadenas qui ouvre le certificat, « Non sécurisé » pour `http`, passage automatique en `https`.
- **Problème** : la pastille montre l'hôte seul, donc `http://banque.fr` et `https://banque.fr` sont identiques. Le cadenas des fenêtres de connexion ne regarde que le schéma.
- **Correction** :
  - Afficher « Non sécurisé » pour `http`, et pour `https` quand `hasOnlySecureContent` est faux.
  - Au clic, montrer le certificat (`SFCertificateTrustPanel`, API publique).
  - Passer automatiquement en HTTPS avec `defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP`. Cette API existe depuis macOS 15.2 (vérifié dans le SDK). L'entrée de `DECISIONS.md` du 2026-10-16 « WebKit n'a pas de repli automatique vers HTTP » est donc périmée.

**✅ W6. Liens vers `file:` ouverts avec accès au dossier entier** (Faible, actif) — corrigé : l'app n'ouvre elle-même que les liens `http(s)` ou du même schéma que la page ; un fichier ouvert par un lien ne lit pas plus que le dossier de la page qui le lie (`FileReadAccess`).
- **Problème** : ⌘-clic, clic milieu et Maj-clic (Peek) font charger le lien par l'app (`BrowserTab.load`).
  - Cela contourne l'interdiction de WebKit d'aller d'une page web vers un `file:`.
  - La page obtient la lecture de **tout le dossier parent** (`allowingReadAccessTo: url.deletingLastPathComponent()`).
  - Combiné à W7 : une page fait télécharger un `.html`, puis le fait ouvrir avec la lecture de tout `~/Downloads`.
- **Correction** :
  - Nouvel onglet et Peek seulement pour `http(s)`. Un `file:` seulement depuis une page `file:`.
  - Lecture limitée au fichier lui-même, sauf s'il a été ouvert explicitement par l'utilisateur.

**✅ W7. Téléchargements sans clic** (Faible à Moyen, actif) — corrigé : bandeau à partir du 2e téléchargement sans clic ou pour un cadre intégré ; liste limitée à 200.
- **Problème** : un lien `download` cliqué par script, ou une réponse « pièce jointe » d'une iframe tierce, lance un téléchargement. Il n'y a aucune limite, aucun geste requis et aucun accord. La quarantaine fonctionne et rien ne s'ouvre seul.
- **Correction** :
  - Demander via le bandeau d'autorisation (comme Safari) à partir du 2e téléchargement automatique d'une page, ou pour une iframe d'un autre site.
  - Limiter le nombre de téléchargements en parallèle.
  - Purger la liste en mémoire au-delà de ~200 éléments.

**✅ W8. Favicons** (Faible, actif) — corrigé : sans cookies, 1 Mo et 15 s au plus, `https` seulement pour une page `https`, formats matriciels décodés hors du fil principal, cache disque lu en asynchrone.
- **Problème** :
  - Le corps est téléchargé en entier avant le contrôle de 1 Mo, et il n'y a pas de délai total.
  - Le décodage `NSImage(data:)` accepte PDF et SVG, dans le processus de l'app.
  - Les cookies sont gardés et partagés entre profils pendant la session.
  - Des icônes `http` sont chargées pour des pages `https`.
  - La lecture disque et l'analyse de teinte tournent sur le fil principal.
- **Correction** :
  - Lecture en flux avec un plafond, et `timeoutIntervalForResource` à ~15 s.
  - Pas de cookies.
  - Décodage avec `CGImageSource`, limité à PNG, ICO, JPEG, GIF et WebP, hors du fil principal.

**✅ W9. Bandeau d'autorisation cliquable trop tôt** (Faible) — corrigé : clics ignorés 0,5 s.
- **Problème** : « Toujours autoriser » est cliquable dès que le bandeau apparaît sous le pointeur.
- **Correction** : ignorer les clics pendant ~0,5 s.

**✅ W10. Journaux trop bavards** (Faible, actif) — corrigé : erreurs par domaine et code (`logSummary`), hôtes des téléchargements et identifiants d'extensions en privé.
- **Problème** :
  - Les hôtes des téléchargements sont en `.public`, fenêtres privées comprises.
  - `error.localizedDescription` est en `.public` et peut contenir un chemin, donc le nom d'utilisateur : `DownloadManager`, `PageSaver`, `PageSourceSchemeHandler`, `ArcImportModel:64`.
- **Correction** : hôtes en `.private` ; domaine et code d'erreur en public, description en `.private`.

**✅ W11. Fenêtres privées rouvertes au lancement** (Faible, actif, vérifié) — corrigé : `restorationBehavior(.disabled)`.
- **Problème** : le `WindowGroup` privé n'a pas `.restorationBehavior(.disabled)`. Des fenêtres privées vides réapparaissent au lancement, sans contenu sensible.

## 2. Fonctions WebKit manquantes (sites courants cassés)

Toutes sont vérifiées. Les en-têtes du SDK disent ce que fait WebKit quand la méthode manque.

**✅ K1. Dialogues JavaScript** (Élevé) — corrigé : feuilles système titrées du site, arrêt possible dès le 2e dialogue.
- **Problème** : `runJavaScriptAlert`, `Confirm` et `TextInputPanel` ne sont pas implémentés.
  - `alert()` n'affiche rien.
  - `confirm()` répond **toujours non** : « Supprimer ce message ? » ne fait plus rien.
  - `prompt()` renvoie `null`.
- **Correction** :
  - Des feuilles `NSAlert` attachées à l'onglet, qui affichent l'origine du cadre (`securityOrigin`).
  - Une file d'attente par onglet, vidée à la navigation, avec une limite de fréquence.

**✅ K2. Envoi de fichiers** (Élevé) — corrigé : panneau d'ouverture du système.
- **Problème** : sans `runOpenPanelWith`, WebKit fait « Annuler » sur macOS. Tout `<input type=file>` est donc inerte : pièces jointes, photo de profil, formulaires.
- **Correction** : un `NSOpenPanel` en feuille, avec sélection multiple et dossiers. Les droits du bac à sable sont déjà là.

**✅ K3. Sites protégés par mot de passe** (Élevé) — corrigé : feuille d'identification, identifiants pour la session.
- **Problème** : sans `webView(_:respondTo:)`, WebKit refuse la demande d'identification. Box, intranets, préproduction (Basic, Digest, NTLM) et certificats client sont inaccessibles.
- **Correction** :
  - Une feuille identifiant et mot de passe, qui montre l'hôte et le realm.
  - `.performDefaultHandling` pour la confiance serveur.

**✅ K4. Sites en `http://` bloqués** (Élevé, vérifié par un test) — corrigé : `Config/Info.plist` avec `NSAllowsArbitraryLoadsInWebContent`, branché sur la cible Matcha.
- **Problème** : sans `NSAppTransportSecurity`, App Transport Security s'applique aux `WKWebView`. `http://neverssl.com` échoue avec l'erreur `NSURLErrorDomain -1022`. Seuls les adresses IP, `.local` et localhost passent.
- **Correction** : `NSAllowsArbitraryLoadsInWebContent = YES` dans un vrai Info.plist (voir A5). Les requêtes `URLSession` (synchro, suggestions) restent sous ATS.

**✅ K5. Échec de chargement invisible** (Élevé) — corrigé : page d'erreur avec « Réessayer » ; certificat : « Afficher le certificat » et bouton rouge « Ouvrir ce site quand même » (exception de session).
- **Problème** : hors ligne, sur une erreur DNS, un délai dépassé ou un certificat invalide, rien ne s'affiche. Seul le plantage d'un processus a sa page (`PageProblemView`). Avec K4, un site `http` donne une page blanche.
- **Correction** : une page d'erreur traduite avec « Réessayer ». Les certificats ont leur propre cas, avec « Afficher le certificat ».

## 3. Robustesse et données

**✅ R1. Plantage quand il ne reste aucun Space** (Critique, actif, vérifié) — corrigé : un Space par défaut est recréé pour le profil restant (test qui reproduisait le plantage).
- **Scénario** :
  1. Le profil B a un Space.
  2. On supprime ce Space : c'est permis, car il en reste un, celui du profil A.
  3. On supprime le profil A : c'est permis, car il reste 2 profils.
  4. `removeProfile` supprime alors le dernier Space, puis `session.spaces[0]` plante (`WindowModel.swift:46`, `MiniWindowManager+HandOff.swift:14`).
- Le même chemin est atteignable par la synchro (`SyncRecordWriter+Delete`).
- **Correction** :
  - Créer un Space pour le profil restant quand c'est le dernier, ou refuser la suppression.
  - Plus aucun accès à l'indice 0.
  - Ajouter un test.

**✅ R2. Base illisible = mode test silencieux** (Élevé, actif, vérifié) — corrigé : alerte (Quitter, Repartir de zéro avec la base mise de côté, Continuer sans enregistrer).
- **Problème** : si la base SwiftData ne s'ouvre pas, `BrowserSession.launch` repasse en mémoire sans prévenir.
  - Plus rien n'est enregistré.
  - `isInMemory` sert aussi de « mode test » : les cookies ne sont plus gardés, les extensions ne démarrent pas, les téléchargements ne sont pas restaurés.
  - Le `try!` du repli peut planter.
- **Correction** :
  - Une alerte : réessayer ou quitter.
  - Une copie de sauvegarde de la base avant tout repli.
  - Séparer « base en mémoire » et « mode test ».

**✅ R3. Lecture de la base en échec traitée comme « vide »** (Moyen, actif) — corrigé au lancement : l'erreur remonte à l'alerte de R2 (la synchro reste en S6).
- **Problème** : `try? fetch` apparaît à 13 endroits. Au lancement, une erreur de lecture crée un 2e profil « Personnel » et un 2e Space « Perso » (`BrowserSession.swift:78-81, 228-235`). Pour la synchro, voir S6.
- **Correction** : propager l'erreur ; ne créer les valeurs par défaut qu'après une lecture réussie et vide.

**✅ R4. Décodage `Codable` fragile** (Moyen, actif) — corrigé : `ExtensionState` tolérant, lecture entrée par entrée (`Lenient`), valeur illisible mise de côté ; `SyncState` et `SyncedExtensions` avec S6.
- **Problème** : `ExtensionState`, `SavedDownload`, `CompiledBlocklist`, `SyncState` et `SyncedExtensions` utilisent le `Codable` synthétisé.
  - Il ignore les valeurs par défaut : ajouter un champ rend les anciennes données illisibles.
  - Pour `ExtensionState`, une seule erreur efface toutes les décisions et réactive les extensions désactivées (`isEnabled ?? true`).
- **Correction** :
  - `init(from:)` avec `decodeIfPresent ?? défaut`, et décodage entrée par entrée.
  - Sauvegarder à part ce qui est illisible.
  - Tester le décodage d'un ancien format.
  - Une extension sans état reste désactivée.

**✅ R5. Session privée recréée** (Moyen, vérifié) — corrigé : porteurs paresseux (`WindowModels`, `PrivateSessionHolder`), observateur retiré à la libération.
- **Problème** : `@State private var session = BrowserSession.makePrivate()` est réévalué à chaque recréation de la vue. Cela recrée un conteneur SwiftData, un gestionnaire de fenêtres et un observateur jamais retiré. Même chose pour `WindowModel` et `CommandBarModel` dans `BrowserWindowView.init`.
- **Correction** : créer ces objets une seule fois, dans un porteur lié à la scène ou dans `.task`.

**✅ R6. Crochets de test actifs en Release** (Faible) — corrigé : arguments lus en Debug seulement, base par défaut jamais effacée, `TestEnvironment` unique.
- **Problème** :
  - `storeName`, `resetStore`, `inMemoryStore` et `downloadsSubfolder` sont lus en Release.
  - `storeName=default` avec `resetStore` effacerait la vraie base, puisque `default` est le nom par défaut de SwiftData.
  - La détection de XCTest est éparpillée.
- **Correction** : `#if DEBUG`, refuser `default`, et un seul `TestEnvironment` injecté.

**✅ R7. Confirmation à la fermeture** (Faible) — corrigé : désactivée par défaut, message juste, jamais pendant une déconnexion, un redémarrage ou un arrêt.
- **Problème** :
  - Elle est activée par défaut et dit que les onglets seront fermés, alors qu'ils sont restaurés.
  - `runModal` dans `applicationShouldTerminate` bloque la déconnexion et le redémarrage.
- **Correction** : la désactiver par défaut ou la reformuler, et ne jamais l'afficher lors d'une déconnexion.

**✅ R8. Enregistrement** (Faible) — corrigé : seules les valeurs changées sont écrites ; schéma versionné et index reportés (raisons dans `DECISIONS.md`).
- `SpaceStore.save` réécrit tous les champs de tous les onglets, `interactionState` compris, une seconde après chaque changement.
- Il n'y a pas de `VersionedSchema` : à ajouter avant le premier renommage de champ.
- Il n'y a pas d'index sur `HistoryRecord`.

## 4. Extensions

**E1. L'identité d'une extension, c'est son nom** (Élevé, actif, vérifié)
- **Problème** : l'identifiant est le nom du manifeste mis en minuscules. Il sert de dossier, de clé du stockage WebKit, de `runtime.id` et d'adresse (`webkit-extension://dark-reader/`).
  - Un faux `.crx` nommé « Bitwarden » est présenté comme une simple « mise à jour ». Il hérite des données de la vraie extension (coffre local), de ses sites autorisés et de son identifiant.
  - Deux extensions de même nom s'écrasent.
  - Un paquet nommé « Safari com.x.y » prend le préfixe réservé `safari-`.
  - Les adresses étant prévisibles, un site peut lister les extensions installées et les encadrer (clickjacking).
- **Correction** :
  - Un identifiant aléatoire et permanent pour chaque nouvelle installation. Les extensions déjà installées gardent le leur.
  - Une mise à jour seulement si l'éditeur est le même (clé CRX3, `manifest.key` ou identifiant gecko). Sinon : « Remplace X (version, origine) : ses données seront effacées ».
  - Interdire `safari-` aux paquets.
  - Montrer l'ancienne version et la différence de droits.

**E2. Une mise à jour annule les refus** (Moyen)
- **Problème** : tous les droits demandés sont réaccordés et les refus effacés. Un utilisateur qui avait limité `<all_urls>` à quelques sites retrouve l'accès à tout.
- **Correction** : n'accorder que les nouveaux droits, après accord, et garder les refus.

**E3. Installation d'un dossier avec liens symboliques** (Moyen, selon WebKit)
- **Problème** : `copyItem` garde les liens. Un dossier peut pointer vers la base SwiftData ou les données WebKit du conteneur, et l'extension pourrait les lire si WebKit suit les liens.
- **Correction** : copier fichier par fichier, refuser liens et alias, avec un plafond de taille.

**✅ E4. Adresses demandées par une extension non filtrées** (Moyen, selon WebKit) — corrigé : `http(s)`, `about:blank` et ses propres pages seulement (`ExtensionURLPolicy`).
- **Problème** : `tabs.create`, `tabs.update` et `windows.create` arrivent jusqu'à `BrowserTab.load`. Une extension sans aucun droit peut donc ouvrir un `file:`, avec accès au dossier parent.
- **Correction** : accepter seulement `http`, `https`, `about:blank` et les pages de l'extension.

**✅ E5. Demandes d'autorisation répétables à l'infini** (Faible) — corrigé : refus retenu 24 h, une demande à la fois par extension, menu « Accès aux sites » dans les Réglages.
- **Problème** :
  - Aucun refus n'est mémorisé.
  - On ne peut pas retirer un site accordé sans supprimer l'extension.
  - Une 2e demande pendant qu'une feuille est ouverte est refusée sans rien dire.
- **Correction** :
  - Mémoriser un refus pour un temps, avec une limite et une file d'attente.
  - Gérer les sites un par un dans les Réglages.

**E6. Installation non atomique, sur le fil principal** (Moyen)
- **Problème** :
  - L'ancien dossier est supprimé avant le déplacement du nouveau.
  - L'état est enregistré avant le chargement.
  - Décompression (jusqu'à 512 Mo), CRC et copie tournent sur le fil principal.
- **Correction** :
  - Valider d'abord, puis échanger avec `replaceItemAt`.
  - Enregistrer l'état après un chargement réussi.
  - Faire les étapes pures en `@concurrent`, sur le modèle de `BlocklistBundle`.

**E7. Divers** (Faible)
- La désinstallation laisse les données d'origine `webkit-extension://`.
- L'équipe d'une extension Safari n'est pas validée (`SecStaticCodeCheckValidity`).
- `~/Applications` est illisible dans le bac à sable, donc sa recherche ne sert à rien.
- Les extensions sont partagées entre profils.
- Le résumé des droits n'a ni `file:` (il affiche une ligne vide) ni `webRequest`.
- L'import Arc n'a pas de limite de profondeur (un fichier forgé fait déborder la pile) et lit le fichier sur le fil principal.
- `ZipWriter` plante au-delà de 65 535 fichiers.
- `ZipArchive.inflate` utilise `baseAddress!`.

## 5. Synchronisation (latent : à corriger avant la 7.7)

Rien n'est branché : il n'y a pas de transport, et seuls les tests créent `SyncEngine`. Les cinq premiers points demandent de **modifier `SYNC.md`**.

**S1. Mises à jour d'extensions silencieuses** (Élevé, contredit `SYNC.md` § 2.5)
- **Problème** :
  - `installUpdates` installe sans accord tout paquet reçu qui ne demande pas plus de droits.
  - `applySettings` applique les droits, les sites et l'accès aux fenêtres privées reçus.
  - Un Mac compromis peut donc remplacer le code d'uBlock sur tous les Mac, en gardant ses droits et ses données.
- **Correction** :
  - Jamais de code installé sans un clic local. Sinon, exiger le même éditeur et une version strictement supérieure.
  - Les droits reçus peuvent seulement réduire ceux de ce Mac.
  - La synchro n'active jamais l'accès aux fenêtres privées.

**S2. Effacement par absence** (Élevé, prévu par `SYNC.md` § 5)
- **Problème** : sur `410 cursor_expired`, tout ce qui manque dans la relecture est supprimé localement. Un serveur, même sans les clés, peut ainsi effacer sur tous les Mac :
  - les profils et leurs données de sites ;
  - les extensions et leur stockage ;
  - les autorisations et les réglages.
- **Correction** :
  - Supprimer seulement sur une suppression chiffrée et authentifiée.
  - Renvoyer ce qui manque au serveur.
  - Un seuil : au-delà de N suppressions, ou pour un profil ou une extension, s'arrêter et demander.

**S3. Les identifiants révèlent les sites** (Moyen, contredit `SYNC.md` § 3.9)
- **Problème** : les UUID v5 sont dérivés publiquement de `site-zoom:<site>`, `site-permission:<profil>|<origine>|<type>`, `extension:<nom>` et `setting:<clé>`. Le serveur peut retrouver les sites zoomés, ceux qui ont la caméra ou le micro, et les extensions.
- **Correction** :
  - Des identifiants calculés par HMAC avec une sous-clé du compte.
  - À la réception, vérifier que l'identifiant correspond aux champs.
  - À faire **avant** qu'un serveur ait des données.

**S4. Rejeu et retour en arrière** (Moyen)
- **Problème** : seule la `version` du serveur, non authentifiée, décide de ce qui est plus récent. Un serveur peut rejouer un ancien contenu authentique : une autorisation caméra révoquée, une extension vulnérable.
- **Correction** : refuser un contenu dont `(modifiedAt, modifiedBy)` n'est pas plus récent que le dernier accepté.

**S5. Contenus reçus appliqués sans contrôle** (Moyen)
- **Problème** :
  - Une autorisation caméra ou micro reçue est accordée sans bandeau.
  - Les adresses d'onglets reçues ne sont pas filtrées : `javascript:`, `file:` et `smb:` passent.
- **Correction** :
  - Appliquer d'office les refus et les retraits. Une autorisation reçue est confirmée une fois sur ce Mac.
  - Accepter seulement les adresses `http(s)`.

**S6. Bogues du moteur**
- **Un champ remis à vide n'est jamais transmis** (Élevé, vérifié)
  - **Problème** : le `Codable` synthétisé omet les optionnels nuls, et `keepingUnknownKeys` remet alors l'ancienne valeur distante. Un onglet sorti d'un dossier, un thème remis par défaut ou un dossier remis à la racine n'arrivent jamais sur les autres Mac, et l'ancienne valeur repart à chaque modification.
  - **Correction** : ne garder que les clés inconnues de cette version, avec une liste des clés connues par type, et un test.
- **Un réglage numérique énorme fait planter l'app en boucle** (Moyen, vérifié)
  - **Problème** : `Int(number)` sur `1e19` (`SyncFields+Settings.swift:71, 102`).
  - **Correction** : `Int(exactly:)`.
- **Un `try? fetch` en échec envoie la suppression de tout à tous les Mac**
  - **Problème** : l'instantané vide passe pour « tout a été supprimé » (`MatchaSyncStore.swift:180`).
  - **Correction** : `snapshot()` et `apply()` qui lèvent une erreur, plus un garde-fou contre les suppressions massives.
- **Un fichier d'état illisible change l'identité de l'appareil**
  - **Problème** : nouvel identifiant d'appareil, première synchro refaite, changements en attente perdus.
  - **Correction** : un décodage tolérant, le fichier mis de côté, l'identifiant d'appareil gardé dans le trousseau.
- **Coordinateur**
  - Une modification faite pendant un cycle attend le déclencheur suivant, jusqu'à 15 min.
  - `stop()` n'arrête pas les cycles.
  - Un cycle part à chaque visite enregistrée dans l'historique et à chaque écriture dans `UserDefaults`.
- **Enregistrements qui attendent leur parent**
  - Ils sont réappliqués à chaque page.
  - Une mise à jour en attente annule la modification distante.
  - Un contenu illisible peut être écrasé, ce qui contredit le § 3.5.
  - L'état grossit sans fin.
- **Clés et trousseau**
  - PBKDF2 n'a pas de plafond d'itérations, et le serveur choisit le sel.
  - Le trousseau avale ses erreurs : un trousseau verrouillé passe pour « déconnecté ».
  - Pas de liste d'accès sur les éléments du trousseau.
  - Pas de rotation de la clé du compte.
- **Données à nettoyer**
  - Les fichiers d'état sont en clair et ne sont pas supprimés à la déconnexion.
  - `user:password@` reste dans les adresses synchronisées.
  - Une date dans le futur fausse l'horloge hybride.

## 6. App Store et distribution

**A1. Bloquants pour le Mac App Store**
- **Problème** :
  - Sparkle : règle 2.4.5(vii), les mises à jour doivent venir de l'App Store seulement.
  - L'API privée `developerExtrasEnabled` : règle 2.5.1. La chaîne du sélecteur reste dans le binaire même quand l'option est désactivée.
  - `LSApplicationCategoryType` est absent : le dépôt est refusé (ITMS-90242).
- **Correction** :
  - Une cible « Matcha App Store » qui partage `Matcha/`, sans Sparkle, avec `APP_STORE` dans ses conditions de compilation.
  - `#if !APP_STORE` autour de l'API privée et du menu de mise à jour.
  - Une catégorie, par exemple Productivité.
  - C'est une étape [MANUEL] dans Xcode.

**A2. Extensions : rejet probable** (règles 2.4.5(iv) et 2.5.2)
- **Problème** : installer du code depuis des fichiers `.crx`, `.xpi` ou `.zip`, renvoyer vers les boutiques Mozilla et Chrome, et surtout les mises à jour silencieuses par la synchro.
- **Décision à prendre**, pour la version App Store :
  - **(A)** seulement les extensions Safari des apps installées ;
  - **(B)** installation depuis un fichier sur action explicite seulement, sans mise à jour silencieuse ni synchro des paquets, avec une explication dans les notes de revue.

**A3. Manifeste de confidentialité absent**
- Ajouter `PrivacyInfo.xcprivacy` : `UserDefaults` avec la raison CA92.1, pas de pistage, aucune donnée collectée.

**A4. Conformité à l'export**
- **Problème** : `ITSAppUsesNonExemptEncryption` est absent. La synchro chiffre (AES-GCM, PBKDF2) avec les frameworks d'Apple.
- **Décision à prendre** : la classification américaine (EAR 5D992) et une éventuelle déclaration à l'ANSSI pour un chiffrement de bout en bout. Cela concerne aussi la distribution Developer ID.

**A5. Info.plist (avec la 8.1)**
- **Problème** :
  - Matcha n'est pas déclaré comme navigateur : pas de types d'URL `http`/`https`, pas de type de document `public.html`. Les tâches 8.2 et 8.3 ne peuvent donc pas fonctionner.
  - L'Info.plist doit aussi recevoir la clé ATS (K4) et les clés Sparkle.
  - Des clés iOS restent dans l'Info.plist généré (`UISupportedInterfaceOrientations…`, `UIStatusBarStyle`…).
  - Les textes d'usage de la caméra et du micro sont trop vagues (règle 5.1.1(ii)).
- **Correction** :
  - Créer `Config/Info.plist`, hors du dossier synchronisé.
  - Régler `INFOPLIST_FILE` et garder `GENERATE_INFOPLIST_FILE`.
  - Supprimer les clés iOS.
  - Préciser les textes d'usage, par exemple : « Les sites que vous autorisez, comme les appels vidéo, peuvent utiliser la caméra. Matcha demande d'abord pour chaque site. »

**A6. Distribution Developer ID**
- **Droits** : `Config/Matcha.entitlements` n'est rattaché à aucune configuration (`CODE_SIGN_ENTITLEMENTS` absent). L'installeur de Sparkle ne pourra donc pas se connecter.
- **`release.sh`** :
  - Un essai à blanc laisse une branche `gh-pages` locale, qui fait échouer la vraie publication.
  - `create-dmg` reçoit l'app au lieu d'un dossier qui la contient (à vérifier).
  - `notarytool | tee | grep` peut échouer à tort, et le journal n'est pas récupéré en cas d'échec.
  - L'identité de signature est ambiguë.
  - Il manque les vérifications finales : `codesign --verify --strict`, `spctl` et `stapler validate`.
- **Contrôles manuels** : l'app qui héberge les tests reçoit la lecture de tout le disque. Ces contrôles doivent donc se faire sur l'app exportée par `release.sh --dry-run`.

**A7. Fiche App Store**
- Une URL de politique de confidentialité.
- Âge 17+ (accès web illimité).
- Pas de « Arc » dans le nom ni dans les mots-clés.
- La suppression de compte, avec la 7.9.
- `client=firefox` dans les suggestions Google est une zone grise.

## 7. Recommandations Apple (HIG, accessibilité, performance)

**H1. Raccourcis et menus**
- ⌘S masque la barre latérale. Le raccourci standard est ⌃⌘S, et ⌘S veut dire « Enregistrer ».
- ⌘O ouvre dans le Space, et il n'y a pas de Fichier > Ouvrir un fichier….
- `CommandGroup(replacing: .textEditing)` retire probablement Orthographe, Substitutions, Transformations et Parole du menu Édition (à vérifier dans l'app).
- Le menu Aide est vide.
- Il manque ⌘. (Arrêter), ⌥⌘R et ⌘E.

**H2. Annulation**
- Il n'y a ni annulation, ni « Rouvrir l'onglet fermé » (⇧⌘T).
- Supprimer un Space ou un dossier, et « Effacer » les onglets du jour, se font sans confirmation et sans annulation.

**H3. Accessibilité**
- « Réduire les animations » n'est respecté que par 3 vues.
- « Augmenter le contraste » n'est jamais lu.
- La barre latérale n'est pas navigable au clavier, et ses sections n'ont pas de titre pour VoiceOver.
- On ne peut réorganiser que par glisser.
- 33 tailles de police sont fixes.

**H4. Performance**
- Un changement de titre de page réévalue toute la fenêtre et reconstruit la barre de menus : `windowActions` est une structure de closures publiée par `focusedSceneValue`, et `.navigationTitle` est lu dans `body`.
- Les instantanés JPEG sont encodés sur le fil principal.

**H5. Divers**
- ⌥⌘N est réservé pour toutes les apps dès le premier lancement.
- L'agent utilisateur est figé sur « Safari 26.6 ».
- La lecture automatique avec son est autorisée.
- Les boutons de la fenêtre sont masqués avec la barre latérale.
- La fenêtre n'a pas de taille par défaut.

## 8. Architecture et code Swift

**Ce qui est bien** :
- aucun `nonisolated(unsafe)` ni `@unchecked Sendable` ;
- `assumeIsolated` employé correctement ;
- `@Observable` partout ;
- des types purs et testables ;
- un `Logger` par module ;
- les règles SwiftData pour CloudKit respectées et testées.

**C1. Couches**
- **Problème** :
  - `Services/` dépend de `Features/` : `ExtensionOwners` utilise `WindowModel` et `MiniWindowManager`, `ExtensionTab` utilise `PeekActions`.
  - De l'interface vit dans `Services/Extensions` : `NSAlert`, `NSPopover`, registre de vues.
  - `Browser/` dépend de `Features/Downloads`.
  - La liste des dossiers de `CLAUDE.md` est périmée.
- **Correction** : déplacer l'interface dans `Features/Extensions`, et injecter un protocole `ExtensionHost`.

**C2. Singletons**
- **Problème** : 9 `static let shared`, et `WebConfigurationFactory` est statique : il attache `ExtensionManager.shared` à toutes les pages.
- **Correction** : une racine de composition dans `MatchaApp.init`, avec injection par `.environment` et par les initialiseurs.

**C3. Types trop gros**
- **Problème** :
  - `TabManager` fait 872 lignes sur 9 fichiers.
  - `ExtensionManager` fait 722 lignes sur 6 fichiers et a une dizaine de rôles.
  - `BrowserWindowView` joue le rôle de contrôleur.
- **Correction** : découper `ExtensionManager` en `ExtensionRegistry`, un délégué et un `ExtensionToolbarModel`.

**C4. Fil principal**
- **Problème** : lecture des favicons, installation d'extensions, chiffrement des paquets, encodage JSON de la synchro et instantanés JPEG tournent sur le fil principal.
- **Correction** : `@concurrent`, comme le projet le fait déjà ailleurs.

**C5. Code dormant qui travaille**
- **Problème** :
  - Le bloqueur (6.2 : ~1 050 lignes, plus 860 lignes de tests) tourne à chaque navigation pour rien, et ses tests compilent de vraies listes WebKit.
  - `ExtensionWindows` calcule des différences même sans extension.
- **Correction** : `contentBlocking` à `nil` quand le bloqueur n'est pas disponible, et ne suivre les fenêtres que si une extension écoute.

**C6. Doublons**
- `MiniCommandBarModel` et `CommandBarModel`.
- Les conversions entre modèle et champs de synchro, écrites dans les deux sens.

**C7. Petits points**
- Les observateurs de `NotificationCenter` ne sont jamais retirés.
- Des compteurs de révision sont tenus à la main, et `installedIdentifiers` lit le disque, même depuis des `body`.
- 7 fichiers contiennent plusieurs types principaux.
- Des commentaires sont périmés.
- Les journaux sont en français.
- Il n'y a pas de CI, et SwiftLint est minimal.

## 9. Tests

**Ce qui est bien** :
- ~1 300 tests ;
- horloges et attentes injectées ;
- SwiftData en mémoire ;
- chiffrement testé contre des valeurs publiées ;
- serveur de synchro en mémoire réaliste ;
- migrations testées.

**T1. Accès réseau et cache réel** : les tests unitaires touchent le vrai réseau et le vrai cache de favicons de l'app. `FaviconService.shared` est la valeur par défaut, et l'hôte des tests est Matcha.app, avec le même conteneur.
- **Correction** : des fabriques de test, et un `URLProtocol` qui refuse tout accès réseau.

**T2. Synchro en échec** : aucun test ne couvre un transport qui échoue en cours de cycle, un conflit sur un contenu illisible ou un fichier d'état corrompu. Le coordinateur n'a qu'un test.

**T3. Attentes fragiles** : ~20 attentes fixes sont suivies d'une assertion négative. Il n'y a aucun `.timeLimit`, alors que ~50 fichiers pilotent WebKit.

**T4. Tests dépendants de l'environnement**
- Des tests dépendent de `/usr/share/doc/postfix` et sont sautés sans rien dire si le dossier disparaît.
- Des tests d'interface vont sur internet.

**T5. Nettoyage** : 8 suites `UserDefaults` ne sont jamais supprimées, et le test du trousseau écrit dans le vrai trousseau.

## 10. Décisions à prendre

1. L'ordre des corrections (proposition ci-dessous).
2. Apps externes : demander confirmation comme Safari ? Cela révise `DECISIONS.md` du 2026-10-16.
3. App Store :
   - cible séparée ou non ;
   - politique d'extensions A ou B ;
   - même identifiant de bundle ou un identifiant distinct.
4. Conformité à l'export et ANSSI.
5. Passer de ⌘S à ⌃⌘S pour la barre latérale.
6. Bloqueur dormant : le neutraliser, ou le retirer dans une étiquette git.
7. Suggestions de recherche actives par défaut (Google reçoit la frappe) : les garder ?
8. Journaux en anglais ?

## 11. Ordre de correction proposé

| Lot | Contenu | Pourquoi d'abord |
|---|---|---|
| 1. Failles web | W1, W3, W2, W6, W10, W11 | Exploitables aujourd'hui, corrections courtes |
| 2. Plantage et données | R1, R2, R3, R4, R5, R6 | Plantage et pertes de données |
| 3. WebKit de base | K1, K2, K3, K5, W5 avec HTTPS automatique, W4 ; K4 avec la 8.1 | Sites courants cassés |
| 4. Extensions | E1, E2, E3, E4, E6, E5 | Usurpation et données d'extensions |
| 5. Synchro | Révision de `SYNC.md` (S1 à S5), puis S6 et T2 | Avant la 7.7, tant qu'aucun serveur n'a de données |
| 6. Distribution | A5, A6, A3, A4 ; puis A1 et A2 si le Mac App Store est visé | Avant la première version publique |
| 7. HIG et accessibilité | H1 à H5 | Finition |
| 8. Architecture et tests | C1 à C7, T1, T3 à T5 | Au fil de l'eau |
