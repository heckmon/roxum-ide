// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Roxum';

  @override
  String get aboutRoxum => 'Sobre o Roxum';

  @override
  String get aboutDeveloper => 'Sobre o desenvolvedor';

  @override
  String get getInTouch => 'Fale comigo';

  @override
  String versionLabel(String version) {
    return 'Versão $version';
  }

  @override
  String get aboutDescription =>
      'Roxum é um IDE de código aberto para Android com runtimes integrados e recursos semelhantes ao VSCode.\nFeito com Flutter, ele busca oferecer uma experiência fluida para desenvolvedores em movimento.\n\nSe quiser apoiar este projeto, visite a página de doações e considere contribuir com qualquer valor.';

  @override
  String get developerIntro =>
      'Olá! Sou Athul, um estudante de engenharia apaixonado por construir ferramentas de código aberto e aplicativos móveis.';

  @override
  String get start => 'Início';

  @override
  String get settings => 'Configurações';

  @override
  String get contributeSourceCode => 'Contribuir/Código-fonte';

  @override
  String get buyMeACoffee => 'Me pague um café';

  @override
  String get privacyPolicy => 'Política de privacidade';

  @override
  String get fileManager => 'Gerenciador de arquivos';

  @override
  String get runtimes => 'Runtimes';

  @override
  String get appTheme => 'Tema do app';

  @override
  String get github => 'GitHub';

  @override
  String get builtInTerminal => 'Terminal integrado';

  @override
  String get openFile => 'Abrir arquivo...';

  @override
  String get openFolder => 'Abrir pasta...';

  @override
  String get openRepository => 'Abrir repositório...';

  @override
  String get openTemplate => 'Abrir modelo';

  @override
  String get projects => 'Projetos';

  @override
  String get recent => 'Recentes';

  @override
  String get noRecentActivity => 'Você não tem atividades recentes';

  @override
  String get projectNotFound => 'Projeto não encontrado!';

  @override
  String get fileNotFound => 'Arquivo não encontrado!';

  @override
  String get newFileTitle => 'Novo arquivo...';

  @override
  String get newProject => 'Novo projeto';

  @override
  String get projectTemplates => 'Modelos de projeto';

  @override
  String get yourProjects => 'Seus projetos';

  @override
  String get createNewFile => 'Criar um novo arquivo';

  @override
  String get createNewProject =>
      'Criar um novo projeto personalizado com controle de versão (Git)';

  @override
  String get openExistingProject => 'Abrir projeto existente';

  @override
  String get enterRepositoryUrl => 'Digite a URL do repositório para clonar';

  @override
  String get creatingProject => 'Criando projeto...';

  @override
  String get cloningRepository => 'Clonando repositório...';

  @override
  String get cloningMayTakeTime => 'Isso pode levar alguns minutos';

  @override
  String get failedToOpenFile => 'Falha ao abrir o arquivo';

  @override
  String get selectedFileCouldNotBeOpened =>
      'O arquivo selecionado não pôde ser aberto.';

  @override
  String get failedToOpenFolder => 'Falha ao abrir a pasta';

  @override
  String get selectedFolderCouldNotBeOpened =>
      'A pasta selecionada não pôde ser aberta.';

  @override
  String get validFilenameRequired => 'Digite um nome de arquivo válido';

  @override
  String get validRepositoryUrlRequired =>
      'Digite uma URL de repositório válida';

  @override
  String get filenamePlaceholder => 'filename.ext';

  @override
  String get repositoryUrlPlaceholder => 'https://github.com/user/repo.git';

  @override
  String get generate => 'Gerando...';

  @override
  String get generated => 'Gerado 🎉';

  @override
  String get runtimeSetupRequired => 'Configuração de runtime necessária';

  @override
  String beforeCreatingTemplateInstall(String requirements) {
    return 'Antes de criar este modelo, instale: $requirements.';
  }

  @override
  String get openDownloadsToInstallFirst =>
      'Abra Downloads para instalar primeiro.';

  @override
  String get projectAlreadyExists => 'O projeto já existe';

  @override
  String get projectAlreadyExistsBody =>
      'Um projeto com esse nome já existe. Deseja sobrescrevê-lo?';

  @override
  String get overwrite => 'Sobrescrever';

  @override
  String get permissionDenied => 'Permissão negada';

  @override
  String get areYouSureDeleteProject =>
      'Tem certeza de que deseja excluir este projeto?';

  @override
  String get actionCannotBeUndone => 'Esta ação não pode ser desfeita.';

  @override
  String failedToOpenTheProject(String error) {
    return 'Falha ao abrir o projeto: $error';
  }

  @override
  String get webTemplateTitle => 'Web';

  @override
  String get webTemplateSubtitle =>
      'Projeto web simples com arquivos HTML, CSS e JavaScript';

  @override
  String get viteAppTemplateTitle => 'Aplicativo Vite';

  @override
  String get viteAppTemplateSubtitle => 'Criar um aplicativo Vite.';

  @override
  String get dartAppTemplateTitle => 'Aplicativo Dart';

  @override
  String get dartAppTemplateSubtitle => 'Criar um aplicativo de console Dart.';

  @override
  String get rustAppTemplateTitle => 'Aplicativo Rust';

  @override
  String get rustAppTemplateSubtitle => 'Criar um projeto Rust.';

  @override
  String get dartRuntime => 'Runtime do Dart';

  @override
  String get rustRuntime => 'Runtime do Rust';

  @override
  String packageUpdatesAvailable(int count) {
    return '$count atualização(ões) de pacote disponível(is) em Downloads.';
  }

  @override
  String get projectsFilesTemplatesSharedStorage =>
      'Projetos, arquivos e templates agora ficam no armazenamento compartilhado.';

  @override
  String directoryAlreadyExists(String name) {
    return 'O diretório \"$name\" já existe';
  }

  @override
  String get failedToCloneRepo => 'Falha ao clonar o repositório.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancelar';

  @override
  String get create => 'Criar';

  @override
  String get openDownloads => 'Abrir downloads';

  @override
  String get copilotSetupRequired => 'Configuração do Copilot necessária';

  @override
  String get nodeRuntimeRequired => 'Runtime do Node necessário';

  @override
  String get loginToGitHubCopilot => 'Entrar no GitHub Copilot';

  @override
  String get connecting => 'Conectando...';

  @override
  String signedInAs(String user) {
    return 'Conectado como $user';
  }

  @override
  String get githubCopilotConnected => 'GitHub Copilot conectado';

  @override
  String get copilotNotAuthorized => 'Copilot não autorizado';

  @override
  String get connectionError => 'Erro de conexão';

  @override
  String get signOut => 'Sair';

  @override
  String get signedOutFromCopilot => 'Saiu do Copilot';

  @override
  String get tryAgain => 'Tentar novamente';

  @override
  String get codeCopied => 'Código copiado!';

  @override
  String get waitTillDownloadFinishes =>
      'Espere o download existente terminar.';

  @override
  String get clangRuntimeRequired =>
      'O runtime Clang é necessário antes de baixar Rust ou Go.';

  @override
  String get openingWebView => 'Abrindo a visualização web...';

  @override
  String get couldNotStartViteServer =>
      'Não foi possível iniciar o servidor Vite. Abra o terminal para ver os logs.';

  @override
  String failedToOpenPreview(String error) {
    return 'Falha ao abrir a prévia: $error';
  }

  @override
  String get syncedBackToSourceFolder =>
      'Sincronizado de volta para a pasta de origem.';

  @override
  String get syncBackFailed => 'Falha na sincronização de volta.';

  @override
  String get saveFile => 'Salvar arquivo';

  @override
  String get exportFolder => 'Exportar pasta';

  @override
  String get exportComplete => 'Exportação concluída.';

  @override
  String exportFailed(String error) {
    return 'Falha na exportação: $error';
  }

  @override
  String get createFolder => 'Criar pasta';

  @override
  String get createFile => 'Criar arquivo';

  @override
  String get folderAlreadyExists => 'A pasta já existe.';

  @override
  String sessionNumber(int count) {
    return 'Sessão $count';
  }

  @override
  String newSessionCreated(String title) {
    return 'Nova sessão criada: $title';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get paste => 'Colar';

  @override
  String get cut => 'Cortar';

  @override
  String get delete => 'Excluir';

  @override
  String get rename => 'Renomear';

  @override
  String get search => 'Pesquisar';

  @override
  String get newFile => 'Novo arquivo';

  @override
  String get newFolder => 'Nova pasta';

  @override
  String get cloneRepo => 'Clonar repositório';

  @override
  String get projectName => 'Nome do projeto';

  @override
  String get repoUrl => 'URL do repositório';

  @override
  String get clone => 'Clonar';

  @override
  String get or => 'Ou';

  @override
  String get supportVia => 'Ou apoiar via:';

  @override
  String get post => 'POST';

  @override
  String get get => 'GET';

  @override
  String get openAICompatible => 'Compatível com OpenAI';

  @override
  String get anthropicMessages => 'Mensagens do Anthropic';

  @override
  String get geminiFunctionCalling => 'Chamadas de função do Gemini';

  @override
  String get noneDisableAgenticTools =>
      'Nenhum (desativar ferramentas agênticas)';

  @override
  String modelIdAlreadyExists(String modelId) {
    return 'O ID do modelo \"$modelId\" já existe';
  }

  @override
  String get modelNameAsPerProviderApi =>
      'nome do modelo conforme a API do provedor';

  @override
  String get apiEndpointPlaceholder =>
      'https://api.example.com/v1/chat/completions';
}
