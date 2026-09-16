# Auditor de Privacidad y Grabaciones - NICE Screen Agent

Herramienta de auditoría local, preservación y desencriptación en tiempo real de las grabaciones de pantalla generadas por **NICE Screen Agent**, acompañada del informe técnico sobre su arquitectura y funcionamiento.

---

## 🚀 ¿Qué hace `ejecutar_auditor.bat`?

`ejecutar_auditor.bat` es el lanzador principal del sistema de auditoría para Windows. Permite iniciar todo el entorno de monitoreo con un solo doble clic sin necesidad de abrir consolas manualmente ni configurar permisos de PowerShell.

### Funciones Principales:

1. **Lanzamiento con un solo clic:**
   * Abre una ventana de consola dedicada titulada `Auditor de Privacidad - ScreenAgent`.
   * Ejecuta el script principal [`iniciar_auditor.ps1`](file:///c:/Proyects/screen/iniciar_auditor.ps1) evadiendo restricciones de políticas de ejecución (`-ExecutionPolicy Bypass -NoProfile`).
   * Mantiene la ventana abierta en caso de detención o error para permitir revisar los registros (`pause`).

2. **Monitoreo y Detección en Tiempo Real:**
   * Supervisa en segundo plano el inicio de grabaciones por parte de `ScreenAgent` detectando automáticamente la creación del proceso `ffmpeg.exe` asociado a la llamada.

3. **Captura de Claves Criptográficas al Vuelo (AES-128):**
   * ScreenAgent cifra cada grabación con una clave única temporal antes de guardarla en el disco.
   * El script intercepta los argumentos de la línea de comandos de FFmpeg en el instante en que se crea el proceso, extrayendo la clave secreta (`-encryption_key`) y el vector de inicialización (`-encryption_iv`).

4. **Preservación Inmediata mediante Enlaces Duros (HardLinks):**
   * Por diseño, ScreenAgent elimina el video local inmediatamente después de subirlo exitosamente a la nube de AWS S3.
   * El auditor crea instantáneamente un enlace duro (*HardLink*) apuntando al archivo en la carpeta `auditoria\temp\`. De esta manera, cuando ScreenAgent borra el archivo de su carpeta temporal, la copia física en disco permanece intacta.

5. **Desencriptación Automática y Entrega de Video Reproducible:**
   * Una vez que la llamada concluye, el auditor utiliza el propio binario local de FFmpeg junto con la clave capturada para desencriptar el video.
   * Genera un archivo `.mp4` limpio, listo para reproducir en cualquier reproductor (como VLC o Windows Media Player) y lo guarda ordenadamente en la carpeta `auditoria\`.

6. **Registro y Telemetría Local:**
   * Notifica en consola la hora exacta de inicio y fin de cada llamada, duración, ID de grabación, resolución capturada y ruta final del video generado.

### 📋 Modo de Uso Rápido:
1. Haz doble clic en [`ejecutar_auditor.bat`](file:///c:/Proyects/screen/ejecutar_auditor.bat).
2. Deja la ventana abierta mientras realizas tus llamadas de trabajo.
3. Las grabaciones desencriptadas se guardarán automáticamente en la carpeta `auditoria\`.
4. Para detener el auditor, presiona `Ctrl + C` en la ventana de consola.

---

# Informe Técnico y Análisis de Funcionamiento: NICE Screen Agent

**Fecha de análisis:** Septiembre 2026  
**Sistema Operativo:** Windows 10 Home (64-bit)  
**Ubicación de este informe:** [`informe_tecnico_nice_screen_agent.md`](file:///c:/Proyects/screen/informe_tecnico_nice_screen_agent.md)

---

## 1. Visión General del Software

| Parámetro | Detalle |
| :--- | :--- |
| **Nombre de la Aplicación** | ScreenAgent |
| **Fabricante / Proveedor** | NICE - inContact |
| **Versión del Producto** | `3.2.12` |
| **Versión de Electron** | `26.3.0` |
| **Motor de Captura de Video** | FFmpeg personalizado (`gdigrab` en Windows) |
| **Fecha de Instalación** | 03 de Septiembre de 2026 |
| **Cadena de Desinstalación** | `MsiExec.exe /I{5A99BBA1-06E2-46C2-AF68-3142903F6161}` |

---

## 2. Organización y Cuenta Vinculada (Tenant)

A través de los archivos de configuración y la telemetría enviada a AWS, se identificaron los parámetros exactos de vinculación institucional:

* **Organización (Tenant):** `certified_languages_internationa99779533` (*Certified Languages International*)
* **ID de Tenant:** `11ef6a32-c573-6d80-b014-0242ac110004`
* **Entorno / Región de Servicio:** `na1` (`https://na1.nice-incontact.com/screen-agent`)
* **Endpoint de Autenticación:** `https://cxone.niceincontact.com/auth/token`
* **Identificador TACK de Sesión:** `11f1a0c8-dd49-54f0-8451-0242ac110004`
* **Estación de Trabajo / Usuario:** `DESKTOP-NB9HN1I \ estefano`

---

## 3. Arquitectura y Componentes del Sistema

El programa está compuesto por varios ejecutables y servicios que interactúan entre sí:

```
[ Arranque Windows: HKLM\...\Run ]
                 │
                 ▼
     ScreenAgentWatchDog.exe (PID: 8244)
                 │  (Supervisa y mantiene vivo el proceso)
                 ▼
          ScreenAgent.exe (Electron Main + Renderer)
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
Puerto Local 31322     ffmpeg.exe (gdigrab)
(Escucha MAX/CXone)    (Captura de pantalla y codificación)
                            │
                            ▼
                     Subida a AWS S3
           (production-us-west-2-screen-recording-bucket)
```

### Rutas en el Disco
* **Binarios del programa:**  
  `C:\Program Files\NICE-InContact\ScreenAgent\`
  * `ScreenAgent.exe`: Aplicación central basada en Chromium / Electron.
  * `ScreenAgentWatchDog.exe`: Proceso guardián compilado en .NET.
  * `ffmpeg.exe`: Binario dedicado para capturar y codificar el video de pantalla.
  * `resources\app.asar`: Archivo empaquetado que contiene toda la lógica JavaScript/Node.js de la aplicación.
* **Archivos de configuración y datos de usuario:**  
  `C:\Users\estefano\AppData\Roaming\ScreenAgent\`
  * `config.json`: Configuración local de endpoints, puertos y parámetros de captura.
  * `configFile.ini`: Credenciales y claves de acceso criptográficas fijas.
  * `logs\ScreenAgent.log`: Registro cronológico detallado de todos los eventos del programa.
  * `recordings\`: Carpeta de almacenamiento temporal donde se depositan los videos durante las llamadas.

### Persistencia e Inicio Automático
El programa se inicia automáticamente cada vez que se enciende la computadora mediante una entrada en el Registro de Windows para todos los usuarios:
* **Ruta de Registro:** `HKLM\Software\Microsoft\Windows\CurrentVersion\Run`
* **Entrada:** `ScreenAgent`
* **Comando:** `"C:\Program Files\NICE-InContact\ScreenAgent\ScreenAgentWatchDog.exe" "C:\Program Files\NICE-InContact\ScreenAgent\ "`

---

## 4. Comportamiento de Grabación (Pantalla, Monitores y Ventanas)

A partir de la descompilación e inspección del código fuente en `resources\app.asar` (`monitorResolutionsExtractor.js` e `ipcEventsHandler.js`), se confirmaron los siguientes puntos críticos:

### ¿Graba toda la pantalla o solo una ventana?
* **Graba TODA la pantalla completa.**
* Utiliza el dispositivo `gdigrab` de FFmpeg capturando el escritorio completo (`desktop`).
* **No se limita** a la ventana de la llamada ni a la pestaña del navegador:
  * Quedan grabadas las aplicaciones activas y secundarias.
  * La barra de tareas, reloj y menú de inicio de Windows.
  * Todas las notificaciones emergentes que aparezcan en pantalla (mensajería, correos, alertas).
  * La posición y el movimiento del cursor del ratón.

### ¿Graba todas las pantallas si hay múltiples monitores?
* **SÍ. El código está diseñado para grabar todos los monitores conectados.**
* En el módulo `monitorResolutionsExtractor.js`, el software ejecuta:
  ```javascript
  const getMonitorsResolutions = () => {
      let displays = electron.screen.getAllDisplays();
      displays.sort((displayA, displayB) => displayA.bounds.x - displayB.bounds.x);
      // Extrae y combina las coordenadas de todos los monitores
  };
  ```
* Detecta todas las pantallas mediante `screen.getAllDisplays()`, las ordena horizontalmente por su posición física y configura a FFmpeg para capturar el área extendida de todas las pantallas conectadas.
* *Nota de tu equipo:* Actualmente tu estación cuenta con 1 monitor principal (`1920x1080`). En caso de conectar un segundo o tercer monitor, el agente capturará todas las pantallas de forma simultánea.

### Parámetros Técnicos del Video Grabado
* **Formato del contenedor:** `.mp4`
* **Resolución de captura:** `1920x1080` (o la suma extendida de los monitores)
* **Tasa de fotogramas (FPS):** **5 FPS** (`framePerSecond: 5`). Es una tasa baja optimizada que mantiene el texto nítido y legible, registra cada clic y cambio de ventana, pero genera archivos sumamente livianos (aprox. 300 KB a 500 KB por minuto de llamada).
* **Intervalo de Keyframe (I-Frame):** 15 fotogramas (`iframeInterval: 15`).

---

## 5. Censura y Enmascaramiento de Pantalla (Masking & Deny List)

El software cuenta con un mecanismo de protección de datos (`processCheckerManager.js`):
* Su propósito es ocultar o poner en pantalla negra el video si el agente abre programas o páginas web confidenciales (por ejemplo, pasarelas de pago con tarjetas de crédito según la norma PCI-DSS, o registros médicos según HIPAA).
* El proceso comprueba cada segundo (`checkIntervalMS: 1000`) si una aplicación o URL prohibida está en primer plano.
* **Estado actual en tu empresa:**
  De acuerdo con los registros de sincronización con la nube:
  ```json
  "processList": [],
  "urlList": []
  ```
  **Las listas de exclusión están completamente vacías**. En consecuencia, **no existe ningún tipo de censura ni enmascaramiento activo**: el agente graba absolutamente todo lo que aparezca en pantalla.

---

## 6. Frecuencias de Envío y Gestión de Archivos

Una de las principales dudas técnicas resueltas fue la administración de las llamadas a lo largo de una jornada:

### A. Grabaciones de Pantalla
* **Disparador por evento (No periódico):** El programa **no toma capturas de pantalla aleatorias ni periódicas fuera de llamada**. Solo graba video mientras existe una llamada activa iniciada por la plataforma de agente.
* **Un archivo por llamada:** Cada llamada genera su propio archivo de video independiente (ej. `1788532962729_000.mp4`) vinculado a un `recordingId` y `segmentId` únicos.
* **Subida inmediata:** Apenas cuelgas la llamada, el archivo se cierra y se inicia de inmediato la subida a AWS S3. No espera al final del día ni a acumular llamadas.
* **Eliminación local obligatoria:** Una vez que el servidor de Amazon confirma la recepción correcta con un código **`HTTP 200 OK`**, el agente **elimina inmediatamente el archivo de tu disco duro local**. Por este motivo la carpeta `recordings\` permanece vacía la mayor parte del tiempo.
* **Comportamiento ante caídas de red:** Si se corta el internet al colgar, el video se almacena en la carpeta local y entra en una cola de reintentos (`retryOnUploadFailureInMS: 600000`). En cuanto regresa la conexión, se suben los archivos pendientes y se eliminan del disco.

### B. Registros (Logs) y Telemetría Técnica
* **Eventos de Pulso (`PULSE`):** Se transmiten periódicamente hacia la cola SQS `production_mcr-connected-screen-agents-sqs` para confirmar que tu estación sigue conectada.
* **Subida de Logs (`ScreenAgent.zip`):**
  * Se sube cada vez que el equipo arranca o se reinicia la aplicación.
  * Por tamaño: Cada vez que `ScreenAgent.log` alcanza **5 MB** (`5242880 bytes`).
  * Por temporizador: Cada vez que se renuevan las credenciales STS de AWS (en tu log el temporizador `credentialsRefreshTimer` está programado para **24,900,164 ms**, es decir, **cada ~6.9 horas**).
* **Refresco de Políticas (`Settings`):** Se consulta cada **12 horas** (`43200000 ms`).

---

## 7. Red y Conectividad Externa

* **Puerto Local (Loopback):** Escucha en `127.0.0.1:31322`. Se utiliza como puente para que la interfaz web del agente (CXone Agent / MAX) se comunique con la aplicación de escritorio y le ordene iniciar/detener la grabación.
* **Conexiones Salientes Establecidas:**
  * **AWS us-west-2 (Oregón):** Conexión HTTPS segura (`Puerto 443`) para el almacenamiento de grabaciones en el bucket S3 `production-us-west-2-screen-recording-bucket` y el envío de mensajes por SQS.
  * **Cloudflare Edge (`172.64.41.3:443`):** Red de distribución para la carga de componentes estáticos y API de NICE.

---

## 8. Evidencia Real de Grabaciones en tu Equipo

En los registros del sistema se documentó la captura de llamadas con los siguientes datos verificables:

### Interacción 1 (04/09/2026 - 09:42 AM)
* **Inicio de grabación:** `09:42:42` (hora local)
* **Fin de grabación:** `09:43:07` (duración: 25 segundos)
* **ID de Grabación:** `32da5e71-fdf7-42d8-9be1-52058a6766d9`
* **Archivo generado:** `1788532962729_000.mp4`
* **Tamaño:** 327,481 bytes (~320 KB)
* **Resolución:** `1920x1080` a 5 FPS
* **Resultado de subida:** `HTTP 200 OK` confirmado a las `09:43:09` (tiempo de subida: ~1.4 s). Archivo local eliminado.

### Interacción 2 (04/09/2026 - 09:54 AM)
* **Inicio de grabación:** `09:54:23` (hora local)
* **Fin de grabación:** `09:55:01` (duración: 38 segundos)
* **ID de Grabación:** `d45025ec-c2ce-475f-94d4-1a68c038719e`
* **Archivo generado:** `1788533663585_000.mp4`
* **Tamaño:** 533,187 bytes (~520 KB)
* **Resolución:** `1920x1080` a 5 FPS
* **Resultado de subida:** `HTTP 200 OK` confirmado a las `09:55:03` (tiempo de subida: ~1.6 s). Archivo local eliminado.

---

## 9. Resumen Ejecutivo de Conclusiones

1. **Tu pantalla solo se graba durante llamadas activas.** No graba fuera de las interacciones.
2. **La grabación abarca el 100% de lo que ves en pantalla** (escritorio completo, ventanas, barra de tareas, notificaciones y cursor).
3. **Soporta múltiples monitores:** Si conectas más pantallas, grabará todos los monitores en el mismo video.
4. **No satura tu disco duro:** Cada llamada se sube de inmediato a la nube y el archivo local se destruye en segundos tras recibir la confirmación de subida.
5. **No hay filtros de privacidad activados:** La lista de exclusión (*Deny List*) de tu empresa está vacía, por lo que nada se censura automáticamente durante las llamadas.
