# SYNC.md — synchronisation de Matcha

Spécification de la synchronisation : données échangées, chiffrement par mot de passe maître et API des serveurs. **Version 1, brouillon** jusqu'à la tâche 7.4 de `PLAN.md`. Elle fait foi pour le client (`Matcha/Services/Sync/`) comme pour le serveur de référence (dépôt `matchabrowser/matcha-server`, tâche 7.8).

---

## 1. Principes

Trois modes, au choix dans Réglages > Synchronisation :

| Mode | Stockage | Protection | Disponible |
| --- | --- | --- | --- |
| iCloud | base privée CloudKit du compte Apple | chiffrement de CloudKit (`encryptedValues`), sans mot de passe maître | oui |
| Serveur privé | serveur installé par l'utilisateur (API v1, § 4) | chiffrement de bout en bout par mot de passe maître (§ 3) | oui |
| Serveur public | serveur hébergé par Matcha, même API | idem | non : option grisée « Bientôt disponible » |

- **Un moteur, trois transports.** Contenu, conflits et suppressions suivent les mêmes règles dans les trois modes. Seul le transport change.
- **Les serveurs ne savent rien.** Ils ne reçoivent que des contenus chiffrés sur le Mac. Ils ne peuvent pas les lire, ni les modifier sans que le client s'en aperçoive. Sans le mot de passe maître ou la clé de secours, personne ne peut récupérer les données, pas même l'administrateur du serveur.
- **Une seule API.** Le serveur public est un serveur privé ouvert à tous.

---

## 2. Données

### 2.1 Ce qui est synchronisé

| Type | Modèle | Champs (`fields`) |
| --- | --- | --- |
| `profile` | `ProfileRecord` | `name`, `order` |
| `space` | `SpaceRecord` | `name`, `symbol`, `theme` (objet `SpaceTheme` : `name`, `colors` = 2 ou 3 × `{red, green, blue}` de 0 à 1, `angle`) ou `null`, `order`, `profileId` |
| `folder` | `FolderRecord` | `name`, `order`, `isCollapsed`, `spaceId`, `parentId` ou `null` |
| `tab` | `TabRecord` favori ou épinglé | `place` (`favorite` ou `pinned`), `url` et `title` d'origine (`pinnedURL`, `pinnedTitle`), `order`, `profileId` (favori) ou `spaceId` (épinglé), `folderId` ou `null` |
| `boost` | `BoostRecord` (tâche 4.7) | `domain`, `css`, `js`, `isEnabled` |

**Restent sur le Mac :** onglets du jour et archivés, adresse et titre courants d'un épinglé, historique de navigation (`HistoryRecord`, une ligne par visite : le moteur ignore ses changements dans l'historique de SwiftData), états de navigation (`interactionState`), regroupements en split view (`splitGroupID`, `splitFraction`), données des sites (cookies, connexions, stockage), permissions des sites (`SitePermissionRecord` : caméra, micro), zoom des sites (`siteZoomLevels`, dans les réglages de l'app), téléchargements, réglages de l'app.

Un onglet qui quitte les favoris ou les épinglés compte comme une suppression pour la synchro. Un onglet qui y entre compte comme une création.

### 2.2 Contenu d'un enregistrement

Un enregistrement porte l'identifiant (`id`, UUID) de son modèle SwiftData. Son contenu est un objet JSON en UTF-8 :

```json
{
  "type": "space",
  "schema": 1,
  "modifiedAt": "2026-10-17T08:30:12.345Z",
  "modifiedBy": "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10",
  "deleted": false,
  "fields": {
    "name": "Perso",
    "symbol": "house.fill",
    "theme": {
      "name": "matcha",
      "colors": [{ "red": 0.55, "green": 0.70, "blue": 0.33 }, { "red": 0.14, "green": 0.21, "blue": 0.10 }],
      "angle": 135
    },
    "order": 0,
    "profileId": "9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"
  }
}
```

- `modifiedAt` vient d'une horloge hybride : la plus grande valeur entre l'heure du Mac et le plus grand `modifiedAt` déjà reçu + 1 ms, en UTC à la milliseconde. Un appareil qui a reçu une modification écrit toujours après elle, même si son horloge retarde.
- `modifiedBy` est l'identifiant de l'appareil : un UUID créé à la première activation de la synchro.
- `deleted: true` marque une suppression. `fields` est alors vide.
- `schema` donne la version du format de `fields` pour ce type. Si un client reçoit un `schema` plus récent que le sien, il garde le contenu tel quel, ne modifie pas l'enregistrement et propose de mettre Matcha à jour. Les champs inconnus d'un `schema` connu sont ignorés.

### 2.3 Règles

- **Conflits :** enregistrement par enregistrement, la modification la plus récente gagne. On compare `modifiedAt`, puis `modifiedBy` en cas d'égalité (le plus grand gagne). Une suppression est une modification comme une autre : si une modification est plus récente qu'une suppression, elle recrée l'enregistrement.
- **Cascade :** l'appareil qui supprime un profil, un Space ou un dossier envoie aussi la suppression de tout ce qu'il contient.
- **Ordre d'application** d'un lot reçu : profils, Spaces, dossiers, onglets, Boosts. Si le parent d'un enregistrement est inconnu, l'enregistrement reste masqué jusqu'à la lecture suivante.
- **Rangs :** deux appareils peuvent donner le même `order`. À l'affichage, l'`id` les départage.
- **Confiance :** le client se fie au contenu déchiffré (`type`, `deleted`), jamais aux métadonnées envoyées par le serveur.

---

## 3. Chiffrement (serveurs privé et public)

### 3.1 Primitives

| Usage | Algorithme | API sur macOS |
| --- | --- | --- |
| Mot de passe → clé maître | PBKDF2-HMAC-SHA256, 600 000 itérations minimum, sel aléatoire de 16 octets, sortie de 32 octets | `CCKeyDerivationPBKDF` (CommonCrypto) |
| Sous-clés | HKDF-SHA256, sel vide, sortie de 32 octets | `HKDF<SHA256>` (CryptoKit) |
| Chiffrement | AES-256-GCM, nonce aléatoire de 12 octets, étiquette de 16 octets | `AES.GCM` (CryptoKit) |
| Aléa | générateur du système | `SymmetricKey(size:)`, `SecRandomCopyBytes` |

Notations : `HKDF(k, "info")` donne une sous-clé de 32 octets. `Seal(k, données, aad)` donne `nonce ‖ chiffré ‖ étiquette`.

Le mot de passe maître est normalisé en Unicode NFKD, puis encodé en UTF-8. Il fait au moins 12 caractères.

### 3.2 Clés

| Clé | Obtenue par | Reçue par le serveur | Rôle |
| --- | --- | --- | --- |
| `masterKey` | PBKDF2(mot de passe, `salt`, `iterations`) | non | dérive `authKey` et `wrapKey` ; jamais enregistrée |
| `authKey` | HKDF(masterKey, "matcha.auth.v1") | oui (il n'en garde qu'un hachage) | prouve la connaissance du mot de passe |
| `wrapKey` | HKDF(masterKey, "matcha.wrap.v1") | non | enveloppe la clé de compte |
| `accountKey` | 32 octets aléatoires, tirés à la création du compte | non | clé de toutes les données ; ne change pas avec le mot de passe |
| `dataKey` | HKDF(accountKey, "matcha.data.v1") | non | chiffre les enregistrements |
| `recoveryKey` | 20 octets aléatoires, tirés à la création du compte | non | clé de secours, gardée par l'utilisateur |
| `recoveryAuthKey` | HKDF(recoveryKey, "matcha.recovery-auth.v1") | oui (hachage) | prouve la connaissance de la clé de secours |
| `recoveryWrapKey` | HKDF(recoveryKey, "matcha.recovery-wrap.v1") | non | enveloppe aussi la clé de compte |

Le serveur stocke deux enveloppes de la clé de compte :

- `wrappedAccountKey` = Seal(wrapKey, accountKey, "matcha.account-key.v1")
- `recoveryWrappedAccountKey` = Seal(recoveryWrapKey, accountKey, "matcha.account-key.v1")

La clé de secours s'affiche en base 32 de Crockford : 32 caractères en 8 groupes de 4 (`7KQ2-M9XD-…`). À la saisie, espaces et tirets sont ignorés ; `O` vaut `0`, `I` et `L` valent `1`.

Côté serveur, `authKey` et `recoveryAuthKey` sont hachées avec Argon2id (conseillé) ou bcrypt. Le serveur ne garde jamais la valeur reçue.

### 3.3 Création du compte

1. `GET /v1/server` : vérifier la version de l'API et le mode d'inscription.
2. Tirer `salt`, `accountKey` et `recoveryKey`, puis calculer les clés du § 3.2.
3. `POST /v1/accounts` avec `kdf`, `authKey`, `recoveryAuthKey` et les deux enveloppes.
4. Afficher le kit de secours : adresse du serveur, identifiant, clé de secours. L'utilisateur doit l'enregistrer en PDF ou l'imprimer avant de continuer.
5. Garder `accountKey` dans le trousseau. Oublier le mot de passe, `masterKey` et `recoveryKey`.

### 3.4 Connexion d'un autre Mac

1. `POST /v1/auth/prelogin` renvoie les paramètres `kdf` du compte. Le client refuse des paramètres plus faibles que son propre minimum : un serveur malveillant ne peut pas affaiblir le calcul pour deviner plus vite le mot de passe.
2. Calculer `masterKey`, `authKey` et `wrapKey`.
3. `POST /v1/auth/login` renvoie les jetons et `wrappedAccountKey`.
4. Ouvrir `wrappedAccountKey` avec `wrapKey`. Le serveur refuse déjà un mauvais mot de passe à l'étape 3 ; un échec ici veut donc dire que l'enveloppe a été altérée.

### 3.5 Chiffrement d'un enregistrement

1. Encoder le contenu JSON (§ 2.2) en UTF-8, puis le compléter jusqu'à un multiple de 256 octets : un octet `0x80`, puis des `0x00` (ISO/IEC 7816-4). Le complément cache la taille exacte.
2. `aad` = `matcha.record.v1|<id en minuscules>|<keyVersion>`. Un contenu recopié sous un autre identifiant ne s'ouvre pas.
3. `payload` = `0x01` (version du format) ‖ Seal(dataKey, contenu complété, aad), en base 64.

À la lecture : vérifier l'octet de version, ouvrir, retirer le complément, décoder. Si une étape échoue, l'enregistrement est ignoré et jamais écrasé. L'erreur est journalisée et la synchro affiche « Données illisibles ».

`keyVersion` vaut 1. Il est réservé à une future rotation de la clé de compte (nouvelle `accountKey`, tous les enregistrements rechiffrés).

### 3.6 Changer le mot de passe maître

Un nouveau `salt` donne de nouvelles `masterKey`, `authKey` et `wrapKey`. Seule `accountKey` est réenveloppée : les données ne sont pas rechiffrées (`POST /v1/account/password`). Les autres appareils sont déconnectés et redemandent le mot de passe.

### 3.7 Mot de passe oublié

1. L'utilisateur saisit sa clé de secours. `POST /v1/auth/recover/start` avec `recoveryAuthKey` renvoie `recoveryWrappedAccountKey` et un jeton de récupération valable 10 minutes.
2. Le client ouvre l'enveloppe avec `recoveryWrapKey` et retrouve `accountKey`. L'utilisateur choisit un nouveau mot de passe, et le client prépare `kdf`, `authKey` et `wrappedAccountKey` comme au § 3.3.
3. `POST /v1/auth/recover/finish`. Les autres appareils sont déconnectés. Le client propose de créer une nouvelle clé de secours.

Si le mot de passe et la clé de secours sont tous les deux perdus, les données sont perdues. Il ne reste qu'à supprimer le compte et à repartir des données d'un Mac.

### 3.8 Sur le Mac

- **Trousseau** (`kSecClassGenericPassword`, service `com.matchabrowser.matcha.sync`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, sans synchronisation par iCloud) : `accountKey`, jetons, identifiant de l'appareil.
- **Jamais enregistrés :** mot de passe maître, `masterKey`, `recoveryKey`.
- **Base SwiftData :** en clair, comme aujourd'hui, protégée par la session macOS et FileVault.

### 3.9 Ce que voit le serveur

**Il voit :** l'identifiant (adresse e-mail), les paramètres `kdf`, les hachages d'`authKey` et de `recoveryAuthKey`, les enveloppes de la clé de compte, le nom et les dates des appareils. Pour chaque enregistrement, il voit aussi l'identifiant, la version, l'indicateur de suppression, la taille arrondie à 256 octets et la date d'écriture.

**Il ne voit pas :** le type des enregistrements, ni aucun nom, adresse, thème ou Boost, ni aucun contenu.

**Limites connues de la v1 :**
- Le serveur reçoit `authKey`. S'il est malveillant, il peut tester des mots de passe hors ligne, au prix d'un calcul PBKDF2 par essai. La longueur minimale et la jauge de solidité servent à ça.
- Un serveur malveillant peut cacher des enregistrements ou renvoyer d'anciennes versions sans être détecté. Il ne peut en revanche ni lire, ni fabriquer, ni déplacer un contenu.

---

## 4. API HTTP v1

### 4.1 Conventions

- **Adresse :** `https://<hôte>[/<chemin>]/v1/…`. HTTPS est obligatoire ; le client n'accepte `http` que pour `localhost`.
- **Format :** JSON en UTF-8 (`Content-Type: application/json`). Données binaires en base 64 standard, avec complément. Dates en ISO 8601, UTC, à la milliseconde. Les UUID se comparent sans tenir compte de la casse ; l'`aad` (§ 3.5) utilise leur forme en minuscules.
- **Identifiant :** l'adresse e-mail, sans espaces autour et en minuscules (normalisée par le client comme par le serveur). Un serveur privé n'est pas obligé de la vérifier.
- **Authentification :** `Authorization: Bearer <accessToken>`, sauf pour `/v1/server` et `/v1/auth/*`.
- **Client :** en-tête `Matcha-Client: <version> (<build>)` sur chaque requête. Un serveur peut refuser une version trop ancienne (`unsupported_client`).
- **Jetons :** opaques pour le client. Le jeton d'accès dure 15 minutes. Le jeton de renouvellement dure 60 jours glissants et ne sert qu'une fois. S'il est réutilisé, le serveur révoque l'appareil (vol probable).
- **Opérations sensibles :** changer le mot de passe ou la clé de secours, supprimer le compte. Elles exigent `authKey` en plus du jeton, ce qui revient à redemander le mot de passe.
- **Erreurs :** `application/problem+json` (RFC 9457) avec un `code` stable (§ 4.7). Le client affiche son propre message, traduit, d'après le `code`.
  ```json
  { "status": 401, "code": "invalid_credentials", "title": "Invalid credentials" }
  ```
- **Limites par défaut**, annoncées par `GET /v1/server` : 256 Kio par contenu chiffré, 500 changements et 4 Mio par envoi.
- **Débit :** au-delà, le serveur répond `429` avec `Retry-After`. Conseillé : 10 tentatives de connexion par quart d'heure pour une même adresse IP et un même identifiant.
- **Compatibilité :** des champs peuvent s'ajouter en v1, et le client ignore les champs inconnus. Tout changement incompatible passe par `/v2`.

### 4.2 Serveur

#### `GET /v1/server`

Sans authentification.

```json
{
  "api": 1,
  "software": "matcha-server 0.1.0",
  "registration": "invitation",
  "limits": {
    "maxPayloadBytes": 262144,
    "maxChangesPerPush": 500,
    "maxRequestBytes": 4194304,
    "maxAccountBytes": null
  },
  "minimumIterations": 600000,
  "features": ["events"]
}
```

- `registration` : `open`, `invitation` (code donné par l'administrateur) ou `closed`.
- `features` : contient `events` si le serveur fournit le flux d'événements (§ 4.6).

### 4.3 Inscription et sessions

Les réponses de connexion renvoient toutes un objet **Session** :

```json
{
  "accountId": "5D0C7A3E-2B1F-4E8D-9A6C-0F3B7E1D2C54",
  "deviceId": "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10",
  "accessToken": "…",
  "refreshToken": "…",
  "expiresIn": 900,
  "wrappedAccountKey": "…",
  "keyVersion": 1
}
```

#### `POST /v1/auth/prelogin`

```json
{ "email": "jeremy@example.com" }
```

Réponse `200` :

```json
{ "kdf": { "algorithm": "pbkdf2-sha256", "iterations": 600000, "salt": "q83vEjRWeJq83vEjRWeJqw==" } }
```

Pour un identifiant inconnu, le serveur répond avec des paramètres plausibles et stables : le sel est HMAC-SHA256(secret du serveur, identifiant), tronqué à 16 octets. On ne peut donc pas savoir quels comptes existent.

#### `POST /v1/accounts`

```json
{
  "email": "jeremy@example.com",
  "invitation": "K7QD-2MXP",
  "kdf": { "algorithm": "pbkdf2-sha256", "iterations": 600000, "salt": "q83vEjRWeJq83vEjRWeJqw==" },
  "authKey": "…",
  "wrappedAccountKey": "…",
  "recovery": { "authKey": "…", "wrappedAccountKey": "…" },
  "device": { "id": "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10", "name": "MacBook Pro" }
}
```

Réponse `201` : Session. `invitation` n'est requis que si `registration` vaut `invitation`.
Erreurs : `registration_closed`, `invitation_required`, `email_taken`, `weak_kdf`.

#### `POST /v1/auth/login`

```json
{ "email": "jeremy@example.com", "authKey": "…", "device": { "id": "…", "name": "Mac mini" } }
```

Réponse `200` : Session. Erreur : `invalid_credentials`.

#### `POST /v1/auth/refresh`

```json
{ "refreshToken": "…" }
```

Réponse `200` : `{ "accessToken": "…", "refreshToken": "…", "expiresIn": 900 }`. Erreurs : `invalid_token`, `device_revoked`.

#### `POST /v1/auth/logout`

Authentifié. Réponse `204`. Révoque les jetons de cet appareil.

#### `POST /v1/auth/recover/start`

```json
{ "email": "jeremy@example.com", "recoveryAuthKey": "…" }
```

Réponse `200` : `{ "recoveryToken": "…", "expiresIn": 600, "recoveryWrappedAccountKey": "…" }`. Erreur : `invalid_credentials`.

#### `POST /v1/auth/recover/finish`

```json
{
  "recoveryToken": "…",
  "kdf": { "algorithm": "pbkdf2-sha256", "iterations": 600000, "salt": "…" },
  "authKey": "…",
  "wrappedAccountKey": "…",
  "recovery": { "authKey": "…", "wrappedAccountKey": "…" },
  "device": { "id": "…", "name": "MacBook Pro" }
}
```

Réponse `200` : Session. Tous les autres appareils sont révoqués. `recovery` est facultatif : s'il est fourni, il remplace la clé de secours.
Erreurs : `invalid_token`, `weak_kdf`.

### 4.4 Compte

Toutes les routes de cette section sont authentifiées.

| Route | Corps | Réponse |
| --- | --- | --- |
| `GET /v1/account` | — | `200` `{ "accountId", "email", "createdAt", "usage": { "records", "bytes" }, "maxAccountBytes" }` |
| `POST /v1/account/password` | `{ "authKey", "kdf", "newAuthKey", "wrappedAccountKey" }` | `204` ; les autres appareils sont révoqués |
| `POST /v1/account/recovery` | `{ "authKey", "recovery": { "authKey", "wrappedAccountKey" } }` | `204` ; nouvelle clé de secours |
| `POST /v1/account/delete` | `{ "authKey" }` | `204` ; compte, appareils et enregistrements effacés tout de suite |

Erreurs : `invalid_credentials` (mauvaise `authKey`), `weak_kdf`.

### 4.5 Appareils

Toutes les routes de cette section sont authentifiées.

| Route | Corps | Réponse |
| --- | --- | --- |
| `GET /v1/devices` | — | `200` `{ "devices": [{ "id", "name", "createdAt", "lastSeenAt", "current" }] }` |
| `PATCH /v1/devices/{id}` | `{ "name" }` | `200` : l'appareil modifié |
| `DELETE /v1/devices/{id}` | — | `204` ; ses jetons sont révoqués. L'appareil reçoit alors `device_revoked` et garde ses données locales. |

### 4.6 Synchronisation

Toutes les routes de cette section sont authentifiées. Chaque compte a un compteur, qui augmente à chaque écriture ; la `version` d'un enregistrement est la valeur du compteur à sa dernière écriture.

Un **enregistrement**, tel que le serveur le renvoie :

```json
{
  "id": "7C4B2E9A-1D3F-4B6E-8A0C-5E2D9F1B3A76",
  "version": 1843,
  "deleted": false,
  "keyVersion": 1,
  "payload": "AQ…",
  "updatedAt": "2026-10-17T08:30:12.401Z"
}
```

Une suppression garde aussi son `payload` chiffré (§ 2.2, `deleted: true`). C'est lui qui fait foi pour le client.

#### `GET /v1/sync/changes?since=<cursor>&limit=<n>`

Renvoie les enregistrements écrits après `cursor`, par version croissante, au plus `limit` (500 par défaut, 1 000 au maximum). Sans `since`, la lecture part du début (première synchro).

```json
{ "changes": [ … ], "cursor": "c_1843", "hasMore": false }
```

- `cursor` est opaque. Le client le garde une fois le lot appliqué, et relit tant que `hasMore` vaut `true`.
- Les suppressions sont conservées au moins 180 jours. Un curseur plus ancien reçoit `410 cursor_expired` ; le client relit alors tout depuis le début (§ 5).

#### `POST /v1/sync/push`

En-tête `Idempotency-Key: <UUID>`. Si la même clé revient dans les 24 heures, le serveur renvoie la même réponse sans réécrire.

```json
{
  "changes": [
    { "id": "7C4B2E9A-…", "baseVersion": 1842, "deleted": false, "keyVersion": 1, "payload": "AQ…" },
    { "id": "E1A0F6B2-…", "baseVersion": null, "deleted": false, "keyVersion": 1, "payload": "AQ…" }
  ]
}
```

- `baseVersion` est la version sur laquelle repose le changement, ou `null` pour une création.
- Les changements sont traités un par un, dans l'ordre, chacun de façon atomique. Un changement est **appliqué** si `baseVersion` est égal à la version actuelle (ou vaut `null` pour un identifiant inconnu). Sinon, il est **en conflit** et rien n'est écrit pour lui.

Réponse `200` :

```json
{
  "results": [
    { "id": "7C4B2E9A-…", "status": "applied", "version": 1843 },
    { "id": "E1A0F6B2-…", "status": "conflict", "current": { "id": "E1A0F6B2-…", "version": 1790, "…": "…" } },
    { "id": "0B9D3C7E-…", "status": "rejected", "code": "payload_too_large" }
  ]
}
```

Codes d'un changement `rejected` : `payload_too_large`, `quota_exceeded`, `invalid_payload`. Erreurs sur la requête entière : `request_too_large`, `invalid_request`.

#### `GET /v1/sync/events`

Disponible si `features` contient `events`. Le flux est en `text/event-stream` (Server-Sent Events). Chaque fois qu'un autre appareil du compte a fait appliquer des changements, le serveur envoie :

```
event: changes
data: {"version":1843}

```

Il envoie aussi un commentaire `: ping` toutes les 30 secondes. À chaque événement, le client relit les changements. Si la connexion tombe, il se reconnecte avec un délai croissant, de 1 seconde à 5 minutes.

### 4.7 Codes d'erreur

| `code` | HTTP | Sens, et réaction du client |
| --- | --- | --- |
| `invalid_request` | 400 | Requête mal formée : bug, journalisé |
| `weak_kdf` | 400 | Itérations sous `minimumIterations` |
| `invalid_credentials` | 401 | Identifiant, `authKey` ou clé de secours faux |
| `token_expired` | 401 | Jeton d'accès expiré : le renouveler, puis rejouer la requête |
| `invalid_token` | 401 | Jeton inconnu : demander une nouvelle connexion |
| `device_revoked` | 401 | Appareil révoqué : se déconnecter et garder les données locales |
| `registration_closed` | 403 | Inscriptions fermées |
| `invitation_required` | 403 | Invitation absente, invalide ou déjà utilisée |
| `not_found` | 404 | Ressource inconnue |
| `email_taken` | 409 | Identifiant déjà utilisé |
| `cursor_expired` | 410 | Curseur trop ancien : tout relire depuis le début |
| `request_too_large` | 413 | Envoi trop gros : le découper |
| `unsupported_client` | 426 | Version de Matcha trop ancienne : proposer la mise à jour |
| `rate_limited` | 429 | Trop de requêtes : attendre `Retry-After` |
| `server_error` | 500 | Erreur du serveur : réessayer plus tard |
| `unavailable` | 503 | Maintenance : attendre `Retry-After` |

---

## 5. Déroulement côté client

**Déclencheurs :** une modification locale (regroupée sur 2 secondes), le lancement, le retour au premier plan, un événement du serveur, une lecture toutes les 15 minutes sans flux d'événements, et le bouton « Synchroniser maintenant ». Une seule synchro tourne à la fois.

**Un cycle :**
1. **Envoyer** les changements en attente, par lots, à partir de l'historique de SwiftData. Pour chaque conflit, déchiffrer `current` et appliquer la règle du § 2.3. Si le serveur a la version la plus récente, elle est appliquée en local et le changement local est abandonné. Sinon, le changement local repart avec `baseVersion` = `current.version`.
2. **Lire** les changements depuis le curseur jusqu'à `hasMore: false`. Déchiffrer chaque contenu, le vérifier, l'appliquer (§ 2.3) face aux changements locaux encore en attente.
3. **Garder** le curseur et le jeton d'historique de SwiftData.

**Première synchro, ou changement de mode :**
- Si les données synchronisées sont vides, le client envoie tout.
- Si ce Mac n'a que les données du premier lancement (profil « Personnel », Space « Perso », aucun favori ni épinglé), il prend les données synchronisées et retire les siennes. Sans ça, chaque Mac ajouterait son propre « Perso ».
- Sinon, il demande : **Fusionner** (par défaut : union par identifiant, règle du § 2.3), **Remplacer les données de ce Mac**, ou **Remplacer les données synchronisées**.

**Curseur expiré :** le client relit tout depuis le début. Un enregistrement local absent du serveur et sans changement en attente est supprimé.

**Appareil révoqué ou déconnexion :** la synchro s'arrête et les données locales restent. La clé de compte et les jetons sont retirés du trousseau.

---

## 6. iCloud

- Moteur : `CKSyncEngine`, sur la base privée du conteneur `iCloud.com.matchabrowser.matcha` (tâche 7.3), zone `Matcha`.
- Un `CKRecord` de type `Item` par enregistrement. Son `recordName` est l'`id`. Le contenu JSON du § 2.2 va dans `encryptedValues["payload"]`, sans complément ni chiffrement par Matcha : CloudKit le chiffre avec des clés du trousseau iCloud.
- Conflit (`serverRecordChanged`) : même règle qu'au § 2.3, à partir de l'enregistrement renvoyé par CloudKit.
- L'état du moteur (`CKSyncEngine.State.Serialization`) est gardé dans Application Support.
- Changement ou déconnexion du compte iCloud : la synchro s'arrête, les données locales restent, et les réglages affichent l'état.
- Pas de mot de passe maître : la protection est celle du compte Apple.

---

## 7. Serveur public

Même API, à une adresse fixée dans l'app (à définir), avec `registration: open`. Avant de l'ouvrir, il faudra décider de l'hébergement, des quotas (`maxAccountBytes`), de la vérification des adresses e-mail (routes à ajouter en v1), des conditions d'utilisation et de la procédure de suppression des comptes. En attendant, l'option reste grisée dans les réglages, avec la mention « Bientôt disponible ».

---

## 8. Questions ouvertes

- **Argon2id plutôt que PBKDF2** côté client, pour mieux résister aux essais hors ligne. Il faudrait une bibliothèque (libsodium ou équivalent), donc ton accord. Le champ `kdf.algorithm` permet de migrer plus tard, compte par compte.
- **Protection contre un serveur qui cache ou rejoue des versions :** un journal signé des versions, en v2.
- **Synchroniser plus :** historique, réglages, permissions des sites. Plus tard, et au choix de l'utilisateur.
- **Langage du serveur de référence :** à choisir avant la tâche 7.8.
