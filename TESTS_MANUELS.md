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
- [ ] Message réseau local dans ta langue : si Matcha n'apparaît pas encore dans Réglages Système > Confidentialité et sécurité > Réseau local, ouvre une page de ton réseau (l'adresse de ta box, par exemple http://192.168.1.1) : la demande de macOS affiche « Un site demande l'accès aux appareils de votre réseau local. » (ou sa traduction). Une fois la demande passée, macOS ne la montre plus.
- [ ] Remets Matcha en français (ou retire-la de la liste des Applications) quand tu as fini.
- Réglé depuis (« Icônes des Spaces », plus bas) : le sous-menu Icône d'un Space, qui affichait les noms techniques des symboles (« circle.fill »…), est remplacé par « Changer l'icône… » et une grille aux noms traduits.

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

### 4.3 Split view

- [ ] Avant de lancer cette version, copie `~/Library/Containers/com.matchabrowser.matcha/Data/Library/Application Support/` ailleurs (la base gagne deux champs). Lance Matcha : Spaces, épinglés, dossiers et onglets sont là.
- [ ] Ouvre apple.com, fr.wikipedia.org et github.com. Sur apple.com, glisse l'onglet Wikipédia jusqu'au bord droit de la page : la moitié droite se colore ; lâche : deux cartes côte à côte, Wikipédia à droite, bordée de la couleur d'accentuation. Glisse GitHub sur le bord gauche de la carte de gauche, puis essaie entre deux cartes : jusqu'à quatre panneaux ; avec quatre, un cinquième onglet ne colore plus rien.
- [ ] Pendant un glisser, au milieu d'une page, rien ne se colore et lâcher ne fait rien ; sur le champ de recherche de google.com, aucun texte « matcha-tab:… » n'apparaît. Hors glisser, clics, défilement, sélection de texte et clic droit dans les pages marchent comme avant (S4). Un fichier glissé du Finder dans une page (pièce jointe Gmail) et un texte glissé depuis Notes dans un champ arrivent toujours.
- [ ] Clique dans chaque panneau : la bordure, la pastille d'adresse et le titre de la fenêtre suivent ; le clic agit du premier coup (un lien s'ouvre) ; ⌘L puis une adresse l'ouvre dans le panneau actif ; ⌘R, ⌘[, ⌘] et ⇧⌘C agissent sur lui.
- [ ] Séparateur : curseur de redimensionnement et petit trait au survol ; glissement fluide même avec des pages lourdes (YouTube, Google Docs) ; jamais moins d'environ 200 pt ; double-clic : parts égales ; une infobulle explique les deux gestes. Rétrécis la fenêtre au minimum avec quatre panneaux : parts égales, rien ne déborde ; agrandis-la : les proportions reviennent. Pareil avec ⌘S.
- [ ] Barre latérale : une ligne par split (icônes et titres ; icônes seules avec 4 onglets dans une barre étroite), morceau actif marqué ; un clic sur un morceau rend ce panneau actif ; un onglet ordinaire cliqué s'affiche seul, un clic sur le split le réaffiche.
- [ ] Menu d'un onglet ordinaire : « Ouvrir en split » l'ajoute à droite du panneau actif et tu peux taper aussitôt dans sa page ; grisé avec 4 panneaux ; absent sur un favori ou sur l'onglet affiché.
- [ ] Menu d'un morceau : « Retirer du split » (l'onglet passe juste sous le split), « Séparer les onglets », « Épingler le split » (il survit à « Effacer »), « Désépingler le split », « Fermer le split ».
- [ ] Glisse la ligne du split dans les épinglés, puis dans un dossier ; replie, déplie, supprime le dossier : le split reste entier. Sur les favoris : refusé.
- [ ] Split du jour : ⌘W ferme le panneau actif, son voisin prend le clavier ; à un onglet, le split disparaît ; × de la ligne : tout se ferme. Split épinglé : ⌘W le décharge en entier (ligne grisée) ; un clic sur un morceau le rouvre aux adresses d'origine.
- [ ] Sur un onglet du jour affiché, glisse un épinglé sur le bord de la carte : le split se range dans les épinglés, rien n'est désépinglé.
- [ ] Liens : ⌘-clic dans un panneau ouvre l'onglet sous le split, hors du split ; un lien qui ouvre une fenêtre l'affiche seul.
- [ ] « Fermer les autres onglets » sur un morceau : le split reste entier.
- [ ] Barre d'adresse au-dessus de la page (Réglages) : une barre par carte ; un clic sur la pastille d'une carte non active l'active puis ouvre la barre de commande sur son adresse ; avec 4 panneaux à 200 pt, rien n'est coupé.
- [ ] Barre masquée (⌘S) : fais apparaître la barre flottante, glisse un onglet sur le bord droit de la carte : le split se crée ; réordonne des onglets dans la barre flottante : ça marche toujours (S5).
- [ ] Change de Space et reviens : même split, même panneau actif ; « Déplacer vers » sur un morceau n'emporte que cet onglet. Fenêtre privée (⇧⌘N) : split possible, rien de gardé.
- [ ] ⌘Q et relance : splits, ordre et proportions retrouvés ; si le dernier onglet utilisé était dans un split, il s'affiche avec ce panneau actif.
- [ ] Vidéo en plein écran dans un panneau, puis Échap : elle revient dans le bon panneau ; une vidéo continue quand tu cliques dans l'autre panneau ou tires le séparateur.
- [ ] Clair, sombre, privé : bordure, intervalles, poignée et zones de dépôt lisibles mais discrets. VoiceOver : la ligne annonce « Split avec … », les panneaux annoncent leur titre et « Panneau actif », le séparateur se règle avec Augmenter et Diminuer.
- [ ] Langues : menus du split en anglais, allemand, espagnol et italien (« riquadro » pour un panneau, jamais « pannello »).
- [ ] Glisse un onglet de la barre sur un champ de texte d'une page (la recherche de Wikipédia par exemple), au milieu de la page : rien n'est collé dans le champ, et l'onglet reprend sa place. Glisser un lien ou du texte d'une page vers une autre marche toujours comme avant.
- Connu : la touche Tab ne change pas le panneau actif (un clic, oui) ; pas encore de glisser d'un onglet hors de la ligne d'un split ni de réordonnancement des panneaux (voir `DECISIONS.md`).

### 4.4 Peek

- [ ] Sur fr.wikipedia.org, Maj+clic sur un lien : l'aperçu grandit depuis le lien. La page derrière s'assombrit ; la barre latérale reste claire. Au-dessus du panneau : le site à gauche, « Ouvrir en onglet » et × à droite, avec leur bulle d'aide. Aucun onglet n'apparaît et la page d'origine ne bouge pas (pas de texte sélectionné ; sinon, dis-le-moi). À refaire en clair, en sombre et en fenêtre privée.
- [ ] Le clavier est tout de suite dans l'aperçu : les flèches et l'espace le font défiler.
- [ ] ⎋ ferme l'aperçu, puis les flèches font défiler la page d'origine. × et ⌘W le ferment aussi ; pendant l'aperçu, le menu Fichier affiche « Fermer l'aperçu ». L'onglet n'est jamais fermé.
- [ ] Une page qui utilise ⎋ le garde (visionneuse, boîte de dialogue : le premier ⎋ la ferme, le second ferme l'aperçu). Saisie japonaise dans un champ de l'aperçu : ⎋ annule la composition sans fermer l'aperçu.
- [ ] Clic sur la zone sombre : l'aperçu se ferme et le lien dessous n'est pas suivi. Clic sur un autre onglet de la barre : l'aperçu se ferme et l'onglet s'affiche du premier coup. Pointeur sur la zone sombre : flèche, pas d'effet de survol de la page dessous (sinon, dis-le-moi).
- [ ] « Ouvrir en onglet » : la page passe dans un onglet juste sous l'onglet d'origine, sans recharger (une vidéo continue, un texte saisi reste). Le clavier est dans la page ; ⌘[ revient aux pages vues dans l'aperçu.
- [ ] Dans l'aperçu : un lien, même « nouvelle fenêtre », reste dedans. ⌘[, ⌘] et ⌘R agissent sur l'aperçu ; ⇧⌘C copie son adresse. ⌘-clic ouvre un onglet en arrière-plan sous l'onglet d'origine, et l'aperçu reste ouvert.
- [ ] Une vidéo avec du son s'arrête dès la fermeture. Dans le Moniteur d'activité, un processus « Web Content » disparaît.
- [ ] Aperçu ouvert : ⌘T ou ⌘L le ferment et ouvrent la barre de commande. ⌃2 ou un glissement de Space le ferment.
- [ ] Maj+clic sur un lien `download` ou sur une entrée du sommaire de Wikipédia : comportement habituel, pas d'aperçu. ⌥⇧-clic : navigation normale.
- [ ] Clic du milieu (molette) sur un lien : onglet en arrière-plan (avant, la page changeait dans l'onglet).
- [ ] Réglages > Général : l'option « Ouvrir dans un aperçu les liens des favoris et des onglets épinglés vers d'autres sites » est décochée par défaut ; un clic sur un lien d'un épinglé garde alors son comportement habituel. Coche-la : dans un épinglé ou un favori, un lien vers un autre site s'ouvre en aperçu ; un lien du même site (ou d'un sous-domaine) reste dans l'onglet. Gmail : les liens des messages ouvrent un onglet, comme avant (redirection par google.com). Un onglet du jour n'est pas concerné. Décoche-la : plus d'aperçu automatique.
- [ ] Split de deux pages : Maj+clic dans le panneau qui n'est pas actif : il devient actif, les deux pages s'assombrissent (pas les barres d'adresse au-dessus des pages, ni l'intervalle entre les cartes) et le panneau se place au milieu des deux. « Ouvrir en onglet » : la page s'affiche seule, rangée juste sous le split dans la barre ; le split reste entier.
- [ ] Space d'un autre profil : l'aperçu est connecté au même compte que l'onglet d'origine.
- [ ] Barre latérale masquée (⌘S, puis survol du bord : la barre flottante reste claire et cliquable), barre d'adresse au-dessus de la page (elle reste claire et un clic sur la pastille ouvre la barre de commande), petite fenêtre (700 × 450), « Réduire les animations » (simple fondu) : l'aperçu tient dans la page et reste utilisable.
- [ ] VoiceOver : le panneau est annoncé « Aperçu » ; « Ouvrir en onglet » et « Fermer l'aperçu » sont lus.
- Connu : la page derrière est assombrie, pas floutée. L'aperçu n'est pas gardé quand tu quittes Matcha.

### 4.5 Mini-fenêtre

- [ ] Finder au premier plan, ⌥⌘N : une mini-fenêtre d'environ 520 × 680, aux couleurs du Space affiché, apparaît au centre de l'écran du pointeur ; tu tapes tout de suite, sans cliquer. La grande fenêtre de Matcha ne passe pas devant le Finder. « météo », Entrée : la recherche s'affiche dans la mini-fenêtre ; avec les suggestions activées, elles apparaissent sous le champ.
- [ ] Barre : ×, ← (après une 2ᵉ page), domaine (un clic = ⌘L, adresse sélectionnée, ligne « Copier l'URL »), « Ouvrir dans Perso ». Clique les boutons tout en haut de la barre : ils répondent (sinon, dis-le-moi). Glisse la zone vide de la barre : la fenêtre bouge. Redimensionne-la : la suivante reprend cette taille.
- [ ] ⌥⌘N trois fois : trois fenêtres décalées ; ⌘W et × ferment chacune, sans toucher aux onglets. Une mini-fenêtre vide se ferme avec Échap. Dans une page, Échap ne ferme jamais la mini-fenêtre.
- [ ] Clic sur la fenêtre du navigateur : la mini-fenêtre reste devant. Clic sur une autre app : elle passe derrière cette app, mais pas derrière la fenêtre du navigateur ; retour à Matcha : elle repasse devant.
- [ ] Connecte-toi à un site, va sur une 2ᵉ page, lance une vidéo, puis « Ouvrir dans … » (ou ⌘O) : la page arrive en tête des onglets du jour, sélectionnée, sans rechargement (vidéo qui continue, toujours connecté) ; Précédent ramène à la 1ʳᵉ page.
- [ ] Deux profils : ouvre une mini-fenêtre depuis un Space du 2ᵉ profil, puis affiche un Space du 1ᵉʳ : le bouton nomme un Space du 2ᵉ profil, et l'ouverture y ramène la fenêtre principale avec la page connectée.
- [ ] Fenêtre principale fermée (⇧⌘W) : ⌥⌘N, une page, ⌘O : la fenêtre revient sur le bon Space avec l'onglet. Puis, fenêtre fermée et une mini-fenêtre ouverte : clic sur l'icône du Dock ; la fenêtre principale revient-elle ? (Sinon : menu Fenêtre, et dis-le-moi.)
- [ ] « Se connecter avec Google » dans une mini-fenêtre : la fenêtre de connexion s'ouvre dans une petite fenêtre au-dessus de la mini-fenêtre (tâche 5.8) et se ferme d'elle-même. ⌘-clic sur un lien : un onglet arrive en arrière-plan dans le Space, sans que la fenêtre principale passe devant. Maj+clic : le lien s'ouvre dans la mini-fenêtre (pas d'aperçu). Un lien `mailto:` ouvre Mail.
- [ ] Dans une mini-fenêtre : ⌘T, ⌘L, ⌘R, ⌘[, ⌘], ⌘O, ⌘W (titre « Fermer la mini-fenêtre » dans le menu Fichier), ⇧⌘W, et ⇧⌘C avec la confirmation « URL copiée » en bas de la mini-fenêtre.
- [ ] Safari en plein écran, ⌥⌘N : la mini-fenêtre apparaît par-dessus, sur le même bureau. Fenêtre de Matcha sur le bureau 1, toi sur le bureau 2 dans une autre app : ⌥⌘N l'ouvre sur le bureau 2, sans changer de bureau. Pareil avec Stage Manager. Deux écrans : elle s'ouvre sur l'écran du pointeur.
- [ ] Fenêtre privée au premier plan, ⌥⌘N : la mini-fenêtre n'est pas privée (tes cookies habituels) et sa page va dans la fenêtre principale.
- [ ] Réglages > Général : « Raccourci de la mini-fenêtre » affiche ⌥⌘N. Enregistre ⌃⌥M et essaie-le depuis une autre app ; ⌘T est refusé ; efface-le (ⓧ) : plus de raccourci, mais Fichier > Nouvelle mini-fenêtre marche toujours. Remets ⌥⌘N.
- [ ] Menu Fenêtre et ⌘` : la mini-fenêtre y figure sous le titre de sa page ; Mission Control la montre.
- [ ] Quitter avec des mini-fenêtres ouvertes : l'alerte s'affiche au-dessus, et rien ne revient au lancement suivant. Supprimer un profil ferme ses mini-fenêtres.
- [ ] VoiceOver : « Fermer la mini-fenêtre », « Précédent », « Adresse », « Ouvrir dans le Space » avec le nom du Space.
- Connu : tant que Matcha tourne, ⌥⌘N ne marche plus dans le Finder (« Nouveau dossier intelligent »), Mail ni Xcode ; si Arc est ouvert, il reçoit aussi ⌥⌘N. ⌘S, Spaces et Accueil ne font rien dans une mini-fenêtre. Les fenêtres de connexion ignorent la taille demandée (5.8).

### 4.6 Copier l'URL

- [ ] Sur une page, ⌘⇧C : une petite capsule « URL copiée » (icône de lien) apparaît en fondu, centrée en bas de la page, reste environ 1,5 s puis disparaît en fondu. Colle dans une autre app (Notes, TextEdit) : c'est bien l'adresse complète de la page.
- [ ] Appuie plusieurs fois sur ⌘⇧C pendant que la capsule est visible : elle reste affichée sans clignoter et ne disparaît qu'environ 1,5 s après le dernier appui.
- [ ] Menu Édition : « Copier l'URL » (⇧⌘C) se trouve juste après le groupe Couper, Copier, Coller… ; il est grisé sans onglet ou sur un onglet vide (⌘T puis Entrée), et ⌘⇧C n'y affiche rien.
- [ ] ⌘L, puis la ligne « Copier l'URL » de la barre de commande (clic, ou ↓ puis Entrée) : la barre se ferme, la même capsule apparaît, l'adresse est copiée.
- [ ] Clic droit sur un onglet de la barre latérale (et sur un favori) > « Copier le lien » : même capsule, avec l'adresse de cet onglet, même s'il n'est pas l'onglet affiché.
- [ ] Pendant que la capsule est visible, clique ou fais défiler la page juste dessous : le clic atteint la page, le clavier reste où il était (un champ de la page garde la saisie).
- [ ] Aspect en clair, en sombre et dans une fenêtre privée (⇧⌘N) : capsule floutée, lisible, discrète ; avec la barre d'adresse au-dessus de la page (Réglages > Apparence), elle reste en bas et ne gêne rien.
- [ ] Facultatif, VoiceOver (⌘F5) : chaque copie annonce « URL copiée ».

### 4.8 Raccourcis supplémentaires

- [ ] Prépare deux favoris, trois épinglés (dont un dans un dossier déplié) et quelques onglets du jour. ⌘1 et ⌘2 affichent les favoris, ⌘3 à ⌘5 les épinglés dans l'ordre de la barre, du haut vers le bas. Un épinglé déchargé se recharge sur son adresse d'origine. ⌘ suivi d'un chiffre sans favori ni épinglé à ce rang ne fait rien (même s'il reste des onglets du jour).
- [ ] ⌘9 affiche le dernier onglet du jour ; sans onglet du jour (« Effacer »), le dernier épinglé.
- [ ] ⌃⇥ passe à l'onglet suivant dans l'ordre de la barre : favoris, épinglés, onglets du jour, puis retour au premier favori. ⌃⇧⇥ fait le chemin inverse, et du premier favori revient au dernier onglet du jour. Garde ⌃ enfoncé et appuie plusieurs fois sur ⇥ : chaque appui avance d'un onglet, sans saut ni clignotement.
- [ ] Replie le dossier : ⌘3… ne comptent plus ses onglets et ⌃⇥ les saute. Déplie-le : ils reviennent.
- [ ] Split de deux pages : ⌃⇥ va d'un panneau à l'autre (la bordure du panneau actif et la pastille d'adresse suivent), puis à la ligne suivante. Un split épinglé numéroté par ⌘ revient sur le panneau que tu avais quitté.
- [ ] Le clavier suit : après ⌃⇥ ou ⌘2, les flèches font défiler la nouvelle page ; dans un champ de la page (recherche, formulaire), ⌃⇥ change quand même d'onglet. Le nom d'un dossier en cours de saisie est validé.
- [ ] Barre de commande ouverte (⌘T ou ⌘L) : ⌘1 ou ⌃⇥ la ferment et affichent l'onglet. Aperçu ouvert (Maj+clic) : ⌃⇥ le ferme et passe à l'onglet suivant ; le raccourci ⌘ de l'onglet affiché ferme l'aperçu et rend le clavier à la page.
- [ ] Menu Onglets (après Spaces) : « Afficher l'onglet suivant » (⌃⇥), « Afficher l'onglet précédent » (⌃⇧⇥), puis les favoris et épinglés numérotés sous leur titre (⌘1…⌘8, un split sous les titres de ses panneaux), puis « Afficher le dernier onglet » (⌘9). Les titres suivent les changements (nouveau favori, onglet renommé par sa page). Sans onglet, tout est grisé.
- [ ] Mini-fenêtre active, puis fenêtre des Réglages : ⌃⇥, ⌘1 et ⌘9 ne changent rien dans la fenêtre de navigation ; le menu Onglets est grisé. Dans une fenêtre privée, ils parcourent ses propres onglets. ⌃1 et ⌃2 changent toujours de Space.
- [ ] Sur un site qui utilise ⌃⇥ ou ⌘1 pour lui-même (éditeur en ligne, Google Docs…), le site garde la main, comme dans Safari ; sinon, dis-le-moi.

## Phase 5

### 5.1 Téléchargements

Les tests d'interface écrivent dans ~/Downloads/MatchaUITests, que l'app efface ensuite ; à la première lecture du dossier, macOS peut te demander d'autoriser « MatchaUITests-Runner » à accéder à Téléchargements : accepte.

- [ ] Au lancement, sans aucun téléchargement : le bouton flèche est déjà là, à gauche dans le pied de la barre (aussi dans une fenêtre privée, ⇧⌘N), et rien ne s'ouvre. Un clic : le panneau monte, « Aucun téléchargement » et « Afficher le dossier Téléchargements », « Effacer » grisé. Ce bouton ouvre ton vrai dossier Téléchargements dans le Finder. La croix ou un nouveau clic sur la flèche ferment le panneau.
- [ ] Menu Présentation : « Afficher les téléchargements ⌥⌘L », sous « Masquer la barre latérale ». ⌥⌘L ouvre le panneau et le titre devient « Masquer les téléchargements » ; ⌥⌘L le referme. Barre masquée (⌘S), pointeur loin du bord : ⌥⌘L réaffiche la barre et ouvre le panneau dedans. Dans une fenêtre privée, ⌥⌘L ouvre son panneau à elle. Grisé quand les Réglages (⌘,), l'historique (⌘Y) ou une mini-fenêtre sont au premier plan. Sur une page qui utiliserait ⌥⌘L pour elle-même, note qui gagne.
- [ ] Gros téléchargement réel (par exemple l'image disque d'une app d'une centaine de Mo) : le bouton flèche, à gauche dans le pied de la barre, s'entoure d'un anneau qui se remplit ; rien ne s'ouvre de soi-même, ni la liste ni le fichier. Ouvre la liste pendant le téléchargement : barre de progression et « 12 Mo sur 140 Mo » qui avancent, bouton ⓧ pour annuler. À la fin, la flèche rebondit une fois, la ligne montre la taille et une loupe (« Afficher dans le Finder »).
- [ ] Lien vers un PDF : il s'affiche dans la page, rien n'est téléchargé. Lien vers un .zip : il est téléchargé, la page reste affichée.
- [ ] Pièce jointe (`Content-Disposition: attachment`), par exemple un fichier d'une release GitHub (« Assets » d'une release) ou le bouton « Download ZIP » d'un dépôt : téléchargée sous le nom donné par le serveur, même si c'est un type que WebKit sait afficher.
- [ ] Le même fichier deux fois : « nom.zip » puis « nom 2.zip » dans Téléchargements, le plus récent en tête de la liste ; aucun fichier n'est écrasé. Une archive « .tar.gz » devient « archive 2.tar.gz ».
- [ ] Annuler pendant un gros téléchargement : la ligne passe à « Annulé », et aucun fichier partiel ne reste dans Téléchargements.
- [ ] « Afficher dans le Finder » : une fenêtre du Finder s'ouvre sur Téléchargements, le fichier sélectionné. Double-clic sur une ligne terminée : le fichier s'ouvre dans son app ; sur une ligne en cours, annulée ou en échec, rien ne se passe.
- [ ] « Effacer » retire les lignes terminées, en échec ou annulées (pas celles en cours) ; les fichiers restent dans Téléchargements. Plus rien dans la liste : le panneau reste ouvert sur « Aucun téléchargement », « Effacer » se grise, le bouton flèche reste.
- [ ] Quarantaine : télécharge une app ou une image disque (.dmg) d'un éditeur, puis ouvre-la depuis le Finder : macOS demande confirmation (Gatekeeper). Dans le Terminal, `xattr -p com.apple.quarantine ~/Downloads/<fichier>` affiche une valeur qui contient « Matcha ».
- [ ] Fenêtre privée (⇧⌘N) : un téléchargement apparaît dans le panneau de la fenêtre privée, pas dans celui de la fenêtre principale (« Aucun téléchargement »). Ferme la fenêtre privée : le fichier reste dans Téléchargements, mais la liste l'oublie (rouvre une fenêtre privée : son panneau est vide). Un téléchargement privé encore en cours à la fermeture est annulé.
- [ ] Mini-fenêtre : un téléchargement lancé depuis sa page apparaît dans la liste de la fenêtre principale ; la mini-fenêtre reste sur sa page.
- [ ] Barre latérale masquée (⌘S) : survole le bord gauche, clique le bouton des téléchargements : le panneau monte dans la barre flottante. Éloigne le pointeur : la barre se cache, panneau compris ; reviens au bord : elle réapparaît avec le panneau toujours ouvert. La croix le ferme.
- [ ] Aperçu (Maj+clic sur un lien) : un lien de téléchargement dans l'aperçu télécharge le fichier, l'aperçu reste ouvert.
- [ ] Quitter Matcha pendant un téléchargement : aucun fichier partiel ne reste dans Téléchargements ; au lancement suivant, la ligne est là, « Échec » en rouge, et son info-bulle dit « Matcha a été quitté avant la fin du téléchargement. ».
- [ ] Liste retenue : télécharge deux fichiers, quitte Matcha (⌘Q) et relance-le : le bouton ne rebondit pas, et le panneau (⌥⌘L) montre les deux lignes, la plus récente en tête, avec leur taille ; « Afficher dans le Finder » et le double-clic marchent. Mets l'un des fichiers à la corbeille puis rouvre le panneau : sa ligne dit « Fichier introuvable », sans bouton, et le double-clic ne fait rien. « Effacer », quitte et relance : la liste reste vide.
- [ ] Fenêtre privée : un téléchargement fait dans une fenêtre privée ne revient jamais au lancement suivant (ni dans la fenêtre principale).
- [ ] Aspect en clair, en sombre et en fenêtre privée : anneau lisible, panneau lisible (titre, « Effacer », croix, trait de séparation, panneau vide), icônes des fichiers (celle de l'app pour une app). Barre au plus étroit avec plusieurs Spaces : note à partir de combien de Spaces leurs icônes touchent le bouton flèche (calcul : cinq, comme déjà pour le bouton +).
- [ ] Facultatif, VoiceOver : « Téléchargements » sur le bouton, nom du fichier et état sur chaque ligne, « Annuler », « Afficher dans le Finder », « Effacer », « Aucun téléchargement », « Afficher le dossier Téléchargements ».
- Connu : un lien `target=_blank` vers un fichier laisse un onglet vide après le téléchargement (Safari le ferme) ; ferme-le à la main. Pas de reprise d'un téléchargement interrompu.
- [ ] Ouvre le panneau des téléchargements pendant qu'un gros fichier arrive, et laisse-le ouvert jusqu'à la fin : il reste ouvert, la ligne passe à « terminé » et la flèche du bouton rebondit une fois. Change de Space : le panneau reste ouvert.

### 5.2 Permissions par site

Pour la caméra et le micro : https://webcamtests.com (bouton « Test my cam »), https://mictests.com (micro seul), ou Google Meet (« Nouvelle réunion » > « Démarrer une réunion instantanée » : caméra et micro ensemble). Les tests d'interface des réglages du site ouvrent https://example.com ; sans réseau, ils sont ignorés.

- [ ] Sur webcamtests.com, « Test my cam » : un bandeau descend en haut de la page et la pousse vers le bas (il ne la couvre pas) : « webcamtests.com souhaite utiliser votre caméra. », avec « Refuser », « Autoriser une fois », « Toujours autoriser ». Attends une minute sans répondre : le bandeau reste et la page attend (rien n'est accordé ni refusé tout seul).
- [ ] La première fois que la caméra (puis le micro) sert, macOS affiche sa propre demande (« “Matcha” souhaite accéder à la caméra »), avant ou après le bandeau de Matcha : accepte-la ; elle ne revient plus ensuite (Réglages Système > Confidentialité et sécurité > Caméra, et Micro : Matcha y est coché). Note dans quel ordre les deux demandes sont apparues. Si tu refuses celle de macOS, la page n'a pas la caméra, même autorisée dans Matcha.
- [ ] « Autoriser une fois » : la caméra s'allume. Recharge (⌘R) et relance le test : le bandeau revient.
- [ ] « Toujours autoriser » : la caméra s'allume. Recharge, puis quitte et relance Matcha et refais le test : plus de bandeau, la caméra s'allume directement.
- [ ] « Refuser » (sur mictests.com, par exemple) : la page affiche son erreur. Recharge et refais le test : refusé aussitôt, sans bandeau.
- [ ] Google Meet : un seul bandeau « … votre caméra et votre micro ». Si la caméra est déjà autorisée pour ce site et le micro pas encore, le bandeau ne parle que du micro.
- [ ] Bouton des réglages du site (deux interrupteurs) à droite de la pastille d'adresse : présent sur un site web, absent sur un onglet vide. Un clic : le panneau glisse sous la pastille et pousse les favoris et les onglets ; en tête l'icône et le nom du site, puis Caméra et Micro sur « Demander », « Autoriser » ou « Refuser » selon tes réponses, puis « Cookies et données du site » et « Effacer… ». Change Caméra sur un site testé, recharge : le site suit ton choix. La croix ou le bouton le ferment ; rien d'autre ne l'ouvre ni ne le ferme. Panneau ouvert, change d'onglet : il montre le site du nouvel onglet ; sur un onglet vide : « Cette page n'a pas de réglages de site. » ; change de Space : il reste ouvert.
- [ ] Barre d'adresse au-dessus de la page (Réglages > Apparence) : même bouton à droite de l'adresse ; le panneau s'ouvre en haut de la carte, sous la barre d'adresse. Split de deux pages : le bouton de l'autre panneau le rend actif et y ouvre le panneau.
- [ ] Connecte-toi à deux sites dans deux onglets. Sur le premier : réglages du site > « Effacer… » : une alerte demande confirmation ; « Annuler » ne change rien. « Effacer » : la page se recharge et tu es déconnecté de ce site seulement ; l'autre site reste connecté. Sur mail.google.com, tout Google est concerné (google.com et ses sous-domaines), pas YouTube.
- [ ] Réglages > Confidentialité > « Autorisations des sites » : chaque décision retenue (site, Caméra ou Micro, Autorisé ou Refusé) avec une corbeille ; la corbeille l'oublie et le site redemande. Avec plusieurs décisions (plus de sept), la liste défile sans agrandir la fenêtre. Avec deux profils, le nom du profil s'affiche sous le site. Le panneau d'un site ouvert suit (il repasse à « Demander »).
- [ ] Deux profils : « Toujours autoriser » dans un Space du premier ne vaut pas dans un Space du second (le bandeau y revient).
- [ ] Fenêtre privée (⇧⌘N) : même bandeau ; « Toujours autoriser » vaut jusqu'à la fermeture de la fenêtre. Ferme-la, rouvres-en une : le site redemande. Rien n'apparaît dans Réglages > Confidentialité, et la fenêtre principale n'a pas cette décision.
- [ ] Aperçu (Maj+clic sur un lien vers webcamtests.com, puis « Test my cam ») : le bandeau s'affiche en haut de l'aperçu. Ferme l'aperçu sans répondre : rien ne reste. Mini-fenêtre (⌥⌘N, puis webcamtests.com) : bandeau en haut de sa page ; « Toujours autoriser » y vaut ensuite pour ce site dans les onglets du même profil.
- [ ] Bandeau en attente : change d'onglet et reviens, il est toujours là. Va sur une autre page dans cet onglet, ou ferme-le, sans répondre : plus de bandeau, la demande est refusée (aucun plantage).
- [ ] Carte étroite (split de trois ou quatre pages, fenêtre de 700 × 450) : le texte du bandeau passe à la ligne et les boutons vont dessous, en colonne si besoin ; rien n'est coupé.
- [ ] Localisation : sur une page qui demande ta position (https://browserleaks.com/geo, ou « Ma position » dans Google Maps), aucun bandeau ; note ce que la page affiche (refus, position indisponible…). Notifications : sur https://www.bennish.net/web-notifications.html, aucun bandeau ; note ce que la page affiche. Les deux sont reportés (`DECISIONS.md`).
- [ ] Partage d'écran dans Meet : note ce qui se passe (WebKit ne passe pas par Matcha pour l'écran).
- [ ] Aspect en clair, en sombre et en fenêtre privée : bandeau et panneau lisibles. Facultatif, VoiceOver : « Demande d'autorisation », le texte du bandeau et ses trois boutons ; « Réglages du site » sur le bouton, « Fermer les réglages du site » sur la croix.
- Connu : « Autoriser une fois » vaut pour la page affichée jusqu'à son rechargement (WebKit garde l'accord le temps de la page). Un onglet en arrière-plan qui demande la caméra attend que tu l'affiches : rien ne le signale dans la barre latérale. Pas de réglages du site dans l'aperçu ni dans une mini-fenêtre.

### 5.3 Recherche dans la page

Une page longue : un article de Wikipédia (https://fr.wikipedia.org/wiki/Paris) ou, sans réseau, file:///usr/share/doc/postfix/html/postconf.5.html. Les tests d'interface utilisent la documentation de Postfix ; sans elle, ils sont ignorés.

- [ ] ⌘F : une barre descend en haut de la page et la pousse vers le bas (sans la couvrir) : loupe, champ « Rechercher dans la page », flèches ⌃ et ⌄, ×. Le champ a le clavier tout de suite : tape sans cliquer.
- [ ] Tape un mot présent plusieurs fois : à mesure que tu tapes (léger délai), l'occurrence est sélectionnée et la page défile jusqu'à elle ; en ajoutant des lettres, la sélection reste sur le même mot tant qu'il correspond. Note si la sélection (grise tant que le champ a le clavier) se voit assez. Pas de nombre d'occurrences : l'API publique ne le donne pas.
- [ ] ⏎, ⌘G ou ⌄ : occurrence suivante ; ⇧⏎, ⇧⌘G ou ⌃ : précédente. Après la dernière, ⏎ revient à la première ; depuis la première, ⇧⏎ va à la dernière. Les majuscules ne comptent pas (« PARIS » trouve « Paris »).
- [ ] Un texte absent (« zzqqxx ») : « Introuvable » au bout du champ ; efface le champ : le mot disparaît.
- [ ] Accents : « ete » et « éte » trouvent « été », « cafe » trouve « café », mais « café » ne trouve pas « cafe » (WebKit : une lettre sans accent trouve aussi les lettres accentuées, pas l'inverse). Note si c'est gênant.
- [ ] ⎋ dans le champ : la barre se ferme, l'occurrence est désélectionnée et la page a le clavier (Espace ou ↓ la font défiler). Le × fait pareil. ⌘F la rouvre avec le dernier texte, tout sélectionné. Barre ouverte, clique dans la page puis ⌘F : le champ reprend le clavier, texte sélectionné.
- [ ] Barre fermée, ⌘G : elle se rouvre avec le dernier texte et cherche (depuis le haut de la page) ; le clavier reste dans la page.
- [ ] Barre ouverte, change d'onglet : elle disparaît. Reviens : elle est là avec son texte, sans reprendre le clavier. Va sur une autre page dans cet onglet : la barre reste, « Introuvable » disparaît. Sur un onglet vide, ⌘F ne fait rien.
- [ ] Menu Édition > Rechercher : « Rechercher… ⌘F », « Rechercher le suivant ⌘G », « Rechercher le précédent ⇧⌘G », chacun une seule fois dans le menu Édition. Suivant et précédent grisés tant que rien n'a été cherché dans la page ; tout est grisé sur un onglet vide et quand les Réglages (⌘,) sont au premier plan.
- [ ] Barre de commande ouverte (⌘T ou ⌘L), ⌘F : elle se ferme et la barre de recherche prend le clavier.
- [ ] Split de deux pages : ⌘F n'ouvre la barre que sur le panneau actif. Rends l'autre actif, ⌘F : chaque panneau a sa barre. Un clic dans le champ ou sur une flèche d'un panneau le rend actif (bordure) ; ⎋ rend le clavier à la page de ce panneau.
- [ ] Aperçu (Maj+clic sur un lien) : ⌘F ouvre la barre en haut de l'aperçu, pas de la carte derrière ; ⎋ ferme la barre et laisse l'aperçu ; un second ⎋ ferme l'aperçu. Barre ouverte, « Ouvrir en onglet » : la barre suit la page dans la carte.
- [ ] Mini-fenêtre (⌥⌘N, puis une page) : ⌘F, ⌘G et ⎋ agissent sur sa page ; la fenêtre derrière n'est pas touchée, et ⎋ dans le champ ne ferme pas la mini-fenêtre. Mini-fenêtre vide : ⌘F ne fait rien.
- [ ] Fenêtre privée (⇧⌘N) : même barre, mêmes raccourcis.
- [ ] Barre d'adresse au-dessus de la page (Réglages > Apparence) : la barre de recherche s'ouvre sous la barre d'adresse, et sous le panneau des réglages du site s'il est ouvert. Barre latérale masquée (⌘S) : la barre est en haut de la carte, rien ne déborde.
- [ ] Barre ouverte, déclenche un bandeau de permission (webcamtests.com, « Test my cam ») : le bandeau s'affiche sous la barre de recherche, qui ne bouge pas.
- [ ] Méthode de saisie japonaise (Romaji) dans le champ : tape « nihon », Espace pour convertir, ⏎ pour valider : ⏎ valide la composition sans passer à l'occurrence suivante ; ⎋ pendant une composition l'annule sans fermer la barre ; rien n'est cherché avant la validation. Sur https://ja.wikipedia.org, le mot validé est trouvé. Touche morte (⌥E puis e → « é ») : pareil.
- [ ] Une page qui garde ⌘F pour elle (Google Docs) : sa propre recherche s'ouvre, pas la barre de Matcha (comme dans Safari).
- [ ] Carte étroite (split de quatre pages, fenêtre de 700 × 450) : note si la barre reste utilisable ou si le × est coupé.
- [ ] Aspect en clair, en sombre et en fenêtre privée. Facultatif, VoiceOver : « Rechercher dans la page » sur la barre et le champ, « Occurrence précédente », « Occurrence suivante », « Fermer la recherche » ; « Introuvable » est annoncé.
- Connu : ni nombre d'occurrences ni surlignage de toutes les occurrences (API privées) ; une occurrence trouvée dans un cadre intégré reste sélectionnée après la fermeture ; ⌘G après la fermeture repart du haut de la page.

### 5.4 Impression, PDF, zoom

Une page longue : un article de Wikipédia (https://fr.wikipedia.org/wiki/Paris) ou, sans réseau, file:///usr/share/doc/postfix/html/postconf.5.html. Les tests d'interface utilisent la documentation de Postfix (zoom, ⌘P et « Exporter au format PDF… » refermés par ⎋) ; la ligne « Zoom » des réglages du site passe par example.com (réseau).

- [ ] ⌘P : la zone d'impression de macOS s'ouvre en feuille sur la fenêtre. L'aperçu montre la page, **pas des pages blanches**, sur plusieurs pages pour une page longue ; format, orientation et échelle sont réglables. « PDF » > « Enregistrer au format PDF » propose le titre de la page comme nom ; le fichier contient le texte (sélectionnable dans Aperçu). ⎋ ou « Annuler » ferme sans rien imprimer.
- [ ] Arrière-plans : imprime une page à fond coloré (https://www.apple.com) : par défaut, les couleurs et images de fond ne sont pas imprimées (comme la case décochée de Safari). Note si c'est gênant : pas de case pour les imprimer pour l'instant.
- [ ] Fichier > « Exporter au format PDF… » : la zone d'enregistrement s'ouvre en feuille, nom = titre de la page + « .pdf » (essaie une page dont le titre contient « / » ou « : » : ils deviennent « - »). Enregistre sur le Bureau puis ouvre le fichier : **toute** la page, d'un seul tenant (une seule feuille très haute), pas seulement la partie visible. Enregistre une seconde fois au même nom : macOS demande de remplacer, puis le fichier est remplacé. « Annuler » ne crée rien. Si tu as une clé USB ou un autre volume, enregistre aussi dessus.
- [ ] Menus : Fichier > « Exporter au format PDF… » et « Imprimer… ⌘P », une seule fois chacun ; Présentation > « Taille réelle ⌘0 », « Zoom avant ⌘+ », « Zoom arrière ⌘- » sous « Recharger la page ». Tout est grisé sur un onglet vide et quand les Réglages (⌘,) sont au premier plan ; « Taille réelle » est grisé à 100 %, « Zoom avant » à 300 %, « Zoom arrière » à 50 %.
- [ ] Zoom : à 100 %, rien à côté de la pastille d'adresse. ⌘+ deux fois : le texte et la mise en page grandissent (pas une simple loupe) ; un badge « 115 % » apparaît en fondu juste à droite de la pastille d'adresse (avant le bouton des réglages du site), la pastille se resserre en douceur, puis il passe à « 125 % » (les chiffres défilent, petite pulsation) et **reste affiché**. ⌘= fait comme ⌘+ (sans Maj). ⌘- : 115 %. ⌘0 : 100 %, le badge disparaît en fondu. Rien d'autre ne s'ouvre. Clique d'abord dans la barre latérale (pas dans la page) puis ⌘+ et ⌘= : ça marche aussi.
- [ ] Clic sur le badge (bulle « Taille réelle » au survol, fond un peu plus marqué) : le site revient à 100 %, comme ⌘0 (ses autres onglets aussi), le badge disparaît ; la barre de commande ne s'ouvre pas. Clique d'abord dans un champ de la page (la recherche de Wikipédia), ⌘+, puis clique le badge : tape du texte, il va toujours dans le champ (le badge ne prend pas le clavier).
- [ ] Le badge suit l'onglet affiché : passe d'un onglet zoomé à un onglet à 100 % et retour, il disparaît puis revient avec le bon pourcentage. Une page sans site (about:blank) zoomée a aussi son badge.
- [ ] Mémorisé par site : zoome une page à 125 %, puis suis un lien vers une autre page du même site : elle s'ouvre à 125 %. ⌘R : toujours 125 %. Un autre onglet du même site (même un sous-domaine : docs.github.com et github.com) prend aussitôt le même zoom quand tu changes celui de la première. Un autre site reste à 100 %. Quitte Matcha et relance-le : le site est toujours à 125 %. ⌘0 : le site est oublié.
- [ ] Split de deux pages du même site : ⌘+ zoome le panneau actif, et l'autre suit. Deux sites différents : seul le panneau actif change ; le badge de la barre latérale est celui du panneau actif. Avec la barre d'adresse au-dessus des pages (Réglages > Apparence), chaque carte a le badge de sa page ; un clic sur celui d'un autre panneau le rend actif et ramène son site à 100 %.
- [ ] Fenêtre privée (⇧⌘N) : un site zoomé dans la fenêtre normale s'y ouvre à 100 % ; ⌘+ y marche ; ferme la fenêtre privée, rouvre-en une : le zoom n'est pas resté ; la fenêtre normale n'a pas changé.
- [ ] Aperçu (Maj+clic sur un lien) : ⌘+ zoome la page de l'aperçu ; un badge « 115 % » apparaît dans la barre flottante de l'aperçu, à droite de son adresse (fond flouté comme elle, lisible sur le voile). La page derrière, si elle est du même site, suit, et la barre latérale montre son badge à elle (rien si elle est d'un autre site). Un clic sur le badge de l'aperçu ramène le site à 100 % sans fermer l'aperçu. « Ouvrir en onglet » garde le zoom et le badge.
- [ ] Mini-fenêtre (⌥⌘N, puis une page) : ⌘+, ⌘-, ⌘0 agissent sur sa page, avec le badge dans la barre de la mini-fenêtre, à droite de son adresse ; un clic dessus revient à 100 %. La fenêtre derrière ne change pas (sauf ses onglets du même site, qui suivent). Le zoom est retenu pour le site (rouvre-le dans un onglet). ⌘P et « Exporter au format PDF… » s'ouvrent en feuille sur la mini-fenêtre.
- [ ] Réglages du site (bouton à droite de l'adresse) : ligne « Zoom » entre Micro et « Cookies et données du site » : −, « 100 % », +. + et − changent la page aussitôt, et le badge suit ; ⌘+ au clavier met la ligne à jour ; un clic sur le pourcentage revient à 100 %. Même chose avec la barre d'adresse au-dessus de la page.
- [ ] Le zoom par pincement du trackpad reste indépendant (il agrandit l'image, n'est pas retenu, ⌘0 ne le défait pas).
- [ ] Une page qui garde ⌘+ ou ⌘- pour elle (Google Maps, Figma) : son propre zoom, comme dans Safari. Note si ⌘= lui échappe (il passe au menu avant la page).
- [ ] Aspect du badge (barre latérale, barre au-dessus de la page, aperçu, mini-fenêtre) en clair, en sombre et en fenêtre privée : lisible, discret, aligné sur la pastille ; une barre latérale étroite tronque l'adresse, jamais le badge. Réglages Système > Accessibilité > Affichage > « Réduire les animations » : plus de pulsation ni de chiffres qui défilent, seulement des fondus. Facultatif, VoiceOver : « Zoom de la page : 125 % » est annoncé à chaque ⌘+, ⌘-, ⌘0 et au clic sur le badge ; le badge se lit « Zoom de la page, 125 %, bouton » ; dans les réglages du site, les boutons s'annoncent « Zoom arrière », « Taille réelle, 125 % », « Zoom avant ».
- [ ] La capsule « URL copiée » (⇧⌘C, tâche 4.6) est inchangée : même place, même durée ; aucune capsule n'apparaît plus pour le zoom.
- Connu : pas de case « Imprimer les arrière-plans » ; l'export en PDF fait une seule feuille de toute la page (pour des pages A4 : « Imprimer… » puis « PDF ») ; le zoom d'un site est commun à tous les profils.

### 5.5 Historique

Des pages avec et sans réseau : la documentation de Postfix (file:///usr/share/doc/postfix/html/index.html, puis le lien « Basic configuration »), un site classique (https://fr.wikipedia.org/wiki/Paris), une application web qui change d'adresse sans recharger (YouTube : passe d'une vidéo à l'autre ; GitHub : parcours les fichiers d'un dépôt). Les tests d'interface utilisent la documentation de Postfix ; sans elle, ils sont ignorés.

- [ ] Au lancement, aucune fenêtre d'historique ne s'ouvre, même si elle était ouverte quand tu as quitté Matcha. Le menu Fenêtre n'a pas d'élément « Historique » en plus.
- [ ] Menu Historique : « Accueil », « Précédent », « Suivant », puis « Afficher tout l'historique ⌘Y ». ⌘Y ouvre la fenêtre « Historique » ; ⌘Y à nouveau la ramène devant (une seule fenêtre) ; ⌘W la ferme.
- [ ] Visite quelques pages, puis ⌘Y : une section « Aujourd'hui », la page la plus récente en tête ; chaque ligne montre l'icône du site, le titre, le domaine (le nom du fichier pour une page locale) et l'heure. Une page visitée hier (ou un autre jour) est sous « Hier » (ou sa date complète, « vendredi 16 octobre 2026 »). Une même page visitée plusieurs fois dans la journée n'a qu'une ligne, à l'heure de la dernière visite. Fenêtre ouverte, visite une autre page : elle apparaît en tête sans rien faire.
- [ ] Recharge une page (⌘R) plusieurs fois de suite : toujours une seule ligne. Les pages about:blank, une page qui n'a pas pu se charger (adresse inexistante, réseau coupé) et une ancre de la page (#section) n'ajoutent rien.
- [ ] YouTube : passe d'une vidéo à l'autre sans recharger : chaque vidéo regardée plus d'une seconde a sa ligne, avec son titre (pas celui de la vidéo précédente). Note si un titre est faux ou manque.
- [ ] Une page dont le titre change tout seul (Gmail : « Boîte de réception (3) », Slack) garde le titre de sa visite : il ne suit pas les notifications.
- [ ] Recherche (champ dans la barre d'outils de la fenêtre) : « paris », « PARIS » et « wikipedia.org » trouvent la page de Paris ; « cafe » trouve une page « Café » (accents et majuscules ignorés) ; deux mots (« postfix basic ») doivent tous deux se trouver dans le titre ou l'adresse. Un texte absent : « Aucun résultat pour “…” ». Efface le champ : tout revient.
- [ ] Double-clic sur une ligne (ou Entrée après l'avoir sélectionnée) : la page s'ouvre dans un nouvel onglet en tête des onglets du jour du Space affiché, et la fenêtre principale passe devant, la page a le clavier. Plusieurs lignes sélectionnées (⌘-clic), puis Entrée : un onglet chacune. Ferme la fenêtre principale (⇧⌘W), puis double-clic dans l'historique : elle se rouvre avec la page.
- [ ] Clic droit sur une ligne : « Ouvrir dans un nouvel onglet », « Copier le lien » (colle l'adresse dans TextEdit ; plusieurs lignes : une adresse par ligne), « Supprimer ». ⌫ supprime les lignes sélectionnées, Édition > Supprimer aussi. Supprimer une ligne ne ferme aucun onglet ; ouvre ensuite ⌘T et tape son titre : la barre ne la propose plus (si elle n'a pas d'autre jour dans l'historique).
- [ ] « Effacer l'historique… » : un dialogue demande la période, avec « La dernière heure », « Aujourd'hui », « Aujourd'hui et hier », « Tout l'historique » et « Annuler » ; « Annuler » ne change rien. Essaie « La dernière heure » : seules les pages de la dernière heure disparaissent. Puis « Tout l'historique » : la fenêtre affiche « Aucun historique ». Tes cookies sont intacts (tu es toujours connecté à tes sites).
- [ ] Barre de commande (⌘T) : tape une partie du titre ou de l'adresse d'une page visitée mais fermée : une ligne d'historique la propose (icône du site, titre, adresse) ; une page déjà ouverte dans un onglet est proposée comme onglet, pas en double. Les pages souvent visitées passent devant. Une mini-fenêtre (⌥⌘N) propose aussi l'historique.
- [ ] Mini-fenêtre : une page visitée dans une mini-fenêtre apparaît dans l'historique (fenêtre ⌘Y) et dans la barre de commande.
- [ ] Fenêtre privée (⇧⌘N) : visite une page qui n'est pas encore dans l'historique. Dans la fenêtre privée, Historique > « Afficher tout l'historique » est grisé et ⌘Y ne fait rien ; sa barre de commande ne propose aucune ligne d'historique. Ferme-la, puis ⌘Y dans la fenêtre principale : la page n'y est pas. Fenêtre de l'historique ouverte pendant ta navigation privée : rien n'y apparaît.
- [ ] Deux profils (Réglages > Profils) : visite une page dans un Space de chaque profil. ⌘Y depuis un Space du premier : seule sa page, et le nom du profil sous le titre de la fenêtre. Passe à un Space du second profil, fenêtre ouverte : la liste change. La barre de commande d'un Space ne propose que l'historique de son profil. « Effacer l'historique… » n'efface que le profil montré. Supprime le second profil : son historique disparaît avec lui.
- [ ] Quitte et relance Matcha : l'historique est toujours là, et la barre de commande le propose dès les premières frappes. Avec un historique de plusieurs semaines, la frappe reste fluide et la fenêtre s'ouvre sans attente visible ; note le contraire.
- [ ] Aspect en clair et en sombre : liste, en-têtes des jours, dialogue d'effacement lisibles ; fenêtre étroite (480 × 320) : les titres sont coupés par « … », jamais l'heure. Facultatif, VoiceOver : chaque ligne se lit « titre, domaine ».
- Connu : les visites de plus d'un an sont effacées au lancement, sans réglage ; supprimer une ligne ne supprime que les visites de ce jour-là ; pas d'effacement de l'historique dans les Réglages ni dans le menu ; une adresse changée par la page pendant que celle-ci charge encore n'est pas une visite à part.

### 5.6 Mémoire

Pour ne pas attendre 30 minutes : Réglages > Général > « Libérer la mémoire des onglets inactifs après » : 15 minutes. Pour aller plus vite encore (version Debug seulement) : `open build/Build/Products/Debug/Matcha.app --args -tabSuspensionDelaySeconds 20` (délai de 20 s, vérifié chaque seconde, quel que soit le réglage). Pour simuler une alerte mémoire : `sudo memory_pressure -S -l warn` (ou `-l critical`) dans le Terminal. Le journal : Console.app, filtre « TabLifecycle » (nombre d'onglets mis en veille, jamais d'adresse).

- [ ] Réglages > Général : le choix « Libérer la mémoire des onglets inactifs après » propose 15 minutes, 30 minutes (par défaut), 1 heure, 2 heures, Jamais, avec la note dessous ; la fenêtre des réglages s'agrandit sans barre de défilement.
- [ ] Mémoire : ouvre une vingtaine d'onglets de sites variés (presse, YouTube, GitHub, Wikipédia…), puis Moniteur d'activité > Mémoire, colonne « Mémoire », les processus « Matcha Web Content » (ou « com.apple.WebKit.WebContent ») : note le total. Reste sur un seul onglet pendant le délai réglé (+ 1 min) : le total baisse nettement, les processus des onglets cachés disparaissent.
- [ ] Dans la barre latérale, rien ne change pendant ce temps : mêmes titres, mêmes icônes, mêmes lignes, rien n'est grisé, × au survol, ordre inchangé. ⌘T et le titre d'un onglet en veille : la barre de commande le propose toujours comme onglet.
- [ ] Clique un onglet en veille : la page revient à la même adresse, au même endroit de la page (défilement), avec, pendant le rechargement, l'image de la page telle qu'elle était (pas de page blanche), qui s'efface en fondu dès la page chargée (2 s au plus). Le titre et l'icône ne clignotent pas dans la barre. Précédent (⌘[) et Suivant (⌘]) marchent comme avant la veille.
- [ ] Jamais une image d'une autre page : redimensionne nettement la fenêtre pendant qu'un onglet est en veille, puis affiche-le : pas d'image, juste le rechargement. Pendant que l'image est affichée, clique un lien ou fais défiler : tu agis sur la vraie page dessous.
- [ ] YouTube : lance une vidéo (avec le son) dans un onglet, passe sur un autre onglet et attends le délai : le son continue, l'onglet n'est jamais mis en veille. Mets la vidéo en pause, change d'onglet, attends : là, il peut se mettre en veille (en revenant, la vidéo repart du début ou de l'endroit retenu par YouTube).
- [ ] Visio (Google Meet ou https://webcamtests.com) avec la caméra et le micro (même coupés dans la page), puis un autre onglet pendant le délai : la visio continue, jamais mise en veille. Un onglet qui attend ta réponse à une demande de permission (bandeau) non plus.
- [ ] Formulaire : commence à remplir un long champ de texte (un brouillon de message, un commentaire), sans l'envoyer, passe sur un autre onglet et attends le délai. **Attendu : le texte saisi est perdu** quand l'onglet revient (la page est rechargée), comme dans Arc ; certains sites le gardent d'eux-mêmes (brouillons Gmail). Dis-moi si c'est gênant : on peut épargner les onglets où l'on a tapé du texte.
- [ ] Applications web épinglées (Gmail, Slack, WhatsApp) : en veille, elles ne se mettent plus à jour (le compteur du titre, « Boîte de réception (3) », reste figé) jusqu'à ce que tu les affiches. Dis-moi si tu préfères que les épinglés et les favoris restent chargés.
- [ ] « Jamais » : choisis-le, laisse des onglets cachés bien plus longtemps que 15 minutes, et lance aussi `sudo memory_pressure -S -l critical` : aucun ne se recharge en revenant (la page est restée telle quelle, pas d'image ni de rechargement).
- [ ] Alerte mémoire (réglage autre que « Jamais ») : avec dix onglets cachés depuis plus d'une minute, `sudo memory_pressure -S -l warn` : environ la moitié, les plus anciennement quittés, se mettent en veille (rechargés au clic, sans image) ; `-l critical` : tous les onglets cachés. L'onglet affiché et celui que tu viens de quitter (moins d'une minute, alerte simple) restent chargés.
- [ ] Épinglé : épingle un site, suis un lien dedans vers une autre page, passe sur un autre onglet et attends le délai, reviens : il est sur la page où tu l'avais laissé (pas sur son adresse d'origine), Précédent ramène à l'origine. ⌘W sur lui le ramène ensuite à son origine, comme avant.
- [ ] Favori : même chose pour un favori, aussi depuis un autre Space du même profil.
- [ ] Split : un split de deux pages affiché pendant le délai : aucun des deux panneaux ne se recharge. Un split caché (autre onglet affiché) se met en veille ; en revenant, les deux panneaux reviennent.
- [ ] Aperçu (Maj+clic) ouvert longtemps sur un onglet : ni l'aperçu ni la page derrière ne se rechargent. Mini-fenêtre (⌥⌘N) laissée ouverte derrière la fenêtre principale plus longtemps que le délai : sa page ne se recharge jamais.
- [ ] Spaces : l'onglet sélectionné d'un autre Space se met en veille après le délai ; en revenant sur ce Space, il revient comme les autres.
- [ ] Fenêtre principale fermée (⇧⌘W, Matcha reste ouvert) plus longtemps que le délai, puis rouverte : l'onglet affiché revient (rechargé), avec son historique.
- [ ] Téléchargement en cours (un gros fichier) depuis un onglet que tu quittes : il continue jusqu'au bout même si l'onglet se met en veille.
- [ ] Zoom : un site zoomé à 125 % revient à 125 % après la veille. Recherche dans la page : une barre de recherche ouverte dans un onglet mis en veille a disparu au retour (comme après un déchargement).
- [ ] Historique (⌘Y) : revenir sur un onglet en veille n'ajoute pas de visite (pas de ligne en plus, heure inchangée).
- [ ] Quitte et relance Matcha avec des onglets en veille : ils sont toujours là, à la bonne page, avec leur historique.
- [ ] Fenêtre privée (⇧⌘N) : mêmes règles ; ses onglets en veille reviennent pareil (rien n'est enregistré).
- [ ] Une page qui joue du son par Web Audio (un jeu, une radio en ligne, un synthétiseur en ligne) dans un onglet caché : note si elle est mise en veille malgré le son (WebKit pourrait ne signaler que les éléments audio et vidéo).
- Connu : le contenu non enregistré d'une page est perdu à la veille (formulaires, position d'une vidéo, état d'un jeu) ; une fenêtre ouverte en onglet par une page (`window.open` sans taille) perd le lien avec sa page d'origine si celle-ci est mise en veille pendant ce temps (les fenêtres de connexion de la 5.8, elles, le gardent) ; un partage d'écran sans caméra ni micro n'est pas détecté.

### 5.7 Plantage d'une page

Pour faire planter une page sans risque : Moniteur d'activité (Applications > Utilitaires), onglet Processeur, champ de recherche « Web Content ». Chaque page de Matcha a son processus (« Matcha Web Content », ou le site de la page dans le nom sur un macOS récent ; sinon « com.apple.WebKit.WebContent »). Pour être sûr de viser le bon : ferme Safari, et repère le processus qui apparaît quand tu ouvres la page (le plus récent a le PID le plus élevé, colonne PID). Sélectionne-le, bouton ⓧ en haut de la fenêtre, puis « Forcer à quitter ». Ça ne touche que cette page. Le journal : Console.app, filtre « Browser » (une ligne « Processus de la page arrêté » par plantage, avec le nombre de plantages en 30 s ; jamais l'adresse).

- [ ] Onglet affiché : ouvre un site (Wikipédia), suis un lien, puis force à quitter le processus de la page : elle se recharge aussitôt, à la même adresse (une page blanche un court instant au plus). Dans la barre latérale, le titre et l'icône de l'onglet ne bougent pas. Précédent (⌘[) ramène à la page d'avant.
- [ ] Onglet caché : ouvre une page, note son processus, passe sur un autre onglet, puis force à quitter ce processus : rien ne change dans la barre (titre, icône, × au survol). Clique l'onglet : la page se recharge, Précédent marche.
- [ ] Autre Space : même chose avec l'onglet sélectionné d'un Space que tu quittes ; il se recharge quand tu reviens sur ce Space. Fenêtre principale fermée (⇧⌘W, Matcha reste ouvert) : la page se recharge quand tu rouvres la fenêtre.
- [ ] Split : force à quitter le processus du panneau qui n'est pas actif : il se recharge tout de suite ; l'autre panneau ne bouge pas.
- [ ] Aperçu (Maj+clic sur un lien) : force à quitter le processus de la page de l'aperçu : elle se recharge dans l'aperçu, qui reste ouvert ; la page derrière ne bouge pas.
- [ ] Mini-fenêtre (⌥⌘N) : force à quitter le processus de sa page : elle se recharge, même si la mini-fenêtre est derrière la fenêtre principale.
- [ ] Deux fois de suite : force à quitter le processus d'une page affichée, puis, dès qu'elle s'est rechargée (moins de 30 s après), celui de la page rechargée. **Attendu :** plus de rechargement ; à la place de la page, un message calme « Cette page a rencontré un problème », le site en dessous et un bouton « Recharger », dans la carte (pas de fenêtre ni d'alerte). Le titre et l'icône de l'onglet n'ont pas changé. « Recharger » (ou ⌘R) ramène la page. Même chose dans un aperçu et dans une mini-fenêtre. Recommence en attendant plus de 30 s entre les deux : la page se recharge seule les deux fois.
- [ ] Message dans un split : un clic sur le message du panneau qui n'est pas actif le rend actif ; son bouton « Recharger » recharge ce panneau-là.
- [ ] Message puis autre chose : avec le message affiché, ⌘L et une autre adresse, ou Précédent : le message part et la page demandée s'affiche.
- [ ] Recherche dans la page (⌘F) ouverte, un mot trouvé, puis plantage : la barre reste ouverte avec son texte, sans résultat ; Entrée retrouve le mot dans la page rechargée.
- [ ] Zoom : un site à 125 % revient à 125 % après le plantage (badge toujours là).
- [ ] Demande de permission en attente (bandeau caméra ou micro, https://webcamtests.com) : au plantage, le bandeau disparaît (demande refusée) ; la page rechargée peut redemander.
- [ ] Historique (⌘Y) : le rechargement après un plantage n'ajoute pas de visite (pas de ligne en plus, heure inchangée), ni celui du bouton « Recharger » du message.
- [ ] Langues : le message et son bouton en anglais, allemand, espagnol et italien (Réglages Système > Général > Langue et région > Applications > Matcha).
- Connu : comme pour la mise en veille, le contenu non enregistré de la page est perdu (formulaire, position d'une vidéo). Pas de test d'interface automatique : aucune façon publique de faire planter une page (seuls les tests unitaires appellent directement le délégué de WebKit).

### 5.8 Fenêtres de connexion

Pour ouvrir à coup sûr une fenêtre avec une taille : https://www.w3schools.com/jsref/met_win_open.asp, un exemple « Try it Yourself » dont le code donne `width=…,height=…`, puis le bouton de l'exemple (et, pour comparer, un exemple sans taille). Le journal : Console.app, filtre « Browser » (une ligne « Fenêtre de connexion ouverte » avec le site, jamais l'adresse).

- [ ] Exemple avec une taille : une petite fenêtre s'ouvre, centrée sur la fenêtre du navigateur, la page à la taille demandée (sous la barre), et non un onglet (barre latérale inchangée). Le titre de la page est dans la barre de titre ; dessous, une fine barre avec le cadenas et le site. Ni bouton Précédent ni champ d'adresse ; le bouton jaune (réduire) est grisé.
- [ ] Exemple sans taille, ou lien « nouvelle fenêtre » : un onglet, comme avant.
- [ ] Clique sur la fenêtre du navigateur : la fenêtre de connexion reste devant. Déplace la fenêtre du navigateur : elle la suit. Déplace ou redimensionne la fenêtre de connexion seule : la fenêtre du navigateur ne bouge pas.
- [ ] ⌘W ferme la fenêtre de connexion, jamais l'onglet derrière ; le bouton rouge et ⇧⌘W aussi. Moniteur d'activité : son processus « Web Content » disparaît. ⎋ ne la ferme pas.
- [ ] « Se connecter avec Google » sur un site qui ouvre une petite fenêtre pour ça (par exemple Canva ou Figma ; si le site change de page au lieu d'ouvrir une fenêtre, essaie-en un autre) : la barre montre accounts.google.com avec le cadenas ; connecte-toi : la fenêtre se ferme d'elle-même et la page d'origine est connectée.
- [ ] « Se connecter avec Apple » (fenêtre sur appleid.apple.com) : même chose. Avec un code à deux facteurs, la fenêtre reste devant pendant que tu le tapes.
- [ ] PayPal : https://developer.paypal.com/demo/checkout/ , bouton PayPal : la fenêtre de paiement s'ouvre (paypal.com, cadenas) ; ferme-la, ou va au bout : la page d'origine le voit.
- [ ] Ta banque, ou un site qui ouvre une validation (3-D Secure) ou un document dans une petite fenêtre : même comportement ; un relevé PDF s'affiche dans la fenêtre ; un fichier qui ne fait que se télécharger : la fenêtre se ferme d'elle-même et le fichier arrive dans les téléchargements de la fenêtre.
- [ ] La barre montre toujours le vrai site, quel que soit le titre de la page. Survole-la : l'adresse complète en bulle d'aide. Si tu tombes sur une fenêtre de connexion en http (sans « s ») : ⚠ et « Non sécurisé » en rouge.
- [ ] Depuis un aperçu (Maj+clic sur un lien vers un site qui propose « Se connecter avec Google » en fenêtre) : la fenêtre de connexion s'ouvre au-dessus, l'aperçu reste un aperçu (pas d'onglet en plus) ; une fois connecté, l'aperçu montre la page connectée.
- [ ] Depuis une mini-fenêtre (⌥⌘N) : la fenêtre de connexion s'ouvre au-dessus de la mini-fenêtre, sans autre mini-fenêtre ; elle reste devant quand tu cliques la mini-fenêtre. Passe sur une autre app (Finder) : les deux passent derrière le Finder ; reviens sur Matcha : la fenêtre de connexion est toujours devant la mini-fenêtre.
- [ ] Fenêtre privée (⇧⌘N) : la fenêtre de connexion est sombre, et la connexion n'apparaît pas dans la fenêtre normale. Ferme la fenêtre privée : sa fenêtre de connexion se ferme aussi.
- [ ] Ferme la fenêtre du navigateur (⇧⌘W sur elle) pendant qu'une fenêtre de connexion est ouverte : la fenêtre de connexion reste à l'écran et utilisable.
- [ ] Dans une fenêtre de connexion, ⌘-clic sur un lien (« Conditions », « Aide ») : un onglet en arrière-plan dans la fenêtre du navigateur, sous l'onglet d'origine ; un lien « nouvelle fenêtre » : un onglet au premier plan. Maj+clic : le lien s'ouvre dans la fenêtre de connexion (pas d'aperçu).
- [ ] Mémoire (5.6, avec le délai court) : ouvre une fenêtre de connexion depuis un onglet, passe sur un autre onglet et laisse passer le délai : l'onglet d'origine ne se met pas en veille tant que la fenêtre est ouverte (la connexion aboutit) ; ferme-la et attends encore : il peut se mettre en veille.
- [ ] Plantage (5.7) : force à quitter le processus de la page de la fenêtre de connexion : elle se recharge dedans.
- [ ] Plein écran : fenêtre du navigateur en plein écran, ouvre une fenêtre de connexion : elle s'ouvre par-dessus, dans le même espace. Deux écrans : fenêtre du navigateur sur le second, la fenêtre de connexion s'ouvre sur celui-là.
- [ ] Langues : « Non sécurisé » en allemand, espagnol et italien. VoiceOver : « Connexion sécurisée » sur le cadenas, puis « Adresse » et le site.
- Connu : la position demandée par la page est ignorée (fenêtre centrée sur la fenêtre d'origine) ; ⌘R, ⌘F, ⌘P et le zoom n'agissent pas dans la fenêtre de connexion, et le menu Fichier y appelle ⌘W « Fermer l'onglet » (il ferme bien la fenêtre de connexion) ; depuis un aperçu, fermer l'aperçu pendant la connexion (clic à côté, autre onglet) la fait échouer. Pas de test d'interface automatique : aucune page locale n'ouvre de fenêtre avec une taille, et les tests ne peuvent ni servir ni écrire de page.

### 5.9 Menu contextuel des pages

Pages : n'importe quel site, ou la documentation de Postfix livrée avec macOS (`file:///usr/share/doc/postfix/html/index.html`, sans réseau : le logo en haut à gauche est une image, « Basic configuration » un lien). Le journal : Console.app, filtre « Browser » (une ligne « Menu contextuel : lien dans un nouvel onglet », jamais l'adresse).

- [ ] Clic droit sur un lien : « Ouvrir le lien », puis **« Ouvrir le lien dans un nouvel onglet »** et **« Ouvrir dans un aperçu »** à la place de « Ouvrir le lien dans une nouvelle fenêtre » ; ensuite, inchangés, « Télécharger le fichier lié », « Copier le lien », un trait, « Partager… » (et « Inspecter l'élément » dans la version Debug). Les deux nouveaux ont une icône comme les autres éléments (macOS 26 et plus).
- [ ] « Ouvrir le lien dans un nouvel onglet » : un onglet en arrière-plan juste sous l'onglet d'origine (et sous ceux déjà ouverts depuis lui) ; la page affichée ne change pas. Recommence sur un épinglé ou un favori : l'onglet va en tête des onglets du jour.
- [ ] « Ouvrir dans un aperçu » : l'aperçu s'ouvre sur le lien, en grandissant depuis l'endroit du clic droit ; aucun onglet en plus.
- [ ] « Copier le lien » puis ⌘V dans la barre de commande : l'adresse du lien (pas de bulle « URL copiée », comme dans Safari). « Télécharger le fichier lié » : le fichier arrive dans les téléchargements.
- [ ] Clic droit sur une image : **« Ouvrir l'image dans un nouvel onglet »** en tête, à la place de « Ouvrir l'image dans une nouvelle fenêtre » ; il ouvre l'image dans un onglet en arrière-plan. « Télécharger l'image » et « Copier l'image » marchent comme avant. Image dans un lien (logo d'un site) : les deux groupes, celui du lien puis celui de l'image.
- [ ] Dans un aperçu (Maj+clic sur un lien), clic droit sur un lien : « Ouvrir le lien dans un nouvel onglet » mais pas « Ouvrir dans un aperçu » (un clic y ouvre déjà le lien sur place). Choisis-le : un onglet en arrière-plan sous l'onglet d'origine, l'aperçu reste ouvert sur sa page.
- [ ] Dans un split, clic droit sur un lien du panneau qui n'est pas actif : « Ouvrir le lien dans un nouvel onglet » l'ouvre sous l'onglet de ce panneau ; « Ouvrir dans un aperçu » rend ce panneau actif et ouvre l'aperçu par-dessus les deux.
- [ ] Mini-fenêtre (Fichier > Nouvelle mini-fenêtre) : pas d'« Ouvrir dans un aperçu » ; « Ouvrir le lien dans un nouvel onglet » ajoute un onglet en arrière-plan dans la fenêtre principale (Space visé, comme ⌘-clic), la mini-fenêtre reste sur sa page et devant.
- [ ] Fenêtre de connexion (5.8) : même menu sans aperçu ; « Ouvrir le lien dans un nouvel onglet » ouvre l'onglet sous l'onglet d'origine, dans la fenêtre du navigateur.
- [ ] Fenêtre privée (⇧⌘N) : l'onglet ouvert par le menu est privé (connecte-toi à un site dans la fenêtre privée, ouvre un lien du même site par le menu : tu y es connecté ; la fenêtre normale ne l'est pas). Il n'apparaît pas dans l'historique.
- [ ] Une page qui ouvre elle-même une fenêtre juste après un clic droit ne doit pas être détournée : sur https://www.w3schools.com/jsref/tryit.asp?filename=tryjsref_win_open (« Try it »), fais un clic droit sur un lien quelconque de la page de résultat, ferme le menu par ⎋, puis clique sur le bouton de l'exemple : un onglet au premier plan, comme d'habitude (ni aperçu ni arrière-plan). Puis choisis « Ouvrir le lien dans un nouvel onglet » sur un lien et, dans la seconde, clique le bouton : le lien part en arrière-plan, la fenêtre de l'exemple au premier plan.
- [ ] Lien `mailto:` (adresse e-mail sur un site) : « Ouvrir le lien dans un nouvel onglet » ouvre Mail (aucun onglet vide).
- [ ] Clic droit ailleurs que sur un lien ou une image : le menu de WebKit inchangé (sur le fond : « Recharger » ; sur un texte sélectionné : « Copier »…).
- [ ] Langues : en allemand « Link in neuem Tab öffnen », « Link in der Vorschau öffnen », « Bild in neuem Tab öffnen » ; en espagnol « Abrir enlace en una pestaña nueva », « Abrir enlace en una vista previa », « Abrir imagen en una pestaña nueva » ; en italien « Apri link in un nuovo pannello », « Apri link in anteprima », « Apri immagine in un nuovo pannello ». Les éléments de WebKit suivent la langue du système.
- Connu : les éléments de WebKit sont reconnus par des identifiants non documentés ; si une version de macOS les change, le menu reste celui de WebKit (« … dans une nouvelle fenêtre » ouvre alors un onglet au premier plan) et le test unitaire `PageMenuIntegrationTests` échoue. « Ouvrir la vidéo / l'audio / le cadre dans une nouvelle fenêtre » restent ceux de WebKit (un onglet au premier plan). Si la page appelle `window.open` dans la seconde qui suit un choix du menu, avant que WebKit n'ouvre la fenêtre du lien (quelques millisecondes), les deux fenêtres peuvent échanger leur place.

### 5.10 Son

Pages : YouTube, Spotify Web (https://open.spotify.com) ou Deezer, un article de presse avec une vidéo YouTube intégrée. Le journal : Console.app, filtre « Browser » (une ligne « Son de la page mis en pause » par clic, jamais l'adresse).

- [ ] YouTube : lance une vidéo avec le son, puis passe sur un autre onglet : un haut-parleur apparaît à droite de la ligne de l'onglet YouTube, sans survol (il apparaît aussi sur la ligne de l'onglet affiché). Survole la ligne : le × apparaît à droite du haut-parleur, qui ne bouge pas. Bulle d'aide du haut-parleur : « Mettre le son en pause ».
- [ ] Clique le haut-parleur : le son s'arrête aussitôt, le haut-parleur disparaît, l'onglet affiché ne change pas et l'onglet YouTube n'est pas fermé. Reviens sur YouTube : la vidéo est en pause là où elle s'est arrêtée ; relance-la : le haut-parleur revient.
- [ ] Mets la vidéo en pause dans la page (barre d'espace) : le haut-parleur disparaît environ 2 s plus tard. Entre deux vidéos d'une playlist, ou entre une publicité et la vidéo, il ne clignote pas.
- [ ] Fin d'une vidéo (va tout à la fin, lecture automatique coupée) : le haut-parleur disparaît environ 2 s après.
- [ ] Son coupé : coupe le son dans le lecteur (haut-parleur de YouTube) ou mets son volume à zéro : le haut-parleur de la ligne disparaît (environ 2 s). Une vidéo qui se lance d'elle-même sans le son (presse, réseaux sociaux) n'en montre pas.
- [ ] Spotify Web ou Deezer : lance un morceau, change d'onglet : **note si le haut-parleur apparaît** (un lecteur qui joue le son par un élément hors de la page ou par Web Audio n'est pas vu, `FEATURES.md`). S'il apparaît, clique-le : la musique se met en pause, et le bouton lecture du site l'indique.
- [ ] Vidéo YouTube intégrée dans un article (une iframe) : lance-la avec le son, change d'onglet : le haut-parleur apparaît aussi.
- [ ] Split : deux pages côte à côte, une vidéo avec le son dans l'une : le haut-parleur est dans le morceau de ce panneau, dans la ligne du split. Survole la ligne : le × de la ligne ne le recouvre pas, même sur le dernier morceau. Un clic dessus met la vidéo en pause sans changer de panneau actif.
- [ ] Favori : mets YouTube en favori, lance une vidéo avec le son, passe sur un autre onglet : une petite pastille haut-parleur en haut à droite de la tuile ; un clic dessus met en pause, sans sélectionner le favori.
- [ ] Épinglé : même chose sur la ligne d'un épinglé. Dans un dossier replié, rien ne se voit (connu).
- [ ] Web Audio : un jeu ou un piano en ligne qui fait du son : **attendu, pas de haut-parleur** (connu). Dis-moi si ça te gêne.
- [ ] Mémoire (5.6, avec le délai court `-tabSuspensionDelaySeconds 20`) : une vidéo qui joue avec le son dans un onglet caché n'est jamais mise en veille, même longtemps ; mets-la en pause par le haut-parleur et attends le délai : là, elle peut se mettre en veille.
- [ ] Navigation : pendant que le son joue, suis un lien vers une autre page dans le même onglet : le haut-parleur disparaît tout de suite.
- [ ] Plantage (5.7) : force à quitter le processus d'une page qui joue du son (Moniteur d'activité) : le haut-parleur disparaît aussitôt.
- [ ] Aperçu (Maj+clic sur un lien vers une vidéo) : lance-la avec le son dans l'aperçu, puis « Ouvrir en onglet » : la ligne du nouvel onglet a son haut-parleur tout de suite, et le son continue.
- [ ] Fenêtre privée (⇧⌘N) : mêmes règles.
- [ ] Rien ne se met en pause tout seul : plusieurs onglets qui jouent du son en même temps gardent chacun leur haut-parleur et leur son, jusqu'à ce que tu cliques.
- [ ] VoiceOver (⌘F5) sur la ligne d'un onglet qui joue : « … Lecture audio en cours » ; menu des actions (VO-⌘-Espace) : « Mettre le son en pause », qui met en pause. Pareil sur une tuile de favori et sur un morceau de split.
- [ ] Langues : bulle et action en allemand « Audio pausieren », en espagnol « Pausar audio », en italien « Metti in pausa l'audio » ; valeur pour VoiceOver « Audiowiedergabe läuft », « Reproduciendo audio », « Riproduzione audio in corso ».
- Connu : pas de haut-parleur pour le son de Web Audio, d'un élément audio hors de la page (`new Audio()`) ou d'un média dans un shadow DOM ; seulement la pause, pas de « couper le son » (API privée) ; rien sur un dossier replié ; une vidéo sans piste audio mais non coupée allume le haut-parleur. Test d'interface automatique `AudioUITests` : il joue quelques secondes d'une musique des Souvenirs de Photos livrée avec macOS (baisse le son avant de lancer les tests d'interface).

### Dossiers personnalisés

En plus du plan : icône (symbole ou emoji) et couleurs du texte et du fond d'un dossier épinglé. Prépare deux onglets épinglés, un dossier (clic droit sur un épinglé > « Nouveau dossier ») et un sous-dossier dedans (clic droit sur le dossier > « Nouveau sous-dossier »).

- [ ] Au lancement, aucun panneau n'est ouvert. Clic droit sur le dossier : « Personnaliser… », juste sous « Renommer ». Le panneau s'ouvre sous la ligne du dossier, entre deux traits, et pousse vers le bas les lignes suivantes ; en tête, le nom du dossier, « Réinitialiser » (grisé) et une croix.
- [ ] Grille d'icônes : le dossier (premier symbole) est entouré ; survol d'un symbole : fond léger et bulle d'aide en français (« Étoile », « Porte-documents »… regarde que les noms sont justes). Un clic : la ligne du dossier change aussitôt d'icône, le symbole est entouré.
- [ ] Emoji : « Emoji et symboles… » ouvre le visualiseur de caractères de macOS ; double-clique un emoji : il arrive dans le champ et sur la ligne, aucun symbole n'est plus entouré. Tapes-en un autre (⌃⌘Espace dans le champ) : il remplace le premier. Une lettre ou un chiffre sont refusés (le champ revient à l'emoji). Vide le champ : l'icône par défaut revient. Essaie un drapeau (🇫🇷), un emoji avec une couleur de peau (👍🏽) et ❤️.
- [ ] Texte : une pastille colore le nom et le symbole (pas l'emoji) ; le cercle barré, « Aucune couleur », rend la couleur du système. Le puits de couleur à droite de « Texte » ouvre le panneau des couleurs de macOS : promène la sélection, la ligne suit en direct, sans à-coup.
- [ ] Fond : une pastille donne à la ligne un fond plein aux coins arrondis. Sans couleur de texte choisie, le nom et le chevron passent en noir sur un fond clair (jaune, orange) et en blanc sur un fond foncé (indigo, gris foncé choisi au puits) ; sur le bleu, le rouge et le violet, le noir l'emporte (règle des WCAG) : dis-moi si tu préfères le blanc. Survol de la ligne : le fond s'éclaircit ou s'assombrit un peu ; glisser un onglet dessus fait de même.
- [ ] Apparence claire et sombre (Réglages Système > Apparence) : les couleurs restent celles choisies, le texte reste lisible. Note si un fond te paraît trop vif en sombre. Fenêtre privée (⇧⌘N) : un dossier s'y personnalise aussi.
- [ ] Sous-dossier : mêmes choix, panneau sous sa ligne (pleine largeur, sans retrait). Replie le dossier parent : le panneau ouvert sous le sous-dossier se cache avec lui, et revient quand tu redéplies.
- [ ] Un seul panneau par fenêtre : « Personnaliser… » sur l'autre dossier y déplace le panneau. Le menu du dossier dont le panneau est ouvert dit « Fermer la personnalisation », qui le ferme. La croix le ferme. Échap le ferme juste après l'ouverture, et aussi après un clic dans le champ emoji ; après un clic dans la page, Échap va à la page.
- [ ] « Réinitialiser » rend l'icône et les couleurs par défaut, puis se grise.
- [ ] Enregistrement : quitte Matcha (⌘Q) et relance : icônes et couleurs retrouvées, sous-dossier compris. Glisse le dossier ailleurs dans les épinglés : il garde son apparence. Supprime-le pendant que son panneau est ouvert : le panneau disparaît avec lui.
- [ ] Change de Space panneau ouvert : il n'apparaît pas dans l'autre Space ; reviens : il est toujours ouvert sous le dossier. Barre masquée (⌘S) : le panneau réapparaît dans la barre flottante.
- [ ] Barre au plus étroit (glisse son bord) : la grille et les pastilles passent sur plus de lignes, rien ne déborde ; en allemand, « Emoji & Symbole … » tient à côté du champ.
- [ ] Langues : « Personnaliser… » en allemand « Anpassen … », en espagnol « Personalizar… », en italien « Personalizza… » ; « Réinitialiser » : « Zurücksetzen », « Restablecer », « Ripristina ».
- [ ] Facultatif, VoiceOver : le nom de chaque symbole et de chaque couleur, « Aucune couleur », « Couleur de texte personnalisée », « Fermer la personnalisation ».
- [ ] Captures (vraie souris, ne touche à rien pendant ce temps) : `TEST_RUNNER_MATCHA_SCREENSHOT=1 TEST_RUNNER_MATCHA_SCREENSHOT_FOLDER=1 xcodebuild … test -only-testing:MatchaUITests/ScreenshotUITests` donne `37-dossier-panneau` et `38-dossier-personnalise` (en sombre : `TEST_RUNNER_MATCHA_SCREENSHOT_SETTINGS_VALUES=AppleInterfaceStyle=Dark`). Tests d'interface `FolderCustomizationUITests` : écrits mais pas encore lancés.
- Connu : pas de défilement automatique vers le panneau s'il s'ouvre en bas de la barre (fais défiler) ; une seule couleur pour le clair et le sombre.

### Icônes des Spaces

En plus du plan : un symbole parmi 45, ou un emoji, pour l'icône d'un Space, comme pour les dossiers. Prépare deux Spaces (bouton + en bas de la barre).

- [ ] Clic sur l'icône du Space affiché : la bulle s'ouvre avec le nom du Space, la section « Icône » (grille de symboles, champ emoji, « Emoji et symboles… »), puis « Thème » comme avant. Le symbole du Space est entouré. Rien ne déborde, et la bulle tient dans la fenêtre sans défiler (essaie aussi avec une fenêtre basse).
- [ ] Survol d'un symbole : fond léger et bulle d'aide en français (« Cercle », « Montagnes », « Tasse à café »… regarde que les noms sont justes). Un clic : l'icône du Space change aussitôt en bas de la barre, le symbole est entouré.
- [ ] Emoji : « Emoji et symboles… » ouvre le visualiseur de caractères de macOS ; double-clique un emoji : il arrive dans le champ et en bas de la barre, en couleurs, un peu plus grand qu'un symbole ; aucun symbole n'est plus entouré. Une lettre ou un chiffre sont refusés. Vide le champ : le cercle revient. Essaie un drapeau (🇫🇷), un emoji avec une couleur de peau (👍🏽) et ❤️.
- [ ] Space non affiché avec un emoji : son emoji est plus petit et atténué ; affiche ce Space (clic ou ⌃2) : il reprend sa taille et son éclat, et le précédent s'atténue. Dis-moi si l'atténuation te va. Un symbole d'un Space non affiché reste gris comme avant.
- [ ] Clic droit sur un Space : « Renommer… », « Modifier le thème… », « Changer l'icône… », « Supprimer le Space » ; plus de sous-menu « Icône » aux noms techniques. « Changer l'icône… » sur un Space non affiché : il s'affiche et sa bulle s'ouvre.
- [ ] Échap dans le champ emoji ferme la bulle ; un clic à côté aussi.
- [ ] Enregistrement : quitte Matcha (⌘Q) et relance : symboles et emoji retrouvés. Un nouveau Space reçoit toujours le symbole suivant de la liste habituelle (étoile, cœur, éclair…).
- [ ] Mini-fenêtre (⌥⌘N) : le bouton « Ouvrir dans ‹Space› » montre l'emoji ou le symbole du Space affiché ; change l'icône du Space : le bouton suit.
- [ ] Apparence claire et sombre (Réglages Système > Apparence) : symboles lisibles, emoji en couleurs.
- [ ] Langues : « Changer l'icône… » en allemand « Symbol ändern … », en espagnol « Cambiar icono… », en italien « Cambia icona… » ; « Thème » : « Thema », « Tema », « Tema ».
- [ ] Facultatif, VoiceOver : le nom de chaque symbole. Colle un emoji dans le champ : VoiceOver atteint toujours la bulle (grille et champ).
- [ ] Le symbole au pied de la barre (dessiné désormais comme un texte, pour que la bulle reste accessible) est centré dans son rond, à la même taille qu'avant, pour le Space affiché comme pour les autres.
- [ ] Captures (vraie souris, ne touche à rien pendant ce temps) : `TEST_RUNNER_MATCHA_SCREENSHOT=1 TEST_RUNNER_MATCHA_SCREENSHOT_THEME=Forêt xcodebuild … test -only-testing:MatchaUITests/ScreenshotUITests` donne `7-theme-editeur`, l'éditeur complet. Tests d'interface `SpaceIconUITests` : lancés le 2026-10-18, ils passent.
- Connu : 45 symboles proposés, pas de recherche dans tous les symboles SF.

## Phase 6

### 6.2 Bloqueur natif (mis de côté)

Mis de côté le 2026-10-18 (`FEATURES.md`) : son code reste, son interface est cachée. À contrôler maintenant :

- [ ] Réglages > Confidentialité : plus de section « Publicités et traqueurs », « Exceptions du bloqueur » ni « Crédits des listes de blocage ». Réglages du site : plus de ligne « Bloquer les publicités et traqueurs » sous « Zoom ». Journal : aucune ligne de la catégorie `ContentBlocker` au lancement.

Contrôles à faire quand on le reprendra. Aucune liste n'est livrée tant que la tâche 6.1 (EasyList, EasyPrivacy) n'est pas faite : le bloqueur est inactif. Les tests unitaires vérifient le blocage avec de petites listes d'essai ; les contrôles avec de vraies publicités sont à faire avec les listes (dernier point, à compléter en 6.1). Journal : app Console, recherche `subsystem:com.matchabrowser.matcha category:ContentBlocker`.

- [ ] Lancement : Matcha s'ouvre aussi vite qu'avant, pages comprises. Dans le journal : « Aucune liste de blocage livrée : bloqueur inactif », puis « Listes prêtes : 0 (0 compilées) » avec une durée de quelques millisecondes.
- [ ] Réglages > Confidentialité, sous « Autorisations des sites » : section « Publicités et traqueurs » avec « Bloquer les publicités et traqueurs » coché mais grisé et « Aucune liste de blocage n'est installée. » ; section « Exceptions du bloqueur » : « Aucune exception. » ; section « Crédits des listes de blocage » : « Les auteurs et les licences des listes de blocage s'afficheront ici. ». La fenêtre des réglages tient sur l'écran sans barre de défilement : dis-moi si elle te paraît trop haute (le bloqueur pourrait avoir son propre onglet).
- [ ] Réglages du site (bouton à côté de l'adresse) sur un site web : une ligne « Bloquer les publicités et traqueurs » (bouclier) sous « Zoom », interrupteur éteint et grisé, note « Aucune liste de blocage n'est installée. » dessous. Sur un onglet vide : pas de ligne (« Cette page n'a pas de réglages de site. »). Barre d'adresse au-dessus de la page : même ligne dans le panneau de la carte.
- [ ] Langues : « Publicités et traqueurs » se dit « Werbung und Tracker » en allemand, « Anuncios y rastreadores » en espagnol, « Pubblicità e tracker » en italien.
- [ ] Rien ne change ailleurs : fenêtres de connexion (Google, Apple), `window.opener` (une connexion « Se connecter avec Google » aboutit), aperçu (Maj+clic), mini-fenêtre, son, onglets dupliqués.
- [ ] Avec les listes (6.1, à compléter alors) : premier lancement, « Listes prêtes : 2 (2 compilées) » et sa durée ; lancement suivant, « (0 compilées) » en quelques millisecondes. Un site plein de publicités (un grand site d'actualité) n'en montre plus. Réglages : chaque liste avec sa version, son nombre de règles et sa date ; crédits avec licence et site. Désactive le bloqueur dans les réglages du site : la page se recharge avec ses publicités, les autres onglets du même site aussi (tous ses sous-domaines), un autre site reste bloqué ; le site apparaît dans « Exceptions du bloqueur », la corbeille (« Bloquer à nouveau ») le rebloque et recharge ses pages. Fenêtre privée : l'exception qu'on y prend ne vaut que pour elle et n'apparaît pas dans les réglages. Décoche le réglage global : les pages rechargées montrent leurs publicités, la ligne du site se grise avec « Désactivé dans Réglages > Confidentialité. ».
- Connu : le réglage global vaut pour les prochains chargements (les pages ouvertes ne sont pas rechargées). Une page ouverte avant que les listes soient prêtes (tout premier lancement après une mise à jour des listes) n'est bloquée qu'à son prochain chargement.

### 6.3 Infrastructure des extensions

Pas encore d'écran pour installer une extension (6.4) ni de boutons (6.5) : la plupart des contrôles se feront avec elles, et en 6.6 avec tes vraies extensions. Les tests unitaires vérifient le chargement, les scripts de contenu, les fenêtres privées, l'ouverture d'un onglet par une extension et les événements (onglets, Spaces, aperçu, mini-fenêtres). Journal : app Console, recherche `subsystem:com.matchabrowser.matcha category:Extensions`.

- [ ] Rien ne change sans extension : lancement aussi rapide, rien ne s'ouvre seul ; onglets, Spaces (⌃1, glissement), splits, aperçu (Maj+clic), mini-fenêtre, fenêtres de connexion (« Se connecter avec Google »), fenêtre privée et téléchargements marchent comme avant.
- [ ] Avec beaucoup d'onglets (une cinquantaine sur plusieurs Spaces) : changer d'onglet ou de Space et charger des pages reste fluide (Matcha suit maintenant tous les onglets pour les extensions).
- [ ] Avec la 6.4 (à compléter alors) : une extension installée se charge au lancement (« Extension chargée » dans le journal) et garde ses réglages d'un lancement à l'autre ; désactivée, elle ne se charge plus.
- [ ] Avec la 6.4 : son script agit dans un onglet, dans un onglet d'un autre Space après être passé sur ce Space, dans l'aperçu, dans une mini-fenêtre et dans une fenêtre de connexion ; il n'agit pas dans une fenêtre privée, jusqu'à ce que tu y autorises l'extension.
- [ ] Avec la 6.5 : la popup d'une extension s'ouvre sous son bouton ; elle vise l'onglet affiché (le panneau actif d'un split, l'aperçu s'il est ouvert). Sa page d'options s'ouvre dans un nouvel onglet. Une extension qui demande une permission en cours de route montre une alerte « … demande un accès supplémentaire » avec « Refuser » par défaut ; rien n'est accordé sans « Autoriser ».
- [ ] Avec la 6.6 : la fenêtre « détachée » d'un gestionnaire de mots de passe s'ouvre en mini-fenêtre ; changer de Space puis rouvrir sa popup vise bien l'onglet du Space affiché.

### 6.4 Installation des extensions

Réglages (⌘,) > Extensions. Extensions Safari : celles des apps de /Applications (Proton Pass for Safari, par exemple). Fichiers : un `.crx` de Chrome (récupéré par un site comme crxextractor.com), un `.xpi` de Firefox (page de l'extension sur addons.mozilla.org, « Télécharger le fichier » dans ses versions), un `.zip` ou un dossier décompressé.

- [ ] L'onglet Extensions s'ouvre ; « Aucune extension installée. » au début ; « Extensions Safari de vos apps » liste les extensions trouvées, avec l'icône de leur app et « Dans <app> ».
- [ ] « Ajouter… » sur une extension Safari : l'écran montre l'icône, « Ajouter « <nom> » ? », la version et l'app, la description, « Elle pourra : » avec des phrases lisibles (historique, presse-papiers, apps du Mac, tous les sites…), « Autoriser dans les fenêtres privées » décoché. « Annuler » : rien n'est installé. « Ajouter l'extension » : elle apparaît dans « Extensions installées », avec « Version … · Dans <app> », son interrupteur allumé et le menu (…).
- [ ] Proton Pass (ou ton gestionnaire) : sa page de connexion (account.proton.me) s'ouvre et trouve l'extension (plus de « Proton Pass is missing permissions »).
- [ ] « Choisir… » avec un `.crx`, un `.xpi`, un `.zip` puis un dossier décompressé : même écran, nom du fichier comme origine ; l'extension s'installe, « Depuis un fichier ». Le même fichier une seconde fois : « Mettre à jour « … » ? » et « Mettre à jour l'extension » ; une seule ligne reste.
- [ ] « Plus d'extensions… » (sous les extensions Safari de tes apps) : l'App Store s'ouvre sur la page « Get Started With Safari Extensions » (extensions Safari par catégorie), comme le bouton de Safari.
- [ ] Sous « Depuis un fichier » : la note sur les extensions Firefox (fichier .xpi depuis la page des versions de l'extension sur addons.mozilla.org ; préférer la version Safari quand elle existe) et le lien « Modules Firefox », qui ouvre addons.mozilla.org dans un nouvel onglet de la fenêtre principale, amenée devant.
- [ ] Un fichier qui n'est pas une extension (une image, un PDF) : message rouge « Ce fichier n'est pas une extension… » ; une archive sans `manifest.json` : « Aucun fichier manifest.json… ».
- [ ] Interrupteur éteint : l'extension n'agit plus (son script ne tourne plus sur les pages) ; quitte et relance : toujours éteinte. Rallumée : elle revient sans redemander ses permissions.
- [ ] Menu (…) > « Autoriser dans les fenêtres privées » : son script agit dans une fenêtre privée (⇧⌘N) seulement une fois coché. « Options… » (si l'extension en a) : sa page d'options s'ouvre dans un nouvel onglet de la fenêtre principale.
- [ ] Menu (…) > « Supprimer… » : confirmation « Supprimer « … » ? » ; l'extension disparaît de la liste ; une extension Safari redevient « Ajouter… » plus bas, et son app est toujours là.
- [ ] Quitte et relance Matcha : les extensions installées sont toujours là, avec leurs réglages.
- [ ] Langues : l'onglet et l'écran des permissions en allemand, espagnol et italien ; aucun texte coupé.
- [ ] Bitwarden (extension Safari de l'app Bitwarden) installé et actif : Moniteur d'activité, Matcha et ses processus « WebKit » restent sous quelques % de processeur au repos (avant le correctif, sa boucle d'attente occupait 40 %).
- Connu : les messages natifs vers l'app de l'extension ne marchent pas (`FEATURES.md`).

### 6.5 Boutons des extensions

Avec au moins une extension installée (Proton Pass, uBlock Origin Lite, Dark Reader…).

- [ ] Barre latérale : une rangée de boutons sous la pastille d'adresse, un par extension, avec son icône ; survol : son titre. Barre d'adresse au-dessus de la page (Réglages > Apparence) : les boutons sont dans la barre, avant le bouton des réglages du site.
- [ ] Clic sur le bouton d'une extension à bulle (Proton Pass) : la bulle s'ouvre sous le bouton, prend la taille de sa page ; clic ailleurs : elle se ferme. Avec un split et la barre au-dessus des pages, la bulle s'ouvre sous le bouton du panneau cliqué et vise ce panneau.
- [ ] La bulle vise la page affichée : changer d'onglet ou de Space puis rouvrir la bulle montre le nouveau site ; avec l'aperçu ouvert (Maj+clic), elle vise l'aperçu.
- [ ] Badge : une extension qui compte (uBlock Origin Lite : nombre de requêtes bloquées) montre un petit badge sur son bouton, qui change d'une page à l'autre.
- [ ] Clic droit sur un bouton : « Options… » (si l'extension en a) ouvre sa page d'options dans un nouvel onglet ; « Masquer le bouton » le retire de la rangée (l'extension continue d'agir) ; « Gérer les extensions… » ouvre Réglages sur l'onglet Extensions.
- [ ] Réglages > Extensions, menu (…) > « Afficher le bouton près de l'adresse » : coché par défaut ; décoché, le bouton disparaît ; recoché, il revient. Quitte et relance : le choix est gardé.
- [ ] Fenêtre privée (⇧⌘N) : seules les extensions autorisées dans les fenêtres privées ont un bouton.
- [ ] Extension désactivée (interrupteur des réglages) : son bouton disparaît ; réactivée, il revient.
