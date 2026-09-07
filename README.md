# Recordatorio desde Outlook

Crea un recordatorio en **Apple Recordatorios** a partir del correo abierto en
**Outlook para Mac**:

- Pregunta el título, con **el asunto del correo como valor por defecto**.
- Copia **el cuerpo del correo** en las notas.
- Añade un **enlace directo al correo** (el `webLink` real de Microsoft Graph).

## Por qué esta arquitectura

El **New Outlook** para Mac (el único disponible ya en este tenant) no
implementa de verdad el modelo de objetos de AppleScript, aunque su
diccionario lo declare. Y el panel del add-in (que sí puede leer el correo
vía Office.js) corre dentro de un WebView en sandbox que bloquea **toda**
conexión de red directa — ni esquemas de URL personalizados
(`recordatoriooutlook://`) ni un servidor en `127.0.0.1`, ambos probados y
descartados. Lo único que ese WebView sí permite son las llamadas a la
propia API de Office.js.

Así que la solución final tiene tres piezas:

1. **Un add-in de Outlook** (`docs/`, servido por GitHub Pages): añade un
   botón "Recordatorio" en la ventana de lectura del correo. Al pulsarlo, no
   intenta llegar hasta el Mac — solo pone la categoría
   `RecordatorioPendiente` en el correo (una llamada a Office.js, no a la
   red).
2. **Un proceso local** (`poller/poller.py`, corriendo siempre en segundo
   plano vía LaunchAgent): pregunta a Microsoft Graph cada pocos segundos
   por correos con esa categoría. Al encontrar uno, hace lo que el WebView no
   podía: dispara la app local.
3. **La app local** (`recordatorio.applescript`): recibe los datos vía el
   esquema de URL `recordatoriooutlook://` — esto sí funciona sin problema
   cuando quien lo invoca es un proceso normal (el poller), no un WebView en
   sandbox. Pregunta el título y crea el recordatorio.

La consecuencia práctica: el recordatorio no aparece al instante al pulsar
el botón, sino unos segundos después (el intervalo de sondeo del poller).

## Instalación

### 1. La app local

```bash
./build.sh
```

Crea `~/Applications/Recordatorio desde Outlook.app` y registra el esquema
`recordatoriooutlook://`.

La primera vez que se use pedirá permiso para **Recordatorios**. Acéptalo.

Compruébalo sin pasar por Outlook ni por el poller:

```bash
./diagnostico.sh
```

### 2. Registrar la app en Entra ID (una vez, como admin del tenant)

El poller necesita leer el correo y sus categorías vía Microsoft Graph.

1. **entra.microsoft.com** → Identidad → Aplicaciones → Registros de
   aplicaciones → **Nuevo registro**.
2. Nombre: `Recordatorio desde Outlook (local)`. Tipo de cuenta: solo este
   directorio.
3. **Autenticación** → Agregar plataforma → **Aplicaciones móviles y de
   escritorio** → marca la URI de redirección sugerida por defecto.
4. En la misma pantalla, activa **"Permitir flujos de cliente público"**.
5. **Permisos de API** → Agregar permiso → Microsoft Graph → Delegados →
   **`Mail.ReadWrite`** → Agregar.
6. **Conceder consentimiento de administrador** para el tenant.
7. Copia el **Id. de aplicación (cliente)** y el **Id. de directorio
   (tenant)** de "Información general" — te los pedirá el instalador del
   poller.

### 3. El poller

```bash
./poller/instalar.sh
```

La primera vez pide el tenant ID, el client ID y tu correo, y abre un flujo
de inicio de sesión por código de dispositivo (te da una URL y un código de
un solo uso para pegar en el navegador). Tras eso, queda instalado como
LaunchAgent, arrancando solo al iniciar sesión.

El refresh token queda en el Llavero de macOS, no en un archivo plano.

Log: `~/Library/Logs/recordatoriooutlook-poller.log`

### 4. El add-in en Outlook

Los archivos están publicados en GitHub Pages:
`https://neldoreth.github.io/outlook-recordatorios/`

Instálalo vía **Aplicaciones integradas** en el centro de administración de
Microsoft 365, asignado solo a tu cuenta (no a todo el tenant) — el sideload
de usuario ("Agregar complemento personalizado") puede estar bloqueado o ser
poco fiable según la configuración del tenant:

1. **admin.microsoft.com** → Configuración → **Aplicaciones integradas** →
   **Cargar aplicaciones personalizadas**.
2. Tipo: complemento de Office → proporcionar enlace al manifiesto:
   `https://neldoreth.github.io/outlook-recordatorios/manifest.xml`
3. Usuarios: **Solo yo**.
4. Acepta el permiso solicitado (`ReadWriteMailbox` — el nivel más alto de
   Office.js; lo exige la propia API de categorías, que Microsoft trata como
   dato de buzón, no solo del correo) y finaliza.

Puede tardar desde minutos hasta un par de horas en aparecer en el cliente,
bajo "Gestionado por el administrador".

### 5. Primer uso

1. Abre un correo, pulsa **Recordatorio**.
2. En el panel, pulsa **Crear recordatorio** — el panel confirma que ha
   etiquetado el correo.
3. Espera unos segundos. El poller lo detecta, y aparece el diálogo nativo
   con el asunto precargado como título.
4. Edítalo si quieres y pulsa **Crear**.

## Configuración

Al principio de `recordatorio.applescript`:

| Propiedad     | Qué hace                                                          |
|---------------|--------------------------------------------------------------------|
| `nombreLista` | Lista de Recordatorios de destino (actualmente `"Trabajo"`). Si no existe, usa la de por defecto. |
| `maxNotas`    | Máximo de caracteres del cuerpo copiados a las notas.              |

Tras editarlo, vuelve a ejecutar `./build.sh`.

### Límite: no se puede elegir la sección/columna dentro de una lista

Si usas la vista de tablero de Recordatorios (columnas tipo "Inbox", "Hoy",
"Por hacer"...), esas secciones son una organización manual — el
diccionario de AppleScript de Recordatorios no expone ninguna propiedad
para asignar una sección al crear un recordatorio. Los que crea esta app
caen en la columna por defecto de la lista (en la práctica, la última /
"Otros"), y hay que arrastrarlos a mano a la columna que quieras. No hay
forma de automatizar ese paso.

En `poller/poller.py`, `INTERVALO_SEGUNDOS` controla cada cuánto se sondea
Graph (por defecto 5s).

## Publicar cambios en el add-in

Los archivos de `docs/` se sirven tal cual por GitHub Pages en cuanto se
suben a la rama `main`:

```bash
git add docs/
git commit -m "..."
git push
```

Outlook cachea el JS/HTML del add-in con cierta agresividad; si un cambio no
se ve, cierra y vuelve a abrir el panel.

## Notas de seguridad

- El add-in pide `ReadWriteMailbox`, el nivel más alto de Office.js — más
  amplio de lo que el add-in usa en la práctica (solo lee el correo abierto y
  le pone una categoría), pero es el mínimo que exige la propia API de
  categorías. No hay un nivel intermedio disponible.
- El poller pide `Mail.ReadWrite` de Graph (con consentimiento de admin),
  acotado a lo necesario para leer el cuerpo/asunto y quitar la categoría
  tras procesar. El token vive en el Llavero, no en un archivo plano.
- Los archivos en `docs/` son estáticos y públicos (sin datos personales ni
  claves) — el manifiesto y el panel son visibles por cualquiera que tenga
  la URL, como cualquier add-in.
- El complemento se instala solo para tu cuenta vía Aplicaciones integradas,
  no se despliega a nivel de tenant.
