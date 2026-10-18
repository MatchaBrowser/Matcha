# FEATURES.md — fonctions mises de côté

Fonctions retirées du plan pour l'instant. **Ne pas les reprendre sans mon accord.** Pour en relancer une, on la remet dans `PLAN.md` à sa place, avec son numéro, et on relit d'abord les notes ci-dessous.

---

## Archivage automatique (ex-tâche 4.2)

**Reportée le 2026-10-17.** L'archivage a été une source de soucis à l'usage ; on le repensera plus tard.

**Texte d'origine :** `Services/ArchiveService.swift`. Réglage : 12 h, 24 h (défaut), 7 jours, 30 jours. Au lancement puis toutes les 10 minutes, les onglets du jour inactifs depuis plus longtemps passent en `archived` et libèrent leur vue. Page Archive avec recherche et restauration ; la barre de commande cherche aussi dans l'archive. Action « Archiver l'onglet » dans la barre de commande. Tests des règles.

**Ce qui existe déjà :** `TabRecord.placeValue` accepte `archived` depuis la 3.1, et `TabRecord.place` vaut alors nil. On garde cette valeur : la retirer changerait le schéma de la base.

**Notes d'une étude faite le 2026-10-17, à vérifier sur le code de l'époque :**
- Ne jamais archiver l'onglet sélectionné d'un Space, ni un onglet qui joue du son ou utilise la caméra ou le micro. Un onglet du jour vide est fermé, sans entrée d'archive.
- `lastActivity` doit être tenu à jour à la sélection, à l'affichage, à l'ouverture en arrière-plan et à l'arrivée dans les onglets du jour. Aujourd'hui, un onglet ouvert en arrière-plan est plus récent que l'onglet sélectionné et lui prend la sélection au lancement suivant.
- Sans changer le schéma : pour un onglet archivé, `lastActivity` peut porter la date d'archivage. L'`interactionState` est gardé pour retrouver l'historique précédent/suivant à la restauration.
- Archiver dans le même tour que le retrait de l'onglet : l'enregistrement automatique de `SpaceStore` a lieu une seconde après.
- Page « Onglets archivés » dans une fenêtre à part (⌥⌘Y) plutôt qu'une feuille, pour que ⌘W et les autres commandes n'agissent pas sur la fenêtre derrière.
- Conservation : 30 jours, 500 entrées au plus, une seule entrée par Space et par adresse.
- Ce qui a posé problème à l'usage reste à préciser avec toi avant de reprendre.

---

## Boosts (ex-tâche 4.7)

**Reportée le 2026-10-17.** Utilité pas certaine ; à revoir plus tard.

**Texte d'origine :** `Features/Boosts/`. `BoostRecord` : domaine, CSS, JavaScript, actif. Le CSS est injecté par un `WKUserScript` au début du document (une balise `<style>`), le JavaScript à la fin ; chaque script vérifie `location.hostname`. À chaque modification : retirer et remettre les scripts sur toutes les vues, puis recharger les onglets concernés. Éditeur : domaine, deux zones de texte à chasse fixe, interrupteur.

**À savoir si on la reprend :**
- `SYNC.md` réserve déjà le type `boost` (`domain`, `css`, `js`, `isEnabled`) ; il ne coûte rien tant que la fonction n'existe pas.
- Questions à trancher : Boosts communs ou par profil ; monde d'exécution du JavaScript (`WKContentWorld`) ; pages dont la politique de sécurité (CSP) refuse les balises `<style>` ; règles de correspondance des domaines (sous-domaines, `www`) dans un type pur testé ; nouveau modèle SwiftData, donc migration de la base.
- Le panneau de réglages du site (5.2) aurait une ligne Boost.

---

## Bloqueur de publicités intégré (ex-tâches 6.1 et 6.2)

**Reporté le 2026-10-18.** En attendant, on utilise une extension existante (uBlock Origin Lite, essayée en 6.6) ; le bloqueur intégré au navigateur viendra plus tard.

**Texte d'origine :**
- 6.1 Listes de blocage (`scripts/build-blocklists.sh`). Télécharger EasyList et EasyPrivacy, les convertir au format de blocage de WebKit avec le ConverterTool d'AdGuard (SafariConverterLib), écrire les JSON dans `Resources/Blocklists/`. **[MANUEL]** Je vérifie la licence de l'outil avant d'en intégrer quoi que ce soit dans l'app.
- 6.2 Bloqueur natif (`Services/ContentBlockerService.swift`). Compiler les JSON avec `WKContentRuleListStore.default()` (réutiliser la version compilée via `lookUpContentRuleList` si l'identifiant et la version n'ont pas changé), ajouter les listes à tous les `userContentController`. Si le compilateur refuse une liste trop grosse, la découper. Exceptions par site avec une petite liste dynamique (`ignore-previous-rules`).

**État :** la 6.2 est faite et testée (commit « 6.2 — Bloqueur natif ») ; la 6.1 n'est pas commencée, aucune liste n'est livrée. Le code reste dans l'app : `Services/ContentBlocker/`, réglages `App/Settings/ContentBlockerSettingsSection.swift`, `ContentBlockerExceptionsSection.swift`, `BlocklistCreditsSection.swift`, ligne du panneau du site `Features/Permissions/ContentBlockerRow.swift`, et leurs tests unitaires. `ContentBlockerService.isAvailable` (faux) cache ces réglages et empêche le lancement du service ; les pages gardent leur contrôleur de contenu propre, sans liste.

**À savoir si on le reprend :**
- Passer `ContentBlockerService.isAvailable` à vrai, puis faire la 6.1 ; les contrôles de `TESTS_MANUELS.md` (6.2) sont prêts.
- Licences : vérifier celles des listes et du convertisseur avant d'intégrer quoi que ce soit (étape [MANUEL] de la 6.1).
- Manifeste attendu : `Resources/Blocklists/blocklists.json` (`DECISIONS.md`, 2026-10-18) ; 150 000 règles au plus par fichier (limite de WebKit, vérifiée), la découpe automatique n'étant qu'un filet.
- Une règle `ignore-previous-rules` n'agit que dans sa propre liste : d'où un contrôleur de contenu par page, et les listes posées ou retirées avant chaque navigation selon le site (exceptions).
- Avec une extension de blocage installée, les deux bloqueraient en double : décider lequel prime (réglage, ou bloqueur intégré coupé quand une telle extension est active).

---

## Synchro par iCloud (ex-tâches 7.3 et 7.6)

**Reportée le 2026-10-18**, à la demande de l'utilisateur : la synchro passe d'abord par un serveur (privé, puis public). Le moteur reste commun à tous les transports (`SyncTransport`), et `SYNC.md` (§ 6) garde la spécification d'iCloud.

**Texte d'origine :**
- 7.3 [MANUEL] iCloud. Nécessite le compte développeur payant. Cible Matcha > Signing & Capabilities : ajouter iCloud, cocher CloudKit, conteneur `iCloud.com.matchabrowser.matcha` ; ajouter aussi Push Notifications (c'est par là que `CKSyncEngine` apprend qu'il y a des changements).
- 7.6 Transport iCloud (`Services/Sync/CloudKitTransport.swift`). `CKSyncEngine` sur la base privée, zone `Matcha`, un `CKRecord` par enregistrement, contenu dans `encryptedValues` (chiffré par CloudKit, sans mot de passe maître) ; paquets d'extension en `CKAsset`, chiffrés par Matcha (`SYNC.md`, § 6). L'état du moteur est conservé. Si le compte iCloud change ou se déconnecte, la synchro s'arrête et les données locales restent.

**À savoir si on la reprend :** le choix « iCloud » s'ajoute à Réglages > Synchronisation (7.9) ; les modèles SwiftData restent compatibles avec CloudKit (règles de `CLAUDE.md`), même si la synchro ne passe pas par le miroir automatique de SwiftData.

---

## Limites connues, à contourner

Fonctions livrées avec une limite, faute d'API publique ou par choix de simplicité. À reprendre quand on aura une solution.

### Permissions des sites (5.2)

- **Notifications des sites** : aucune API publique de WebKit ne permet de répondre à une demande de notification (`WKUIDelegate`, `WKWebView`, `WKWebsiteDataStore`, `WKPreferences` vérifiés dans le SDK de macOS 27). Les sites ne peuvent pas envoyer de notifications. Piste : surveiller les prochains SDK.
- **Localisation** : `webView(_:requestGeolocationPermissionFor:initiatedBy:)` n'existe que depuis macOS 27 (rien de public avant). Il faudra une étape **[MANUEL]** (cocher « Location » dans App Sandbox, ajouter `NSLocationUsageDescription`), puis un cas `location` qui réutilise le bandeau, sous `@available(macOS 27, *)`.
- **Onglet en arrière-plan qui demande une permission** : la demande attend qu'on affiche l'onglet, sans aucun signal dans la barre latérale. Piste : une pastille sur la ligne de l'onglet.
- **Pas de réglages du site dans l'aperçu (Peek) ni dans la mini-fenêtre**. Piste : réutiliser le panneau dans leur barre.
- **Partage d'écran** : il ne passe pas par la demande de permission de WebKit qu'on intercepte ; comportement à vérifier à la main.

### Téléchargements (5.1)

- **Lien `target=_blank` qui ne mène qu'à un téléchargement** (ou adresse d'un fichier tapée dans un nouvel onglet) : l'onglet ouvert reste vide. Safari le referme. Piste : fermer un onglet neuf dont la première navigation devient un téléchargement.
- **Pas de reprise** d'un téléchargement interrompu, et pas d'avertissement quand une page lance de nombreux téléchargements.

### Barre de commande (4.1)

- **Flou** : au-dessus d'une page, le matériau ne floute pas le contenu de la page (WebKit dessine la page dans un autre processus) ; le panneau prend une teinte unie.

### Dossiers personnalisés

- **Panneau ouvert en bas de la barre** : rien ne défile de soi-même ; il faut faire défiler les onglets pour voir tout le panneau. Piste : faire défiler juste assez pour montrer son en-tête et la grille.
- **Une seule couleur pour le clair et le sombre** : un fond vif choisi en clair reste vif en sombre. Piste : une variante sombre tirée de la couleur, comme pour les thèmes des Spaces.
- **Symboles** : 35 proposés, pas de recherche dans tous les symboles SF. L'emoji passe par le champ ou le visualiseur de caractères du système.

### Icônes des Spaces

- **Symboles** : 45 proposés (pleins), pas de recherche dans tous les symboles SF ; l'emoji passe par le champ ou le visualiseur de caractères, comme pour les dossiers.

### Mémoire des onglets (5.6)

- **Texte saisi perdu** : un onglet mis en veille recharge sa page en revenant ; ce qui n'a pas été envoyé (formulaire, brouillon) est perdu, comme l'état d'une app web ou la position d'une vidéo. Piste : demander à la page, par un script dans un monde isolé (`WKContentWorld`), si un champ a été modifié, et l'épargner, comme le fait Chrome.
- **Applications web épinglées** (messagerie, discussion) : en veille, elles ne se mettent plus à jour (compteur du titre figé) jusqu'à leur affichage. Piste : un réglage pour garder chargés les épinglés et les favoris.
- **Média arrêté** : `requestMediaPlaybackState` répond « en lecture » dès qu'un média de la page n'est pas en pause, même chargé sans avoir été lancé ou coupé (vérifié en 5.10) : un tel onglet ne se met jamais en veille. Il voit bien Web Audio et `new Audio()` (vérifié). Piste : une API publique de WebKit qui dirait si la page est audible.
- **Partage d'écran sans caméra ni micro** : aucune API publique ne le signale ; l'onglet peut se mettre en veille.
- **Fenêtre ouverte en onglet par une page** (`window.open` sans taille) : si la page d'origine se met en veille pendant ce temps, `window.opener` ne la retrouve plus. Les fenêtres de connexion (5.8) protègent, elles, leur page d'origine. Piste : la même règle pour un onglet ouvert par `window.open` tant qu'il est ouvert.

### Fenêtres de connexion (5.8)

- **Position demandée ignorée** : la fenêtre est centrée sur sa fenêtre d'origine. Sans le délégué privé de WebKit, la page lit `screenX`, `outerWidth` et `outerHeight` à 0 et ne peut pas calculer une position juste ; `window.moveTo` et `window.resizeTo` sont sans effet (vérifié).
- **Menus de page** (⌘R, ⌘F, ⌘P, zoom, ⌘[ et ⌘]) : sans effet dans une fenêtre de connexion (ils visent la fenêtre de navigation ou la mini-fenêtre). Le glissement à deux doigts revient en arrière. Dans le menu Fichier, ⌘W s'appelle encore « Fermer l'onglet » quand elle est au premier plan (il la ferme bien). Piste : suivre la fenêtre de connexion active comme la mini-fenêtre active (`FrontPage`).
- **Ouverte depuis un aperçu** : si l'aperçu se ferme pendant la connexion (clic à côté de lui dans la fenêtre, autre onglet, ⌘T), sa page disparaît et la connexion ne peut plus la prévenir. Piste : garder l'aperçu ouvert tant qu'il a une fenêtre de connexion.

### Menu contextuel des pages (5.9)

- **Identifiants non documentés** : les éléments de WebKit sont reconnus par des identifiants absents des en-têtes publics ; si une version de macOS les change, le menu reste celui de WebKit (« … dans une nouvelle fenêtre » ouvre un onglet au premier plan) et `PageMenuIntegrationTests` échoue. Piste : une API publique de menu contextuel pour macOS, si WebKit en publie une.
- **Vidéo, audio, cadre** : « Ouvrir la vidéo (l'audio, le cadre) dans une nouvelle fenêtre » restent ceux de WebKit et ouvrent un onglet au premier plan. Piste : les remplacer comme le lien et l'image (titres vidéo et audio à distinguer).
- **`window.open` simultané** : une fenêtre ouverte par la page dans les quelques millisecondes entre le choix et la fenêtre de WebKit prend le choix à sa place. Aucune information publique ne distingue les deux.
- **« Ouvrir dans un aperçu »** charge l'adresse sans `Referer`, comme Maj+clic.
- **« Ouvrir le lien en split »** : renvoyé de la 4.3 vers la 5.9 (`DECISIONS.md`), absent du texte de la 5.9 ; pas fait. À décider avec toi.

### Son (5.10)

- **Son non détecté** : pas de haut-parleur pour le son de Web Audio (jeux, synthétiseurs, certains lecteurs), d'un élément audio hors de la page (`new Audio()`) ou d'un média dans un shadow DOM : le script ne voit que les éléments audio et vidéo du document (iframes comprises). Aucune API publique ne dit si une page est audible (`_isPlayingAudio` est privé), et `requestMediaPlaybackState` allumerait l'icône sur toute page qui a une vidéo arrêtée. Piste : surveiller les prochains SDK.
- **Pas de coupure du son**, seulement la pause : couper le son d'une page n'existe que dans l'API privée de WebKit.
- **Dossier replié** : un épinglé qui joue du son dans un dossier replié ne se voit pas. Piste : un haut-parleur sur la ligne du dossier.
- **Vidéo sans piste audio et non coupée** (rare : ces vidéos sont presque toujours coupées) : le haut-parleur s'affiche. Piste : `audioTracks`, à vérifier sur les lecteurs en flux (YouTube).

### Extensions (6.3)

- **Page d'extension et page web dans le même onglet** : WebKit exige une vue web créée avec la configuration de l'extension pour ses pages (`webkit-extension:`), et une autre pour le web. Les pages d'extension s'ouvrent donc dans un nouvel onglet (ou une mini-fenêtre) ; taper une adresse dans un onglet qui montre une page d'options ne fait rien, et `tabs.update()` d'une page web vers une page d'extension (ou l'inverse) est refusé. Un onglet de page d'extension restauré au lancement suivant reste vide. Piste : que `BrowserTab` change de vue web dans `load` et retrouve alors le magasin de données de son profil.
- **Fenêtres** : Matcha n'a qu'une fenêtre principale ; `windows.create()` d'une fenêtre « normal » ouvre ses adresses en onglets dans la fenêtre principale, une fenêtre « popup » devient une mini-fenêtre (sa première adresse seulement) ; une fenêtre privée est refusée ; les onglets à déplacer et le rang d'un nouvel onglet sont ignorés. Une extension ne peut pas fermer une fenêtre de navigation, ni changer la taille ou l'état d'une fenêtre.
- **Non pris en charge** : couper le son d'un onglet (aucune API publique), mode lecture, sélection de plusieurs onglets hors des splits (`tabs.highlight`), changer l'onglet parent. Messages vers une app native (`runtime.sendNativeMessage`, ce qui relie un gestionnaire de mots de passe à son app pour Mac) : rien pour une extension chargée depuis un dossier ; pour une extension chargée depuis le `.appex` d'une app (App Store, `WKWebExtension(appExtensionBundle:)`), WebKit les transmet par défaut au code natif de l'extension, à vérifier en 6.6.
- **Fenêtre principale fermée** : ses onglets disparaissent pour les extensions jusqu'à sa réouverture ; leurs pages encore chargées ne peuvent plus parler à leur extension.
- **Cookies** (`browser.cookies`) : le magasin par défaut des extensions n'est celui d'aucun profil ; elles n'atteignent les cookies d'un profil que par ses onglets ouverts.
- **Demandes de permissions** : alerte en feuille, tout ou rien ; l'écran intégré viendra avec la 6.4. Une extension déposée dans `Application Support/Extensions/` sans passer par l'installation (6.4) n'a aucune permission.
- **Bulle d'une action** : ancrée en haut à droite de la fenêtre, en attendant les boutons des extensions (6.5).

### Installation des extensions (6.4)

- **Messages natifs** (`runtime.sendNativeMessage`, `connectNative`) : WebKit ne sait pas joindre l'app d'une extension Safari chargée par Matcha (« Error creating NSExtension » ; constaté avec Proton Pass et Bitwarden) : ce passage est réservé à Safari. Matcha les refuse donc lui-même (« Native messaging is not supported in Matcha. »), réponses espacées d'une seconde par extension. Une extension qui en a besoin perd ces fonctions : Bitwarden pour Safari passe par son app pour copier et lire le presse-papiers, ouvrir sa bulle, télécharger un fichier et surveiller l'expiration du coffre. Piste : répondre nous-mêmes aux commandes connues d'une extension (celles de Bitwarden : `copyToClipboard`, `readFromClipboard`, `showPopover`, `downloadFile`, `sleep`), avec les API publiques (presse-papiers, bulle, panneau d'enregistrement).
- **Installer depuis les boutiques** (Chrome Web Store, addons.mozilla.org) : il faut d'abord télécharger le `.crx` ou le `.xpi`. Piste : un bouton « Ajouter à Matcha » sur la page d'une extension, qui télécharge son paquet.
- **Identifiant Chrome** : une extension de Chrome installée depuis un `.crx` n'a pas son identifiant Chrome (tiré de sa clé publique) ; un site qui l'appelle par cet identifiant (`externally_connectable`) ne la trouve pas. Piste : lire la clé dans l'en-tête CRX3 (protobuf) ou le champ `key` du manifeste et en tirer l'identifiant, comme pour Safari.
- **Signature des `.crx`** : non vérifiée ; l'utilisateur choisit le fichier et voit les permissions avant d'installer. Une extension Safari d'app, elle, est vérifiée par WebKit (manifeste contrôlé par la signature du `.appex`).
- **Mises à jour** : rien n'est mis à jour seul. Une extension Safari suit son app (App Store) ; un fichier se réinstalle par-dessus (« Mettre à jour l'extension »), ses données gardées.
- **Permissions facultatives** (`optional_permissions`) : pas montrées à l'installation ; l'extension les demande en cours de route (alerte de la 6.3).
- **Menu de Bitwarden dans les champs** (icône et suggestions au focus d'un champ) : ne s'affiche pas. Son conteneur (`overlay/menu.html`) n'accepte que les adresses `chrome-extension:`, `moz-extension:` ou `safari-web-extension:` (`isExtensionUrlWithOrigin`) ; Matcha sert les pages d'extension sous `webkit-extension:`, et WebKit ne charge pas dans les pages web d'une autre app les pages servies sous ces trois schémas (vérifié par des tests, `DECISIONS.md`). Le reste marche : bulle de l'extension, remplissage depuis la bulle, badge. Vérifié le 2026-10-18 : ajouter `"webkit-extension:"` à cette liste (version Firefox de Bitwarden modifiée à la main) fait apparaître le menu, qui marche. Pistes : demander à Bitwarden ce changement d'une ligne (ticket rédigé pour bitwarden/clients), ou les raccourcis des extensions (`commands`, ⌘⇧L de Bitwarden : `WKWebExtensionContext.performCommand(for:)` sur les touches).
- **Versions Firefox des extensions** : Matcha s'annonce comme Safari ; une extension qui choisit ses chemins d'après l'identifiant de navigateur prend ceux de Safari. Constaté avec Bitwarden pour Firefox : sa boucle Safari appelle `runtime.sendNativeMessage`, absent faute de la permission (facultative dans cette version), échoue aussitôt et tourne sans rendre la main : son processus se fige, sa bulle ne s'ouvre pas. Préférer la version Safari d'une extension quand elle existe.
- **À surveiller** : une fois, Matcha entier a cessé de répondre après avoir éteint puis rallumé une extension et rechargé la page ; rien de reproduit depuis (relancer Matcha a suffi).

### Boutons des extensions (6.5)

- **Bouton masqué** : la bulle de l'extension n'est plus accessible (ses scripts continuent d'agir sur les pages). Piste : un menu « Extensions » (pièce de puzzle) qui liste les extensions masquées, comme Chrome.
- **Mini-fenêtres et fenêtres de connexion** : pas de boutons ; une bulle demandée pour leur page s'ouvre au coin haut droit de la fenêtre.
- **Menu de l'action** (`menus` avec le contexte « action ») : pas repris dans le menu contextuel du bouton. **Couleur du badge** : celle de Matcha (WebKit ne la donne pas).
- **Ordre des boutons** : par nom ; pas de glisser-déposer pour les ranger.
