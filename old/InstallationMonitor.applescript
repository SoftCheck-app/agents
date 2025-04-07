-- Monitor de instalaciones para macOS utilizando AppleScript
-- Este script detecta nuevas aplicaciones instaladas y permite aprobar o denegar la instalación

-- Biblioteca para manejar peticiones HTTP
use AppleScript version "2.4"
use scripting additions
use framework "Foundation"

-- Establecer URL del backend
property backendURL : "http://127.0.0.1:5000"
property verificationEndpoint : "http://127.0.0.1:5000/verify"

-- Función para obtener la lista actual de aplicaciones
on getCurrentApps()
	set appFolder to POSIX path of "/Applications"
	set currentApps to {}
	
	tell application "System Events"
		set appList to name of every disk item of folder appFolder whose name ends with ".app"
		repeat with appName in appList
			copy appName to end of currentApps
		end repeat
	end tell
	
	return currentApps
end getCurrentApps

-- Función para verificar si una aplicación ya existe en la lista
on appExists(appName, appsList)
	repeat with existingApp in appsList
		if existingApp as string is equal to appName as string then
			return true
		end if
	end repeat
	return false
end appExists

-- Función para obtener el nombre de usuario
on getUsername()
	return do shell script "whoami"
end getUsername

-- Función para obtener la dirección MAC
on getMacAddress()
	try
		set macResult to do shell script "ifconfig | grep ether | head -n 1 | awk '{print $2}'"
		if macResult is "" then
			return "00:00:00:00:00:00"
		end if
		return macResult
	on error
		return "00:00:00:00:00:00"
	end try
end getMacAddress

-- Función para calcular el hash SHA256 de un archivo
on calculateSHA256(filePath)
	try
		set theCommand to "shasum -a 256 " & quoted form of filePath & " | awk '{print $1}'"
		set theResult to do shell script theCommand
		return theResult
	on error
		return "no_disponible"
	end try
end calculateSHA256

-- Función para buscar el ejecutable principal de una aplicación
on findMainExecutable(appPath)
	set macosPath to appPath & "/Contents/MacOS"
	
	try
		set fileList to paragraphs of (do shell script "ls -1 " & quoted form of macosPath)
		if (count of fileList) > 0 then
			set exePath to macosPath & "/" & item 1 of fileList
			return exePath
		end if
	on error
		-- Intentar encontrar usando el nombre de la app
		set appName to last item of my splitString(appPath, "/")
		set appName to text 1 thru -5 of appName -- Quitar ".app"
		set potentialPath to macosPath & "/" & appName
		
		try
			do shell script "test -x " & quoted form of potentialPath
			return potentialPath
		on error
			return ""
		end try
	end try
	
	return ""
end findMainExecutable

-- Función auxiliar para dividir una cadena
on splitString(theString, theDelimiter)
	set oldDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to theDelimiter
	set theArray to every text item of theString
	set AppleScript's text item delimiters to oldDelimiters
	return theArray
end splitString

-- Función para enviar datos al backend
on sendDataToAPI(appInfo)
	set theJSON to "{\"nombre\":\"" & quoted form of (appInfo's nombre) & "\", \"version\":\"" & quoted form of (appInfo's version) & "\", \"ruta\":\"" & quoted form of (appInfo's ruta) & "\", \"sha256\":\"" & quoted form of (appInfo's sha256) & "\", \"username\":\"" & quoted form of (appInfo's username) & "\", \"mac_address\":\"" & quoted form of (appInfo's mac_address) & "\"}"
	
	-- Crear array JSON con un solo elemento
	set jsonArray to "[" & theJSON & "]"
	
	try
		set curlCmd to "curl -s -X POST -H \"Content-Type: application/json\" -d '" & jsonArray & "' " & backendURL
		do shell script curlCmd
		log "Datos enviados correctamente al backend"
		return true
	on error errMsg
		log "Error al enviar datos al backend: " & errMsg
		return false
	end try
end sendDataToAPI

-- Función para verificar si el software está autorizado en el servidor
on verifySoftware(appInfo)
	set theJSON to "{\"nombre\":\"" & quoted form of (appInfo's nombre) & "\", \"version\":\"" & quoted form of (appInfo's version) & "\", \"sha256\":\"" & quoted form of (appInfo's sha256) & "\", \"username\":\"" & quoted form of (appInfo's username) & "\", \"mac_address\":\"" & quoted form of (appInfo's mac_address) & "\"}"
	
	try
		-- Usar curl con la opción -w "%{http_code}" para obtener el código de estado HTTP
		set curlCmd to "curl -s -w \"%{http_code}\" -X POST -H \"Content-Type: application/json\" -d '" & theJSON & "' " & verificationEndpoint & " -o /dev/null"
		set httpResponse to do shell script curlCmd
		
		log "Respuesta de verificación: " & httpResponse
		
		-- Si la respuesta es 200, el software está autorizado
		if httpResponse is "200" then
			log "Software autorizado por el servidor"
			return true
		else
			log "Software NO autorizado por el servidor (respuesta: " & httpResponse & ")"
			return false
		end if
	on error errMsg
		log "Error al verificar software: " & errMsg
		return false
	end try
end verifySoftware

-- Función para obtener la versión de una aplicación
on getAppVersion(appPath)
	try
		set plistPath to appPath & "/Contents/Info.plist"
		set versionCmd to "/usr/libexec/PlistBuddy -c \"Print :CFBundleShortVersionString\" " & quoted form of plistPath & " 2>/dev/null"
		set versionResult to do shell script versionCmd
		
		if versionResult is not "" then
			return versionResult
		end if
	on error
		-- No se pudo obtener la versión
	end try
	
	return "desconocida"
end getAppVersion

-- Configurar carpeta de cuarentena con los permisos adecuados (solo una vez)
on setupQuarantineFolder()
	set quarantineFolder to (POSIX path of (path to home folder)) & "Library/Application Support/AppQuarantine/"
	
	-- Crear carpeta de cuarentena si no existe y establecer permisos adecuados
	try
		do shell script "mkdir -p " & quoted form of quarantineFolder & " && chmod 777 " & quoted form of quarantineFolder
		log "Carpeta de cuarentena configurada con permisos"
		return quarantineFolder
	on error errMsg
		log "Error al configurar carpeta de cuarentena: " & errMsg
		return quarantineFolder -- Intentamos devolver la ruta de todos modos
	end try
end setupQuarantineFolder

-- Función para mover la aplicación a cuarentena usando Finder (sin privilegios de admin)
on moveToQuarantine(appPath)
	set quarantineFolder to setupQuarantineFolder()
	
	-- Extraer nombre de la aplicación
	set appName to last item of my splitString(appPath, "/")
	set quarantinePath to quarantineFolder & appName
	
	try
		-- Usar Finder para mover la aplicación (no requiere privilegios admin)
		tell application "Finder"
			set sourceItem to POSIX file appPath as alias
			set targetFolder to POSIX file quarantineFolder as alias
			
			-- Si ya existe en cuarentena, eliminarlo primero
			if exists POSIX file quarantinePath then
				delete POSIX file quarantinePath
			end if
			
			-- Mover a la carpeta de cuarentena
			move sourceItem to targetFolder with replacing
			log "Aplicación movida a cuarentena usando Finder: " & quarantinePath
		end tell
		
		return quarantinePath
	on error errMsg
		log "Error al mover a cuarentena con Finder: " & errMsg
		
		-- Intento alternativo con shell script (sin privilegios)
		try
			do shell script "mv " & quoted form of appPath & " " & quoted form of quarantineFolder
			log "Aplicación movida a cuarentena con shell script: " & quarantinePath
			return quarantinePath
		on error errMsg2
			log "Error al mover a cuarentena con método alternativo: " & errMsg2
			return ""
		end try
	end try
end moveToQuarantine

-- Función para restaurar la aplicación desde cuarentena usando Finder
on restoreFromQuarantine(quarantinePath)
	set appName to last item of my splitString(quarantinePath, "/")
	set destinationPath to "/Applications/" & appName
	
	try
		-- Usar Finder para restaurar la aplicación
		tell application "Finder"
			set sourceItem to POSIX file quarantinePath as alias
			set targetFolder to POSIX file "/Applications/" as alias
			
			-- Si ya existe en Applications, eliminarlo primero
			if exists POSIX file destinationPath then
				delete POSIX file destinationPath
			end if
			
			-- Mover de vuelta a /Applications/
			move sourceItem to targetFolder with replacing
			log "Aplicación restaurada desde cuarentena usando Finder: " & destinationPath
		end tell
		
		return true
	on error errMsg
		log "Error al restaurar desde cuarentena con Finder: " & errMsg
		
		-- Intento alternativo con shell script (sin privilegios)
		try
			do shell script "mv " & quoted form of quarantinePath & " " & quoted form of "/Applications/"
			log "Aplicación restaurada con shell script: " & destinationPath
			return true
		on error errMsg2
			log "Error al restaurar con método alternativo: " & errMsg2
			return false
		end try
	end try
end restoreFromQuarantine

-- Función para eliminar permanentemente la aplicación usando Finder (sin privilegios)
on deleteApplication(appPath)
	try
		-- Usar Finder para eliminar la aplicación
		tell application "Finder"
			delete POSIX file appPath
			log "Aplicación eliminada permanentemente usando Finder: " & appPath
		end tell
		
		return true
	on error errMsg
		log "Error al eliminar aplicación con Finder: " & errMsg
		
		-- Intento alternativo con shell script (sin privilegios)
		try
			do shell script "rm -rf " & quoted form of appPath
			log "Aplicación eliminada con shell script: " & appPath
			return true
		on error errMsg2
			log "Error al eliminar con método alternativo: " & errMsg2
			
			-- Tercer método: mover a la papelera
			try
				tell application "Finder"
					set itemToDelete to POSIX file appPath as alias
					delete itemToDelete
					log "Aplicación movida a la papelera: " & appPath
				end tell
				return true
			on error errMsg3
				log "Error al mover a la papelera: " & errMsg3
				return false
			end try
		end try
	end try
end deleteApplication

-- Procesar una nueva aplicación detectada
on processNewApplication(appName, appPath)
	set appVersion to getAppVersion(appPath)
	set username to getUsername()
	set macAddress to getMacAddress()
	
	-- Buscar el ejecutable principal
	set mainExecutable to findMainExecutable(appPath)
	set sha256 to "no_disponible"
	
	if mainExecutable is not "" then
		set sha256 to calculateSHA256(mainExecutable)
	end if
	
	-- Crear objeto con la información de la app
	set appInfo to {nombre:appName, version:appVersion, ruta:appPath, sha256:sha256, username:username, mac_address:macAddress}
	
	-- Mostrar diálogo informando que se ha detectado una instalación
	set dialogText to "Se ha detectado la instalación de una nueva aplicación: " & appName & "
	
Versión: " & appVersion & "
Ruta: " & appPath & "
SHA256: " & sha256 & "
Usuario: " & username & "

La instalación ha sido bloqueada temporalmente mientras se verifica con el servidor."
	
	display dialog dialogText buttons {"OK"} default button 1 with title "Instalación Detectada" with icon caution
	
	-- Mover a cuarentena temporalmente
	set quarantinePath to moveToQuarantine(appPath)
	
	if quarantinePath is not "" then
		-- Enviar datos al backend para registro
		sendDataToAPI(appInfo)
		
		-- Verificar si el software está autorizado en el servidor
		if verifySoftware(appInfo) then
			-- Software autorizado, restaurar desde cuarentena
			set restored to restoreFromQuarantine(quarantinePath)
			
			if restored then
				display dialog "El software " & appName & " está autorizado. La instalación ha sido permitida." buttons {"OK"} default button 1 with title "Software Autorizado" with icon note
				return true
			else
				display dialog "El software " & appName & " está autorizado, pero hubo un problema al restaurarlo. Por favor, contacte al administrador." buttons {"OK"} default button 1 with title "Error de Restauración" with icon stop
				return false
			end if
		else
			-- Software no autorizado, eliminar permanentemente
			set deleted to deleteApplication(quarantinePath)
			
			if deleted then
				display dialog "El software " & appName & " NO está autorizado en la base de datos. La instalación ha sido bloqueada." buttons {"OK"} default button 1 with title "Software No Autorizado" with icon stop
			else
				display dialog "El software " & appName & " NO está autorizado, pero hubo un problema al eliminarlo. Por favor, contacte al administrador." buttons {"OK"} default button 1 with title "Error de Eliminación" with icon stop
			end if
			
			return false
		end if
	else
		display dialog "No se pudo bloquear la instalación de " & appName & ". Por favor, contacte al administrador." buttons {"OK"} default button 1 with title "Error de Bloqueo" with icon stop
		return false
	end if
end processNewApplication

-- Función principal que ejecuta el ciclo de monitoreo
on runMonitor()
	-- Configurar carpeta de cuarentena al inicio para evitar problemas de permisos
	setupQuarantineFolder()
	
	-- Obtener lista inicial de aplicaciones y guardarla como referencia
	set initialApps to getCurrentApps()
	
	-- Guardar la lista inicial en un archivo temporal para debugging si es necesario
	try
		set initialAppsList to ""
		repeat with appName in initialApps
			set initialAppsList to initialAppsList & appName & return
		end repeat
		
		set tempFile to (path to temporary items as string) & "initial_apps.txt"
		set fileRef to open for access tempFile with write permission
		write initialAppsList to fileRef
		close access fileRef
		
		log "Lista inicial de aplicaciones guardada en: " & tempFile
	on error
		-- Si no se puede guardar, continúa sin error
	end try
	
	-- Mostrar notificación de inicio
	display notification "Monitor de instalaciones iniciado" with title "Monitor de Instalaciones"
	log "Monitor iniciado. Se han detectado " & (count of initialApps) & " aplicaciones iniciales que NO generarán alertas."
	
	-- Bucle principal
	repeat
		-- Obtener lista actual de aplicaciones
		set currentApps to getCurrentApps()
		
		-- Buscar nuevas aplicaciones (que no estaban en la lista inicial)
		repeat with currentApp in currentApps
			-- Verificar si esta aplicación ya existía cuando se inició el monitor
			if not my appExists(currentApp, initialApps) then
				log "Nueva aplicación detectada: " & currentApp
				set appPath to "/Applications/" & currentApp
				
				-- Procesar la nueva aplicación (bloquear y verificar)
				set appName to text 1 thru -5 of currentApp
				processNewApplication(appName, appPath)
				
				-- Actualizar lista de aplicaciones conocidas
				copy currentApp to end of initialApps
			end if
		end repeat
		
		-- Esperar antes del siguiente escaneo (10 segundos)
		delay 10
	end repeat
end runMonitor

-- Ejecutar el monitor
runMonitor() 