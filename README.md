# Windows Services Optimizer

Script PowerShell interactif pour alleger Windows 11 (build >= 22621).

## Utilisation

```powershell
# Mode simulation (aucune modification)
.\Optimize-Windows.ps1 -DryRun

# Mode reel (execution en admin obligatoire)
.\Optimize-Windows.ps1
```

## Avertissements

- Execute uniquement sur Windows 11 22H2+.
- Cree automatiquement un point de restauration + des sauvegardes CSV.
- Les paquets AppX desinstalles ne peuvent etre restaures que manuellement via le Microsoft Store.

## Voir aussi

- `docs/superpowers/specs/2026-04-21-windows-services-optimizer-design.md` — design complet.
