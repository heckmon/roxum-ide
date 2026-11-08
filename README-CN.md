 <p align="left">
  <a href="./README.md">English</a> |
  <a href="./README-CN.md">简体中文</a> |
  <a href="./README-ES.md">Español</a>
</p>

# Roxum IDE

Roxum IDE 是一款基于 Flutter 构建、以移动设备为优先的 Android 代码编辑器和轻量级 IDE。

它将代码编辑、终端工作流、Git/GitHub 工具、AI 辅助、运行环境下载以及深度自定义功能整合到一个应用中。

#### Roxum 使用强大的 [code_forge](https://github.com/heckmon/code_forge) 软件包作为编辑器引擎。

<a href="https://play.google.com/store/apps/details?id=com.roxum">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="60">
</a>

> [!NOTE]
> 当前版本仍存在一些问题，对于非 Play Store 用户来说，应用体积也比较庞大。
>
> 即将推出的 v3.0.0 版本旨在解决这些问题。不过，部分计划中的改动可能与 Google Play 政策冲突。因此，Roxum 的未来版本可能会从 Play Store 转移到 F-Droid 和 GitHub Releases。

---

<details>
<summary><h2>v3.0.0 即将推出的新功能</h2></summary>

### rox – Roxum 包管理器

- 安装各种 Linux 工具，不再局限于预定义的编译器。
- 这种实现方式可能与 [Google Play 政策](https://support.google.com/googleplay/android-developer/answer/16559646) 存在冲突。

### 自定义扩展支持

- 像 VS Code 一样构建自定义扩展。
- 通过应用内扩展商店安装其他用户开发的扩展。
- 使用 Lua 作为扩展脚本语言，类似于 Neovim。

</details>

---

## 功能列表

- **完全免费且开源。**
- **内置 Termux 支持，可将 Termux 用作后端。**
- **下载或加载本地 GGUF LLM 模型，实现离线聊天和代码补全。**
- **支持主流编程语言的离线编译器和扩展。**
- **内置 245 款主题，并支持创建自定义主题。**
- **内置终端。**
- **采用 Rope 和 Sum Tree 数据结构的高性能编辑器后端，设计理念类似 Zed 编辑器。**
- **AI 代码补全。**
- **支持 LSP（代码提示、自动补全、错误高亮、悬停信息等）。**
- **集成 Git 和 GitHub。**
- **支持 SSH，可连接远程系统。**
- **支持集成外部 AI 服务提供商，实现 Agentic Editing（智能代理辅助编辑）。**

## 2.11.0 版本更新

- 改进了代码执行功能。
- Roxum 内置的 Markdown 引擎已迁移至 GitHub-Flavored Markdown（GFM）。
- 修复了文件打开相关的问题。

---

### 应用截图

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

# 如果你所在的国家或地区无法访问 Play Store

## 从 [Releases](https://github.com/heckmon/roxum-ide/releases) 下载完整 APK

#### 或者

## 从源代码构建

本节主要面向中国等无法访问 Play Store 的用户。其他用户建议按照上面的说明，从 Play Store 下载功能完整的 APK。

克隆此仓库，然后按照以下步骤操作：

请确保系统已安装 [git-lfs](https://git-lfs.com/)，并且可以通过系统的 `PATH` 环境变量访问它。不要跳过此步骤，因为编译器和解释器存储在 GitHub Large File Storage（Git LFS）中。

#### 1）将应用构建为 `aab` Bundle

> [!NOTE]
>
> 为了在构建中包含所有编译器、解释器和扩展，我们将应用构建为独立的 `aab` 文件，因此其体积会比从 Play Store 下载的 APK 更大。
>
> Play Store 版本的体积较小，因为这些外部依赖项会在用户请求使用相应的编译器、解释器或扩展时按需下载。

开始之前，请确保已安装必要的 Flutter 和 Android 开发工具。

### 使用 Flutter

```bash
flutter run
```

---

### 或者

### 使用 gradlew

```bash
cd android && ./gradlew -Ptarget-platform=android-arm64 :app:bundleRelease
```

生成的文件位于：

`build/app/outputs/bundle/release/app-release.aab`

#### 2）从 AAB 创建 APK

要在设备上安装 AAB，首先需要将其转换为 APK。

请从官方仓库下载最新版本的 bundletool：

https://github.com/google/bundletool/releases

然后执行以下命令生成 APK：

```bash
java -jar path/to/bundletool.jar build-apks --bundle=your_app/build/app/outputs/bundle/release/app-release.aab --output=output.apks --mode=universal
```

这将在当前目录下生成一个名为 `output.apks` 的文件。

#### 3）安装 APK

确保已通过 `adb` 连接 Android 模拟器或实体设备。

```bash
java -jar /path/to/bundletool.jar install-apks --apks=output.apks
```

---

特别感谢 ♥️

- [@MaximoMachado](https://github.com/MaximoMachado) — 为 Play Store 版本的发布提供了资金支持。