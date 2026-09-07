#!/usr/bin/env python3
"""Puente local para «Recordatorio desde Outlook».

El panel del add-in corre dentro del WebView de Outlook, que bloquea la
navegación a esquemas de URL personalizados (recordatoriooutlook://). Este
servidor escucha en 127.0.0.1 y reenvía la petición a ese esquema mediante
`open`, que sí puede lanzar la app local sin restricciones — es un proceso
normal, no un WebView en sandbox.

No guarda ni procesa el contenido del correo: se limita a reenviar la
consulta tal cual a la app, que es quien construye el recordatorio.
"""
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PUERTO = 47850
ORIGEN_PERMITIDO = "https://neldoreth.github.io"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # el log real va al archivo que configura el LaunchAgent

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", ORIGEN_PERMITIDO)
        # Requerido por la comprobación de acceso a red local/privada de
        # WebKit y Chromium al saltar de un origen público (GitHub Pages) a
        # una dirección de loopback, incluso en peticiones "simples".
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Access-Control-Allow-Methods", "GET")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def do_GET(self):
        partes = urlsplit(self.path)
        if partes.path != "/crear":
            self.send_response(404)
            self._cors()
            self.end_headers()
            return

        origen = self.headers.get("Origin", "")
        if origen and origen != ORIGEN_PERMITIDO:
            self.send_response(403)
            self._cors()
            self.end_headers()
            return

        consulta = ("?" + partes.query) if partes.query else ""
        url = "recordatoriooutlook://crear" + consulta
        subprocess.Popen(["open", url])

        self.send_response(204)
        self._cors()
        self.end_headers()


def main():
    servidor = ThreadingHTTPServer(("127.0.0.1", PUERTO), Handler)
    servidor.serve_forever()


if __name__ == "__main__":
    main()
