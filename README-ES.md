[English](./README.md) | [简体中文](./README-CN.md) | [Español](./README-ES.md)

# Roxum IDE

Roxum IDE es un editor de código y un mini IDE para Android, diseñado con un enfoque prioritario en dispositivos móviles y desarrollado con Flutter.

Combina edición de código, flujos de trabajo con terminal, herramientas para Git/GitHub, asistencia mediante IA, descarga de entornos de ejecución y una amplia personalización en una sola aplicación.

#### Roxum utiliza el potente paquete [code_forge](https://github.com/heckmon/code_forge) como motor de edición.

<a href="https://play.google.com/store/apps/details?id=com.roxum">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="60">
</a>

## Lista de características

- **Completamente gratuito y de código abierto.**
- **Compatibilidad integrada con Termux para utilizarlo como backend.**
- **Descarga o carga modelos LLM locales en formato GGUF para chatear y completar código sin conexión.**
- **Compiladores y extensiones sin conexión para los lenguajes de programación más populares.**
- **245 temas integrados y la posibilidad de crear temas personalizados.**
- **Terminal integrada.**
- **Backend del editor desarrollado en Rust, con estructuras de datos rope y sum tree, similar al editor Zed.**
- **Autocompletado de código mediante IA.**
- **Compatibilidad con LSP (sugerencias, autocompletado, resaltado de errores, información al pasar el cursor, etc.).**
- **Integración con Git y GitHub.**
- **Compatibilidad con SSH para conectarse a sistemas remotos.**
- **Integración con proveedores externos de IA para la edición autónoma mediante agentes.**

---

### Galería

<table>
  <tr>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/home.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/ag.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/ag_diff.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/rt-roxum.jpg" width="100%"></td>
  </tr>
  <tr>
    <td><img src="https://lh3.googleusercontent.com/o8_GNH3SBQnbnrJWduWE9xbW-RF8NBO3iphBx1mEc_gVYbSkyAGZyy5zEcMTGupt_1oCQipOpZMwbjlhJgbjyEs" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/ext.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/diag.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/accnt.jpg" width="100%"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/explorer.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/lsp.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/ai_cmpl.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/themes.jpg" width="100%"></td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/git_diff.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/gguf.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/termenu.jpg" width="100%"></td>
    <td><img src="https://raw.githubusercontent.com/heckmon/android-arm64-shared-libraries/refs/heads/main/scrnshots/term.jpg" width="100%"></td>
  </tr>
</table>

---

# Si Google Play Store no está disponible en tu país

## Descarga el APK completo desde [Releases](https://github.com/heckmon/roxum-ide/releases)

#### O BIEN

## Compila desde el código fuente

Esta sección está dirigida a usuarios de países como China, donde Google Play Store no está disponible. En los demás casos, se recomienda descargar el APK completo con todas las funciones desde Google Play Store, como se indica anteriormente.

Clona este repositorio y sigue estos pasos:

Asegúrate de que [git-lfs](https://git-lfs.com/) esté instalado en tu sistema y sea accesible a través de la variable `PATH`. No omitas este paso: los compiladores e intérpretes se almacenan mediante Git Large File Storage.

#### 1) Compilar la aplicación como un paquete `aab`

> [!NOTE]
>
> Para incluir todos los compiladores, intérpretes y extensiones en la compilación, generamos un archivo `aab` independiente. Este archivo es más grande que el APK descargado desde Google Play Store. La versión distribuida mediante Play Store ocupa menos espacio porque estas dependencias externas se descargan bajo demanda cuando el usuario solicita un compilador, intérprete o extensión específicos.

Antes de comenzar, instala las herramientas necesarias para desarrollar con Flutter y Android.

```bash
cd android && ./gradlew :app:bundleRelease
```

El archivo generado estará en:

`build/app/outputs/bundle/release/app-release.aab`

#### 2) Crear un APK a partir del archivo AAB

Para instalar un archivo AAB en tu dispositivo, primero debes convertirlo en un APK. Descarga la versión más reciente de bundletool desde el repositorio oficial:

https://github.com/google/bundletool/releases

A continuación, genera el APK:

```bash
java -jar path/to/bundletool.jar build-apks --bundle=your_app/build/app/outputs/bundle/release/app-release.aab --output=output.apks --mode=universal
```

Esto generará un archivo llamado `output.apks` en el directorio actual.

#### 3) Instalar el archivo APKS

Asegúrate de que haya un emulador o dispositivo físico conectado mediante `adb`.

```bash
java -jar /path/to/bundletool.jar install-apks --apks=output.apks
```

---

Agradecimientos especiales ♥️

- [@MaximoMachado](https://github.com/MaximoMachado): ayudó a financiar la publicación en Google Play Store.