# Windows Services Optimizer — Design

**Date** : 2026-04-21
**Statut** : Validé (brainstorming)
**Cible** : Windows 11 build ≥ 22621 (22H2+)

## 1. Objectif

Fournir un script PowerShell interactif qui allège une installation Windows 11 en posant des questions d'usage à l'utilisateur (imprimante, Bluetooth, Xbox, télémétrie, etc.) et en désactivant les services, tâches planifiées, fonctionnalités optionnelles et applications AppX qui ne lui servent pas — avec un filet de sécurité complet (point de restauration + export CSV + script de rollback).

## 2. Choix validés

| Décision | Choix |
|----------|-------|
| Technologie | PowerShell `.ps1` console |
| Style d'interaction | Hybride : questions par catégorie + section avancée item par item |
| Filet de sécurité | Point de restauration + CSV d'état initial + script `Restore-<timestamp>.ps1` |
| Portée | Services + tâches planifiées + fonctionnalités optionnelles + applications AppX |
| Version OS | Windows 11 (build ≥ 22621) uniquement |
| Architecture | Moteur `.ps1` + catalogue `.json` (séparation données/logique) |

## 3. Architecture

### Structure de fichiers

```
WinServices/
├── Optimize-Windows.ps1       # Moteur (orchestration + UI console)
├── catalog.json               # Données : catégories + section avancée
├── README.md                  # Usage + avertissements
└── backups/                   # Généré à l'exécution
    ├── services-<timestamp>.csv
    ├── tasks-<timestamp>.csv
    ├── features-<timestamp>.csv
    ├── appx-<timestamp>.csv
    └── Restore-<timestamp>.ps1
```

### Responsabilités du moteur

- Vérifier l'élévation administrateur (relance `-Verb RunAs` si besoin).
- Vérifier la version Windows (build ≥ 22621) — abort sinon.
- Charger et valider `catalog.json` (schéma minimal).
- Créer un point de restauration système.
- Exporter les CSV d'état initial.
- Dérouler la phase catégories, puis la phase avancée.
- Afficher un récapitulatif + double confirmation avant application.
- Dispatcher chaque item vers son handler selon `type` (service / task / feature / appx).
- Écrire au fur et à mesure le script `Restore-<timestamp>.ps1` inverse.
- Afficher le bilan final (succès / échecs, chemin du dossier backups).

Principe SOLID (SRP + OCP) : le moteur ne connaît pas la liste des services. Ajouter une catégorie = éditer le JSON, aucun code à modifier.

### Handlers (4 types)

| type    | Action `disable`                                        | Action `restore`                        |
|---------|---------------------------------------------------------|-----------------------------------------|
| service | `Stop-Service` + `Set-Service -StartupType Disabled`    | `Set-Service -StartupType <initial>` + `Start-Service` si initial `Running` |
| task    | `Disable-ScheduledTask`                                 | `Enable-ScheduledTask`                  |
| feature | `Disable-WindowsOptionalFeature -Online -NoRestart`     | `Enable-WindowsOptionalFeature -Online -NoRestart` |
| appx    | `Get-AppxPackage <name> \| Remove-AppxPackage`          | Commentaire documentatoire — réinstallation via Microsoft Store (cf. §6) |

## 4. Format `catalog.json`

```json
{
  "version": "1.0",
  "minWindowsBuild": 22621,
  "categories": [
    {
      "id": "printing",
      "question": "Utilises-tu une imprimante (locale ou réseau) ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "Spooler", "description": "File d'impression" },
        { "type": "service", "name": "PrintNotify" },
        { "type": "task",    "name": "\\Microsoft\\Windows\\Printing\\EduPrintProv" }
      ]
    }
  ],
  "advanced": [
    { "type": "service", "name": "Fax", "description": "Service de fax" }
  ]
}
```

### Champs

- `version` : version du schéma (évolution future).
- `minWindowsBuild` : build minimum supporté. Le moteur refuse de tourner en-dessous.
- `categories[]` : questions groupées par thématique d'usage.
  - `id` : identifiant stable (logs, debug).
  - `question` : texte affiché.
  - `keepIfYes` : `true` = "oui j'utilise → on garde" ; `false` = "oui je veux désactiver → on désactive". Évite les doubles négations.
  - `items[]` : éléments impactés par la catégorie.
- `advanced[]` : items posés individuellement en fin de parcours (chacun sa question).

### Champs d'item

- `type` : `service | task | feature | appx` (dispatch handler).
- `name` : identifiant natif selon le type (nom de service, TaskPath complet, FeatureName, AppX Name).
- `description` *(optionnel)* : texte affiché à côté du nom pour aider l'utilisateur.

## 5. Flux d'exécution

1. **Démarrage**
   - Élévation admin (relance si besoin).
   - Vérif build Windows ≥ `minWindowsBuild`.
   - Chargement + validation `catalog.json`.
2. **Avertissement initial** + consentement `[O/N]`.
3. **Sauvegardes préalables**
   - `backups/<timestamp>/` créé.
   - Export `services.csv`, `tasks.csv`, `features.csv`, `appx.csv` filtrés sur les items du catalogue.
   - `Checkpoint-Computer -RestorePointType MODIFY_SETTINGS` (fallback `APPLICATION_INSTALL` si limite 24h).
4. **Phase catégories** : pour chaque catégorie → question, lecture `[O/N/S]`, marquage KEEP/DISABLE selon `keepIfYes`.
5. **Phase avancée** : pour chaque item dans `advanced[]` → question individuelle avec description.
6. **Récapitulatif** : nombre d'items par type à désactiver + option "voir détail" + confirmation finale `[O/N]`.
7. **Application** : dispatch handler, log chaque opération, append commande inverse dans `Restore-<timestamp>.ps1`.
8. **Clôture** : bilan (N succès / M échecs), chemin absolu du dossier backups, rappel redémarrage.

### Conventions UX console

- Couleurs : cyan = question, jaune = avertissement, rouge = action destructive (AppX, télémétrie), vert = succès, gris = info.
- Touches : `O`/`Y` = oui, `N` = non, `S` = skip catégorie, `Ctrl+C` = abort propre.
- Actions destructives (AppX, features) : double confirmation (question catégorie + confirmation finale globale).

## 6. Sauvegarde & restauration

### CSV d'export (exemples)

**`services.csv`** : `Name, StartType, Status, DisplayName`
**`tasks.csv`** : `TaskPath, TaskName, State`
**`features.csv`** : `FeatureName, State`
**`appx.csv`** : `Name, PackageFullName, Publisher`

### `Restore-<timestamp>.ps1`

Script PowerShell exécutable généré incrémentalement, contenant les commandes inverses pour chaque item effectivement modifié (pas juste marqué). Une section commentée par type.

### Point de restauration

`Enable-ComputerRestore -Drive "C:\"` puis `Checkpoint-Computer`.
Gestion de la limite 24h de Windows : si échec, warning non-bloquant (les CSV restent le filet principal).

### ⚠ Limitation AppX

Les paquets AppX désinstallés **ne sont pas restaurables automatiquement** (le `.appx` source n'est pas conservé). Le `Restore.ps1` documente en commentaires les paquets retirés ; la réinstallation passe par le Microsoft Store. Un **avertissement explicite** est affiché avant la phase AppX.

## 7. Catalogue initial

### Catégories (14)

1. Imprimante — `Spooler`, `PrintNotify`, `PrintWorkflowUserSvc`, tâche `EduPrintProv`
2. Fax — service `Fax`
3. Bluetooth — `bthserv`, `BluetoothUserService`, `BTAGService`, `BthAvctpSvc`
4. Xbox / Game Bar — `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc` + AppX `XboxGamingOverlay`, `GamingApp`, `Xbox.TCUI`, `XboxSpeechToTextOverlay`
5. Hyper-V — services `vmcompute`, `vmms`, `HvHost`, `vmic*` + feature `Microsoft-Hyper-V-All`
6. WSL — features `Microsoft-Windows-Subsystem-Linux`, `VirtualMachinePlatform`
7. Bureau à distance (RDP entrant) — `TermService`, `SessionEnv`, `UmRdpService`
8. Partage SMB — `LanmanServer`, `Browser`
9. Localisation (GPS) — `lfsvc`
10. Biométrie (Windows Hello) — `WbioSrvc`
11. Clavier tactile / encre — `TabletInputService`, `TextInputManagementService`
12. OneDrive — AppX `Microsoft.OneDriveSync`, tâches `OneDrive Standalone Update Task-*`
13. Cortana & Bing — AppX `Microsoft.549981C3F5F10`
14. **Télémétrie Microsoft** (inversé) — `DiagTrack`, `dmwappushservice`, `WerSvc`, `PcaSvc`, `WdiServiceHost`, `WdiSystemHost` + tâches Compatibility Appraiser, CEIP Consolidator, USB CEIP, AitAgent, ProgramDataUpdater, DiskDiagnosticDataCollector

### Section avancée (22 items)

Services : `Fax`, `RetailDemo`, `MapsBroker`, `WMPNetworkSvc`, `PhoneSvc`, `SCardSvr`, `ScDeviceEnum`, `SEMgrSvc`, `SharedAccess`, `WalletService`.
AppX : `Microsoft.BingNews`, `Microsoft.BingWeather`, `Microsoft.YourPhone`, `Microsoft.MicrosoftSolitaireCollection`, `Microsoft.People`, `MicrosoftTeams`, `Clipchamp.Clipchamp`, `Microsoft.ZuneMusic`, `Microsoft.ZuneVideo`.
Features : `Internet-Explorer-Optional-amd64`, `WindowsMediaPlayer`, `WorkFolders-Client`.

### Services protégés (jamais touchés — liste noire codée dans le moteur)

`AudioSrv`, `AudioEndpointBuilder`, `BFE`, `CryptSvc`, `Dhcp`, `Dnscache`, `EventLog`, `LSM`, `MpsSvc`, `NlaSvc`, `Power`, `ProfSvc`, `RpcEptMapper`, `RpcSs`, `Schedule`, `SENS`, `Themes`, `UserManager`, `WinDefend`, `Winmgmt`, `wscsvc`.

Le moteur refuse de désactiver ces services même s'ils apparaissent dans le JSON (garde-fou contre une édition hasardeuse du catalogue).

## 8. Gestion d'erreurs

- Chaque handler encapsule son opération dans `try/catch`.
- Un item en échec est logué en rouge mais ne stoppe pas la boucle.
- Le bilan final liste les échecs avec l'exception associée.
- Le `Restore.ps1` n'inclut **que** les items effectivement modifiés (pas ceux en échec).

## 9. Tests (stratégie)

Le script cible Windows en environnement admin, donc les tests unitaires purs sont limités. Plan :

- **Mode `-DryRun`** : exécute tout le flux sauf les mutations (pas de `Set-Service`, pas de `Remove-AppxPackage`, etc.). Affiche en vert ce qui aurait été fait. → Mode par défaut pour les premiers lancements utilisateur.
- **Validation du catalogue** : une fonction `Test-Catalog` vérifie la structure JSON, l'absence de `name` en doublon, et qu'aucun item `service` n'est dans la liste noire. À exécuter avant chaque release.
- **Tests manuels** : VM Windows 11 fraîche, exécution `-DryRun` puis exécution réelle, vérification du `Restore.ps1`.

## 10. Hors scope (explicitement exclus)

- Windows 10, Windows Server, Windows Home ≤ 21H2.
- Modification de clés de registre (debloat registre → script séparé si besoin).
- Modification de la stratégie de groupe (`gpedit`).
- Gestion du pilote/driver level.
- Restauration automatique des paquets AppX (cf. §6).
- Interface graphique (WPF/WinForms).
