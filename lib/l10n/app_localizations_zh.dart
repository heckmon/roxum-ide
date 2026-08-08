// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Roxum';

  @override
  String get aboutRoxum => '关于 Roxum';

  @override
  String get aboutDeveloper => '关于开发者';

  @override
  String get getInTouch => '联系我';

  @override
  String versionLabel(String version) {
    return '版本 $version';
  }

  @override
  String get aboutDescription =>
      'Roxum 是一款面向 Android 的开源 IDE，内置运行时，并提供与 VSCode 类似的功能。\n它基于 Flutter 构建，目标是为移动开发者提供流畅的使用体验。\n\n如果你愿意支持这个项目，请前往捐赠页面并考虑任意金额的赞助。';

  @override
  String get developerIntro => '你好！我是 Athul，一名热衷于构建开源工具和移动应用的工程学生。';

  @override
  String get start => '开始';

  @override
  String get settings => '设置';

  @override
  String get contributeSourceCode => '贡献/源代码';

  @override
  String get buyMeACoffee => '请我喝杯咖啡';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get fileManager => '文件管理器';

  @override
  String get runtimes => '运行时';

  @override
  String get appTheme => '应用主题';

  @override
  String get github => 'GitHub';

  @override
  String get builtInTerminal => '内置终端';

  @override
  String get openFile => '打开文件...';

  @override
  String get openFolder => '打开文件夹...';

  @override
  String get openRepository => '打开仓库...';

  @override
  String get openTemplate => '打开模板';

  @override
  String get projects => '项目';

  @override
  String get recent => '最近';

  @override
  String get noRecentActivity => '你还没有任何最近活动';

  @override
  String get projectNotFound => '未找到项目！';

  @override
  String get fileNotFound => '未找到文件！';

  @override
  String get newFileTitle => '新建文件...';

  @override
  String get newProject => '新建项目';

  @override
  String get projectTemplates => '项目模板';

  @override
  String get yourProjects => '你的项目';

  @override
  String get createNewFile => '创建一个新文件';

  @override
  String get createNewProject => '创建一个带版本控制（Git）的自定义项目';

  @override
  String get openExistingProject => '打开现有项目';

  @override
  String get enterRepositoryUrl => '输入要克隆的仓库地址';

  @override
  String get creatingProject => '正在创建项目...';

  @override
  String get cloningRepository => '正在克隆仓库...';

  @override
  String get cloningMayTakeTime => '这可能需要几分钟';

  @override
  String get failedToOpenFile => '打开文件失败';

  @override
  String get selectedFileCouldNotBeOpened => '所选文件无法打开。';

  @override
  String get failedToOpenFolder => '打开文件夹失败';

  @override
  String get selectedFolderCouldNotBeOpened => '所选文件夹无法打开。';

  @override
  String get validFilenameRequired => '请输入有效的文件名';

  @override
  String get validRepositoryUrlRequired => '请输入有效的仓库地址';

  @override
  String get filenamePlaceholder => 'filename.ext';

  @override
  String get repositoryUrlPlaceholder => 'https://github.com/user/repo.git';

  @override
  String get generate => '正在生成...';

  @override
  String get generated => '已生成 🎉';

  @override
  String get runtimeSetupRequired => '需要运行时设置';

  @override
  String beforeCreatingTemplateInstall(String requirements) {
    return '在创建此模板前，请先安装：$requirements。';
  }

  @override
  String get openDownloadsToInstallFirst => '先打开下载页面进行安装。';

  @override
  String get projectAlreadyExists => '项目已存在';

  @override
  String get projectAlreadyExistsBody => '同名项目已存在。要覆盖它吗？';

  @override
  String get overwrite => '覆盖';

  @override
  String get permissionDenied => '权限被拒绝';

  @override
  String get areYouSureDeleteProject => '你确定要删除这个项目吗？';

  @override
  String get actionCannotBeUndone => '此操作无法撤销。';

  @override
  String failedToOpenTheProject(String error) {
    return '打开项目失败：$error';
  }

  @override
  String get webTemplateTitle => 'Web';

  @override
  String get webTemplateSubtitle => '一个使用 HTML、CSS 和 JavaScript 文件的简单网页项目';

  @override
  String get viteAppTemplateTitle => 'Vite 应用';

  @override
  String get viteAppTemplateSubtitle => '创建一个 Vite 应用。';

  @override
  String get dartAppTemplateTitle => 'Dart 应用';

  @override
  String get dartAppTemplateSubtitle => '创建一个 Dart 控制台应用。';

  @override
  String get rustAppTemplateTitle => 'Rust 应用';

  @override
  String get rustAppTemplateSubtitle => '创建一个 Rust 项目。';

  @override
  String get dartRuntime => 'Dart 运行时';

  @override
  String get rustRuntime => 'Rust 运行时';

  @override
  String packageUpdatesAvailable(int count) {
    return '下载中有 $count 个软件包更新可用。';
  }

  @override
  String get projectsFilesTemplatesSharedStorage => '项目、文件和模板现在位于共享存储中。';

  @override
  String directoryAlreadyExists(String name) {
    return '目录“$name”已存在';
  }

  @override
  String get failedToCloneRepo => '克隆仓库失败。';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get openDownloads => '打开下载';

  @override
  String get copilotSetupRequired => '需要配置 Copilot';

  @override
  String get nodeRuntimeRequired => '需要 Node 运行时';

  @override
  String get loginToGitHubCopilot => '登录 GitHub Copilot';

  @override
  String get connecting => '正在连接...';

  @override
  String signedInAs(String user) {
    return '已登录为 $user';
  }

  @override
  String get githubCopilotConnected => 'GitHub Copilot 已连接';

  @override
  String get copilotNotAuthorized => 'Copilot 未授权';

  @override
  String get connectionError => '连接错误';

  @override
  String get signOut => '退出登录';

  @override
  String get signedOutFromCopilot => '已从 Copilot 退出登录';

  @override
  String get tryAgain => '重试';

  @override
  String get codeCopied => '代码已复制！';

  @override
  String get waitTillDownloadFinishes => '请等待当前下载完成。';

  @override
  String get clangRuntimeRequired => '在下载 Rust 或 Go 之前需要 Clang 运行时。';

  @override
  String get openingWebView => '正在打开网页视图...';

  @override
  String get couldNotStartViteServer => '无法启动 Vite 服务器。打开终端查看日志。';

  @override
  String failedToOpenPreview(String error) {
    return '打开预览失败：$error';
  }

  @override
  String get syncedBackToSourceFolder => '已同步回源文件夹。';

  @override
  String get syncBackFailed => '同步回源失败。';

  @override
  String get saveFile => '保存文件';

  @override
  String get exportFolder => '导出文件夹';

  @override
  String get exportComplete => '导出完成。';

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get createFolder => '创建文件夹';

  @override
  String get createFile => '创建文件';

  @override
  String get folderAlreadyExists => '文件夹已存在。';

  @override
  String sessionNumber(int count) {
    return '会话 $count';
  }

  @override
  String newSessionCreated(String title) {
    return '已创建新会话：$title';
  }

  @override
  String get copy => '复制';

  @override
  String get paste => '粘贴';

  @override
  String get cut => '剪切';

  @override
  String get delete => '删除';

  @override
  String get rename => '重命名';

  @override
  String get search => '搜索';

  @override
  String get newFile => '新建文件';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get cloneRepo => '克隆仓库';

  @override
  String get projectName => '项目名称';

  @override
  String get repoUrl => '仓库地址';

  @override
  String get clone => '克隆';

  @override
  String get or => '或';

  @override
  String get supportVia => '或通过以下方式支持：';

  @override
  String get post => 'POST';

  @override
  String get get => 'GET';

  @override
  String get openAICompatible => '兼容 OpenAI';

  @override
  String get anthropicMessages => 'Anthropic 消息格式';

  @override
  String get geminiFunctionCalling => 'Gemini 函数调用';

  @override
  String get noneDisableAgenticTools => '无（禁用代理工具）';

  @override
  String modelIdAlreadyExists(String modelId) {
    return '模型 ID“$modelId”已存在';
  }

  @override
  String get modelNameAsPerProviderApi => '按提供方 API 的模型名称';

  @override
  String get apiEndpointPlaceholder =>
      'https://api.example.com/v1/chat/completions';
}
