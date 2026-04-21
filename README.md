# Windows Services Optimizer

Script PowerShell interactif pour alléger Windows 11 (build ≥ 22621) en posant des questions d'usage puis en désactivant les services, tâches planifiées, fonctionnalités optionnelles et paquets AppX non utilisés.

## Prérequis

- Windows 11 22H2 ou supérieur (build ≥ 22621)
- PowerShell 5.1+ (inclus dans Windows 11)
- Droits administrateur

## Utilisation

### Mode simulation (recommandé pour découvrir)

```powershell
.\Optimize-Windows.ps1 -DryRun
```

Aucune modification n'est appliquée. Les questions sont posées et le script affiche ce qui serait fait.

### Mode réel

```powershell
.\Optimize-Windows.ps1
```

Le script :
1. Vérifie l'élévation administrateur et la version Windows.
2. Crée un point de restauration système.
3. Exporte l'état actuel de tous les items concernés dans `backups/<timestamp>/`.
4. Te pose 14 questions par catégorie d'usage (imprimante, Xbox, Bluetooth, etc.).
5. Te propose une section avancée item par item (21 items).
6. Affiche un récapitulatif et demande confirmation finale.
7. Applique les modifications et génère `Restore-<timestamp>.ps1` pour annuler.

## Restauration

Trois niveaux disponibles :

1. **Restauration fine** — exécuter `backups/<timestamp>/Restore-<timestamp>.ps1` en admin pour réactiver uniquement les éléments modifiés.
2. **Restauration système** — utiliser le point de restauration créé automatiquement avant modification.
3. **Paquets AppX** — doivent être réinstallés manuellement via le Microsoft Store (limitation technique : le paquet source n'est pas conservé localement après désinstallation).

## Services protégés

Le script refuse catégoriquement de désactiver les services vitaux (Audio, WinDefend, RpcSs, Dhcp, EventLog, etc.) même s'ils figurent dans le catalogue. La liste exacte est définie dans `$script:ProtectedServices` en tête de `Optimize-Windows.ps1`.

## Catalogue

Le fichier `catalog.json` contient :
- **14 catégories** groupées par usage (Imprimante, Fax, Bluetooth, Xbox, Hyper-V, WSL, RDP, SMB, GPS, Hello, tactile, OneDrive, Cortana, Télémétrie)
- **21 items avancés** (services, AppX, features posés individuellement en fin de parcours)

Tu peux l'éditer pour personnaliser les questions ou ajouter des services — le script valide la structure au démarrage et refuse tout item incluant un service protégé.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester -Path tests/
```

Les tests utilisent `Mock` Pester pour les cmdlets Windows-only (`Get-Service`, `Get-ScheduledTask`, etc.) et s'exécutent donc aussi bien sur Linux / macOS (développement) que sur Windows.

## Avertissements

- **Teste d'abord en `-DryRun`** avant toute exécution réelle.
- Désactiver la télémétrie et certains services Xbox/OneDrive peut affecter des fonctionnalités Windows (Store, Hello, synchro…).
- Sur une machine professionnelle, vérifie avec ton admin IT avant de désinstaller Teams ou des features Entreprise.
- Un redémarrage est recommandé après exécution pour que tous les changements prennent effet.

## Design

Voir `docs/superpowers/specs/2026-04-21-windows-services-optimizer-design.md`.
