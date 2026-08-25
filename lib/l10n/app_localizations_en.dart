// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Roxum';

  @override
  String get aboutRoxum => 'About Roxum';

  @override
  String get aboutDeveloper => 'About the developer';

  @override
  String get getInTouch => 'Get in touch';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Roxum is an open-source IDE for Android with built in runtimes and features similar to VSCode.\nBuilt with Flutter, it aims to provide a seamless experience for developers on the go.\n\nIf you\'d like to support this project, please visit the donation page and consider making a contribution of any amount';

  @override
  String get developerIntro =>
      'Hi! I\'m Athul, an engineering student passionate about building open-source tools and mobile apps.';

  @override
  String get start => 'Start';

  @override
  String get settings => 'Settings';

  @override
  String get contributeSourceCode => 'Contribute/Source code';

  @override
  String get buyMeACoffee => 'Buy me a coffee';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get fileManager => 'File manager';

  @override
  String get runtimes => 'Runtimes';

  @override
  String get appTheme => 'App theme';

  @override
  String get github => 'GitHub';

  @override
  String get builtInTerminal => 'Built-in terminal';

  @override
  String get openFile => 'Open File...';

  @override
  String get openFolder => 'Open Folder...';

  @override
  String get openRepository => 'Open Repository...';

  @override
  String get openTemplate => 'Open Template';

  @override
  String get projects => 'Projects';

  @override
  String get recent => 'Recent';

  @override
  String get noRecentActivity => 'You don\'t have any recent activity';

  @override
  String get projectNotFound => 'Project not found!';

  @override
  String get fileNotFound => 'File not found!';

  @override
  String get newFileTitle => 'New File...';

  @override
  String get newProject => 'New Project';

  @override
  String get projectTemplates => 'Project Templates';

  @override
  String get yourProjects => 'Your Projects';

  @override
  String get createNewFile => 'Create a new file';

  @override
  String get createNewProject =>
      'Create a new custom project with version control (Git)';

  @override
  String get openExistingProject => 'Open existing project';

  @override
  String get enterRepositoryUrl => 'Enter the repository URL to clone';

  @override
  String get creatingProject => 'Creating project...';

  @override
  String get cloningRepository => 'Cloning repository...';

  @override
  String get cloningMayTakeTime => 'This may take a few minutes';

  @override
  String get failedToOpenFile => 'Failed to open file';

  @override
  String get selectedFileCouldNotBeOpened =>
      'The selected file could not be opened.';

  @override
  String get failedToOpenFolder => 'Failed to open folder';

  @override
  String get selectedFolderCouldNotBeOpened =>
      'The selected folder could not be opened.';

  @override
  String get validFilenameRequired => 'Please enter a valid filename';

  @override
  String get validRepositoryUrlRequired =>
      'Please enter a valid repository URL';

  @override
  String get filenamePlaceholder => 'filename.ext';

  @override
  String get repositoryUrlPlaceholder => 'https://github.com/user/repo.git';

  @override
  String get generate => 'Generating...';

  @override
  String get generated => 'Generated 🎉';

  @override
  String get runtimeSetupRequired => 'Runtime Setup Required';

  @override
  String beforeCreatingTemplateInstall(String requirements) {
    return 'Before creating this template, please install: $requirements.';
  }

  @override
  String get openDownloadsToInstallFirst =>
      'Open Downloads to install it first.';

  @override
  String get projectAlreadyExists => 'Project already exists';

  @override
  String get projectAlreadyExistsBody =>
      'A project with this name already exists. Do you want to overwrite it?';

  @override
  String get overwrite => 'Overwrite';

  @override
  String get permissionDenied => 'Permission denied';

  @override
  String get areYouSureDeleteProject =>
      'Are you sure you want to delete this project?';

  @override
  String get actionCannotBeUndone => 'This action cannot be undone.';

  @override
  String failedToOpenTheProject(String error) {
    return 'Failed to open the project: $error';
  }

  @override
  String get webTemplateTitle => 'Web';

  @override
  String get webTemplateSubtitle =>
      'Simple web project with HTML, CSS and a JavaScript files';

  @override
  String get viteAppTemplateTitle => 'Vite app';

  @override
  String get viteAppTemplateSubtitle => 'Create a vite app.';

  @override
  String get dartAppTemplateTitle => 'Dart app';

  @override
  String get dartAppTemplateSubtitle => 'Create a Dart console app.';

  @override
  String get rustAppTemplateTitle => 'Rust app';

  @override
  String get rustAppTemplateSubtitle => 'Create a Rust project.';

  @override
  String get dartRuntime => 'Dart runtime';

  @override
  String get rustRuntime => 'Rust runtime';

  @override
  String packageUpdatesAvailable(int count) {
    return '$count package update(s) available in Downloads.';
  }

  @override
  String get projectsFilesTemplatesSharedStorage =>
      'Projects, Files and Templates now live in shared storage.';

  @override
  String directoryAlreadyExists(String name) {
    return 'Directory \"$name\" already exists';
  }

  @override
  String get failedToCloneRepo => 'Failed to clone the repo.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get create => 'Create';

  @override
  String get openDownloads => 'Open Downloads';

  @override
  String get copilotSetupRequired => 'Copilot Setup Required';

  @override
  String get nodeRuntimeRequired => 'Node Runtime Required';

  @override
  String get loginToGitHubCopilot => 'Login to GitHub Copilot';

  @override
  String get connecting => 'Connecting...';

  @override
  String signedInAs(String user) {
    return 'Signed in as $user';
  }

  @override
  String get githubCopilotConnected => 'GitHub Copilot Connected';

  @override
  String get copilotNotAuthorized => 'Copilot Not Authorized';

  @override
  String get connectionError => 'Connection Error';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signedOutFromCopilot => 'Signed out from Copilot';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get codeCopied => 'Code copied!';

  @override
  String get waitTillDownloadFinishes =>
      'Wait till the existing download finishes.';

  @override
  String get clangRuntimeRequired =>
      'Clang runtime is required before downloading Rust or Go.';

  @override
  String get openingWebView => 'Opening web view...';

  @override
  String get couldNotStartViteServer =>
      'Could not start Vite server. Open terminal to inspect logs.';

  @override
  String failedToOpenPreview(String error) {
    return 'Failed to open preview: $error';
  }

  @override
  String get syncedBackToSourceFolder => 'Synced back to source folder.';

  @override
  String get syncBackFailed => 'Sync back failed.';

  @override
  String get saveFile => 'Save file';

  @override
  String get exportFolder => 'Export folder';

  @override
  String get exportComplete => 'Export complete.';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get createFolder => 'Create folder';

  @override
  String get createFile => 'Create file';

  @override
  String get folderAlreadyExists => 'Folder already exists.';

  @override
  String sessionNumber(int count) {
    return 'Session $count';
  }

  @override
  String newSessionCreated(String title) {
    return 'New session created: $title';
  }

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String get cut => 'Cut';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get search => 'Search';

  @override
  String get newFile => 'New File';

  @override
  String get newFolder => 'New Folder';

  @override
  String get cloneRepo => 'Clone Repository';

  @override
  String get projectName => 'Project Name';

  @override
  String get repoUrl => 'Repository URL';

  @override
  String get clone => 'Clone';

  @override
  String get or => 'Or';

  @override
  String get supportVia => 'Or support via:';

  @override
  String get post => 'POST';

  @override
  String get get => 'GET';

  @override
  String get openAICompatible => 'OpenAI-compatible';

  @override
  String get anthropicMessages => 'Anthropic Messages';

  @override
  String get geminiFunctionCalling => 'Gemini Function Calling';

  @override
  String get noneDisableAgenticTools => 'None (disable agentic tools)';

  @override
  String modelIdAlreadyExists(String modelId) {
    return 'Model ID \"$modelId\" already exists';
  }

  @override
  String get modelNameAsPerProviderApi =>
      'model name as per the provider\'s api';

  @override
  String get apiEndpointPlaceholder =>
      'https://api.example.com/v1/chat/completions';
}
