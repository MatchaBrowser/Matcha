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

### Spaces (4.0)

- **Sous-menu Icône d'un Space** : il affiche les noms techniques des symboles (« circle.fill »…). Piste : n'afficher que les icônes, ou des noms traduits.

### Mémoire des onglets (5.6)

- **Texte saisi perdu** : un onglet mis en veille recharge sa page en revenant ; ce qui n'a pas été envoyé (formulaire, brouillon) est perdu, comme l'état d'une app web ou la position d'une vidéo. Piste : demander à la page, par un script dans un monde isolé (`WKContentWorld`), si un champ a été modifié, et l'épargner, comme le fait Chrome.
- **Applications web épinglées** (messagerie, discussion) : en veille, elles ne se mettent plus à jour (compteur du titre figé) jusqu'à leur affichage. Piste : un réglage pour garder chargés les épinglés et les favoris.
- **Son par Web Audio** : `requestMediaPlaybackState` ne signale peut-être que les éléments audio et vidéo ; à vérifier à la main.
- **Partage d'écran sans caméra ni micro** : aucune API publique ne le signale ; l'onglet peut se mettre en veille.
- **Fenêtre ouverte par une page** (connexion « avec Google »…) : si la page d'origine se met en veille pendant ce temps, `window.opener` ne la retrouve plus.
