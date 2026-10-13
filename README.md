# Export Apple IPA

Un script simple pour compiler une application iOS depuis un projet Xcode et créer un fichier `.ipa`. Les étapes s’affichent dans le Terminal et les détails sont enregistrés dans un journal.

## 1. Installer les prérequis

Il faut un **Mac avec Xcode complet** installé depuis le Mac App Store. Ouvre Xcode une première fois et termine l’installation des composants iOS proposés.

Si le script ne trouve pas Xcode, sélectionne son installation :

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Ton projet doit déjà compiler pour iOS et proposer un scheme permettant l’action Archive. Ce script exporte une application existante ; il ne crée pas de projet Xcode.

## 2. Télécharger le projet

Dans le Terminal :

```bash
git clone https://github.com/Allen-Jacob/export-apple-ipa.git
cd export-apple-ipa
```

Tu peux aussi choisir **Code → Download ZIP** sur GitHub, décompresser l’archive puis ouvrir un Terminal dans le dossier obtenu.

## 3. Configurer

Crée ta configuration personnelle :

```bash
cp export.config export.local.config
open -e export.local.config
```

Modifie surtout la source :

```bash
SOURCE_PATH="$HOME/Projects/MonApplication"
OUTPUT_DIR="$HOME/IPA-Exports"
SCHEME=""
BUILD_CONFIGURATION="Release"
```

- `SOURCE_PATH` : dossier contenant le projet, ou chemin direct vers un `.xcodeproj` ou `.xcworkspace`. Vide : le script demande le chemin au lancement.
- `OUTPUT_DIR` : dossier de destination des IPA et journaux, créé si nécessaire.
- `SCHEME` : vide pour la détection automatique ; renseigne le nom du scheme pour automatiser l’export.
- `BUILD_CONFIGURATION` : `Release` par défaut.
- `EXPORT_OPTIONS_PLIST` : option de signature décrite plus bas.

Entoure les chemins de guillemets pour conserver les espaces. Les chemins absolus et `$HOME` sont recommandés ; les chemins relatifs partent du dossier courant du Terminal. Les fichiers de configuration utilisent la syntaxe Bash et sont exécutés par le script : utilise uniquement une configuration de confiance.

Le script charge `export.config`, puis `export.local.config` si présent. Les arguments de commande ont priorité sur la source, la destination et le scheme. La configuration personnelle est ignorée par Git.

## 4. Exporter

```bash
bash Exporter-IPA.command
```

Si plusieurs projets ou schemes sont trouvés, choisis dans la liste affichée. Pour éviter toute question, définis une source précise et un scheme.

Tu peux aussi passer les paramètres directement :

```bash
bash Exporter-IPA.command "$HOME/Projects/MonApplication/MonApplication.xcodeproj" "$HOME/IPA-Exports" MonApplication
```

À la fin, le Terminal affiche le chemin du fichier IPA et du journal `compilation-*.log`. Chaque export utilise un nom distinct.

```bash
open "$HOME/IPA-Exports"
```

## Export signé (facultatif)

Par défaut, le script produit un **IPA non signé**, qui nécessite une signature avant installation sur un iPhone. Il ne crée ni certificat ni profil Apple.

Pour un export signé, configure la signature dans Xcode avec ton compte Apple et prépare un `ExportOptions.plist` adapté à ton mode de distribution, par exemple à partir d’un export réussi dans Xcode. Ajoute son chemin dans `export.local.config` :

```bash
EXPORT_OPTIONS_PLIST="$HOME/Projects/ExportOptions.plist"
```

Le script utilise alors `xcodebuild -exportArchive` et autorise la mise à jour des profils de provisioning. Les certificats et profils nécessaires doivent déjà être accessibles sur ton Mac. Les réglages de signature et les options d’export dépendent du projet et du compte Apple.

## Aide et dépannage

```bash
bash Exporter-IPA.command --help
```

- **Xcode introuvable** : installe Xcode complet et sélectionne-le avec la commande de l’étape 1.
- **Aucun projet trouvé** : indique le dossier du projet ou son `.xcodeproj` / `.xcworkspace`.
- **Compilation échouée** : ouvre le journal indiqué et vérifie que le projet compile dans Xcode pour un appareil iOS.
- **Plusieurs projets ou schemes en automatisation** : fournis un chemin précis et le scheme.
- **Archive sans application** : vérifie le scheme et le réglage `SKIP_INSTALL` de la cible application.

La vérification finale contrôle l’intégrité ZIP de l’IPA. Elle ne valide pas son installation ni sa signature sur un appareil.

## Conserver le tutoriel en PDF

Ce README suffit pour l’installation. Pour une copie PDF, ouvre cette page GitHub dans ton navigateur, utilise **Imprimer**, puis **Enregistrer au format PDF**.
