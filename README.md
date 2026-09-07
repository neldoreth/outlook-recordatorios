# Recordatorio desde Outlook

Crea un recordatorio en **Apple Recordatorios** a partir del correo abierto en
**Outlook para Mac**:

- Pregunta el título, con **el asunto del correo como valor por defecto**.
- Copia **el cuerpo del correo** en las notas.
- Añade un **enlace directo al correo** en Outlook Web.

## Por qué esta arquitectura

El **New Outlook** para Mac (el único disponible ya en este tenant) no
implementa de verdad el modelo de objetos de AppleScript, aunque su
diccionario lo declare — `selected objects`, `every account`, etc. fallan en
tiempo de ejecución. Por eso la solución tiene dos piezas:

1. **Un add-in de Outlook** (`docs/`, servido por GitHub Pages): añade un
   botón "Recordatorio" en la ventana de lectura del correo. Ahí sí funciona
   la API oficial (Office.js) y se puede leer el asunto, el cuerpo y el
   identificador del mensaje.
2. **Una app local** (`recordatorio.applescript`): recibe esos datos vía el
   esquema de URL `recordatoriooutlook://`, pregunta el título y crea el
   recordatorio con AppleScript (esto sí funciona siempre, es Recordatorios
   quien lo expone, no Outlook).

## Instalación

### 1. La app local

```bash
./build.sh
```

Crea `~/Applications/Recordatorio desde Outlook.app` y registra el esquema
`recordatoriooutlook://`.

La primera vez que se use pedirá permiso para **Recordatorios**. Acéptalo.
Si te equivocas, se reinicia en Ajustes del Sistema › Privacidad y seguridad.

Compruébalo sin pasar por Outlook:

```bash
./diagnostico.sh
```

### 2. El add-in en Outlook

Los archivos están publicados en GitHub Pages:
`https://neldoreth.github.io/outlook-recordatorios/`

Para instalarlo **solo en tu cuenta** (no afecta al resto del tenant):

1. En Outlook, abre un correo cualquiera.
2. Cinta de opciones › **Obtener complementos** (o el icono de complementos).
3. **Mis complementos** › **Agregar un complemento personalizado** ›
   **Agregar desde URL**.
4. Pega: `https://neldoreth.github.io/outlook-recordatorios/manifest.xml`
5. Acepta la advertencia de complemento no verificado (es tuyo).

Ya debería aparecer el botón **Recordatorio** al abrir un correo.

### 3. Primer uso

1. Abre un correo, pulsa **Recordatorio**.
2. En el panel, pulsa **Crear recordatorio**.
3. macOS pedirá confirmación para abrir la app la primera vez — acéptalo.
4. Aparece el diálogo con el asunto precargado; edítalo si quieres y pulsa
   **Crear**.

Si el primer salto a la app no ocurre solo (algunos navegadores integrados
bloquean el primer intento), el panel muestra un enlace **"Abrir en
Recordatorios"** para hacerlo a mano esa vez.

## Configuración

Al principio de `recordatorio.applescript`:

| Propiedad     | Qué hace                                                          |
|---------------|--------------------------------------------------------------------|
| `nombreLista` | Lista de Recordatorios de destino. Si no existe, usa la de por defecto. |
| `maxNotas`    | Máximo de caracteres del cuerpo copiados a las notas.              |

Tras editarlo, vuelve a ejecutar `./build.sh`.

## Publicar cambios en el add-in

Los archivos de `docs/` se sirven tal cual por GitHub Pages en cuanto se
suben a la rama `main`:

```bash
git add docs/
git commit -m "..."
git push
```

Outlook cachea el JS/HTML del add-in con cierta agresividad; si un cambio no
se ve, cierra y vuelve a abrir el panel, o quita y vuelve a añadir el
complemento.

## El enlace al correo

Se construye con el `itemId` que da Office.js:

```
https://outlook.office.com/owa/?ItemID=<id>&exvsurl=1&viewmodel=ReadMessageItem
```

Si más adelante mueves el correo a otra carpeta, el enlace puede dejar de
resolver. Para uso normal de bandeja de entrada y archivo no es un problema.

## Notas de seguridad

- El add-in pide el permiso mínimo (`ReadItem`): solo puede leer el correo
  abierto, no enviar ni modificar nada.
- Los archivos en `docs/` son estáticos, no contienen datos personales ni
  claves — sirven solo de puente para pasar los datos del correo del panel
  a la app local, vía el propio navegador del usuario.
- El complemento se instala solo para tu cuenta (`Agregar desde URL` en Mis
  complementos), no se despliega a nivel de tenant.
