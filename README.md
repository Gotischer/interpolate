# MPV Interpolation Wizard

Asistente automatizado para instalar interpolación de frames en [mpv](https://mpv.io) usando VapourSynth + RIFE (TensorRT/NCNN) o MVTools como respaldo. Convierte videos de 24/30 fps en reproducción fluida a 60/120/144 Hz.

> **v2.1.0**: scene detection real (no morphing en cortes), upscale NIS post-RIFE (mismo shader que SVP), cap a 1080p para garantizar fluidez en sources 4K, cleanup de variables de entorno persistentes que rompían el `mpv.exe` directo, fixes de instalación R76 (`0x7e`, autoload API3, deps `vsmlrt`).

## Descargar

Solo necesitas un archivo: descárgalo desde la última release.

[➜ Descargar MPV-Interp-Wizard.bat](https://github.com/Gotischer/interpolate/releases/latest)

Doble clic y listo. No requiere instalación previa.

## Características

| Característica | Descripción |
|----------------|-------------|
| 🎮 **Multi-GPU** | NVIDIA RTX/GTX, AMD Radeon, Intel Arc, iGPU |
| 🔄 **RIFE TensorRT** | Interpolación AI de alta calidad (NVIDIA RTX 20-50) |
| 🌐 **RIFE NCNN/Vulkan** | Para AMD, Intel Arc, NVIDIA antiguas |
| 🐢 **MVTools (CPU)** | Fallback universal sin GPU dedicada |
| 🎬 **Scene Detection** | Polyfill con `PlaneStats` (sin plugins) — RIFE corta limpio en cambios de escena |
| 🔍 **Cap 1080p + NIS upscale** | RIFE corre como máximo a 1080p; mpv hace upscale al display real con el shader NVIDIA Image Scaling (mismo que usa SVP) |
| 📺 **Multi-monitor** | Detecta cambios de refresh rate y re-aplica el filtro al mover la ventana |
| 🌈 **HDR** | Interpolación HDR con preservación BT.2020/PQ/HLG y metadata MaxCLL |
| 🔧 **Auto-update** | Notificaciones de nuevas versiones |

### Soporte de GPU

| GPU | Backend | Modelo | Calidad |
|-----|---------|--------|---------|
| RTX 5090/5080 (Blackwell) | TensorRT | v4.25 | 🏆 Máxima |
| RTX 4090-4060 (Ada) | TensorRT | v4.25 | 🏆 Máxima |
| RTX 3090-3050 (Ampere) | TensorRT | v4.25 | 🏆 Máxima |
| RTX 2080-2060 (Turing) | TensorRT | v4.25 | ⚡ Balanceado |
| GTX 1080-1050 (Pascal) | TensorRT | v4.25 | 💨 Rendimiento |
| AMD RX 7xxx (RDNA3) | NCNN/Vulkan | v4.25 | ⚡ Balanceado |
| AMD RX 6xxx (RDNA2) | NCNN/Vulkan | v4.22 | 💨 Rendimiento |
| Intel Arc | NCNN/Vulkan | v4.22 | ⚡ Balanceado |
| iGPU / Otras | MVTools | — | 🐢 Básica |

`v4.25` (no `_heavy`) es el default desde v2.1 para garantizar fluidez 4K@60 en RTX 30/40/50 incluso con HDR. Si tu uso es exclusivamente ≤1080p y querés calidad máxima podés editar `interpolation.vpy` y cambiar `RIFEModel.v4_25` por `RIFEModel.v4_25_heavy`.

## Requisitos

- **Windows 10 o superior**
- **mpv build con VapourSynth habilitado** — el wizard se prueba contra los builds de [**shinchiro**](https://github.com/shinchiro/mpv-winbuild-cmake/releases). Los builds oficiales de mpv.io **no incluyen** VapourSynth.
  - Bajá el `.7z` que corresponda a tu CPU:
    - `mpv-x86_64-v3-YYYYMMDD-git-XXXXXXX.7z` — recomendado en CPU moderna (Intel Haswell+ / AMD Zen+, con AVX2).
    - `mpv-x86_64-YYYYMMDD-git-XXXXXXX.7z` — baseline, para CPU previa a 2013.
  - Mínimo: cualquier release de 2025 en adelante (necesita API de VapourSynth R76).
  - Extraé el `.7z` a una carpeta (ej. `H:\mpv\`) y dejá los archivos sueltos ahí — esa será la ruta a `mpv.exe` que pide el wizard.
- **~7 GB libres en disco** para VapourSynth + vs-mlrt + modelos RIFE
- **Driver NVIDIA reciente** (solo si vas a usar RIFE TensorRT — recomendado: NVIDIA Game Ready/Studio 560+ para RTX 50xx, 550+ para RTX 30/40xx)
- **Python embed 3.13.x** — lo descarga el wizard automáticamente (no hace falta tenerlo instalado)

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

```
Source (cualquier res) ──┐
                         ├─→ Downscale a max 1920×1080 (RGBH)
                         ├─→ Scene detection (PlaneStats)
                         ├─→ RIFE (TRT/NCNN) × multi
                         ├─→ Convert YUV420P10
                         └─→ mpv VO + NVScaler.glsl ──→ Display nativo
```

- **Cap a 1080p**: garantiza fluidez en GPU normal incluso con sources 4K/UHD.
- **Multi máximo 5×**: para 24 fps + 120 Hz da exactos 120 fps, sin sobrecargar la GPU con 6×.
- **NIS upscale**: mpv hace el upscale espacial final al display real con el shader público de NVIDIA — mismo que usa SVP.

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

## Reportar problemas

Abre un [issue](https://github.com/Gotischer/interpolate/issues) e incluye `mpv-interp-wizard.log`.

## Licencia

[MIT](LICENSE)
