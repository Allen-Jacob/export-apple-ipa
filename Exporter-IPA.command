#!/bin/bash
set -euo pipefail

# Usage : bash Exporter-IPA.command [dossier-projet] [dossier-sortie] [scheme]
log=''
child=''
work=''
fail() { printf '\n  ✗ %s\n' "$*" >&2; [[ -z $log ]] || printf '  Journal : %s\n' "$log" >&2; exit 1; }
cleanup() {
  if [[ -n $child ]]; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
  [[ -z $work ]] || rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'fail "L’opération a échoué (ligne $LINENO)."' ERR
run_step() {
  local label=$1 status=0 tick=0 bar
  shift
  { printf '\n--- %s ---\n' "$label"; printf '%q ' "$@"; printf '\n'; } >> "$log"
  "$@" >> "$log" 2>&1 &
  child=$!
  if [[ -t 1 ]]; then
    while kill -0 "$child" 2>/dev/null; do
      case $((tick % 4)) in
        0) bar='====                ' ;; 1) bar='     ====           ' ;;
        2) bar='          ====      ' ;; 3) bar='               ====' ;;
      esac
      printf '\r  [%s] %s\033[K' "$bar" "$label"
      tick=$((tick + 1))
      sleep 0.3
    done
  else
    printf '  … %s\n' "$label"
  fi
  wait "$child" || status=$?
  child=''
  if [[ -t 1 ]]; then printf '\r\033[K'; fi
  [[ $status -eq 0 ]] || fail "$label : échec (code $status). Consulte le journal."
  printf '  ✓ %s\n' "$label"
}
if [[ ${1:-} == --help ]]; then
  printf '%s\n' 'Usage : bash Exporter-IPA.command [dossier-projet] [dossier-sortie] [scheme]' 'Paramètres par défaut : export.config, à côté du script.' 'Les arguments remplacent les valeurs de export.config.' 'Sortie par défaut : dossier IPA-Exports dans ton dossier personnel.' 'Par défaut : IPA non signé. Export signé : définir EXPORT_OPTIONS_PLIST.'
  exit 0
fi
[[ $# -le 3 ]] || fail 'Trop d’arguments. Utilise --help.'
[[ $(uname -s) == Darwin ]] || fail 'Ce script nécessite macOS et Xcode.'
xcrun --find xcodebuild >/dev/null 2>&1 || fail 'Installe Xcode et sélectionne-le avec xcode-select.'
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_PATH=''
OUTPUT_DIR=''
SCHEME=''
BUILD_CONFIGURATION=Release
EXPORT_OPTIONS_PLIST=${EXPORT_OPTIONS_PLIST:-}
if [[ -f "$script_dir/export.config" ]]; then
  # Fichier Bash local : ne charger qu’une configuration de confiance.
  source "$script_dir/export.config"
fi
if [[ -f "$script_dir/export.local.config" ]]; then
  source "$script_dir/export.local.config"
fi
project=${1:-$SOURCE_PATH}
default_source=''
default_output="$HOME/IPA-Exports"
output=${2:-$OUTPUT_DIR}
scheme=${3:-$SCHEME}
printf '\n  ┌─────────────────────────────┐\n  │       EXPORT IPA · Xcode    │\n  └─────────────────────────────┘\n\n'
if [[ -z $project ]]; then
  [[ -t 0 ]] || fail 'Fournis le dossier source en premier argument.'
  printf '  Source [%s] : ' "$default_source"
  read -r project
  project=${project:-$default_source}
  [[ -n $project ]] || fail "Indique le chemin du projet Xcode."
fi
if [[ -z $output ]]; then
  if [[ -t 0 ]]; then
    printf '  Destination [%s] : ' "$default_output"
    read -r output
  fi
  output=${output:-$default_output}
fi
case "$output" in '~/'*) output="$HOME/${output:2}" ;; esac
# Accepte aussi ~/… saisi dans le Terminal.
case "$project" in '~/'*) project="$HOME/${project:2}" ;; esac
[[ $project == / ]] || project=${project%/}
[[ -d $project ]] || fail "Dossier introuvable : $project"
project=$(cd "$project" && pwd)
case "$project" in
  *.xcworkspace|*.xcodeproj) ;;
  *)
    candidates=()
    while IFS= read -r -d '' candidate; do
      candidates+=("$candidate")
    done < <(find "$project" -type d \( -name .git -o -name .swiftpm -o -name .build -o -name node_modules -o -name Pods -o -name Carthage -o -name build -o -name DerivedData \) -prune -o -type d \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) -print0 -prune)
    [[ ${#candidates[@]} -gt 0 ]] || fail 'Aucun projet Xcode trouvé dans ce dossier.'
    workspaces=()
    for candidate in "${candidates[@]}"; do
      [[ $candidate != *.xcworkspace ]] || workspaces+=("$candidate")
    done
    if [[ ${#workspaces[@]} -gt 0 ]]; then candidates=("${workspaces[@]}"); fi
    if [[ ${#candidates[@]} -eq 1 ]]; then
      project=${candidates[0]}
    else
      [[ -t 0 ]] || fail 'Plusieurs projets trouvés : passe le chemin du .xcodeproj ou .xcworkspace directement.'
      printf 'Plusieurs projets trouvés. Choisis un numéro :\n'
      PS3='Projet : '
      select candidate in "${candidates[@]}"; do
        if [[ -n $candidate ]]; then project=$candidate; break; fi
      done
      [[ $project == *.xcodeproj || $project == *.xcworkspace ]] || fail 'Aucun projet sélectionné.'
    fi
    ;;
esac
case "$project" in
  *.xcworkspace) container=(-workspace "$project") ;;
  *.xcodeproj) container=(-project "$project") ;;
esac
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/export-ipa.XXXXXX")
run_id="$(date +%Y%m%d-%H%M%S)-${work##*.}"
log="$output/compilation-$run_id.log"
: > "$log"
if [[ -z $scheme ]]; then
  run_step '1/4 · Détection du scheme' xcodebuild "${container[@]}" -list
  listing=$(cat "$log")
  schemes=()
  while IFS= read -r item; do
    [[ -z $item ]] || schemes+=("$item")
  done < <(printf '%s\n' "$listing" | awk '/^[[:space:]]*Schemes:/{active=1;next} active && /^[[:space:]]*$/{active=0} active {sub(/^[[:space:]]+/, ""); print}')
  [[ ${#schemes[@]} -gt 0 ]] || fail 'Aucun scheme disponible. Configure un scheme dans Xcode.'
  preferred=$(basename "$project")
  preferred=${preferred%.*}
  for item in "${schemes[@]}"; do
    if [[ $item == "$preferred" ]]; then scheme=$item; break; fi
  done
  if [[ -n $scheme ]]; then
    :
  elif [[ ${#schemes[@]} -eq 1 ]]; then
    scheme=${schemes[0]}
  else
    [[ -t 0 ]] || fail 'Plusieurs schemes disponibles : passe le scheme comme troisième argument.'
    printf 'Choisis le scheme de ton application :\n'
    PS3='Scheme : '
    select item in "${schemes[@]}"; do
      if [[ -n $item ]]; then scheme=$item; break; fi
    done
  fi
fi
[[ -n $scheme ]] || fail 'Un scheme est nécessaire.'
printf '\n  Projet : %s\n  Scheme : %s\n  Sortie : %s\n\n' "$project" "$scheme" "$output"
archive="$work/Application.xcarchive"
options=${EXPORT_OPTIONS_PLIST:-}
case "$options" in '~/'*) options="$HOME/${options:2}" ;; esac
cmd=(xcodebuild "${container[@]}" -scheme "$scheme" -configuration "$BUILD_CONFIGURATION" -destination 'generic/platform=iOS' -archivePath "$archive" archive)
if [[ -z $options ]]; then
  cmd+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY=')
else
  [[ -f $options ]] || fail "ExportOptions.plist introuvable : $options"
  cmd+=(-allowProvisioningUpdates)
fi
run_step "2/4 · Compilation et archive" "${cmd[@]}"
if [[ -n $options ]]; then
  run_step "3/4 · Export signé" xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -exportPath "$work/export" -allowProvisioningUpdates
  shopt -s nullglob
  ipas=("$work/export/"*.ipa)
  [[ ${#ipas[@]} -eq 1 ]] || fail 'L’export doit produire exactement un IPA ; consulte le journal.'
  result="$output/Application-$run_id.ipa"
  cp "${ipas[0]}" "$result"
else
  shopt -s nullglob
  apps=("$archive/Products/Applications/"*.app)
  [[ ${#apps[@]} -eq 1 ]] || fail 'L’archive doit contenir exactement une application iOS ; vérifie le scheme et SKIP_INSTALL.'
  platform=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "${apps[0]}/Info.plist")
  [[ $platform == iPhoneOS ]] || fail 'L’application archivée ne cible pas un appareil iOS.'
  mkdir "$work/package" "$work/package/Payload"
  run_step "3/4 · Préparation de l’IPA" ditto "${apps[0]}" "$work/package/Payload/$(basename "${apps[0]}")"
  result="$output/Application-$run_id-non-signe.ipa"
  run_step "3/4 · Création de l’IPA" ditto -c -k --keepParent "$work/package/Payload" "$result"
fi
run_step "4/4 · Vérification de l’IPA" unzip -t "$result"
printf '\nIPA créé : %s\nJournal : %s\n' "$result" "$log"
if [[ -z $options ]]; then
  printf 'Cet IPA est non signé : une signature est nécessaire avant installation sur un iPhone.\n'
fi

