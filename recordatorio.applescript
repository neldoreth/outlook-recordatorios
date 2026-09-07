-- Recordatorio desde Outlook
-- Recibe los datos de un correo desde el add-in de Outlook (vía el esquema de
-- URL recordatoriooutlook://) y crea un recordatorio en Apple Recordatorios:
--
--   · Pregunta el título, con el asunto del correo como valor por defecto
--   · Copia el cuerpo del correo en las notas
--   · Añade un enlace directo al correo (Outlook Web)

------------------------------------------------------------------
-- CONFIGURACIÓN
------------------------------------------------------------------
-- Lista de Recordatorios donde crear la tarea.
-- Si no existe, se usa la lista por defecto.
property nombreLista : "Trabajo"

-- Máximo de caracteres del cuerpo que se copian a las notas.
property maxNotas : 4000


on open location theURL
	set datos to analizarURL(theURL)
	set elAsunto to obtenerParametro(datos, "asunto")
	set elCuerpo to obtenerParametro(datos, "cuerpo")
	set elEnlace to obtenerParametro(datos, "enlace")
	set elRemitente to obtenerParametro(datos, "remitente")
	set elTituloSugerido to obtenerParametro(datos, "titulo")
	if elTituloSugerido is "" then set elTituloSugerido to elAsunto

	activate
	try
		set respuesta to display dialog "Título del recordatorio:" default answer elTituloSugerido ¬
			with title "Nuevo recordatorio desde Outlook" ¬
			buttons {"Cancelar", "Crear"} default button "Crear" ¬
			with icon note
	on error number -128
		return -- cancelado por el usuario
	end try

	set elTitulo to text returned of respuesta
	if elTitulo is "" then set elTitulo to elTituloSugerido
	if elTitulo is "" then set elTitulo to "(sin asunto)"

	set lasNotas to componerNotas(elAsunto, elCuerpo, elEnlace, elRemitente)
	crearRecordatorio(elTitulo, lasNotas)
end open location


on run
	activate
	display alert "Recordatorio desde Outlook" message ¬
		"Esta app no se abre directamente: pulsa el botón «Recordatorio» en la ventana de un correo en Outlook." ¬
		as informational buttons {"Vale"} default button "Vale"
end run


------------------------------------------------------------------
-- URL
------------------------------------------------------------------
on analizarURL(theURL)
	-- Se queda con todo lo que va tras el primer "?"
	set laConsulta to ""
	if theURL contains "?" then
		set textoAnterior to text item delimiters
		set text item delimiters to "?"
		set losTrozos to text items of theURL
		set laConsulta to item 2 of losTrozos
		set text item delimiters to textoAnterior
	end if
	return laConsulta
end analizarURL


on obtenerParametro(laConsulta, elNombre)
	if laConsulta is "" then return ""

	set textoAnterior to text item delimiters
	set text item delimiters to "&"
	set losPares to text items of laConsulta
	set text item delimiters to textoAnterior

	set elPrefijo to elNombre & "="
	repeat with unPar in losPares
		set unPar to unPar as text
		if unPar begins with elPrefijo then
			set elValor to text ((length of elPrefijo) + 1) thru -1 of unPar
			return decodificarURL(elValor)
		end if
	end repeat
	return ""
end obtenerParametro


on decodificarURL(elTexto)
	if elTexto is "" then return ""
	try
		return do shell script "/usr/bin/python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]), end=\"\")' " & quoted form of elTexto
	on error
		return elTexto
	end try
end decodificarURL


------------------------------------------------------------------
-- NOTAS
------------------------------------------------------------------
on componerNotas(elAsunto, elCuerpo, elEnlace, elRemitente)
	set lasLineas to {}

	if elEnlace is not "" then
		set end of lasLineas to "Abrir en Outlook:"
		set end of lasLineas to elEnlace
		set end of lasLineas to ""
	end if

	if elRemitente is not "" then
		set end of lasLineas to "De: " & elRemitente
	end if
	if elAsunto is not "" then
		set end of lasLineas to "Asunto: " & elAsunto
	end if

	set elCuerpoLimpio to limpiar(elCuerpo)
	if elCuerpoLimpio is not "" then
		set end of lasLineas to "————————————————————"
		set end of lasLineas to elCuerpoLimpio
	end if

	set textoAnterior to text item delimiters
	set text item delimiters to return
	set resultado to lasLineas as text
	set text item delimiters to textoAnterior
	return resultado
end componerNotas


on limpiar(elTexto)
	if elTexto is "" then return ""

	if (length of elTexto) > maxNotas then
		set elTexto to (text 1 thru maxNotas of elTexto) & return & "[…] (cuerpo recortado)"
	end if

	-- Colapsa bloques de líneas en blanco (frecuentes en las firmas)
	repeat 6 times
		set elTexto to reemplazar(elTexto, return & return & return, return & return)
		set elTexto to reemplazar(elTexto, linefeed & linefeed & linefeed, linefeed & linefeed)
	end repeat

	return elTexto
end limpiar


on reemplazar(elTexto, buscar, sustituir)
	set textoAnterior to text item delimiters
	set text item delimiters to buscar
	set losTrozos to text items of elTexto
	set text item delimiters to sustituir
	set resultado to losTrozos as text
	set text item delimiters to textoAnterior
	return resultado
end reemplazar


------------------------------------------------------------------
-- RECORDATORIOS
------------------------------------------------------------------
on crearRecordatorio(elTitulo, lasNotas)
	tell application "Reminders"
		set laLista to missing value
		try
			set laLista to first list whose name is nombreLista
		end try
		if laLista is missing value then set laLista to default list

		tell laLista
			make new reminder with properties {name:elTitulo, body:lasNotas}
		end tell
	end tell
end crearRecordatorio
