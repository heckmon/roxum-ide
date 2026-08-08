import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Roxum'**
  String get appTitle;

  /// No description provided for @aboutRoxum.
  ///
  /// In en, this message translates to:
  /// **'About Roxum'**
  String get aboutRoxum;

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'About the developer'**
  String get aboutDeveloper;

  /// No description provided for @getInTouch.
  ///
  /// In en, this message translates to:
  /// **'Get in touch'**
  String get getInTouch;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Roxum is an open-source IDE for Android with built in runtimes and features similar to VSCode.\nBuilt with Flutter, it aims to provide a seamless experience for developers on the go.\n\nIf you\'d like to support this project, please visit the donation page and consider making a contribution of any amount'**
  String get aboutDescription;

  /// No description provided for @developerIntro.
  ///
  /// In en, this message translates to:
  /// **'Hi! I\'m Athul, an engineering student passionate about building open-source tools and mobile apps.'**
  String get developerIntro;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @contributeSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Contribute/Source code'**
  String get contributeSourceCode;

  /// No description provided for @buyMeACoffee.
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee'**
  String get buyMeACoffee;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @fileManager.
  ///
  /// In en, this message translates to:
  /// **'File manager'**
  String get fileManager;

  /// No description provided for @runtimes.
  ///
  /// In en, this message translates to:
  /// **'Runtimes'**
  String get runtimes;

  /// No description provided for @appTheme.
  ///
  /// In en, this message translates to:
  /// **'App theme'**
  String get appTheme;

  /// No description provided for @github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @builtInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Built-in terminal'**
  String get builtInTerminal;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open File...'**
  String get openFile;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder...'**
  String get openFolder;

  /// No description provided for @openRepository.
  ///
  /// In en, this message translates to:
  /// **'Open Repository...'**
  String get openRepository;

  /// No description provided for @openTemplate.
  ///
  /// In en, this message translates to:
  /// **'Open Template'**
  String get openTemplate;

  /// No description provided for @projects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projects;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @noRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any recent activity'**
  String get noRecentActivity;

  /// No description provided for @projectNotFound.
  ///
  /// In en, this message translates to:
  /// **'Project not found!'**
  String get projectNotFound;

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found!'**
  String get fileNotFound;

  /// No description provided for @newFileTitle.
  ///
  /// In en, this message translates to:
  /// **'New File...'**
  String get newFileTitle;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get newProject;

  /// No description provided for @projectTemplates.
  ///
  /// In en, this message translates to:
  /// **'Project Templates'**
  String get projectTemplates;

  /// No description provided for @yourProjects.
  ///
  /// In en, this message translates to:
  /// **'Your Projects'**
  String get yourProjects;

  /// No description provided for @createNewFile.
  ///
  /// In en, this message translates to:
  /// **'Create a new file'**
  String get createNewFile;

  /// No description provided for @createNewProject.
  ///
  /// In en, this message translates to:
  /// **'Create a new custom project with version control (Git)'**
  String get createNewProject;

  /// No description provided for @openExistingProject.
  ///
  /// In en, this message translates to:
  /// **'Open existing project'**
  String get openExistingProject;

  /// No description provided for @enterRepositoryUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter the repository URL to clone'**
  String get enterRepositoryUrl;

  /// No description provided for @creatingProject.
  ///
  /// In en, this message translates to:
  /// **'Creating project...'**
  String get creatingProject;

  /// No description provided for @cloningRepository.
  ///
  /// In en, this message translates to:
  /// **'Cloning repository...'**
  String get cloningRepository;

  /// No description provided for @cloningMayTakeTime.
  ///
  /// In en, this message translates to:
  /// **'This may take a few minutes'**
  String get cloningMayTakeTime;

  /// No description provided for @failedToOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to open file'**
  String get failedToOpenFile;

  /// No description provided for @selectedFileCouldNotBeOpened.
  ///
  /// In en, this message translates to:
  /// **'The selected file could not be opened.'**
  String get selectedFileCouldNotBeOpened;

  /// No description provided for @failedToOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder'**
  String get failedToOpenFolder;

  /// No description provided for @selectedFolderCouldNotBeOpened.
  ///
  /// In en, this message translates to:
  /// **'The selected folder could not be opened.'**
  String get selectedFolderCouldNotBeOpened;

  /// No description provided for @validFilenameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid filename'**
  String get validFilenameRequired;

  /// No description provided for @validRepositoryUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid repository URL'**
  String get validRepositoryUrlRequired;

  /// No description provided for @filenamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'filename.ext'**
  String get filenamePlaceholder;

  /// No description provided for @repositoryUrlPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'https://github.com/user/repo.git'**
  String get repositoryUrlPlaceholder;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generate;

  /// No description provided for @generated.
  ///
  /// In en, this message translates to:
  /// **'Generated 🎉'**
  String get generated;

  /// No description provided for @runtimeSetupRequired.
  ///
  /// In en, this message translates to:
  /// **'Runtime Setup Required'**
  String get runtimeSetupRequired;

  /// No description provided for @beforeCreatingTemplateInstall.
  ///
  /// In en, this message translates to:
  /// **'Before creating this template, please install: {requirements}.'**
  String beforeCreatingTemplateInstall(String requirements);

  /// No description provided for @openDownloadsToInstallFirst.
  ///
  /// In en, this message translates to:
  /// **'Open Downloads to install it first.'**
  String get openDownloadsToInstallFirst;

  /// No description provided for @projectAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Project already exists'**
  String get projectAlreadyExists;

  /// No description provided for @projectAlreadyExistsBody.
  ///
  /// In en, this message translates to:
  /// **'A project with this name already exists. Do you want to overwrite it?'**
  String get projectAlreadyExistsBody;

  /// No description provided for @overwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwrite;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get permissionDenied;

  /// No description provided for @areYouSureDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this project?'**
  String get areYouSureDeleteProject;

  /// No description provided for @actionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get actionCannotBeUndone;

  /// No description provided for @failedToOpenTheProject.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the project: {error}'**
  String failedToOpenTheProject(String error);

  /// No description provided for @webTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get webTemplateTitle;

  /// No description provided for @webTemplateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Simple web project with HTML, CSS and a JavaScript files'**
  String get webTemplateSubtitle;

  /// No description provided for @viteAppTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Vite app'**
  String get viteAppTemplateTitle;

  /// No description provided for @viteAppTemplateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a vite app.'**
  String get viteAppTemplateSubtitle;

  /// No description provided for @dartAppTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Dart app'**
  String get dartAppTemplateTitle;

  /// No description provided for @dartAppTemplateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a Dart console app.'**
  String get dartAppTemplateSubtitle;

  /// No description provided for @rustAppTemplateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rust app'**
  String get rustAppTemplateTitle;

  /// No description provided for @rustAppTemplateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a Rust project.'**
  String get rustAppTemplateSubtitle;

  /// No description provided for @dartRuntime.
  ///
  /// In en, this message translates to:
  /// **'Dart runtime'**
  String get dartRuntime;

  /// No description provided for @rustRuntime.
  ///
  /// In en, this message translates to:
  /// **'Rust runtime'**
  String get rustRuntime;

  /// No description provided for @packageUpdatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} package update(s) available in Downloads.'**
  String packageUpdatesAvailable(int count);

  /// No description provided for @projectsFilesTemplatesSharedStorage.
  ///
  /// In en, this message translates to:
  /// **'Projects, Files and Templates now live in shared storage.'**
  String get projectsFilesTemplatesSharedStorage;

  /// No description provided for @directoryAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Directory \"{name}\" already exists'**
  String directoryAlreadyExists(String name);

  /// No description provided for @failedToCloneRepo.
  ///
  /// In en, this message translates to:
  /// **'Failed to clone the repo.'**
  String get failedToCloneRepo;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @openDownloads.
  ///
  /// In en, this message translates to:
  /// **'Open Downloads'**
  String get openDownloads;

  /// No description provided for @copilotSetupRequired.
  ///
  /// In en, this message translates to:
  /// **'Copilot Setup Required'**
  String get copilotSetupRequired;

  /// No description provided for @nodeRuntimeRequired.
  ///
  /// In en, this message translates to:
  /// **'Node Runtime Required'**
  String get nodeRuntimeRequired;

  /// No description provided for @loginToGitHubCopilot.
  ///
  /// In en, this message translates to:
  /// **'Login to GitHub Copilot'**
  String get loginToGitHubCopilot;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @signedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {user}'**
  String signedInAs(String user);

  /// No description provided for @githubCopilotConnected.
  ///
  /// In en, this message translates to:
  /// **'GitHub Copilot Connected'**
  String get githubCopilotConnected;

  /// No description provided for @copilotNotAuthorized.
  ///
  /// In en, this message translates to:
  /// **'Copilot Not Authorized'**
  String get copilotNotAuthorized;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get connectionError;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signedOutFromCopilot.
  ///
  /// In en, this message translates to:
  /// **'Signed out from Copilot'**
  String get signedOutFromCopilot;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied!'**
  String get codeCopied;

  /// No description provided for @waitTillDownloadFinishes.
  ///
  /// In en, this message translates to:
  /// **'Wait till the existing download finishes.'**
  String get waitTillDownloadFinishes;

  /// No description provided for @clangRuntimeRequired.
  ///
  /// In en, this message translates to:
  /// **'Clang runtime is required before downloading Rust or Go.'**
  String get clangRuntimeRequired;

  /// No description provided for @openingWebView.
  ///
  /// In en, this message translates to:
  /// **'Opening web view...'**
  String get openingWebView;

  /// No description provided for @couldNotStartViteServer.
  ///
  /// In en, this message translates to:
  /// **'Could not start Vite server. Open terminal to inspect logs.'**
  String get couldNotStartViteServer;

  /// No description provided for @failedToOpenPreview.
  ///
  /// In en, this message translates to:
  /// **'Failed to open preview: {error}'**
  String failedToOpenPreview(String error);

  /// No description provided for @syncedBackToSourceFolder.
  ///
  /// In en, this message translates to:
  /// **'Synced back to source folder.'**
  String get syncedBackToSourceFolder;

  /// No description provided for @syncBackFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync back failed.'**
  String get syncBackFailed;

  /// No description provided for @saveFile.
  ///
  /// In en, this message translates to:
  /// **'Save file'**
  String get saveFile;

  /// No description provided for @exportFolder.
  ///
  /// In en, this message translates to:
  /// **'Export folder'**
  String get exportFolder;

  /// No description provided for @exportComplete.
  ///
  /// In en, this message translates to:
  /// **'Export complete.'**
  String get exportComplete;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get createFolder;

  /// No description provided for @createFile.
  ///
  /// In en, this message translates to:
  /// **'Create file'**
  String get createFile;

  /// No description provided for @folderAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Folder already exists.'**
  String get folderAlreadyExists;

  /// No description provided for @sessionNumber.
  ///
  /// In en, this message translates to:
  /// **'Session {count}'**
  String sessionNumber(int count);

  /// No description provided for @newSessionCreated.
  ///
  /// In en, this message translates to:
  /// **'New session created: {title}'**
  String newSessionCreated(String title);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @newFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get newFile;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @cloneRepo.
  ///
  /// In en, this message translates to:
  /// **'Clone Repository'**
  String get cloneRepo;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project Name'**
  String get projectName;

  /// No description provided for @repoUrl.
  ///
  /// In en, this message translates to:
  /// **'Repository URL'**
  String get repoUrl;

  /// No description provided for @clone.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get clone;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @supportVia.
  ///
  /// In en, this message translates to:
  /// **'Or support via:'**
  String get supportVia;

  /// No description provided for @post.
  ///
  /// In en, this message translates to:
  /// **'POST'**
  String get post;

  /// No description provided for @get.
  ///
  /// In en, this message translates to:
  /// **'GET'**
  String get get;

  /// No description provided for @openAICompatible.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible'**
  String get openAICompatible;

  /// No description provided for @anthropicMessages.
  ///
  /// In en, this message translates to:
  /// **'Anthropic Messages'**
  String get anthropicMessages;

  /// No description provided for @geminiFunctionCalling.
  ///
  /// In en, this message translates to:
  /// **'Gemini Function Calling'**
  String get geminiFunctionCalling;

  /// No description provided for @noneDisableAgenticTools.
  ///
  /// In en, this message translates to:
  /// **'None (disable agentic tools)'**
  String get noneDisableAgenticTools;

  /// No description provided for @modelIdAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Model ID \"{modelId}\" already exists'**
  String modelIdAlreadyExists(String modelId);

  /// No description provided for @modelNameAsPerProviderApi.
  ///
  /// In en, this message translates to:
  /// **'model name as per the provider\'s api'**
  String get modelNameAsPerProviderApi;

  /// No description provided for @apiEndpointPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'https://api.example.com/v1/chat/completions'**
  String get apiEndpointPlaceholder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr', 'pt', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
