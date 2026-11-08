 <p align="left">
  <a href="./README.md">English</a> |
  <a href="./README-CN.md">简体中文</a> |
  <a href="./README-ES.md">Español</a>
</p>

# Roxum IDE

Roxum IDE es un editor de código y mini IDE para Android, diseñado principalmente para dispositivos móviles y desarrollado con Flutter.

Combina edición de código, herramientas de terminal, integración con Git/GitHub, asistencia de IA, descarga de entornos de ejecución y amplias opciones de personalización en una sola aplicación.

#### Roxum utiliza el potente paquete [code_forge](https://github.com/heckmon/code_forge) como motor de edición.

<a href="https://play.google.com/store/apps/details?id=com.roxum">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="60">
</a>

> [!NOTE]
> La versión actual todavía presenta algunos problemas y ocupa bastante espacio, especialmente para los usuarios que no utilizan Play Store.
>
> La próxima versión v3.0.0 pretende solucionar estos problemas. Sin embargo, algunos de los cambios previstos podrían entrar en conflicto con las políticas de Google Play. Por ello, las futuras versiones de Roxum podrían dejar Play Store y distribuirse a través de F-Droid y GitHub Releases.

---

<details>
<summary><h2>¿Qué llegará en la versión v3.0.0?</h2></summary>

### rox – El gestor de paquetes de Roxum

- Instala una amplia variedad de herramientas de Linux en lugar de estar limitado a compiladores predefinidos.
- Este enfoque podría entrar en conflicto con las [políticas de Google Play](https://support.google.com/googleplay/android-developer/answer/16559646).

### Compatibilidad con extensiones personalizadas

- Crea extensiones personalizadas, de forma similar a VS Code.
- Instala extensiones desarrolladas por otros usuarios a través de la tienda de extensiones integrada en la aplicación.
- Lua será el lenguaje de scripting para las extensiones, de forma similar a Neovim.

</details>

---

## Lista de características

- **Completamente gratuito y de código abierto.**
- **Compatibilidad integrada con Termux para utilizarlo como backend.**
- **Descarga o carga modelos LLM locales en formato GGUF para chatear sin conexión y completar código.**
- **Compiladores y extensiones sin conexión para los lenguajes de programación más populares.**
- **245 temas integrados y la posibilidad de crear temas personalizados.**
- **Terminal integrada.**
- **Un potente motor de edición basado en estructuras de datos Rope y Sum Tree, con un diseño similar al editor Zed.**
- **Autocompletado de código mediante IA.**
- **Compatibilidad con LSP (sugerencias, autocompletado, resaltado de errores, información al pasar el cursor, etc.).**
- **Integración con Git y GitHub.**
- **Compatibilidad con SSH para conectarse a sistemas remotos.**
- **Integración con proveedores externos de IA para la edición mediante agentes (Agentic Editing).**

## Novedades de la versión 2.11.0

- Mejoras en la ejecución de código.
- El motor Markdown integrado de Roxum se ha migrado a GitHub-Flavored Markdown (GFM).
- Corrección de errores al abrir archivos.

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

# Si Play Store no está disponible en tu país

## Descarga el APK completo desde [Releases](https://github.com/heckmon/roxum-ide/releases)

#### O

## Compila desde el código fuente

Esta sección está dirigida principalmente a usuarios de países como China, donde Play Store no está disponible. Para los demás usuarios, se recomienda descargar el APK con todas las funciones desde Play Store, como se ha indicado anteriormente.

Clona este repositorio y sigue estos pasos:

Asegúrate de que [git-lfs](https://git-lfs.com/) esté instalado en tu sistema y sea accesible a través de la variable de entorno `PATH`. No omitas este paso: los compiladores e intérpretes están almacenados en GitHub Large File Storage (Git LFS).

#### 1) Compilar la aplicación como un paquete `aab`

> [!NOTE]
>
> Para incluir todos los compiladores, intérpretes y extensiones en la compilación, generamos la aplicación como un archivo `aab` independiente, cuyo tamaño es mayor que el del APK descargado desde Play Store.
>
> La versión de Play Store ocupa menos espacio porque estas dependencias externas se descargan bajo demanda cuando el usuario solicita un compilador, intérprete o extensión específicos.

Antes de comenzar, asegúrate de tener instaladas las herramientas necesarias para el desarrollo con Flutter y Android.

### Con Flutter

```bash
flutter run
```

---

### O

### Con gradlew

```bash
cd android && ./gradlew -Ptarget-platform=android-arm64 :app:bundleRelease
```

El archivo generado estará en:

`build/app/outputs/bundle/release/app-release.aab`

#### 2) Crear un APK a partir del AAB

Para instalar un archivo AAB en tu dispositivo, primero debes convertirlo a APK.

Descarga la última versión de bundletool desde el repositorio oficial:

https://github.com/google/bundletool/releases

Después, genera el APK con el siguiente comando:

```bash
java -jar path/to/bundletool.jar build-apks --bundle=your_app/build/app/outputs/bundle/release/app-release.aab --output=output.apks --mode=universal
```

Esto generará un archivo llamado `output.apks` en el directorio actual.

#### 3) Instalar el APK

Asegúrate de tener conectado un emulador o dispositivo físico mediante `adb`.

```bash
java -jar /path/to/bundletool.jar install-apks --apks=output.apks
```

---

Agradecimientos especiales ♥️

- [@MaximoMachado](https://github.com/MaximoMachado) — ayudó a financiar el lanzamiento en Play Store.