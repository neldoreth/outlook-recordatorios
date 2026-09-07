#!/bin/bash
# Envía un correo de prueba al manejador de recordatoriooutlook:// y muestra
# el diálogo real de la app, sin pasar por Outlook. Útil para depurar el
# formato de las notas o el enlace sin tener que instalar el add-in.
set -euo pipefail

TITULO="Correo de prueba"
ASUNTO="Re: Asunto de ejemplo"
CUERPO=$'Hola,\n\nEsto es un cuerpo de prueba con varias líneas.\n\nUn saludo'
ENLACE="https://outlook.office365.com/owa/?ItemID=EJEMPLO&exvsurl=1&viewmodel=ReadMessageItem"
REMITENTE="Persona de Ejemplo <ejemplo@dominio.com>"

codificar() {
	python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""), end="")' "$1"
}

URL="recordatoriooutlook://crear?titulo=$(codificar "$TITULO")&asunto=$(codificar "$ASUNTO")&cuerpo=$(codificar "$CUERPO")&enlace=$(codificar "$ENLACE")&remitente=$(codificar "$REMITENTE")"

echo "Abriendo: $URL"
open "$URL"
