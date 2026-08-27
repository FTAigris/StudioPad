# Compilar e instalar StudioPad sin pagar

StudioPad se compila como un IPA sin firma y AltStore Classic lo firma con una cuenta Apple gratuita. Esa firma vence cada siete días, por lo que AltStore debe renovarla periódicamente.

## Opción A: compilación gratuita en GitHub

Esta opción evita tener una Mac física.

1. Crea una cuenta gratuita de GitHub.
2. Crea un repositorio y sube el contenido de esta carpeta.
3. Abre la pestaña **Actions** del repositorio.
4. Elige **Crear IPA sin firma** y pulsa **Run workflow**.
5. Cuando termine, descarga el artefacto `StudioPad-unsigned-ipa`.
6. Extrae el ZIP para obtener `StudioPad-unsigned.ipa`.

Los repositorios públicos pueden usar ejecutores estándar de GitHub Actions gratuitamente. Los repositorios privados consumen la cuota incluida en la cuenta gratuita. Configura un límite de gasto de cero si no deseas cargos accidentales.

## Opción B: compilación en una Mac prestada

Se necesita Xcode 26 y XcodeGen.

1. Abre Terminal en esta carpeta.
2. Ejecuta `chmod +x scripts/build_unsigned_ipa.sh`.
3. Ejecuta `scripts/build_unsigned_ipa.sh`.
4. Recoge `build/StudioPad-unsigned.ipa`.

## Instalar desde Windows

1. Instala AltStore Classic siguiendo exclusivamente su documentación oficial.
2. Conecta el iPad al computador y activa el modo desarrollador cuando iPadOS lo solicite.
3. Abre AltStore en el iPad, selecciona **My Apps**, pulsa `+` y elige `StudioPad-unsigned.ipa`.
4. Mantén AltServer disponible periódicamente para que AltStore renueve la firma gratuita.

No uses certificados empresariales encontrados en páginas de descarga. Pueden ser revocados y los perfiles de administración desconocidos pueden modificar ajustes del dispositivo.

## Primera apertura

1. Autoriza cámara y micrófono.
2. En **Transmisión**, elige la plataforma e introduce la URL RTMP/RTMPS y la clave.
3. En **Cámara**, prueba primero una grabación local corta.
4. Para emitir la pantalla, abre **Pantalla**, toca el botón de ReplayKit y elige **StudioPad Pantalla**. Mantén esa pestaña abierta hasta que comience la cuenta regresiva.
