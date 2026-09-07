#!/bin/bash
# Compila recordatorio.applescript en una app lanzable.
set -euo pipefail

ORIGEN="$(cd "$(dirname "$0")" && pwd)/recordatorio.applescript"
DESTINO="${1:-$HOME/Applications/Recordatorio desde Outlook.app}"

mkdir -p "$(dirname "$DESTINO")"
rm -rf "$DESTINO"
osacompile -o "$DESTINO" "$ORIGEN"

PLIST="$DESTINO/Contents/Info.plist"
set_key() { /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"; }

set_key NSRemindersUsageDescription               "Crear el recordatorio a partir del correo."
set_key NSRemindersFullAccessUsageDescription     "Crear el recordatorio a partir del correo."
set_key CFBundleName                              "Recordatorio desde Outlook"

# Registra el esquema de URL que usa el add-in de Outlook para entregar los
# datos del correo (recordatoriooutlook://crear?...).
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.oscar.recordatoriooutlook" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string recordatoriooutlook" "$PLIST"

# Firma ad-hoc: mantiene estable la identidad para los permisos de privacidad,
# así macOS no vuelve a preguntar en cada recompilación.
codesign --force --deep --sign - "$DESTINO"

# macOS debe releer el registro de esquemas de URL de la app.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINO" >/dev/null 2>&1 || true

echo "Creada: $DESTINO"
