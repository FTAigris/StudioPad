# StudioPad

Primera versión de una aplicación de producción y transmisión para iPad, escrita de forma nativa con SwiftUI, AVFoundation y ReplayKit. No contiene código copiado de OBS Studio ni está afiliada con OBS Project.

## Equipos objetivo

- iPad Air de 4.ª generación con iPadOS 26.6: dispositivo mínimo de prueba.
- iPad Pro de 11 pulgadas con M2: dispositivo previsto para uso posterior.
- Despliegue mínimo del proyecto: iPadOS 18.

## Funciones incluidas

- Vista previa de cámara frontal o trasera.
- Micrófono, silencio y selección de cámara.
- Grabación local y guardado en Fotos.
- Transmisión RTMP/RTMPS a YouTube, Twitch, Kick o un servidor personalizado.
- Calidad 720p, 30/60 FPS y bitrate ajustable.
- Emisión de la pantalla completa mediante una extensión ReplayKit.
- Mezcla del audio del iPad y del micrófono durante la emisión de pantalla.
- Flujo de compilación de un IPA sin firma mediante GitHub Actions o una Mac.

## Limitaciones de esta versión

- En iPadOS 26.6, cámara y pantalla son modos separados. La captura unificada de pantalla y cámara con ScreenCaptureKit requiere iPadOS 27.
- La clave queda en el llavero protegido del iPad. Al iniciar una emisión de pantalla, StudioPad la entrega a su extensión por la interfaz local del dispositivo durante un máximo de 15 segundos. Esto evita depender de App Groups y de una cuenta de desarrollador de pago.
- El código se revisó de forma estática en Windows. La validación final requiere compilarlo con Xcode 26 y probarlo físicamente en el iPad Air 4.
- Una cuenta Apple gratuita limita la instalación a tres aplicaciones y exige renovar la firma cada siete días.

## Crear el IPA

Consulta [docs/BUILDING.md](docs/BUILDING.md). El flujo de GitHub Actions permite compilar sin poseer una Mac física y después instalar el IPA desde Windows con AltStore Classic.

## Seguridad

- Nunca incluyas una clave de transmisión dentro del repositorio.
- Mantén el repositorio privado si vas a añadir información personal.
- No compartas contraseñas de Apple ni certificados de firma.
- Descarga AltStore únicamente desde su sitio oficial.

## Verificación local

Desde Windows o macOS, ejecuta:

```text
python scripts/verify_project.py
```

Este control valida la estructura, los archivos de configuración y la ausencia de destinos RTMP con claves incrustadas.
