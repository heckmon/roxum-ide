// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Roxum';

  @override
  String get aboutRoxum => 'À propos de Roxum';

  @override
  String get aboutDeveloper => 'À propos du développeur';

  @override
  String get getInTouch => 'Me contacter';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Roxum est un IDE open source pour Android avec des runtimes intégrés et des fonctionnalités similaires à VSCode.\nConçu avec Flutter, il vise à offrir une expérience fluide aux développeurs en déplacement.\n\nSi vous souhaitez soutenir ce projet, veuillez visiter la page de dons et envisager une contribution de votre choix.';

  @override
  String get developerIntro =>
      'Bonjour ! Je suis Athul, un étudiant en ingénierie passionné par la création d\'outils open source et d\'applications mobiles.';

  @override
  String get start => 'Accueil';

  @override
  String get settings => 'Paramètres';

  @override
  String get contributeSourceCode => 'Contribuer/Code source';

  @override
  String get buyMeACoffee => 'Offrez-moi un café';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get fileManager => 'Gestionnaire de fichiers';

  @override
  String get runtimes => 'Runtimes';

  @override
  String get appTheme => 'Thème de l\'app';

  @override
  String get github => 'GitHub';

  @override
  String get builtInTerminal => 'Terminal intégré';

  @override
  String get openFile => 'Ouvrir le fichier...';

  @override
  String get openFolder => 'Ouvrir le dossier...';

  @override
  String get openRepository => 'Ouvrir le dépôt...';

  @override
  String get openTemplate => 'Ouvrir le modèle';

  @override
  String get projects => 'Projets';

  @override
  String get recent => 'Récent';

  @override
  String get noRecentActivity => 'Vous n\'avez aucune activité récente';

  @override
  String get projectNotFound => 'Projet introuvable !';

  @override
  String get fileNotFound => 'Fichier introuvable !';

  @override
  String get newFileTitle => 'Nouveau fichier...';

  @override
  String get newProject => 'Nouveau projet';

  @override
  String get projectTemplates => 'Modèles de projet';

  @override
  String get yourProjects => 'Vos projets';

  @override
  String get createNewFile => 'Créer un nouveau fichier';

  @override
  String get createNewProject =>
      'Créer un nouveau projet personnalisé avec contrôle de version (Git)';

  @override
  String get openExistingProject => 'Ouvrir un projet existant';

  @override
  String get enterRepositoryUrl => 'Saisissez l\'URL du dépôt à cloner';

  @override
  String get creatingProject => 'Création du projet...';

  @override
  String get cloningRepository => 'Clonage du dépôt...';

  @override
  String get cloningMayTakeTime => 'Cela peut prendre quelques minutes';

  @override
  String get failedToOpenFile => 'Impossible d\'ouvrir le fichier';

  @override
  String get selectedFileCouldNotBeOpened =>
      'Le fichier sélectionné n\'a pas pu être ouvert.';

  @override
  String get failedToOpenFolder => 'Impossible d\'ouvrir le dossier';

  @override
  String get selectedFolderCouldNotBeOpened =>
      'Le dossier sélectionné n\'a pas pu être ouvert.';

  @override
  String get validFilenameRequired =>
      'Veuillez saisir un nom de fichier valide';

  @override
  String get validRepositoryUrlRequired =>
      'Veuillez saisir une URL de dépôt valide';

  @override
  String get filenamePlaceholder => 'filename.ext';

  @override
  String get repositoryUrlPlaceholder => 'https://github.com/user/repo.git';

  @override
  String get generate => 'Génération...';

  @override
  String get generated => 'Généré 🎉';

  @override
  String get runtimeSetupRequired => 'Configuration du runtime requise';

  @override
  String beforeCreatingTemplateInstall(String requirements) {
    return 'Avant de créer ce modèle, veuillez installer : $requirements.';
  }

  @override
  String get openDownloadsToInstallFirst =>
      'Ouvrez Téléchargements pour l\'installer d\'abord.';

  @override
  String get projectAlreadyExists => 'Le projet existe déjà';

  @override
  String get projectAlreadyExistsBody =>
      'Un projet portant ce nom existe déjà. Voulez-vous l\'écraser ?';

  @override
  String get overwrite => 'Écraser';

  @override
  String get permissionDenied => 'Permission refusée';

  @override
  String get areYouSureDeleteProject =>
      'Voulez-vous vraiment supprimer ce projet ?';

  @override
  String get actionCannotBeUndone => 'Cette action est irréversible.';

  @override
  String failedToOpenTheProject(String error) {
    return 'Impossible d\'ouvrir le projet : $error';
  }

  @override
  String get webTemplateTitle => 'Web';

  @override
  String get webTemplateSubtitle =>
      'Projet web simple avec des fichiers HTML, CSS et JavaScript';

  @override
  String get viteAppTemplateTitle => 'Application Vite';

  @override
  String get viteAppTemplateSubtitle => 'Créer une application Vite.';

  @override
  String get dartAppTemplateTitle => 'Application Dart';

  @override
  String get dartAppTemplateSubtitle => 'Créer une application console Dart.';

  @override
  String get rustAppTemplateTitle => 'Application Rust';

  @override
  String get rustAppTemplateSubtitle => 'Créer un projet Rust.';

  @override
  String get dartRuntime => 'Runtime Dart';

  @override
  String get rustRuntime => 'Runtime Rust';

  @override
  String packageUpdatesAvailable(int count) {
    return '$count mise(s) à jour de paquet disponible(s) dans Téléchargements.';
  }

  @override
  String get projectsFilesTemplatesSharedStorage =>
      'Les projets, fichiers et modèles se trouvent désormais dans le stockage partagé.';

  @override
  String directoryAlreadyExists(String name) {
    return 'Le dossier \"$name\" existe déjà';
  }

  @override
  String get failedToCloneRepo => 'Échec du clonage du dépôt.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuler';

  @override
  String get create => 'Créer';

  @override
  String get openDownloads => 'Ouvrir les téléchargements';

  @override
  String get copilotSetupRequired => 'Configuration de Copilot requise';

  @override
  String get nodeRuntimeRequired => 'Runtime Node requis';

  @override
  String get loginToGitHubCopilot => 'Se connecter à GitHub Copilot';

  @override
  String get connecting => 'Connexion...';

  @override
  String signedInAs(String user) {
    return 'Connecté en tant que $user';
  }

  @override
  String get githubCopilotConnected => 'GitHub Copilot connecté';

  @override
  String get copilotNotAuthorized => 'Copilot non autorisé';

  @override
  String get connectionError => 'Erreur de connexion';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signedOutFromCopilot => 'Déconnecté de Copilot';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get codeCopied => 'Code copié !';

  @override
  String get waitTillDownloadFinishes =>
      'Veuillez attendre la fin du téléchargement existant.';

  @override
  String get clangRuntimeRequired =>
      'Le runtime Clang est requis avant de télécharger Rust ou Go.';

  @override
  String get openingWebView => 'Ouverture de la vue web...';

  @override
  String get couldNotStartViteServer =>
      'Impossible de démarrer le serveur Vite. Ouvrez le terminal pour voir les journaux.';

  @override
  String failedToOpenPreview(String error) {
    return 'Impossible d\'ouvrir l\'aperçu : $error';
  }

  @override
  String get syncedBackToSourceFolder => 'Synchronisé vers le dossier source.';

  @override
  String get syncBackFailed => 'Échec de la synchronisation retour.';

  @override
  String get saveFile => 'Enregistrer le fichier';

  @override
  String get exportFolder => 'Exporter le dossier';

  @override
  String get exportComplete => 'Exportation terminée.';

  @override
  String exportFailed(String error) {
    return 'Échec de l\'exportation : $error';
  }

  @override
  String get createFolder => 'Créer un dossier';

  @override
  String get createFile => 'Créer un fichier';

  @override
  String get folderAlreadyExists => 'Le dossier existe déjà.';

  @override
  String sessionNumber(int count) {
    return 'Session $count';
  }

  @override
  String newSessionCreated(String title) {
    return 'Nouvelle session créée : $title';
  }

  @override
  String get copy => 'Copier';

  @override
  String get paste => 'Coller';

  @override
  String get cut => 'Couper';

  @override
  String get delete => 'Supprimer';

  @override
  String get rename => 'Renommer';

  @override
  String get search => 'Rechercher';

  @override
  String get newFile => 'Nouveau fichier';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get cloneRepo => 'Cloner le dépôt';

  @override
  String get projectName => 'Nom du projet';

  @override
  String get repoUrl => 'URL du dépôt';

  @override
  String get clone => 'Cloner';

  @override
  String get or => 'Ou';

  @override
  String get supportVia => 'Ou soutenir via :';

  @override
  String get post => 'POST';

  @override
  String get get => 'GET';

  @override
  String get openAICompatible => 'Compatible OpenAI';

  @override
  String get anthropicMessages => 'Messages Anthropic';

  @override
  String get geminiFunctionCalling => 'Appels de fonctions Gemini';

  @override
  String get noneDisableAgenticTools =>
      'Aucun (désactiver les outils agentiques)';

  @override
  String modelIdAlreadyExists(String modelId) {
    return 'L\'ID du modèle \"$modelId\" existe déjà';
  }

  @override
  String get modelNameAsPerProviderApi =>
      'nom du modèle selon l\'API du fournisseur';

  @override
  String get apiEndpointPlaceholder =>
      'https://api.example.com/v1/chat/completions';
}
