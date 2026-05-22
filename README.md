# MPV Interpolation Wizard

Asistente automatizado para instalar interpolación de frames en [mpv](https://mpv.io) usando VapourSynth + RIFE (TensorRT/NCNN) o MVTools como respaldo. Convierte videos de 24/30 fps en reproducción fluida a 60/120/144 Hz.

> **v2.1.15**: MVTools real para GPUs pre-Turing (TRT 10 ya no soporta Pascal, NCNN no implementa GridSample en este build), env vars User-level para que `mpv.exe` directo funcione sin `mpv-vs.bat`, guard contra clips con metadata de FPS inválida (WhatsApp, capturas de teléfono), crash logger funcional en el `.vpy`, detección de VC++ Redistributable faltante. Robustez consolidada después de 15 iteraciones de debugging real con GPUs de varias generaciones.

## Descargar

Solo necesitas un archivo: descárgalo desde la última release.

[➜ Descargar MPV-Interp-Wizard.bat](https://github.com/Gotischer/interpolate/releases/latest)

Doble clic y listo. No requiere instalación previa.

## Características

| Característica | Descripción |
|----------------|-------------|
| 🎮 **Backend automático según GPU** | Detecta hardware y elige el backend viable (TRT-RTX / TRT / NCNN+Vulkan / OpenVINO / MVTools) |
| 🔄 **RIFE TensorRT-RTX** | Variante con kernels sm_120 para RTX 50xx (Blackwell) — engine compila en ~1 s vs minutos del TRT genérico. *NVIDIA only* |
| 🔄 **RIFE TensorRT** | RTX 20xx/30xx/40xx — engine pre-compilado, latencia baja, throughput alto. *NVIDIA only* |
| 🌐 **RIFE NCNN/Vulkan** | Intento para AMD/Intel modernas — usa Vulkan, sin dependencias propietarias. *Cobertura incompleta: ver tabla abajo* |
| 🐢 **MVTools (CPU)** | Pascal y anteriores, AMD/Intel cuando RIFE no es viable — motion vectors clásicos (no neural), paraleliza en todos los hilos del CPU. *No es RIFE, es la técnica que usa SVP* |
| 🎬 **Scene Detection sin plugins** | Polyfill con `PlaneStats` (en core de VapourSynth) — RIFE corta limpio en cambios de escena, sin morphing |
| 🔍 **Cap 1080p + NIS upscale** | RIFE procesa máximo a 1080p; mpv hace upscale al display real con el shader NVIDIA Image Scaling (mismo que usa SVP). **NIS ≠ DLSS** — es un shader espacial público que corre en cualquier GPU |
| 📺 **Multi-monitor** | Detecta cambios de refresh rate y re-aplica el filtro al mover la ventana entre monitores 60/120/144 Hz |
| 🌈 **HDR completo** | Interpolación preservando BT.2020/PQ/HLG y metadata MaxCLL/MaxFALL; toggle por sesión con `Ctrl+h` |
| 🛡️ **Robustez de clips raros** | Guard contra fps inválida (videos de WhatsApp/captura/VFR) — el filtro normaliza antes de pasar a RIFE/MVTools |
| 🧰 **Crash logger en el `.vpy`** | Si VapourSynth falla, escribe `interpolation.error.log` con traceback Python completo (mpv solo muestra un genérico "Could not initialize") |
| 🌐 **Env vars User-level** | Instala variables persistentes así `mpv.exe` directo funciona — no obliga a usar `mpv-vs.bat` |
| 🔧 **Auto-update** | Notificaciones de nuevas versiones desde GitHub |

### Soporte de GPU

> **Nota sobre RIFE y NVIDIA**: RIFE (Real-Time Intermediate Flow Estimation) es un **modelo neural open source**, no una tecnología propietaria de NVIDIA. Se distribuye como `.onnx` y puede ejecutarse en cualquier hardware compatible. Lo que sí es exclusivo de NVIDIA es **TensorRT** (el runtime de inferencia más rápido). Para AMD e Intel, RIFE puede correr con NCNN/Vulkan, OpenVINO o DirectML. Sin embargo, no todos los runtimes implementan todas las operaciones del modelo en todas las versiones — la cobertura real depende del backend específico y de la generación de GPU.

| GPU | Backend | Modelo | Calidad | Estado real |
|-----|---------|--------|---------|-------------|
| RTX 5090/5080/5070 (Blackwell) | TensorRT | v4.25 | 🏆 Máxima | ✅ Probado |
| RTX 4090-4060 (Ada) | TensorRT | v4.25 | 🏆 Máxima | ✅ Funcional por arquitectura |
| RTX 3090-3050 (Ampere) | TensorRT | v4.25 | 🏆 Máxima | ✅ Funcional por arquitectura |
| RTX 2080-2060 (Turing) | TensorRT | v4.25 | ⚡ Balanceado | ✅ Funcional por arquitectura |
| **GTX 1080-1050 (Pascal)** | **MVTools (CPU)** | — | 🐢 Compatible | ✅ Probado |
| **GTX 9xx y anteriores** | **MVTools (CPU)** | — | 🐢 Compatible | ⚠ No probado, fallback por defecto |
| AMD RX 7xxx (RDNA3) | NCNN/Vulkan (intento) → MVTools | v4.25 | ⚡ Balanceado | ⚠ No probado en AMD real |
| AMD RX 6xxx (RDNA2) | NCNN/Vulkan (intento) → MVTools | v4.22 | 💨 Rendimiento | ⚠ No probado en AMD real |
| Intel Arc | NCNN/Vulkan (intento) → MVTools | v4.22 | ⚡ Balanceado | ⚠ No probado en Intel Arc real |
| iGPU / sin GPU dedicada | MVTools (CPU) | — | 🐢 Básica | ✅ Probado |

**Por qué Pascal y NVIDIA antiguas van a MVTools por defecto:**

- **TensorRT 10** dropeó soporte de compute capability < 7.5. Los `nvinfer_builder_resource_smXX_10.dll` que ship vs-mlrt cubren `sm_75` (Turing) hasta `sm_120` (Blackwell). No hay `sm_61` (Pascal) ni `sm_52` (Maxwell). Engine compile falla.
- **NCNN/Vulkan**: el build oficial de vs-mlrt **no implementa `GridSample`** (operación fundamental del warping basado en optical flow que RIFE necesita). El plugin carga, pero el modelo no se puede ejecutar — esto se confirmó en hardware real (GTX 1060). Posiblemente afecta también a AMD/Intel pero no fue verificado.
- **ORT_DML**: técnicamente funciona en cualquier GPU con DirectX 12 (incluyendo Pascal). En GTX 1060 medimos 100-200 ms por frame a 1080p — inviable a 60 Hz. En GPUs AMD/Intel modernas (RDNA3, Arc, RX 7000) el rendimiento podría ser muy distinto pero no se probó.

**Estado en AMD e Intel**: el wizard intentará configurar **NCNN/Vulkan** como primer backend en hardware AMD/Intel moderno. Si el `.vpy` falla en runtime (típicamente por el bug de GridSample), el `interpolation.error.log` lo va a registrar y conviene cambiar manualmente el backend a **OV_GPU** (para Intel) u **ORT_DML** (para AMD). En el peor caso, el fallback es MVTools en CPU que funciona en cualquier hardware.

**MVTools** no es RIFE — es interpolación clásica basada en motion vectors (la técnica que SVP usa por defecto). Calidad menor que RIFE neural pero **fluidez garantizada** en cualquier hardware con CPU multinúcleo decente. Es el path correcto cuando RIFE no es viable.

`v4.25` (no `_heavy`) es el default para garantizar fluidez 4K@60 en RTX 30/40/50 incluso con HDR. Si tu uso es exclusivamente ≤1080p y querés calidad máxima podés editar `interpolation.vpy` y cambiar `RIFEModel.v4_25` por `RIFEModel.v4_25_heavy`.

## Requisitos

### Obligatorios (todos los backends)

- **Windows 10 o superior** (x64).
- **Visual C++ Redistributable 2015-2022 (x64)** — **CRÍTICO**. Sin esto, `VSScript.dll` no carga y mpv reporta el opaco "Could not initialize VapourSynth scripting" sin más info. Si el instalador dice "Another version is already installed" pero el sistema sigue fallando, ir a Programas → Microsoft Visual C++ 2015-2022 Redistributable (x64) → Modificar → **Reparar**.
  - Descarga oficial (14 MB): [aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe)
- **mpv build con VapourSynth habilitado** — el wizard se prueba contra los builds de [**shinchiro**](https://github.com/shinchiro/mpv-winbuild-cmake/releases). Los builds oficiales de mpv.io **no incluyen** VapourSynth.
  - Bajá el `.7z` que corresponda a tu CPU:
    - `mpv-x86_64-v3-YYYYMMDD-git-XXXXXXX.7z` — recomendado en CPU moderna (Intel Haswell+ / AMD Zen+, con AVX2).
    - `mpv-x86_64-YYYYMMDD-git-XXXXXXX.7z` — baseline, para CPU previa a 2013.
  - Mínimo: cualquier release de **mayo 2026 en adelante** (los builds previos no incluyen MSVC runtimes bundleados; el wizard intenta copiarlos del portable de VapourSynth pero no siempre tiene todos).
  - Extraé el `.7z` a una carpeta (ej. `H:\mpv\` o `D:\Software\mpv\`) y dejá los archivos sueltos ahí — esa será la ruta a `mpv.exe` que pide el wizard.
- **Python embed 3.13.x** — lo descarga el wizard automáticamente (no hace falta tenerlo instalado en el sistema).

### Según backend

| Backend | GPU/CPU | Espacio en disco |
|---|---|---|
| **TensorRT-RTX** | NVIDIA RTX 50xx con driver 560+ | ~7 GB (CUDA + TRT + modelos RIFE) |
| **TensorRT** | NVIDIA RTX 20/30/40xx con driver 550+ | ~7 GB |
| **NCNN/Vulkan** | AMD RX 6xxx+, Intel Arc, drivers actualizados con Vulkan 1.3 | ~2 GB |
| **OpenVINO** | Intel iGPU / CPU x86_64 | ~1.5 GB |
| **MVTools (CPU)** | Cualquier CPU moderna multi-core (Ryzen 5+ / Intel 4c+) | ~600 MB |

MVTools no requiere GPU; corre nativo en CPU. Recomendado: 8+ hilos lógicos para procesar 1080p × 2 en tiempo real con buen margen.

## Cómo se usa

1. Descarga `MPV-Interp-Wizard.bat` desde la [última release](https://github.com/Gotischer/interpolate/releases/latest)
2. Doble clic. Si SmartScreen lo bloquea: "Más información" → "Ejecutar de todas formas"
3. La primera vez: configura rutas (mpv.exe, carpeta de instalación)
4. Elige "Instalar" — toma 10-30 minutos según tu conexión
5. Agrega una línea a tu `mpv.conf` para activar el upscaler NIS (ver abajo)
6. Abre cualquier video con mpv. ¡Listo!

### Configuración manual de `mpv.conf`

El wizard copia `NVScaler.glsl` a `portable_config/shaders/` pero **no toca tu `mpv.conf`** (es archivo de usuario). Agregá esta línea para activar el upscaler de NVIDIA:

```ini
glsl-shaders=~~/shaders/NVScaler.glsl
```

Opcional, recomendado para HDR sin drops en escenas oscuras o muy luminosas:

```ini
hdr-compute-peak=no
video-sync=display-resample-vdrop
```

Y si tenés más de una GPU (típico: laptop con iGPU + RTX, o desktop con AMD integrada + RTX), fijá la dedicada explícitamente:

```ini
gpu-api=d3d11
d3d11-adapter=NVIDIA
```

### Atajos en mpv

| Atajo | Acción |
|-------|--------|
| `Ctrl+i` | Toggle interpolación ON/OFF |
| `Ctrl+h` | Toggle interpolación HDR ON/OFF |
| `Ctrl+Shift+i` | Forzar interpolación ON |
| `Ctrl+Shift+d` | Mostrar diagnóstico OSD |

## HDR

Por defecto, el wizard interpola contenido HDR preservando el colorspace (BT.2020/PQ/HLG) y los metadatos (MaxCLL, MaxFALL). RIFE corre sobre RGBH (RGB Half-float 16-bit) para no perder rango dinámico. Si prefieres el comportamiento clásico (desactivar interpolación y cambiar el Hz del monitor en HDR), usá `Ctrl+h` durante la reproducción.

Cobertura por formato HDR:

| Formato | Estado |
|---------|--------|
| HDR10 (PQ static) | ✓ Interpolación + metadata |
| HDR10+ (dynamic) | ✓ Interpolación, metadata HDR10+ preservada |
| Dolby Vision Perfil 5 | ✓ RIFE sobre BL, RPU pasa al display |
| Dolby Vision Perfil 7 | ⚠ Solo BL (limitación del decoder) |
| HLG | ✓ Interpolación + transfer HLG |

## Cómo se interpola (pipeline real)

**Path RIFE (RTX 20xx+, AMD modernas, Intel Arc):**
```
Source ──┐
         ├─→ AssumeFPS (si fps inválida)
         ├─→ Downscale a max 1920×1080 (RGBS, fp32)
         ├─→ Scene detection (PlaneStats)
         ├─→ Pad mod32
         ├─→ RIFE (TRT/TRT-RTX/NCNN/OV) × multi (cap 5)
         ├─→ Crop + convert YUV420P10
         └─→ mpv VO + NVScaler.glsl ──→ Display nativo
```

**Path MVTools (Pascal, GTX 9xx, iGPU, CPU-only):**
```
Source ──┐
         ├─→ AssumeFPS (si fps inválida)
         ├─→ Convert YUV420P8
         ├─→ mv.Super (pirámide de motion vectors)
         ├─→ mv.Analyse (forward + backward)
         ├─→ mv.FlowFPS × multi (cap 2-3)
         ├─→ Convert YUV420P10
         └─→ mpv VO ──→ Display nativo
```

- **Cap a 1080p (RIFE)**: garantiza fluidez en cualquier GPU compatible incluso con sources 4K/UHD.
- **Multi máximo 5× (RIFE)**: para 24 fps + 120 Hz da exactos 120 fps, sin sobrecargar la GPU con 6×.
- **Multi máximo 2× (MVTools)**: motion vectors clásicos son más caros que RIFE neural por frame; 24→48 fps mantiene CPU debajo de 50% en Ryzen 7.
- **AssumeFPS guard**: si el clip viene con `fps = 0/0` (típico de WhatsApp y VFR), se normaliza a `container_fps` antes de procesarlo — evita crashes en RIFE/MVTools que requieren fps válida.
- **NIS upscale**: mpv hace el upscale espacial final al display real con el shader público de NVIDIA — mismo que usa SVP.
- **Crash logger**: cualquier excepción Python durante la evaluación del `.vpy` se captura y escribe a `<portable_config>/interpolation.error.log` con traceback completo, Python version, sys.path y env vars relevantes — útil para diagnóstico cuando mpv solo dice "Could not initialize VapourSynth scripting".

### NIS ≠ DLSS (toda la familia DLSS)

Aclaración importante porque NIS vive en el repo `NVIDIA/DLSS` de GitHub y la gente lo confunde con cualquiera de los productos DLSS. **NIS no es ningún DLSS** — comparte el repo solo porque NVIDIA lo distribuye junto, pero técnicamente son cosas distintas:

| Tecnología | Qué hace | GPU requerida | ¿Por qué la usamos / no? |
|---|---|---|---|
| **NIS** (lo que usamos) | Upscale espacial (Lanczos + sharpening) | Cualquiera con compute shaders | ✓ GLSL público MIT, integra como shader de mpv |
| **DLSS Super Resolution** | Upscale con red neuronal | RTX 20xx+ (Tensor Cores) | ✗ Requiere motion vectors + depth buffer del render — un video grabado no los tiene |
| **DLSS Frame Generation** (DLSS-FG) | Genera frames intermedios con AI — **conceptualmente igual que RIFE** | RTX 40xx+ (Optical Flow Accelerator) | ✗ Necesita OFA hardware + Streamline SDK integrado por app. RIFE hace lo mismo sin esos requisitos |
| **DLSS Multi Frame Generation** (DLSS 4 MFG) | Hasta 3 frames generados por uno renderizado | RTX 50xx exclusivo | ✗ Mismo problema que FG, peor: 50xx-only |
| **DLSS Ray Reconstruction** | Denoising AI para ray tracing | RTX 20xx+ | ✗ No aplica a video reproducción |
| **DLAA** | Antialiasing con la red de DLSS-SR | RTX 20xx+ | ✗ No aplica (no estamos renderizando geometría) |

**Diferencia clave con RIFE vs DLSS-FG**: ambos interpolan frames con AI, pero:
- **DLSS-FG** depende de motion vectors generados durante el render (un juego sabe cómo se mueve cada pixel porque lo pintó él). Un video pre-grabado **no tiene esos datos** — DLSS-FG no puede funcionar.
- **RIFE** estima el optical flow internamente desde dos frames consecutivos. Por eso funciona en cualquier video y en cualquier GPU.

El shader `NVScaler.glsl` que el wizard copia a `portable_config/shaders/` es **solo NIS** (la parte de upscale espacial) y **funciona en cualquier GPU**. La elección entre RTX/AMD/Intel solo afecta al **backend de RIFE** (TensorRT vs NCNN-Vulkan vs OpenVINO), no al upscaler post-RIFE.

## Multi-Monitor

`auto_mode.lua` escucha `display-fps`. Si movés la ventana entre un monitor 60 Hz y un TV 120 Hz, detecta el cambio, remueve el filtro VapourSynth y lo vuelve a agregar — RIFE recalcula `multi` para el nuevo refresh rate.

## Estructura del repositorio

```
mpv-interp-wizard.ps1          # Entry point principal
modules/                       # Módulos PowerShell
  Config.psm1                  # Configuración JSON
  GPU.psm1                     # Detección de GPU
  Download.psm1                # Descargas (aria2)
  VapourSynth.psm1             # Instalación VS
  VsMlrt.psm1                  # Bundle vs-mlrt
  Patcher.psm1                 # Parches vsmlrt.py
  Templates.psm1               # Generación de archivos
  Updater.psm1                 # Auto-actualización
  Diagnostics.psm1             # Diagnóstico
  UI.psm1                      # Interfaz terminal
templates/                     # Templates editables
  interpolation-rife.vpy       # Template RIFE (incluye SC detection)
  interpolation-mvtools.vpy    # Template MVTools
  auto_mode.lua                # Control automático
  set_display_hz.ps1           # Cambio de Hz
  shaders/
    NVScaler.glsl              # NVIDIA Image Scaling v1.0.2 (NIS)
profiles/
  gpu-profiles.json            # Perfiles por GPU
build-single-bat.ps1           # Genera el .bat
.github/workflows/release.yml  # CI/CD
```

## Publicar una versión nueva

```bash
git tag -a v2.1.0 -m "Notas del release"
git push origin v2.1.0
```

GitHub Actions construye el `.bat` empaquetado, calcula SHA256 y publica la release con el binario adjunto.

## Verificar la descarga

```powershell
Get-FileHash MPV-Interp-Wizard.bat -Algorithm SHA256
```

Compara con el contenido de `SHA256.txt` publicado en la release.

## Solución de problemas comunes

### `"Could not initialize VapourSynth scripting"` en mpv-debug.log

mpv no puede cargar `VSScript.dll`. Causas en orden de probabilidad:

1. **Falta Visual C++ Redistributable 2015-2022 (x64)** — descarga e instala desde [aka.ms/vs/17/release/vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe). Si dice "already installed", entrá a Programas instalados, click derecho → Modificar → **Reparar**.
2. **mpv build sin VapourSynth habilitado** — los builds oficiales de mpv.io NO sirven. Usar shinchiro.
3. **`interpolation.vpy` con BOM** (instalaciones < v2.1.9 generaban el archivo con UTF-8 BOM, lo que rompe el parser Python) — abrí el `.vpy` con Notepad++ / VSCode y guardalo como UTF-8 SIN BOM, o ejecutá Reparar → Regenerar `interpolation.vpy` con el wizard actualizado.

### No se genera `interpolation.error.log`

Significa que el `.vpy` ni siquiera llega a ejecutarse — el problema está antes (carga de VSScript.dll o dependencias). Verificá VC++ Redist (punto 1 de arriba).

### El video va a 7-10 fps en una GPU vieja

RIFE neural no es viable en GPUs pre-Turing (TRT 10 dropeó Pascal, NCNN no tiene GridSample, ORT_DML es muy lento). El wizard a partir de v2.1.12 detecta esto y enruta automáticamente a MVTools. Si tu instalación es vieja y todavía usa RIFE, ejecutá el wizard actualizado → **Reinstalar**.

### `"GridSample not supported yet!"` con NCNN/Vulkan

El build de NCNN en vs-mlrt no implementa esa operación. RIFE no puede ejecutarse. Solución: el wizard auto-detecta esto en hardware afectado y selecciona MVTools.

### mpv.exe directo no funciona pero `mpv-vs.bat` sí

Te falta el set de variables de entorno. v2.1.14+ las setea a nivel User automáticamente durante Install. Si tenés una instalación previa, ejecutá Reparar → **Setear variables de entorno User**. Después cerrá sesión y volvé a entrar (Explorer y los terminales heredan las nuevas vars al arrancar).

### Mensaje sobre "fps no válido" o crashes con videos de WhatsApp

v2.1.15+ tiene un guard que normaliza el framerate con `AssumeFPS` cuando el clip viene sin metadata válida (caso típico de WhatsApp, capturas de teléfono, screen recordings con VFR). Si tu `.vpy` es de una versión anterior, ejecutá Reparar → Regenerar `interpolation.vpy`.

## Reportar problemas

Abre un [issue](https://github.com/Gotischer/interpolate/issues) e incluye:

1. `mpv-interp-wizard.log` (del wizard)
2. `mpv-debug.log` con `--msg-level=vapoursynth=v --log-file=mpv-debug.log`
3. `<portable_config>/interpolation.error.log` si existe (traceback Python real)
4. Salida de Diagnóstico desde el wizard

## Licencia

[MIT](LICENSE)
