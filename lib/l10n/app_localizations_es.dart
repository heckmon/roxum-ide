// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Roxum';

  @override
  String get aboutRoxum => 'Acerca de Roxum';

  @override
  String get aboutDeveloper => 'Acerca del desarrollador';

  @override
  String get getInTouch => 'Ponte en contacto';

  @override
  String versionLabel(String version) {
    return 'Versión $version';
  }

  @override
  String get aboutDescription =>
      'Roxum es un IDE de código abierto para Android con runtimes integrados y funciones similares a VSCode.\nConstruido con Flutter, busca ofrecer una experiencia fluida para desarrolladores en movimiento.\n\nSi quieres apoyar este proyecto, visita la página de donaciones y considera hacer una contribución de cualquier importe.';

  @override
  String get developerIntro =>
      '¡Hola! Soy Athul, un estudiante de ingeniería apasionado por crear herramientas de código abierto y aplicaciones móviles.';

  @override
  String get start => 'Inicio';

  @override
  String get settings => 'Ajustes';

  @override
  String get contributeSourceCode => 'Contribuir/Código fuente';

  @override
  String get buyMeACoffee => 'Invítame a un café';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get fileManager => 'Gestor de archivos';

  @override
  String get runtimes => 'Runtimes';

  @override
  String get appTheme => 'Tema de la app';

  @override
  String get github => 'GitHub';

  @override
  String get builtInTerminal => 'Terminal integrada';

  @override
  String get openFile => 'Abrir archivo...';

  @override
  String get openFolder => 'Abrir carpeta...';

  @override
  String get openRepository => 'Abrir repositorio...';

  @override
  String get openTemplate => 'Abrir plantilla';

  @override
  String get projects => 'Proyectos';

  @override
  String get recent => 'Reciente';

  @override
  String get noRecentActivity => 'No tienes actividad reciente';

  @override
  String get projectNotFound => '¡Proyecto no encontrado!';

  @override
  String get fileNotFound => '¡Archivo no encontrado!';

  @override
  String get newFileTitle => 'Nuevo archivo...';

  @override
  String get newProject => 'Nuevo proyecto';

  @override
  String get projectTemplates => 'Plantillas de proyecto';

  @override
  String get yourProjects => 'Tus proyectos';

  @override
  String get createNewFile => 'Crear un archivo nuevo';

  @override
  String get createNewProject =>
      'Crear un proyecto personalizado nuevo con control de versiones (Git)';

  @override
  String get openExistingProject => 'Abrir proyecto existente';

  @override
  String get enterRepositoryUrl =>
      'Introduce la URL del repositorio para clonar';

  @override
  String get creatingProject => 'Creando proyecto...';

  @override
  String get cloningRepository => 'Clonando repositorio...';

  @override
  String get cloningMayTakeTime => 'Esto puede tardar unos minutos';

  @override
  String get failedToOpenFile => 'No se pudo abrir el archivo';

  @override
  String get selectedFileCouldNotBeOpened =>
      'No se pudo abrir el archivo seleccionado.';

  @override
  String get failedToOpenFolder => 'No se pudo abrir la carpeta';

  @override
  String get selectedFolderCouldNotBeOpened =>
      'No se pudo abrir la carpeta seleccionada.';

  @override
  String get validFilenameRequired => 'Introduce un nombre de archivo válido';

  @override
  String get validRepositoryUrlRequired =>
      'Introduce una URL de repositorio válida';

  @override
  String get filenamePlaceholder => 'filename.ext';

  @override
  String get repositoryUrlPlaceholder => 'https://github.com/user/repo.git';

  @override
  String get generate => 'Generando...';

  @override
  String get generated => 'Generado 🎉';

  @override
  String get runtimeSetupRequired => 'Se requiere configuración del runtime';

  @override
  String beforeCreatingTemplateInstall(String requirements) {
    return 'Antes de crear esta plantilla, instala: $requirements.';
  }

  @override
  String get openDownloadsToInstallFirst =>
      'Abre Descargas para instalarlo primero.';

  @override
  String get projectAlreadyExists => 'El proyecto ya existe';

  @override
  String get projectAlreadyExistsBody =>
      'Ya existe un proyecto con este nombre. ¿Quieres sobrescribirlo?';

  @override
  String get overwrite => 'Sobrescribir';

  @override
  String get permissionDenied => 'Permiso denegado';

  @override
  String get areYouSureDeleteProject =>
      '¿Seguro que quieres eliminar este proyecto?';

  @override
  String get actionCannotBeUndone => 'Esta acción no se puede deshacer.';

  @override
  String failedToOpenTheProject(String error) {
    return 'No se pudo abrir el proyecto: $error';
  }

  @override
  String get webTemplateTitle => 'Web';

  @override
  String get webTemplateSubtitle =>
      'Proyecto web simple con archivos HTML, CSS y JavaScript';

  @override
  String get viteAppTemplateTitle => 'Aplicación Vite';

  @override
  String get viteAppTemplateSubtitle => 'Crear una aplicación Vite.';

  @override
  String get dartAppTemplateTitle => 'Aplicación Dart';

  @override
  String get dartAppTemplateSubtitle => 'Crear una aplicación de consola Dart.';

  @override
  String get rustAppTemplateTitle => 'Aplicación Rust';

  @override
  String get rustAppTemplateSubtitle => 'Crear un proyecto Rust.';

  @override
  String get dartRuntime => 'Runtime de Dart';

  @override
  String get rustRuntime => 'Runtime de Rust';

  @override
  String packageUpdatesAvailable(int count) {
    return 'Hay $count actualización(es) de paquetes disponibles en Descargas.';
  }

  @override
  String get projectsFilesTemplatesSharedStorage =>
      'Los proyectos, archivos y plantillas ahora están en el almacenamiento compartido.';

  @override
  String directoryAlreadyExists(String name) {
    return 'El directorio \"$name\" ya existe';
  }

  @override
  String get failedToCloneRepo => 'No se pudo clonar el repositorio.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancelar';

  @override
  String get create => 'Crear';

  @override
  String get openDownloads => 'Abrir descargas';

  @override
  String get copilotSetupRequired => 'Se requiere configurar Copilot';

  @override
  String get nodeRuntimeRequired => 'Se requiere el runtime de Node';

  @override
  String get loginToGitHubCopilot => 'Iniciar sesión en GitHub Copilot';

  @override
  String get connecting => 'Conectando...';

  @override
  String signedInAs(String user) {
    return 'Has iniciado sesión como $user';
  }

  @override
  String get githubCopilotConnected => 'GitHub Copilot conectado';

  @override
  String get copilotNotAuthorized => 'Copilot no autorizado';

  @override
  String get connectionError => 'Error de conexión';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get signedOutFromCopilot => 'Sesión cerrada en Copilot';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get codeCopied => '¡Código copiado!';

  @override
  String get waitTillDownloadFinishes =>
      'Espera a que termine la descarga existente.';

  @override
  String get clangRuntimeRequired =>
      'Se requiere el runtime de Clang antes de descargar Rust o Go.';

  @override
  String get openingWebView => 'Abriendo vista web...';

  @override
  String get couldNotStartViteServer =>
      'No se pudo iniciar el servidor Vite. Abre la terminal para ver los registros.';

  @override
  String failedToOpenPreview(String error) {
    return 'No se pudo abrir la vista previa: $error';
  }

  @override
  String get syncedBackToSourceFolder =>
      'Sincronizado de vuelta a la carpeta de origen.';

  @override
  String get syncBackFailed => 'La sincronización de vuelta falló.';

  @override
  String get saveFile => 'Guardar archivo';

  @override
  String get exportFolder => 'Exportar carpeta';

  @override
  String get exportComplete => 'Exportación completada.';

  @override
  String exportFailed(String error) {
    return 'Exportación fallida: $error';
  }

  @override
  String get createFolder => 'Crear carpeta';

  @override
  String get createFile => 'Crear archivo';

  @override
  String get folderAlreadyExists => 'La carpeta ya existe.';

  @override
  String sessionNumber(int count) {
    return 'Sesión $count';
  }

  @override
  String newSessionCreated(String title) {
    return 'Nueva sesión creada: $title';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get paste => 'Pegar';

  @override
  String get cut => 'Cortar';

  @override
  String get delete => 'Eliminar';

  @override
  String get rename => 'Renombrar';

  @override
  String get search => 'Buscar';

  @override
  String get newFile => 'Nuevo archivo';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get cloneRepo => 'Clonar repositorio';

  @override
  String get projectName => 'Nombre del proyecto';

  @override
  String get repoUrl => 'URL del repositorio';

  @override
  String get clone => 'Clonar';

  @override
  String get or => 'O';

  @override
  String get supportVia => 'O apoya vía:';

  @override
  String get post => 'POST';

  @override
  String get get => 'GET';

  @override
  String get openAICompatible => 'Compatible con OpenAI';

  @override
  String get anthropicMessages => 'Mensajes de Anthropic';

  @override
  String get geminiFunctionCalling => 'Llamadas a funciones de Gemini';

  @override
  String get noneDisableAgenticTools =>
      'Ninguno (desactivar herramientas agénticas)';

  @override
  String modelIdAlreadyExists(String modelId) {
    return 'El ID del modelo \"$modelId\" ya existe';
  }

  @override
  String get modelNameAsPerProviderApi =>
      'nombre del modelo según la API del proveedor';

  @override
  String get apiEndpointPlaceholder =>
      'https://api.example.com/v1/chat/completions';
}
