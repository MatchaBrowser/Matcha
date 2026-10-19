# Matcha — instructions pour Claude

## Le projet

**Matcha** (organisation GitHub `matchabrowser`, identifiant `com.matchabrowser.matcha`) : navigateur macOS natif au style d'Arc : barre latérale seule, Spaces colorés, page dans une carte aux coins arrondis, barre de commande. Les pages sont affichées par WebKit via `WKWebView` ; tout le reste (interface, onglets, Spaces) est construit par nous.

`PLAN.md` est la feuille de route et la source de vérité : tâches numérotées, phase par phase. `SYNC.md` spécifie la synchronisation (données, chiffrement, API des serveurs). `FEATURES.md` liste les fonctions mises de côté : ne les reprends pas sans mon accord. `TESTS_MANUELS.md` liste les contrôles à faire à la main ; chaque tâche y ajoute les siens.

## Environnement

- macOS 27, Xcode 27, Swift 6.4 en mode de langage Swift 6 (concurrence stricte).
- Cible de déploiement minimale : **macOS 15.4** (première version avec `WKWebExtension`).
- App SwiftUI + AppKit, données en SwiftData, tests avec Swift Testing.
- Le projet utilise des **dossiers synchronisés** (Xcode 16 et plus) : tout fichier créé sous `Matcha/` ou `MatchaTests/` est compilé automatiquement. Ne modifie pas `project.pbxproj` à la main, sauf si une tâche le demande explicitement.
- Édition dans VS Code avec les extensions Swift et SweetPad ; Xcode reste installé pour la compilation, la signature et les réglages du projet.

## Commandes

```bash
# Compiler (Debug)
set -o pipefail && xcodebuild -project Matcha.xcodeproj -scheme Matcha \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build build | xcbeautify

# Lancer les tests
set -o pipefail && xcodebuild -project Matcha.xcodeproj -scheme Matcha \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build test | xcbeautify

# Lancer l'app compilée
open build/Build/Products/Debug/Matcha.app

# Formater puis vérifier le style
swiftformat . && swiftlint

# Vérifier les traductions (après une compilation, sans recompiler) : clés absentes ou périmées,
# textes non traduits en français, allemand, espagnol ou italien
scripts/check-localizations.sh

# Relire les textes d'une langue (anglais → traduction) ; --missing, --comments
scripts/strings.sh fr

# Tout vérifier d'un coup, comme la CI (GitHub Actions) : format, style, compilation sans avertissement,
# traductions, tests unitaires ; --fix formate d'abord
scripts/check.sh
```

`xcbeautify` s'installe avec `brew install xcbeautify`. S'il manque, retire `| xcbeautify` et `set -o pipefail &&`.

## Façon de travailler

1. Au début de chaque session, lis `PLAN.md` et repère la première tâche non cochée.
2. Une tâche à la fois. Avant de coder, résume en 2 ou 3 lignes ce que tu vas faire et quels fichiers tu touches.
3. Après chaque tâche :
   - `scripts/check.sh` passe : format, style, compilation **sans erreur ni avertissement**, traductions (aucune clé absente, périmée ou non traduite) et tests unitaires ;
   - tu coches la tâche dans `PLAN.md` ;
   - tu fais un commit au format `1.4 — Résolution URL ou recherche`.
4. **[MANUEL]** = action à faire par moi dans Xcode ou sur le portail Apple. Donne-moi les étapes exactes, clic par clic, puis attends ma confirmation.
5. **[À VOIR]** = contrôle visuel ou manuel. Dis-moi précisément quoi ouvrir et quoi vérifier. Si un outil de contrôle de l'écran est disponible dans ta session, tu peux l'utiliser ; sinon, demande-moi.
6. Ne commence pas une nouvelle phase tant que je n'ai pas validé le critère « Fini quand » de la phase en cours.
7. Toute décision non évidente (choix d'API, compromis, fonction reportée) → une ligne dans `DECISIONS.md` : date, décision, raison.
8. Si une API ne se comporte pas comme le plan le décrit, vérifie sa signature dans le SDK (documentation Xcode ou en-têtes de WebKit) avant tout contournement, et signale-moi l'écart. Les noms d'API du plan sont indicatifs : le SDK fait foi.

## Règles de code

- **Concurrence** : tout ce qui touche WebKit ou l'interface est `@MainActor`.
- **État observable** avec `@Observable` (framework Observation), pas `ObservableObject`.
- **Deux mondes séparés** : les modèles persistés SwiftData (suffixe `Record`) et les objets d'exécution (`BrowserTab`, qui possède le `WKWebView`). Jamais de `WKWebView` dans un modèle SwiftData.
- **SwiftData compatible CloudKit dès le départ** : pas de `@Attribute(.unique)`, chaque propriété a une valeur par défaut ou est optionnelle, chaque relation est optionnelle avec son inverse.
- **Couches** : `Browser/`, `Services/` et `Models/` n'utilisent rien de `Features/` ni d'`App/` ; ce qu'il leur faut de l'interface passe par un protocole (`PageDialogPresenting`, `PopupWindowHosting`, `ExtensionHost`). Aucun `static let shared` : les services partagés sont créés une fois dans `AppEnvironment` (racine de composition, `MatchaApp.init`) et donnés par les initialiseurs (`SessionServices` pour les sessions) ou par `.environment`.
- **API publiques uniquement.** Jamais de sélecteurs privés, de `value(forKey:)` sur des clés non documentées, ni de `perform(_:)` sur des méthodes cachées. Si une fonction n'est possible qu'avec une API privée, on la reporte et on le note dans `DECISIONS.md`.
- **Dépendances autorisées** : KeyboardShortcuts (sindresorhus) et Sparkle. Toute autre dépendance → me demander avant.
- **Fichiers courts** : un type principal par fichier, moins de 300 lignes environ.
- **Code en anglais** : noms, commentaires (de ligne, de documentation et de bloc, scripts compris) et messages de journal. Les documents du projet (`PLAN.md`, `DECISIONS.md`…) restent en français.
- **Logique testable** (analyse d'URL, archivage, import, classement de la barre de commande) dans des types purs, sans dépendance à l'interface, couverts par des tests.
- **Journalisation** avec `Logger` (os.log), une catégorie par module, messages en anglais ; jamais d'adresse complète en clair. Pas de `print` laissé dans le code.
- **Textes de l'interface en anglais dans le code**, traduits dans la même tâche dans toutes les langues du catalogue (`Matcha/Resources/*.xcstrings`) : français, allemand, espagnol, italien. Après une compilation, `scripts/check-localizations.sh` doit passer.

## Structure des dossiers

```
Matcha/
  App/              point d'entrée, commandes de menu, raccourcis, réglages
  Browser/          navigation : sessions, Spaces, BrowserTab, TabManager, disposition de la barre latérale,
                    configuration WebKit, délégués, recherche dans la page, aperçu, zoom, thèmes
  Models/           modèles SwiftData (*Record)
  Services/         sans interface : favicons, téléchargements, historique, autorisations, code source des
                    pages, cycle de vie des onglets, recherche de texte (Matching/), bloqueur, extensions,
                    import, synchro (Sync/)
  Features/         l'interface, une fonction par dossier
    Window/         fenêtre, fond du Space, carte de contenu
    Sidebar/        barre latérale, favoris, épinglés, onglets du jour
    Spaces/         sélecteur, éditeur de thème, gestes
    CommandBar/     barre de commande et ses fournisseurs
    Peek/           aperçu flottant des liens
    MiniWindow/     petite fenêtre flottante (équivalent de Little Arc)
    PopupWindow/    fenêtres de connexion
    Downloads/      panneau des téléchargements
    History/        fenêtre de l'historique
    FindInPage/ PageZoom/ Permissions/ SiteSecurity/ Dialogs/ Printing/ Extensions/ Import/
  Resources/        catalogues de textes, listes de blocage
MatchaTests/
MatchaUITests/
scripts/            vérifications, génération et publication
```
