[English](./README.md) | [简体中文](./README-CN.md) | [Español](./README-ES.md)

# Roxum IDE

Roxum IDE 是一款专为移动设备设计的 Android 代码编辑器和轻量级 IDE，使用 Flutter 构建。

它将代码编辑、终端工作流、Git/GitHub 工具、AI 辅助、运行时环境下载以及深度自定义功能整合到一个应用中。

#### Roxum 使用功能强大的 [code_forge](https://github.com/heckmon/code_forge) 软件包作为编辑器引擎。

<a href="https://play.google.com/store/apps/details?id=com.roxum">
  <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" height="60">
</a>

## 功能列表

- **完全免费且开源。**
- **内置 Termux 支持，可使用 Termux 作为后端。**
- **下载或加载本地 GGUF 格式的大语言模型（LLM），实现离线聊天和代码补全。**
- **为主流编程语言提供离线编译器和扩展。**
- **内置 245 款主题，并支持创建自定义主题。**
- **内置终端。**
- **基于 Rust 构建的编辑器后端，使用 rope 和 sum tree 数据结构，设计理念类似于 Zed 编辑器。**
- **AI 代码补全。**
- **支持 LSP（代码提示、自动补全、错误高亮、悬停信息等）。**
- **集成 Git 和 GitHub。**
- **支持 SSH，可连接远程系统。**
- **支持集成外部 AI 服务提供商，实现基于智能代理的代码编辑。**

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

# 如果你所在的国家或地区无法访问 Google Play 商店

## 从 [Releases](https://github.com/heckmon/roxum-ide/releases) 下载完整 APK

#### 或者

## 从源代码构建

本节主要面向中国等无法访问 Google Play 商店的国家或地区的用户。其他用户建议直接从上文提到的 Google Play 商店下载功能完整的 APK。

克隆此仓库，然后按照以下步骤操作：

确保系统已安装 [git-lfs](https://git-lfs.com/)，并且可以通过 `PATH` 环境变量访问该工具。**不要跳过此步骤**，因为编译器和解释器存储在 GitHub Large File Storage（Git LFS）中。

#### 1）将应用构建为 `aab` 软件包

> [!NOTE]
>
> 为了在构建中包含所有编译器、解释器和扩展，我们将应用构建为独立的 `aab` 文件。该文件比从 Google Play 商店下载的 APK 更大。Play 商店版本体积更小，因为这些外部依赖项会在用户请求使用相应的编译器、解释器或扩展时按需下载。

开始之前，请安装必要的 Flutter 和 Android 开发工具。

```bash
cd android && ./gradlew :app:bundleRelease
```

生成的文件位于：

`build/app/outputs/bundle/release/app-release.aab`

#### 2）从 AAB 创建 APK

要在设备上安装 AAB 文件，需要先将其转换为 APK。请从官方仓库下载最新版本的 bundletool：

https://github.com/google/bundletool/releases

然后执行以下命令生成 APK：

```bash
java -jar path/to/bundletool.jar build-apks --bundle=your_app/build/app/outputs/bundle/release/app-release.aab --output=output.apks --mode=universal
```

执行后，当前目录下将生成名为 `output.apks` 的文件。

#### 3）安装 APKS 文件

确保已通过 `adb` 连接 Android 模拟器或实体设备。

```bash
java -jar /path/to/bundletool.jar install-apks --apks=output.apks
```

---

特别感谢 ♥️

- [@MaximoMachado](https://github.com/MaximoMachado)：为应用在 Google Play 商店的发布提供了资金支持。