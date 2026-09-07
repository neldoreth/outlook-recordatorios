#!/usr/bin/env python3
"""Recordatorio desde Outlook — proceso local.

El panel del add-in corre en un WebView en sandbox que bloquea cualquier
conexión de red directa (ni esquemas de URL personalizados ni un servidor
en 127.0.0.1). Lo único que sí puede hacer desde dentro es llamar a la API
de Office.js, así que en vez de intentar llegar hasta este Mac, el panel se
limita a poner la categoría "RecordatorioPendiente" en el correo abierto.

Este script (pensado para correr siempre en segundo plano vía LaunchAgent)
pregunta a Microsoft Graph cada pocos segundos por correos con esa
categoría, y por cada uno que encuentra:
  1. Muestra el diálogo nativo de título (con el asunto precargado).
  2. Crea el recordatorio en Apple Recordatorios (reutilizando la app y el
     esquema de URL recordatoriooutlook://, que sí funcionan sin problema
     cuando quien los invoca es un proceso normal, no un WebView).
  3. Quita la categoría del correo para no procesarlo dos veces.

Uso:
  poller.py --login      Autenticación inicial (una vez, a mano).
  poller.py              Bucle de sondeo (esto es lo que lanza el LaunchAgent).
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_PATH = Path(__file__).parent / "config.json"
CATEGORIA = "RecordatorioPendiente"
INTERVALO_SEGUNDOS = 5
SERVICIO_KEYCHAIN = "RecordatorioOutlookPoller"

SCOPE = "offline_access https://graph.microsoft.com/Mail.ReadWrite"


def cargar_config():
    if not CONFIG_PATH.exists():
        sys.exit(
            f"Falta {CONFIG_PATH}. Copia config.example.json a config.json "
            "y rellena tenant_id y client_id (ver README)."
        )
    return json.loads(CONFIG_PATH.read_text())


def keychain_guardar(cuenta, valor):
    subprocess.run(
        ["security", "add-generic-password", "-a", cuenta, "-s", SERVICIO_KEYCHAIN,
         "-w", valor, "-U"],
        check=True, capture_output=True,
    )


def keychain_leer(cuenta):
    r = subprocess.run(
        ["security", "find-generic-password", "-a", cuenta, "-s", SERVICIO_KEYCHAIN, "-w"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def post_form(url, datos):
    cuerpo = urllib.parse.urlencode(datos).encode()
    peticion = urllib.request.Request(url, data=cuerpo, method="POST")
    peticion.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(peticion, timeout=20) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode())


def login(config):
    tenant = config["tenant_id"]
    client_id = config["client_id"]
    base = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0"

    r = post_form(f"{base}/devicecode", {"client_id": client_id, "scope": SCOPE})
    if "device_code" not in r:
        sys.exit(f"Error solicitando el código de dispositivo: {r}")

    print(r["message"])
    print("Esperando a que completes el inicio de sesión…")

    intervalo = r.get("interval", 5)
    device_code = r["device_code"]
    while True:
        time.sleep(intervalo)
        t = post_form(f"{base}/token", {
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": client_id,
            "device_code": device_code,
        })
        if "access_token" in t:
            keychain_guardar(config["cuenta"], t["refresh_token"])
            print("Autenticación completada. El token queda guardado en el Llavero.")
            return
        error = t.get("error")
        if error == "authorization_pending":
            continue
        if error == "slow_down":
            intervalo += 5
            continue
        sys.exit(f"Error de autenticación: {t}")


def token_de_acceso(config):
    tenant = config["tenant_id"]
    client_id = config["client_id"]
    cuenta = config["cuenta"]
    refresh_token = keychain_leer(cuenta)
    if not refresh_token:
        sys.exit("No hay sesión guardada. Ejecuta primero: poller.py --login")

    base = f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0"
    t = post_form(f"{base}/token", {
        "grant_type": "refresh_token",
        "client_id": client_id,
        "refresh_token": refresh_token,
        "scope": SCOPE,
    })
    if "access_token" not in t:
        sys.exit(f"No se pudo renovar la sesión: {t}. Ejecuta de nuevo: poller.py --login")

    # Los refresh tokens rotan; nos quedamos siempre con el último.
    if "refresh_token" in t:
        keychain_guardar(cuenta, t["refresh_token"])
    return t["access_token"]


def graph_get(access_token, url):
    peticion = urllib.request.Request(url)
    peticion.add_header("Authorization", f"Bearer {access_token}")
    peticion.add_header("ConsistencyLevel", "eventual")
    peticion.add_header("Prefer", 'outlook.body-content-type="text"')
    with urllib.request.urlopen(peticion, timeout=20) as resp:
        return json.loads(resp.read().decode())


def graph_patch(access_token, url, cuerpo):
    datos = json.dumps(cuerpo).encode()
    peticion = urllib.request.Request(url, data=datos, method="PATCH")
    peticion.add_header("Authorization", f"Bearer {access_token}")
    peticion.add_header("Content-Type", "application/json")
    urllib.request.urlopen(peticion, timeout=20)


def mensajes_pendientes(access_token):
    query = urllib.parse.urlencode({
        "$filter": f"categories/any(c:c eq '{CATEGORIA}')",
        "$select": "id,subject,body,webLink,from,categories",
        "$top": "5",
        "$count": "true",
    }, safe="'()")
    url = f"https://graph.microsoft.com/v1.0/me/messages?{query}"
    r = graph_get(access_token, url)
    return r.get("value", [])


def abrir_recordatorio(subject, body, weblink, remitente):
    # quote (no urlencode/quote_plus): el decodificador en AppleScript espera
    # %20 para los espacios, igual que encodeURIComponent en JS — quote_plus
    # los codificaría como "+", indistinguible de un "+" literal del texto.
    campos = {
        "titulo": subject,
        "asunto": subject,
        "cuerpo": body,
        "enlace": weblink,
        "remitente": remitente,
    }
    params = "&".join(
        f"{clave}={urllib.parse.quote(valor, safe='')}"
        for clave, valor in campos.items()
    )
    url = "recordatoriooutlook://crear?" + params
    subprocess.Popen(["open", url])


def procesar(access_token, mensaje):
    subject = mensaje.get("subject") or ""
    body = (mensaje.get("body") or {}).get("content") or ""
    weblink = mensaje.get("webLink") or ""
    remitente_obj = (mensaje.get("from") or {}).get("emailAddress") or {}
    remitente = remitente_obj.get("name") or ""
    direccion = remitente_obj.get("address") or ""
    if remitente and direccion:
        remitente = f"{remitente} <{direccion}>"
    elif direccion:
        remitente = direccion

    abrir_recordatorio(subject, body, weblink, remitente)

    restantes = [c for c in (mensaje.get("categories") or []) if c != CATEGORIA]
    graph_patch(
        access_token,
        f"https://graph.microsoft.com/v1.0/me/messages/{mensaje['id']}",
        {"categories": restantes},
    )


def bucle(config):
    while True:
        try:
            access_token = token_de_acceso(config)
            for mensaje in mensajes_pendientes(access_token):
                procesar(access_token, mensaje)
        except Exception as e:
            print(f"[poller] error en la ronda de sondeo: {e}", file=sys.stderr)
        time.sleep(INTERVALO_SEGUNDOS)


def main():
    config = cargar_config()
    if "--login" in sys.argv:
        login(config)
    else:
        bucle(config)


if __name__ == "__main__":
    main()
