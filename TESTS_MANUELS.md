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
- [ ] « Se connecter avec Google » dans une mini-fenêtre : la fenêtre de connexion s'ouvre en mini-fenêtre et se ferme d'elle-même. ⌘-clic sur un lien : un onglet arrive en arrière-plan dans le Space, sans que la fenêtre principale passe devant. Maj+clic : le lien s'ouvre dans la mini-fenêtre (pas d'aperçu). Un lien `mailto:` ouvre Mail.
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

- [ ] Gros téléchargement réel (par exemple l'image disque d'une app d'une centaine de Mo) : le bouton flèche apparaît à gauche dans le pied de la barre, entouré d'un anneau qui se remplit ; rien ne s'ouvre de soi-même, ni la liste ni le fichier. Ouvre la liste pendant le téléchargement : barre de progression et « 12 Mo sur 140 Mo » qui avancent, bouton ⓧ pour annuler. À la fin, la flèche rebondit une fois, la ligne montre la taille et une loupe (« Afficher dans le Finder »).
- [ ] Lien vers un PDF : il s'affiche dans la page, rien n'est téléchargé. Lien vers un .zip : il est téléchargé, la page reste affichée.
- [ ] Pièce jointe (`Content-Disposition: attachment`), par exemple un fichier d'une release GitHub (« Assets » d'une release) ou le bouton « Download ZIP » d'un dépôt : téléchargée sous le nom donné par le serveur, même si c'est un type que WebKit sait afficher.
- [ ] Le même fichier deux fois : « nom.zip » puis « nom 2.zip » dans Téléchargements, le plus récent en tête de la liste ; aucun fichier n'est écrasé. Une archive « .tar.gz » devient « archive 2.tar.gz ».
- [ ] Annuler pendant un gros téléchargement : la ligne passe à « Annulé », et aucun fichier partiel ne reste dans Téléchargements.
- [ ] « Afficher dans le Finder » : une fenêtre du Finder s'ouvre sur Téléchargements, le fichier sélectionné. Double-clic sur une ligne terminée : le fichier s'ouvre dans son app ; sur une ligne en cours, annulée ou en échec, rien ne se passe.
- [ ] « Effacer » retire les lignes terminées, en échec ou annulées (pas celles en cours) ; les fichiers restent dans Téléchargements. Plus rien dans la liste : le panneau se ferme et le bouton disparaît.
- [ ] Quarantaine : télécharge une app ou une image disque (.dmg) d'un éditeur, puis ouvre-la depuis le Finder : macOS demande confirmation (Gatekeeper). Dans le Terminal, `xattr -p com.apple.quarantine ~/Downloads/<fichier>` affiche une valeur qui contient « Matcha ».
- [ ] Fenêtre privée (⇧⌘N) : un téléchargement y montre son propre bouton ; la fenêtre principale n'en montre pas. Ferme la fenêtre privée : le fichier reste dans Téléchargements, mais la liste l'oublie (rouvre une fenêtre privée : pas de bouton). Un téléchargement privé encore en cours à la fermeture est annulé.
- [ ] Mini-fenêtre : un téléchargement lancé depuis sa page apparaît dans la liste de la fenêtre principale ; la mini-fenêtre reste sur sa page.
- [ ] Barre latérale masquée (⌘S) : survole le bord gauche, clique le bouton des téléchargements : le panneau monte dans la barre flottante. Éloigne le pointeur : la barre se cache, panneau compris ; reviens au bord : elle réapparaît avec le panneau toujours ouvert. La croix le ferme.
- [ ] Aperçu (Maj+clic sur un lien) : un lien de téléchargement dans l'aperçu télécharge le fichier, l'aperçu reste ouvert.
- [ ] Quitter Matcha pendant un téléchargement : au lancement suivant, la liste est vide (elle ne dure que le temps de la session) et aucun fichier partiel ne reste dans Téléchargements.
- [ ] Aspect en clair, en sombre et en fenêtre privée : anneau lisible, panneau lisible (titre, « Effacer », croix, trait de séparation), icônes des fichiers (celle de l'app pour une app).
- [ ] Facultatif, VoiceOver : « Téléchargements » sur le bouton, nom du fichier et état sur chaque ligne, « Annuler », « Afficher dans le Finder », « Effacer ».
- Connu : un lien `target=_blank` vers un fichier laisse un onglet vide après le téléchargement (Safari le ferme) ; ferme-le à la main. Pas de reprise d'un téléchargement interrompu.
- [ ] Ouvre le panneau des téléchargements pendant qu'un gros fichier arrive, et laisse-le ouvert jusqu'à la fin : il reste ouvert, la ligne passe à « terminé » et la flèche du bouton rebondit une fois. Change de Space : le panneau reste ouvert.
