#!/bin/bash
# Configura, autentica e instala el poller como LaunchAgent (arranca solo
# al iniciar sesión).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$REPO/poller/config.json"
LABEL="com.oscar.recordatoriooutlook.poller"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/recordatoriooutlook-poller.log"

if [ ! -f "$CONFIG" ]; then
	echo "Primera vez: hay que rellenar poller/config.json"
	echo
	read -r -p "Id. de directorio (tenant) de Entra ID: " TENANT_ID
	read -r -p "Id. de aplicación (cliente) de Entra ID: " CLIENT_ID
	read -r -p "Tu correo de la cuenta de M365: " CUENTA

	python3 - "$CONFIG" "$TENANT_ID" "$CLIENT_ID" "$CUENTA" <<'PY'
import json, sys
path, tenant_id, client_id, cuenta = sys.argv[1:5]
with open(path, "w") as f:
    json.dump({"tenant_id": tenant_id, "client_id": client_id, "cuenta": cuenta}, f, indent=2)
PY
	echo "Guardado en $CONFIG"
fi

echo
echo "Autenticando (una vez, hace falta abrir un navegador y escribir un código)…"
python3 "$REPO/poller/poller.py" --login

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/python3</string>
		<string>$REPO/poller/poller.py</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo
echo "Poller instalado y en marcha (sondeando cada ${INTERVALO:-5}s)."
echo "Log: $LOG"
