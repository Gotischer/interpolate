# MPV Interpolation Wizard

Asistente automatizado para instalar interpolación de frames en [mpv](https://mpv.io) usando VapourSynth + RIFE (TensorRT/NCNN) o MVTools como respaldo. Convierte videos de 24/30 fps en reproducción fluida a 60/120/144 Hz.

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
| 🎬 **Scene Detection** | Evita artifacts en cortes de escena |
| 📺 **Multi-monitor** | Detecta 60Hz/120Hz automáticamente |
| 🌈 **HDR** | Interpolación HDR con preservación BT.2020/PQ |
| 🔧 **Auto-update** | Notificaciones de nuevas versiones |

### Soporte de GPU

| GPU | Backend | Modelo | Calidad |
|-----|---------|--------|---------|
| RTX 5090/5080 (Blackwell) | TensorRT | v4.25_heavy | 🏆 Máxima |
| RTX 4090-4060 (Ada) | TensorRT | v4.25_heavy | 🏆 Máxima |
| RTX 3090-3050 (Ampere) | TensorRT | v4.25_heavy | 🏆 Máxima |
| RTX 2080-2060 (Turing) | TensorRT | v4.25 | ⚡ Balanceado |
| GTX 1080-1050 (Pascal) | TensorRT | v4.25 | 💨 Rendimiento |
| AMD RX 7xxx (RDNA3) | NCNN/Vulkan | v4.25 | ⚡ Balanceado |
| AMD RX 6xxx (RDNA2) | NCNN/Vulkan | v4.22 | 💨 Rendimiento |
| Intel Arc | NCNN/Vulkan | v4.22 | ⚡ Balanceado |
| iGPU / Otras | MVTools | — | 🐢 Básica |

## Requisitos

- Windows 10 o superior
- mpv con soporte VapourSynth ([shinchiro](https://github.com/shinchiro/mpv-winbuild-cmake/releases) o [Gresaca](https://github.com/Gresaca/mpv-build/releases))
- ~7 GB libres en disco para RIFE
- Driver NVIDIA reciente (solo para RIFE/TensorRT)

## Cómo se usa

1. Descarga `MPV-Interp-Wizard.bat` desde la [última release](https://github.com/Gotischer/interpolate/releases/latest)
2. Doble clic. Si SmartScreen lo bloquea: "Más información" → "Ejecutar de todas formas"
3. La primera vez: configura rutas (mpv.exe, carpeta de instalación)
4. Elige "Instalar" — toma 10-30 minutos según tu conexión
5. Abre cualquier video con mpv. ¡Listo!

### Atajos en mpv

| Atajo | Acción |
|-------|--------|
| `Ctrl+i` | Toggle interpolación ON/OFF |
| `Ctrl+h` | Toggle interpolación HDR ON/OFF |
| `Ctrl+Shift+i` | Forzar interpolación ON |
| `Ctrl+Shift+d` | Mostrar diagnóstico OSD |

## HDR

Por defecto, el wizard interpola contenido HDR preservando el colorspace (BT.2020/PQ/HLG). Si prefieres el comportamiento clásico (desactivar interpolación y cambiar el Hz del monitor para HDR), usa `Ctrl+h` durante la reproducción o desactiva HDR interpolation en el menú de configuración.

## Multi-Monitor

El wizard detecta automáticamente el refresh rate del monitor donde está la ventana de mpv. Si mueves la ventana entre un monitor de 60Hz y un TV de 120Hz, el filtro se reconfigura automáticamente.

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
  interpolation-rife.vpy       # Template RIFE
  interpolation-mvtools.vpy    # Template MVTools
  auto_mode.lua                # Control automático
  set_display_hz.ps1           # Cambio de Hz
profiles/
  gpu-profiles.json            # Perfiles por GPU
build-single-bat.ps1           # Genera el .bat
.github/workflows/release.yml  # CI/CD
```

## Publicar una versión nueva

```bash
git tag v2.0.0
git push origin v2.0.0
```

GitHub Actions construye el .bat, calcula SHA256 y publica la release.

## Verificar la descarga

```powershell
Get-FileHash MPV-Interp-Wizard.bat -Algorithm SHA256
```

Compara con el contenido de `SHA256.txt` publicado en la release.

## Reportar problemas

Abre un [issue](https://github.com/Gotischer/interpolate/issues) e incluye `mpv-interp-wizard.log`.

## Licencia

[MIT](LICENSE)
