# TESTS_MANUELS.md — contrôles à faire à la main

Ce fichier liste les contrôles que les tests automatiques ne couvrent pas : rendu visuel, vrais sites, gestes, comptes, plusieurs Mac. Chaque tâche terminée y ajoute ses contrôles. Coche une case une fois le contrôle réussi ; si un contrôle échoue, note ce que tu as vu sous la case et dis-le-moi.

**Préparer l'app :**

```bash
cd ~/development/matcha
set -o pipefail && xcodebuild -project Matcha.xcodeproj -scheme Matcha \
  -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build build | xcbeautify
open build/Build/Products/Debug/Matcha.app
```

Ou ⌘R dans Xcode.

---

## En attente d'avant la phase 4

### Icône et compilation dans Xcode

- [ ] Dans Xcode, ⌘B se termine sans erreur ni avertissement.
- [ ] L'icône Matcha (bol vert sur fond vert foncé) apparaît dans le Dock pendant que l'app tourne, et dans le Finder sur `build/Build/Products/Debug/Matcha.app`. Si le Dock garde une icône vide : quitter l'app et la relancer.

### Fin de la phase 3 : « Fini quand »

- [ ] Réglages (⌘,) > Profils : crée un deuxième profil ; il arrive avec son propre Space.
- [ ] Dans un Space du premier profil, connecte-toi à un compte Google (gmail.com). Dans le Space du deuxième profil, connecte-toi à un autre compte Google.
- [ ] Dans un onglet, va sur trois pages à la suite (par exemple apple.com, puis un lien, puis un autre lien).
- [ ] Quitte Matcha (⌘Q) et relance-la. Chaque Space est toujours connecté à son propre compte Google.
- [ ] Dans l'onglet de l'étape 3, le bouton Précédent ramène bien aux pages d'avant, sans rechargement complet.
- [ ] Contrôle de fin de phase (tableau en bas de `PLAN.md`) : Google, compte Apple, ta banque ; Meet ou Zoom (caméra, micro) ; YouTube en plein écran ; Figma, Google Docs ou Notion ; WhatsApp Web ou Slack ; ton journal ; un PDF. Note ce qui ne marche pas.

---

## Phase 4

### 4.0 Langues

- [ ] Sur ton Mac en français, toute l'interface est en français, avec les mêmes textes qu'avant : barre latérale, menus (Fichier, Spaces, Historique…), menu contextuel des onglets, réglages, alerte « Quitter Matcha ? ». Les menus standards de macOS (Édition, Fenêtre, Aide) doivent maintenant être en français eux aussi.
- [ ] Réglages (⌘,) > Général : une section Langue avec le bouton « Changer la langue… ». Le bouton ouvre Réglages Système > Général > Langue et région.
- [ ] Dans Langue et région > Applications, clique sur +, choisis Matcha et la langue English, puis relance Matcha : tout est en anglais. Refais la même chose avec Deutsch, Español et Italiano. Pour chaque langue, regarde :
  - la barre latérale, les menus, le menu contextuel d'un onglet et celui d'un Space ;
  - les quatre onglets des réglages ;
  - les noms des thèmes dans l'éditeur de thème (clic sur l'icône du Space) ;
  - qu'aucun texte n'est coupé ou ne déborde (l'allemand est le plus long).
- [ ] Réglages > Profils : le nombre de Spaces d'un profil s'accorde (« 1 Space », « 2 Spaces »).
- [ ] Message caméra et micro dans ta langue : dans le Terminal, lance `tccutil reset Camera com.matchabrowser.matcha` puis `tccutil reset Microphone com.matchabrowser.matcha`, et ouvre un site qui demande la caméra (par exemple webcamtests.com).
- [ ] Remets Matcha en français (ou retire-la de la liste des Applications) quand tu as fini.
- Connu, laissé tel quel : le sous-menu Icône d'un Space affiche les noms techniques des symboles (« circle.fill »…). C'était déjà le cas avant ; noté dans `DECISIONS.md`.

### 4.1 Barre de commande

- [ ] Lancement sans onglet, puis nouvelle fenêtre privée (⇧⌘N) : la barre ne s'ouvre pas d'elle-même ; la page vide affiche « Appuyez sur ⌘T pour rechercher ou saisir une adresse. » ; ⌘T aussitôt, sans cliquer dans la fenêtre, ouvre la barre (au lancement comme juste après ⇧⌘N) ; taper une lettre avant ⌘T ne fait rien.
- [ ] ⌘T : la barre apparaît aussitôt, centrée, floutée, ombrée, en clair et en sombre, et dans une fenêtre privée ; taper juste après ⌘T n'envoie aucune lettre à la page.
- [ ] Taper « gith » : onglets et actions tout de suite, suggestions du moteur un court instant après, sous les résultats locaux, sans faire sauter la ligne sélectionnée.
- [ ] Taper vite « apple.com » puis Entrée : apple.com s'ouvre (jamais une suggestion) ; la 2e ligne propose de rechercher « apple.com ».
- [ ] Touches mortes : « ^ » puis « e » donne « ê » sans lancer de ligne. Saisie japonaise (Romaji) : taper « nihon », choisir un candidat avec ↑ ↓, Entrée valide la composition sans rien lancer ; une 2e Entrée lance la recherche.
- [ ] Guillemets : taper "pain au levain" ; les guillemets restent droits dans la recherche lancée.
- [ ] Un onglet d'un autre Space : la ligne montre le nom du Space ; Entrée bascule de Space avec l'animation.
- [ ] ⌘L sur une page : URL complète sélectionnée, « Copier l'URL » proposée ; Échap rend le clavier à la page (un champ de la page reçoit aussitôt la saisie).
- [ ] Barre ouverte, clic sur la page ou sur un onglet de la barre latérale : la barre se ferme et le clic agit du premier coup.
- [ ] ⌘T, taper « swift », puis cliquer sur « Nouvel onglet » (ou ⌘L, taper, puis cliquer sur la pastille d'adresse) : la barre se ferme et se rouvre à neuf, sans « swift » (écart voulu, voir `DECISIONS.md`) ; ⌘T ou ⌘L à la place du clic gardent le texte. Puis ⌘Z dans le champ : rien ne casse.
- [ ] Barre d'adresse au-dessus de la page, barre latérale masquée (⌘S puis ⌘L), petite fenêtre (700 × 450 : la liste défile), Réduire les animations.
- [ ] Suggestions avec Google, DuckDuckGo et Bing ; réglage coupé : plus aucune, même en le coupant barre ouverte (⌘, puis retour à la fenêtre) ; « intranet:8080 » ou une adresse e-mail : aucune ; fenêtre privée : aucune requête (Console, catégorie `CommandBar`, ou un moniteur réseau).
- [ ] VoiceOver : ↑ ↓ annonce le titre de la ligne.
- Connu : au-dessus d'une page, le flou ne montre pas le contenu de la page (texte, images) ; le panneau prend une teinte unie tirée du fond de la page. Dis-moi si ça te gêne (détail dans `DECISIONS.md`).

### 4.6 Copier l'URL

- [ ] Sur une page, ⌘⇧C : une petite capsule « URL copiée » (icône de lien) apparaît en fondu, centrée en bas de la page, reste environ 1,5 s puis disparaît en fondu. Colle dans une autre app (Notes, TextEdit) : c'est bien l'adresse complète de la page.
- [ ] Appuie plusieurs fois sur ⌘⇧C pendant que la capsule est visible : elle reste affichée sans clignoter et ne disparaît qu'environ 1,5 s après le dernier appui.
- [ ] Menu Édition : « Copier l'URL » (⇧⌘C) se trouve juste après le groupe Couper, Copier, Coller… ; il est grisé sans onglet ou sur un onglet vide (⌘T puis Entrée), et ⌘⇧C n'y affiche rien.
- [ ] ⌘L, puis la ligne « Copier l'URL » de la barre de commande (clic, ou ↓ puis Entrée) : la barre se ferme, la même capsule apparaît, l'adresse est copiée.
- [ ] Clic droit sur un onglet de la barre latérale (et sur un favori) > « Copier le lien » : même capsule, avec l'adresse de cet onglet, même s'il n'est pas l'onglet affiché.
- [ ] Pendant que la capsule est visible, clique ou fais défiler la page juste dessous : le clic atteint la page, le clavier reste où il était (un champ de la page garde la saisie).
- [ ] Aspect en clair, en sombre et dans une fenêtre privée (⇧⌘N) : capsule floutée, lisible, discrète ; avec la barre d'adresse au-dessus de la page (Réglages > Apparence), elle reste en bas et ne gêne rien.
- [ ] Facultatif, VoiceOver (⌘F5) : chaque copie annonce « URL copiée ».
