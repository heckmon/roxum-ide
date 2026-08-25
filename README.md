<p align="left">
  <a href="./README.md">English</a> |
  <a href="./README-CN.md">简体中文</a> |
  <a href="./README-ES.md">Español</a>
</p>

# Roxum IDE

Roxum IDE is a mobile-first code editor and mini IDE for Android, built with Flutter.
It combines editing, terminal workflows, Git/GitHub tooling, AI assistance, runtime downloads, and deep customization in one app.

#### Roxum uses the powerful [code_forge](https://github.com/heckmon/code_forge) package as the editor engine.

<a href="https://play.google.com/store/apps/details?id=com.roxum">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="60">
</a>

## Feature list:
- **Completely free and open source.**
- **Built-in Termux support for using Termux as a backend.**
- **Download or load local GGUF LLM models for offline chat and code completion.**
- **Offline compilers and extensions for popular languages.**
- **245 built-in themes and, an option for creating custom themes.**
- **Built-in terminal.**
- **Rust based editor backend using rope and sum tree data structures, similar to the zed editor.**
- **AI Code Completion.**
- **LSP support (suggesions, completions, error highlighting, hover info, etc).**
- **Git and Github intergration.**
- **SSH support for connecting with remote systems.**  
- **Intergrate with external AI providers for agentic editing.**

## What's new in 2.5.0:
  - FIX: [#43](https://github.com/heckmon/roxum-ide/issues/43)
  - FIX: [#20](https://github.com/heckmon/roxum-ide/issues/20)
  - FEATURE: [#42](https://github.com/heckmon/roxum-ide/issues/42)

---
### Gallery

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
<br>

# If playstore isn't accessible in your country:
## Download the full apk from [releases](https://github.com/heckmon/roxum-ide/releases)

#### OR

## Build from source

This section is intended for users from countries like China where the Play Store isn't accessible. Otherwise, it is recommended to download the full-featured APK from the Play Store as mentioned above.<br>

Clone this repo, then:

Make sure that [git-lfs](https://git-lfs.com/) is installed in your system and accessible via the `path`. Don't skip this step; the compilers and interpreters are stored in the GitHub large file storage.
#### 1) Build the app as an `aab` bundle.

> [!NOTE]
> 
> To include all compilers, interpreters and extensions in the build, we build it as a standalone `aab` file, which is bigger compared to the APK downloaded from the Play Store. The Play Store build is smaller because these external dependencies are downloaded on demand when the user requests the particular compiler/interpreter/extension.

```bash
cd android && ./gradlew :app:bundleRelease
```
This will generate the output file in `build/app/outputs/bundle/release/app-release.aab`

#### 2) Creating APK from AAB
To install aab in your device, it needs to be converted to apk first. For that, download the latest bundletool from the official repo:
https://github.com/google/bundletool/releases

Then build the APK:
```bash
java -jar path/to/bundletool.jar build-apks --bundle=your_app/build/app/outputs/bundle/release/app-release.aab --output=output.apks --mode=universal
```
This will generate a file called output.apks in the current directory
#### 3) Then install the apks:
Make sure that you are connected to an emulator or physical device via `adb`.
```bash
java -jar /path/to/bundletool.jar install-apks --apks=output.apks
```
---

Special Thanks ♥️
- [@MaximoMachado](https://github.com/MaximoMachado) — helped fund the Play store release.
