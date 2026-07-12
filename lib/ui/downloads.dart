import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';

class _PfdRuntimeConfig {
  final String moduleName;
  final String? assetArchiveName;
  final bool requiresExtraction;
  final double weight;
  final String displayName;

  const _PfdRuntimeConfig({
    required this.moduleName,
    this.assetArchiveName,
    this.requiresExtraction = true,
    required this.weight,
    required this.displayName,
  });
}

class DownloadManager extends StatefulWidget {
  const DownloadManager({super.key});

  @override
  State<DownloadManager> createState() => _DownloadManagerState();
}

class _DownloadManagerState extends State<DownloadManager> {
  final Set<int> loadingIndexes = {};
  late final AppThemeState appThemeState;
  late final Stream<Map<String, dynamic>> _pfdInstallEvents;
  Future<void> _pfdInstallChain = Future<void>.value();
  final Set<StreamSubscription<Map<String, dynamic>>> _activePfdSubscriptions = {};

  static const Map<String, _PfdRuntimeConfig> _pfdRuntimes = {
    'node': _PfdRuntimeConfig(
      moduleName: 'node_feature',
      assetArchiveName: 'node.zip',
      weight: 80.0,
      displayName: 'Node',
    ),
    'python': _PfdRuntimeConfig(
      moduleName: 'python_feature',
      assetArchiveName: 'python.zip',
      weight: 80.0,
      displayName: 'Python',
    ),
    'java': _PfdRuntimeConfig(
      moduleName: 'java_feature',
      assetArchiveName: 'java-21-openjdk.zip',
      weight: 80.0,
      displayName: 'Java',
    ),
    'java-21-openjdk': _PfdRuntimeConfig(
      moduleName: 'java_feature',
      assetArchiveName: 'java-21-openjdk.zip',
      weight: 80.0,
      displayName: 'Java',
    ),
    'kotlin': _PfdRuntimeConfig(
      moduleName: 'kotlin_feature',
      assetArchiveName: 'kotlin.zip',
      weight: 80.0,
      displayName: 'Kotlin',
    ),
    'clang': _PfdRuntimeConfig(
      moduleName: 'clang_feature',
      assetArchiveName: 'clang.zip',
      weight: 80.0,
      displayName: 'Clang',
    ),
    'dart': _PfdRuntimeConfig(
      moduleName: 'dart_feature',
      assetArchiveName: 'dart.zip',
      weight: 80.0,
      displayName: 'Dart',
    ),
    'rust': _PfdRuntimeConfig(
      moduleName: 'rust_feature',
      assetArchiveName: 'rust.zip',
      weight: 80.0,
      displayName: 'Rust',
    ),
    'go': _PfdRuntimeConfig(
      moduleName: 'go_feature',
      assetArchiveName: 'go.zip',
      weight: 80.0,
      displayName: 'Go',
    ),
    'ruby': _PfdRuntimeConfig(
      moduleName: 'ruby_feature',
      assetArchiveName: 'ruby.zip',
      weight: 80.0,
      displayName: 'Ruby',
    ),
    'lua': _PfdRuntimeConfig(
      moduleName: 'lua_feature',
      assetArchiveName: 'lua.zip',
      weight: 80.0,
      displayName: 'Lua',
    ),
  };
  static const Map<String, _PfdRuntimeConfig> _pfdExtensions = {
    'ty': _PfdRuntimeConfig(
      moduleName: 'ty_feature',
      requiresExtraction: false,
      weight: 80.0,
      displayName: 'Ty',
    ),
    'rust-analyzer': _PfdRuntimeConfig(
      moduleName: 'rust_analyzer_feature',
      requiresExtraction: false,
      weight: 80.0,
      displayName: 'rust-analyzer',
    ),
    'gopls': _PfdRuntimeConfig(
      moduleName: 'gopls_feature',
      requiresExtraction: false,
      weight: 80.0,
      displayName: 'gopls',
    ),
    'emmyluals': _PfdRuntimeConfig(
      moduleName: 'emmylua_feature',
      requiresExtraction: false,
      weight: 80.0,
      displayName: 'EmmyLuaLs',
    ),
    
    'bash-language-server': _PfdRuntimeConfig(
      moduleName: 'bash_language_server_feature',
      assetArchiveName: 'bash-language-server.zip',
      weight: 80.0,
      displayName: 'bash-language-server',
    ),
    'copilot-language-server': _PfdRuntimeConfig(
      moduleName: 'copilot_language_server_feature',
      assetArchiveName: 'copilot-language-server.zip',
      weight: 80.0,
      displayName: 'Github Copilot',
    ),
    'kmp-lsp': _PfdRuntimeConfig(
      moduleName: 'kmp_lsp_feature',
      requiresExtraction: false,
      weight: 80.0,
      displayName: 'Kmp LSP',
    ),
    'vscode-langservers-extracted': _PfdRuntimeConfig(
      moduleName: 'vscode_langservers_extracted_feature',
      assetArchiveName: 'vscode-langservers-extracted.zip',
      weight: 80.0,
      displayName: 'VSCode Extracted LSP Servers',
    ),
  };

  static const List<String> _pythonDynloadModules = [
    'array.cpython-313-aarch64-linux-android.so',
    '_asyncio.cpython-313-aarch64-linux-android.so',
    'binascii.cpython-313-aarch64-linux-android.so',
    '_bisect.cpython-313-aarch64-linux-android.so',
    '_blake2.cpython-313-aarch64-linux-android.so',
    '_bz2.cpython-313-aarch64-linux-android.so',
    'cmath.cpython-313-aarch64-linux-android.so',
    '_codecs_cn.cpython-313-aarch64-linux-android.so',
    '_codecs_hk.cpython-313-aarch64-linux-android.so',
    '_codecs_iso2022.cpython-313-aarch64-linux-android.so',
    '_codecs_jp.cpython-313-aarch64-linux-android.so',
    '_codecs_kr.cpython-313-aarch64-linux-android.so',
    '_codecs_tw.cpython-313-aarch64-linux-android.so',
    '_contextvars.cpython-313-aarch64-linux-android.so',
    '_csv.cpython-313-aarch64-linux-android.so',
    '_ctypes.cpython-313-aarch64-linux-android.so',
    '_ctypes_test.cpython-313-aarch64-linux-android.so',
    '_datetime.cpython-313-aarch64-linux-android.so',
    '_decimal.cpython-313-aarch64-linux-android.so',
    '_elementtree.cpython-313-aarch64-linux-android.so',
    'fcntl.cpython-313-aarch64-linux-android.so',
    '_hashlib.cpython-313-aarch64-linux-android.so',
    '_heapq.cpython-313-aarch64-linux-android.so',
    '_interpchannels.cpython-313-aarch64-linux-android.so',
    '_interpqueues.cpython-313-aarch64-linux-android.so',
    '_interpreters.cpython-313-aarch64-linux-android.so',
    '_json.cpython-313-aarch64-linux-android.so',
    '_lsprof.cpython-313-aarch64-linux-android.so',
    '_lzma.cpython-313-aarch64-linux-android.so',
    'math.cpython-313-aarch64-linux-android.so',
    '_md5.cpython-313-aarch64-linux-android.so',
    'mmap.cpython-313-aarch64-linux-android.so',
    '_multibytecodec.cpython-313-aarch64-linux-android.so',
    '_opcode.cpython-313-aarch64-linux-android.so',
    '_pickle.cpython-313-aarch64-linux-android.so',
    '_posixsubprocess.cpython-313-aarch64-linux-android.so',
    'pyexpat.cpython-313-aarch64-linux-android.so',
    '_queue.cpython-313-aarch64-linux-android.so',
    '_random.cpython-313-aarch64-linux-android.so',
    'resource.cpython-313-aarch64-linux-android.so',
    'select.cpython-313-aarch64-linux-android.so',
    '_sha1.cpython-313-aarch64-linux-android.so',
    '_sha2.cpython-313-aarch64-linux-android.so',
    '_sha3.cpython-313-aarch64-linux-android.so',
    '_socket.cpython-313-aarch64-linux-android.so',
    '_sqlite3.cpython-313-aarch64-linux-android.so',
    '_ssl.cpython-313-aarch64-linux-android.so',
    '_statistics.cpython-313-aarch64-linux-android.so',
    '_struct.cpython-313-aarch64-linux-android.so',
    'syslog.cpython-313-aarch64-linux-android.so',
    'termios.cpython-313-aarch64-linux-android.so',
    '_testbuffer.cpython-313-aarch64-linux-android.so',
    '_testcapi.cpython-313-aarch64-linux-android.so',
    '_testclinic.cpython-313-aarch64-linux-android.so',
    '_testclinic_limited.cpython-313-aarch64-linux-android.so',
    '_testexternalinspection.cpython-313-aarch64-linux-android.so',
    '_testimportmultiple.cpython-313-aarch64-linux-android.so',
    '_testinternalcapi.cpython-313-aarch64-linux-android.so',
    '_testlimitedcapi.cpython-313-aarch64-linux-android.so',
    '_testmultiphase.cpython-313-aarch64-linux-android.so',
    '_testsinglephase.cpython-313-aarch64-linux-android.so',
    'unicodedata.cpython-313-aarch64-linux-android.so',
    'xxlimited_35.cpython-313-aarch64-linux-android.so',
    'xxlimited.cpython-313-aarch64-linux-android.so',
    'xxsubtype.cpython-313-aarch64-linux-android.so',
    '_xxtestfuzz.cpython-313-aarch64-linux-android.so',
    'zlib.cpython-313-aarch64-linux-android.so',
    '_zoneinfo.cpython-313-aarch64-linux-android.so',
  ];
  static const Map<String, String> _pythonLibSymlinkMap = {
    'libcrypto.so': 'libcrypto_python.so',
    'libsqlite3.so': 'libsqlite3_python.so',
    'libssl.so': 'libssl_python.so',
  };
  static const List<String> _pythonEnginesModules = [
    'afalg.so',
    'capi.so',
    'loader_attic.so',
    'padlock.so',
  ];
  static const List<String> _pythonOsslModules = [
    'legacy.so',
  ];
  static const List<String> _javaRuntimeLibraryPaths = [
    'lib/libandroid-shmem.so',
    'lib/libandroid-spawn.so',
    'lib/libattach.so',
    'lib/libawt_headless.so',
    'lib/libawt.so',
    'lib/libawt_xawt.so',
    'lib/libdt_socket.so',
    'lib/libextnet.so',
    'lib/libfontmanager.so',
    'lib/libinstrument.so',
    'lib/libj2gss.so',
    'lib/libj2pcsc.so',
    'lib/libj2pkcs11.so',
    'lib/libjaas.so',
    'lib/libjavajpeg.so',
    'lib/libjava.so',
    'lib/libjawt.so',
    'lib/libjdwp.so',
    'lib/libjimage.so',
    'lib/libjli.so',
    'lib/libjsig.so',
    'lib/libjsound.so',
    'lib/liblcms.so',
    'lib/lible.so',
    'lib/libmanagement_agent.so',
    'lib/libmanagement_ext.so',
    'lib/libmanagement.so',
    'lib/libmlib_image.so',
    'lib/libnet.so',
    'lib/libnio.so',
    'lib/libprefs.so',
    'lib/librmi.so',
    'lib/libsctp.so',
    'lib/libsplashscreen.so',
    'lib/libsyslookup.so',
    'lib/libverify.so',
    'lib/libzip.so',
    'lib/server/libjsig.so',
    'lib/server/libjvm.so',
  ];
  static const List<String> _clangRuntimeLibraryPaths = [
    'libclang-cpp.so',
    'libffi.so',
    'libLLVM.so',
    'lib/clang/21/lib/linux/libclang_rt.asan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.hwasan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.tsan-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.ubsan_minimal-aarch64-android.so',
    'lib/clang/21/lib/linux/libclang_rt.ubsan_standalone-aarch64-android.so',
  ];
  static const List<String> _goToolBinaries = [
    'asm',
    'cgo',
    'compile',
    'cover',
    'fix',
    'link',
    'preprofile',
    'vet',
  ];
  
  final List<_ComingSoonRuntimeItem> _comingSoonRuntimes = [];

  @override
  void initState() {
    appThemeState = context.read<AppThemeBloc>().state;
    _pfdInstallEvents = NativeChannel.moduleInstallEvents().asBroadcastStream();
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final catalogState = context.read<PackageCatalogCubit>().state;
      if (catalogState.runtimes.isEmpty &&
          catalogState.extensions.isEmpty &&
          !catalogState.isSyncing) {
        context.read<PackageCatalogCubit>().refreshCatalog();
      }
    });
  }

  @override
  void dispose() {
    for (final subscription in _activePfdSubscriptions.toList()) {
      subscription.cancel();
    }
    _activePfdSubscriptions.clear();
    super.dispose();
  }

  _PfdRuntimeConfig? _runtimePfdConfig(
    String? packageParentName, {
    required bool isExtension,
  }) {
    if (!Platform.isAndroid || packageParentName == null) {
      return null;
    }
    final normalizedParentName = packageParentName.toLowerCase();
    if (isExtension) {
      return _pfdExtensions[normalizedParentName];
    }
    return _pfdRuntimes[normalizedParentName];
  }

  bool _hasAnotherDownloadInProgress(int currentIndex) {
    return loadingIndexes.any((index) => index != currentIndex);
  }

  bool _isClangRuntimeInstalled() {
    final clangDir = Directory('$runtimesDir/clang');
    return clangDir.existsSync();
  }

  Future<void> _startDownload(
    BuildContext context,
    int index,
    String url,
    String archiveName,
    String targetDir,
    bool isExtension, {
    String? packageParentName,
    Extension? extensionMetadata,
  }) async {
    final downloadBloc = context.read<DownloadManagerBloc>();
    final normalizedParentName = packageParentName?.toLowerCase();

    if (_hasAnotherDownloadInProgress(index)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wait till the existing download finishes.'),
          ),
        );
      }
      return;
    }

    if (!isExtension &&
        (normalizedParentName == 'rust' || normalizedParentName == 'go') &&
        !_isClangRuntimeInstalled()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clang runtime is required before downloading Rust or Go.'),
          ),
        );
      }
      return;
    }

    setState(() {
      loadingIndexes.add(index);
    });

    final pfdConfig = _runtimePfdConfig(
      packageParentName,
      isExtension: isExtension,
    );

    if (Platform.isAndroid && pfdConfig == null) {
      if (mounted) {
        setState(() {
          loadingIndexes.remove(index);
        });
      }
      downloadBloc.clearProgress(index);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This ${isExtension ? 'extension' : 'runtime'} is not available through Play Feature Delivery in this build.',
            ),
          ),
        );
      }
      return;
    }

    if (pfdConfig != null) {
      final pfdOk = await _ensurePfdFeatureInstalled(
        context,
        index,
        downloadBloc,
        config: pfdConfig,
      );
      if (!pfdOk) {
        if (mounted) {
          setState(() {
            loadingIndexes.remove(index);
          });
        }
        downloadBloc.clearProgress(index);
        return;
      }

      if (!pfdConfig.requiresExtraction) {
        if (!context.mounted) {
          if (mounted) {
            setState(() {
              loadingIndexes.remove(index);
            });
          }
          downloadBloc.clearProgress(index);
          return;
        }

        final completed = await _finalizeModuleOnlyInstall(
          context: context,
          index: index,
          downloadBloc: downloadBloc,
          config: pfdConfig,
          packageParentName: packageParentName,
          extensionMetadata: extensionMetadata,
          isExtension: isExtension,
        );

        if (!completed) {
          downloadBloc.clearProgress(index);
        }

        if (mounted) {
          setState(() {
            loadingIndexes.remove(index);
          });
        }
        return;
      }
    }

    final stagedArchiveName = pfdConfig?.assetArchiveName;
    if (pfdConfig != null &&
        (stagedArchiveName == null || stagedArchiveName.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${pfdConfig.displayName} feature is missing an install archive configuration.',
            ),
          ),
        );
      }
      if (mounted) {
        setState(() {
          loadingIndexes.remove(index);
        });
      }
      downloadBloc.clearProgress(index);
      return;
    }

    final archivePath = pfdConfig != null
      ? "$tempDir/$stagedArchiveName"
      : "$targetDir/$archiveName";
    final extractDir = isExtension
      ? extensionDir
      : runtimesDir;

    if (pfdConfig != null && context.mounted) {
      final staged = await _stagePackageArchiveFromPfd(
        context: context,
        config: pfdConfig,
        archivePath: archivePath,
      );
      if (!staged) {
        if (mounted) {
          setState(() {
            loadingIndexes.remove(index);
          });
        }
        downloadBloc.clearProgress(index);
        return;
      }

      await _startExtraction(
        downloadBloc,
        index,
        archivePath,
        extractDir,
        archiveName,
        runtimeParentName: packageParentName,
      );
      
      if (mounted) {
        setState(() {
          loadingIndexes.remove(index);
        });
      }
      return;
    }
  }

  Future<bool> _finalizeModuleOnlyInstall({
    required BuildContext context,
    required int index,
    required DownloadManagerBloc downloadBloc,
    required _PfdRuntimeConfig config,
    required String? packageParentName,
    required Extension? extensionMetadata,
    required bool isExtension,
  }) async {
    final normalizedParent = packageParentName?.toLowerCase();
    if (!isExtension || normalizedParent == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${config.displayName} is configured as module-only but not mapped as an extension.',
            ),
          ),
        );
      }
      return false;
    }

    try {
      final Extension metadata = extensionMetadata ?? extensions.firstWhere(
        (item) => item.parentName.toLowerCase() == normalizedParent);

      if (normalizedParent == 'ty') {
        await _createTyExecutableSymlink();
      } else if (normalizedParent == 'rust-analyzer') {
        await _createRustAnalyzerExecutableSymlink();
      } else if (normalizedParent == 'gopls') {
        await _createGoplsExecutableSymlink();
      } else if (normalizedParent == 'emmyluals') {
        await _createEmmyLuaExecutableSymlink();
      } else if(normalizedParent == 'kmp-lsp') {
        await _createKmpLspExecutableSymlink();
      } else {
        throw Exception(
          'Unsupported module-only extension: ${config.displayName}',
        );
      }

      await _writeInstalledExtensionMetadata(metadata);

      downloadBloc.updateProgress(index, 100.0);
      downloadBloc.markFullyCompleted(index);
      if (!context.mounted) return true;
      await context.read<PackageCatalogCubit>().refreshInstalledStatusOnly();
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to install ${config.displayName.toLowerCase()}: $e',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _createTyExecutableSymlink() async {
    await _createModuleExecutableSymlink(
      executableName: 'ty',
      libraryFileName: 'libty.so',
    );
  }
  
  Future<void> _createKmpLspExecutableSymlink() async {
    await _createModuleExecutableSymlink(
      executableName: 'kmp-lsp',
      libraryFileName: 'libkmplsp.so',
    );
  }

  Future<void> _createRustAnalyzerExecutableSymlink() async {
    await _createModuleExecutableSymlink(
      executableName: 'rust-analyzer',
      libraryFileName: 'librust-analyzer.so',
    );
  }

  Future<void> _createGoplsExecutableSymlink() async {
    await _createModuleExecutableSymlink(
      executableName: 'gopls',
      libraryFileName: 'libgopls.so',
    );
  }

  Future<void> _createEmmyLuaExecutableSymlink() async {
    await _createModuleExecutableSymlink(
      executableName: 'emmyluals',
      libraryFileName: 'libemmy.so',
    );
  }

  Future<void> _createModuleExecutableSymlink({
    required String executableName,
    required String libraryFileName,
  }) async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final libraryPath = '$sharedPath/$libraryFileName';
    if (!await File(libraryPath).exists()) {
      throw Exception('$libraryFileName not found at $libraryPath');
    }

    final launcherBinDir = Directory(binDir);
    if (!await launcherBinDir.exists()) {
      await launcherBinDir.create(recursive: true);
    }

    await _ensureSymlink(
      linkPath: '$binDir/$executableName',
      targetPath: libraryPath,
    );
  }

  Future<void> _writeInstalledExtensionMetadata(Extension extension) async {
    final installDir = Directory('$extensionDir/${extension.parentName}');
    if (!await installDir.exists()) {
      await installDir.create(recursive: true);
    }

    final packageFile = File('${installDir.path}/rsx-package.json');
    await packageFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(extension.toJson()),
      flush: true,
    );
  }

  Future<bool> _stagePackageArchiveFromPfd({
    required BuildContext context,
    required _PfdRuntimeConfig config,
    required String archivePath,
  }) async {
    final assetName = config.assetArchiveName;
    if (assetName == null || assetName.isEmpty) {
      return false;
    }

    try {
      await NativeChannel.copyModuleAssetToPath(
        moduleName: config.moduleName,
        assetName: assetName,
        targetPath: archivePath,
      );
      return true;

    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to stage ${config.displayName.toLowerCase()} feature bundle: $e',
            ),
          ),
        );
      }
      return false;
    }
  }

  double _mergeProgress(double basePercent, double secondStagePercent) {
    final clamped = secondStagePercent.clamp(0.0, 100.0);
    return basePercent + (clamped * ((100.0 - basePercent) / 100.0));
  }

  Future<T> _runPfdInstallSerial<T>(Future<T> Function() action) {
    final previous = _pfdInstallChain;
    final gate = Completer<void>();
    _pfdInstallChain = gate.future;

    return previous.catchError((_) {}).then((_) async {
      try {
        return await action();
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
    });
  }

  Future<bool> _ensurePfdFeatureInstalled(
    BuildContext context,
    int index,
    DownloadManagerBloc downloadBloc,
    {
    required _PfdRuntimeConfig config,
    }
  ) async {
    return _runPfdInstallSerial(() async {
      final alreadyInstalled = await NativeChannel.isModuleInstalled(config.moduleName);
      if (alreadyInstalled) {
        downloadBloc.updateProgress(index, config.weight);
        return true;
      }

      final completer = Completer<bool>();
      final subscription = _pfdInstallEvents.listen(
        (event) {
          final moduleName = event['moduleName']?.toString();
          if (moduleName != config.moduleName) return;

          final status = event['status']?.toString().toLowerCase() ?? 'unknown';
          final dynamic progressValue = event['progress'];
          final double pfdProgress = progressValue is num ? progressValue.toDouble() : 0.0;
          downloadBloc.updateProgress(
            index,
            _mergeProgress(0.0, pfdProgress) * (config.weight / 100.0),
          );

          if (status == 'installed') {
            downloadBloc.updateProgress(index, config.weight);
            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return;
          }

          if (status == 'failed' || status == 'canceled') {
            if (!completer.isCompleted) {
              completer.complete(false);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );
      _activePfdSubscriptions.add(subscription);

      try {
        await NativeChannel.installModule(config.moduleName);
        final ok = await completer.future.timeout(
          const Duration(minutes: 3),
          onTimeout: () => false,
        );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to download ${config.displayName.toLowerCase()} feature module',
              ),
            ),
          );
        }
        return ok;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${config.displayName} feature install error: $e',
              ),
            ),
          );
        }
        return false;
      } finally {
        await subscription.cancel();
        _activePfdSubscriptions.remove(subscription);
      }
    });
  }

  Future<void> _startExtraction(
    DownloadManagerBloc downloadBloc,
    int index,
    String archivePath,
    String extractDir,
    String archiveName, {
    String? runtimeParentName,
  }) async {
    downloadBloc.startExtracting(index);
    
    try {
      await Extractor.extractZipBackground(
        archivePath,
        extractDir,
        archiveName: archiveName,
        onProgress: (progress) {
          downloadBloc.updateExtractionProgress(index, progress);
        },
      );
      
      final archiveFile = File(archivePath);
      if (await archiveFile.exists()) {
        await archiveFile.delete();
      }

      if(archiveName == "copilot-language-server.zip"){
        final String sharedPath = await NativeChannel.getLibraryPath();
        await Process.run("ln", ["-sf", "$sharedPath/librg.so", "$extensionDir/copilot-language-server/bin/linux/arm64/rg"]);
      }

      final normalizedRuntimeName = runtimeParentName?.toLowerCase();

      if (normalizedRuntimeName == 'python' || archiveName == 'python.zip') {
        await _createPythonRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'java' ||
          normalizedRuntimeName == 'java-21-openjdk' ||
          archiveName == 'java-21-openjdk.zip') {
        await _copyJavaRuntimeLibraries();
      }

      if (normalizedRuntimeName == 'clang' || archiveName == 'clang.zip') {
        await _createClangRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'dart' || archiveName == 'dart.zip') {
        await _createDartRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'rust' || archiveName == 'rust.zip') {
        await _createRustRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'go' || archiveName == 'go.zip') {
        await _createGoRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'ruby' || archiveName == 'ruby.zip') {
        await _createRubyRuntimeSymlinks();
      }

      if (normalizedRuntimeName == 'lua' || archiveName == 'lua.zip') {
        await _createLuaRuntimeSymlinks();
      }
      
      downloadBloc.markFullyCompleted(index);
    } catch (e) {
      debugPrint('Error during extraction: $e');
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to extract: $e',
            ),
          ),
        );
      }
      downloadBloc.markFullyCompleted(index);
    } finally {
      if (mounted) {
        await context.read<PackageCatalogCubit>().refreshInstalledStatusOnly();
      }
    }
  }

  Future<void> _createPythonRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final pythonLibDir = Directory('$runtimesDir/python/lib');
    final dynloadDir = Directory('$runtimesDir/python/lib/python3.13/lib-dynload');
    final enginesDir = Directory('$runtimesDir/python/lib/engines-3');
    final osslModulesDir = Directory('$runtimesDir/python/lib/ossl-modules');

    if (!await pythonLibDir.exists()) {
        return;
    }

    if (!await dynloadDir.exists()) {
        await dynloadDir.create(recursive: true);
    }

    if (!await enginesDir.exists()) {
      await enginesDir.create(recursive: true);
    }

    if (!await osslModulesDir.exists()) {
      await osslModulesDir.create(recursive: true);
    }

    for (final moduleFile in _pythonDynloadModules) {
      await _ensureSymlink(
        linkPath: '${dynloadDir.path}/$moduleFile',
        targetPath: '$sharedPath/$moduleFile',
      );
    }

    for (final entry in _pythonLibSymlinkMap.entries) {
      await _ensureSymlink(
        linkPath: '${pythonLibDir.path}/${entry.key}',
        targetPath: '$sharedPath/${entry.value}',
      );
    }

    for (final moduleFile in _pythonEnginesModules) {
      await _ensureSymlink(
        linkPath: '${enginesDir.path}/$moduleFile',
        targetPath: '$sharedPath/$moduleFile',
      );
    }

    for (final moduleFile in _pythonOsslModules) {
      await _ensureSymlink(
        linkPath: '${osslModulesDir.path}/$moduleFile',
        targetPath: '$sharedPath/$moduleFile',
      );
    }
  }

  Future<void> _copyJavaRuntimeLibraries() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final javaHomeDir = Directory('$runtimesDir/java-21-openjdk');

    if (!await javaHomeDir.exists()) {
      return;
    }

    for (final runtimeRelativePath in _javaRuntimeLibraryPaths) {
      final sourcePath = '$sharedPath/${runtimeRelativePath.split('/').last}';
      if (!await File(sourcePath).exists()) {
        debugPrint('Missing Java runtime library for $runtimeRelativePath (checked $sourcePath)');
        continue;
      }

      await _ensureFileCopy(
        destinationPath: '${javaHomeDir.path}/$runtimeRelativePath',
        sourcePath: sourcePath,
      );
    }
  }

  Future<void> _createClangRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final clangDir = Directory('$runtimesDir/clang');

    if (!await clangDir.exists()) {
      return;
    }

    for (final runtimeRelativePath in _clangRuntimeLibraryPaths) {
      await _ensureSymlink(
        linkPath: '${clangDir.path}/$runtimeRelativePath',
        targetPath: '$sharedPath/${runtimeRelativePath.split('/').last}',
      );
    }
  }


  Future<void> _createRustRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final sysBinDir = Directory(binDir);
    final sysLibDir = Directory(libDir);

    if (!await sysBinDir.exists()) {
      await sysBinDir.create(recursive: true);
    }
    if (!await sysLibDir.exists()) {
      await sysLibDir.create(recursive: true);
    }

    await _ensureSymlink(
      linkPath: '$binDir/rustc',
      targetPath: '$sharedPath/librustc.so',
    );

    await _ensureSymlink(
      linkPath: '$binDir/rustloader',
      targetPath: '$sharedPath/librstloader.so',
    );

    await _ensureSymlink(
      linkPath: '$binDir/cargo',
      targetPath: '$sharedPath/libcargo.so',
    );

    await _ensureSymlink(
      linkPath: '$libDir/libicudata.so.78',
      targetPath: '$sharedPath/libicudata.so',
    );

    final rustlibAarch64Dir = Directory('$runtimesDir/rust/lib/rustlib/aarch64-linux-android/lib');
    if (!await rustlibAarch64Dir.exists()) {
      await rustlibAarch64Dir.create(recursive: true);
    }

    final otherLibs = [
        'libandroid-execinfo.so',
        'libdarling_macro-403b3f47737f0e10.so',
        'libderive_setters-61a4b05c47bf1772.so',
        'libderive_where-558b72763d14629c.so',
        'libdisplaydoc-88ec4bfd0c13b0f9.so',
        'libffi.so',
        'libLLVM.so',
        'libproc_macro_hack-b9a0cb31558b686e.so',
        'libref_cast_impl-a8bcededf9b7ab39.so',
        'librustc_driver-cd257725849a655d.so',
        'librustc_fluent_macro-cc29f51bb1aff38e.so',
        'librustc_index_macros-5b5db17373d6eb5f.so',
        'librustc_macros-cd1aad3275f4d011.so',
        'librustc_type_ir_macros-94b75363d95b2ff4.so',
        'libschemars_derive-590652653e5b083d.so',
        'libserde_derive-5c6bc018f5fc6183.so',
        'libstd-6ea53b9eff82e224.so',
        'libthiserror_impl-a3575ba7b15740eb.so',
        'libtracing_attributes-ab9b431608591db8.so',
        'libunic_langid_macros_impl-cb32e7867e91c5f5.so',
        'libyoke_derive-9a29fbe7d205c401.so',
        'libzerofrom_derive-6b82ce44af5b9e5d.so',
        'libzerovec_derive-851096cd7124147b.so'
    ];

    for (final lib in otherLibs) {
        await _ensureSymlink(
            linkPath: '${rustlibAarch64Dir.path}/$lib',
            targetPath: '$sharedPath/$lib',
        );
    }
  }

  Future<void> _createGoRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final goRuntimeBinDir = Directory('$runtimesDir/go/bin');
    final goRuntimeToolDir = Directory('$runtimesDir/go/pkg/tool/android_arm64');
    final launcherBinDir = Directory(binDir);

    if (!await goRuntimeBinDir.exists()) {
      await goRuntimeBinDir.create(recursive: true);
    }

    if (!await goRuntimeToolDir.exists()) {
      await goRuntimeToolDir.create(recursive: true);
    }

    if (!await launcherBinDir.exists()) {
      await launcherBinDir.create(recursive: true);
    }

    await _ensureSymlink(
      linkPath: '${goRuntimeBinDir.path}/go',
      targetPath: '$sharedPath/libgo.so',
    );

    await _ensureSymlink(
      linkPath: '${goRuntimeBinDir.path}/gofmt',
      targetPath: '$sharedPath/libgofmt.so',
    );

    await _ensureSymlink(
      linkPath: '$binDir/go',
      targetPath: '$sharedPath/libgo.so',
    );

    await _ensureSymlink(
      linkPath: '$binDir/gofmt',
      targetPath: '$sharedPath/libgofmt.so',
    );

    for (final toolName in _goToolBinaries) {
      await _ensureSymlink(
        linkPath: '${goRuntimeToolDir.path}/$toolName',
        targetPath: '$sharedPath/lib$toolName.so',
      );
    }
  }

  Future<void> _createRubyRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final rubyRuntimeRoot = Directory('$runtimesDir/ruby/lib/ruby');
    final sharedDir = Directory(sharedPath);
    final systemLibDir = Directory(libDir);

    if (!await rubyRuntimeRoot.exists() || !await sharedDir.exists()) {
      return;
    }

    if (!await systemLibDir.exists()) {
      await systemLibDir.create(recursive: true);
    }

    await for (final entity in sharedDir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final stagedName = entity.path.split('/').last;
      if (!stagedName.startsWith('ruby_') || !stagedName.endsWith('.so')) {
        continue;
      }

      final encodedRelative = stagedName.substring('ruby_'.length);
      final relativePath = encodedRelative.replaceAll('__', '/');
      await _ensureSymlink(
        linkPath: '${rubyRuntimeRoot.path}/$relativePath',
        targetPath: '$sharedPath/$stagedName',
      );
    }

    await _ensureSymlink(
      linkPath: '$libDir/libruby.so.3.4',
      targetPath: '$sharedPath/libruby.so',
    );
  }

  Future<void> _createLuaRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final luaBinDir = Directory('$runtimesDir/lua/bin');

    if (!await luaBinDir.exists()) {
      await luaBinDir.create(recursive: true);
    }

    await _ensureSymlink(
      linkPath: '${luaBinDir.path}/lua',
      targetPath: '$sharedPath/liblua.so',
    );

    await _ensureSymlink(
      linkPath: '${luaBinDir.path}/luac',
      targetPath: '$sharedPath/libluac.so',
    );
  }

  Future<void> _createDartRuntimeSymlinks() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    final dartBinDir = Directory('$runtimesDir/dart/bin');
    final launcherBinDir = Directory(binDir);

    if (!await dartBinDir.exists()) {
      return;
    }

    if (!await launcherBinDir.exists()) {
      await launcherBinDir.create(recursive: true);
    }

    await _ensureSymlink(
      linkPath: '${dartBinDir.path}/dart',
      targetPath: '$sharedPath/libdart.so',
    );

    await _ensureSymlink(
      linkPath: '${dartBinDir.path}/dartvm',
      targetPath: '$sharedPath/libdartvm.so',
    );

    final aotIntermediate = '${dartBinDir.path}/libdart.so';
    await _ensureSymlink(
      linkPath: aotIntermediate,
      targetPath: '$sharedPath/libdartaotruntime.so',
    );

    await _ensureSymlink(
      linkPath: '${dartBinDir.path}/dartaotruntime',
      targetPath: aotIntermediate,
    );

    await _ensureSymlink(
      linkPath: '$binDir/dart',
      targetPath: '$sharedPath/libloader.so',
    );
  }

  Future<void> _ensureFileCopy({
    required String destinationPath,
    required String sourcePath,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        debugPrint('Failed to copy missing source file: $sourcePath');
        return;
      }

      final sourceStat = await sourceFile.stat();
      final existingType = await FileSystemEntity.type(destinationPath, followLinks: false);

      if (existingType == FileSystemEntityType.file) {
        final destinationFile = File(destinationPath);
        final destinationStat = await destinationFile.stat();
        if (destinationStat.size == sourceStat.size) {
          return;
        }
        await destinationFile.delete();
      } else if (existingType == FileSystemEntityType.link) {
        await Link(destinationPath).delete();
      } else if (existingType == FileSystemEntityType.directory) {
        await Directory(destinationPath).delete(recursive: true);
      }

      await File(destinationPath).parent.create(recursive: true);
      await sourceFile.copy(destinationPath);
    } catch (e) {
      debugPrint('Failed to copy file $sourcePath -> $destinationPath: $e');
    }
  }

  Future<void> _ensureSymlink({
    required String linkPath,
    required String targetPath,
  }) async {
    try {
      final existingType = await FileSystemEntity.type(linkPath, followLinks: false);
      if (existingType == FileSystemEntityType.file) {
        await File(linkPath).delete();
      } else if (existingType == FileSystemEntityType.link) {
        await Link(linkPath).delete();
      } else if (existingType == FileSystemEntityType.directory) {
        await Directory(linkPath).delete(recursive: true);
      }

      await Link(linkPath).create(targetPath, recursive: true);
    } catch (e) {
      debugPrint('Failed to create symlink $linkPath -> $targetPath: $e');
    }
  }

  void _deletePathIfExistsSync(String targetPath) {
    try {
      final existingType = FileSystemEntity.typeSync(
        targetPath,
        followLinks: false,
      );

      if (existingType == FileSystemEntityType.file) {
        File(targetPath).deleteSync();
      } else if (existingType == FileSystemEntityType.link) {
        Link(targetPath).deleteSync();
      } else if (existingType == FileSystemEntityType.directory) {
        Directory(targetPath).deleteSync(recursive: true);
      }
    } catch (e) {
      debugPrint('Failed to delete path $targetPath: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final catalogState = context.watch<PackageCatalogCubit>().state;
    final runtimeItems = catalogState.runtimes;
    final extensionItems = catalogState.extensions;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "Downloads",
            style: TextStyle(
              color: appThemeState.appTheme.selectScreenCardTextColor
            )
          ),
          backgroundColor: Colors.transparent,
          bottom: TabBar(
            labelColor: Color.fromARGB(255, 17, 120, 189),
            indicatorColor: Color.fromARGB(255, 17, 120, 189),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(
                icon: FaIcon(FontAwesomeIcons.gears, size: 26),
                text: "Runtimes",
              ),
              Tab(
                icon: Icon(Icons.extension),
                text: "Extensions",
              )
            ]
          ),
        ),
        body: TabBarView(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: runtimeItems.isEmpty
                  ? _buildCatalogStateView(
                      title: 'No runtimes available in this build',
                      actionLabel: 'Refresh',
                      onRetry: () => context.read<PackageCatalogCubit>().refreshCatalog(),
                    )
                  : ListView.builder(
                itemCount: runtimeItems.length + _comingSoonRuntimes.length,
                itemBuilder: (_, index) {
                  if (index >= runtimeItems.length) {
                    final comingSoonRuntime = _comingSoonRuntimes[index - runtimeItems.length];
                    final textColor = appThemeState.appTheme.selectScreenCardTextColor.withAlpha(180);

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: Card(
                        child: Opacity(
                          opacity: 0.7,
                          child: ListTile(
                            enabled: false,
                            contentPadding: EdgeInsets.zero,
                            leading: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: comingSoonRuntime.icon,
                            ),
                            title: Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      comingSoonRuntime.name,
                                      style: TextStyle(color: textColor),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withAlpha(45),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Coming soon',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            subtitle: Text(
                              comingSoonRuntime.details,
                              style: TextStyle(color: textColor.withAlpha(180)),
                            ),
                            trailing: SizedBox(
                              height: 50,
                              width: 100,
                              child: LinearPercentIndicator(
                                progressColor: Colors.grey.withAlpha(120),
                                percent: 0.0,
                                width: 95,
                                lineHeight: 40,
                                barRadius: const Radius.circular(20),
                                center: const Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final runtime = runtimeItems[index];
                  final hasUpdate = catalogState.runtimeUpdates.contains(
                    runtime.parentName,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    child: Card(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: runtime.icon,
                        ),
                        title: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text("${runtime.name} - ${runtime.version ?? ''}"),
                              ),
                              if (hasUpdate)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withAlpha(40),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Update',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Text(
                                "Size: ${runtime.archiveSize} MB",
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            Text(runtime.details)
                          ],
                        ),
                        trailing: SizedBox(
                          height: 50,
                          width: 100,
                          child: BlocBuilder<DownloadManagerBloc, DownloadManagerState>(
                            builder: (context, downloadState) {
                              final percent = downloadState.downloadProgress[index] ?? 0;
                              final File archiveFile = File("$runtimesDir/${runtimeItems[index].archiveName}");
                              final Directory parentDir = Directory("$runtimesDir/${runtimeItems[index].parentName}");
                              
                              
                              final isExtracting = downloadState.isExtracting(index);
                              final extractionPercent = downloadState.extractionProgress[index] ?? 0;
                              final runtimePfdConfig = _runtimePfdConfig(
                                runtime.parentName,
                                isExtension: false,
                              );
                              final displayExtractionPercent = runtimePfdConfig != null
                                  ? _mergeProgress(runtimePfdConfig.weight, extractionPercent)
                                  : extractionPercent;
                              
                              
                              if (isExtracting) {
                                if (displayExtractionPercent > 0.0 && displayExtractionPercent < 100.0) {
                                  return LinearPercentIndicator(
                                    progressColor: Colors.greenAccent.withAlpha(180),
                                    percent: (displayExtractionPercent / 100).clamp(0.0, 1.0),
                                    width: 95,
                                    lineHeight: 40,
                                    barRadius: Radius.circular(20),
                                    center: Text("${(displayExtractionPercent).toStringAsFixed(0)}%",
                                      style: const TextStyle(fontSize: 12)),
                                  );
                                } else {
                                  
                                  return LinearPercentIndicator(
                                    progressColor: Colors.greenAccent.withAlpha(180),
                                    percent: 0.0,
                                    width: 95,
                                    lineHeight: 40,
                                    barRadius: Radius.circular(20),
                                    center: const SizedBox(
                                      height: 25,
                                      width: 25,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                              }
                              
                              final zipExistsButNotExtracted = archiveFile.existsSync() && !parentDir.existsSync();
                              if (zipExistsButNotExtracted && !isExtracting) {
                                
                                return LinearPercentIndicator(
                                  progressColor: Colors.orangeAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: const SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              }
                              
                              final isFullyInstalled = parentDir.existsSync() || downloadState.isFullyCompleted(index);
                              final isUpdateAvailable = hasUpdate;

                              if (isFullyInstalled && isUpdateAvailable) {
                                return IconButton(
                                  onPressed: () async {
                                    if (!context.mounted) return;
                                    _startDownload(
                                      context,
                                      index,
                                      runtimeItems[index].url,
                                      runtimeItems[index].archiveName,
                                      downloadsDir,
                                      false,
                                      packageParentName: runtimeItems[index].parentName,
                                    );
                                  },
                                  icon: Icon(Icons.system_update, color: Colors.orange),
                                  tooltip: 'Update to latest version',
                                );
                              }

                              if (isFullyInstalled) {
                                return IconButton(
                                  onPressed: (){
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: appThemeState.appTheme.isDark ? appThemeState.appTheme.scaffoldBg : null,
                                        title: Text(
                                          'Delete ${runtime.name} - ${runtime.version}?',
                                          style: TextStyle(
                                            color: appThemeState.appTheme.selectScreenCardTextColor,
                                            fontSize: 20
                                          ),
                                        ),
                                        content: Text(
                                          "Are you sure you want to delete this runtime?",
                                          style: TextStyle(
                                            color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                            fontSize: 16
                                          )
                                        ),
                                        actions: [
                                          ElevatedButton(
                                            onPressed: ()=> Navigator.of(context).pop(),
                                            child: Text('Cancel')
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              if(archiveFile.existsSync()){
                                                archiveFile.deleteSync(recursive: true);
                                              }
                                              if(parentDir.existsSync()){
                                                parentDir.deleteSync(recursive: true);
                                              }
                                              if (runtime.parentName.toLowerCase() == 'rust') {
                                                _deletePathIfExistsSync('$binDir/rustc');
                                                _deletePathIfExistsSync('$binDir/cargo');
                                                _deletePathIfExistsSync('$libDir/libicudata.so.78');
                                                _deletePathIfExistsSync('$libDir/libicuuc.so.78');
                                              }
                                              if (runtime.parentName.toLowerCase() == 'go') {
                                                _deletePathIfExistsSync('$binDir/go');
                                                _deletePathIfExistsSync('$binDir/gofmt');
                                              }
                                              if (runtime.parentName.toLowerCase() == 'ruby') {
                                                _deletePathIfExistsSync('$libDir/libruby.so.3.4');
                                              }
                                              if (runtimePfdConfig != null) {
                                                NativeChannel.uninstallModule(
                                                  runtimePfdConfig.moduleName,
                                                );
                                              }
                                              context.read<DownloadManagerBloc>().removeDownload(index);
                                              setState(() {
                                                loadingIndexes.remove(index);
                                              });
                                              Navigator.of(context).pop();
                                            },
                                            style: ButtonStyle(
                                              backgroundColor: WidgetStateProperty.all<Color>(Colors.red)
                                            ),
                                            child: Text('Delete', style: TextStyle(color: Colors.white))
                                          )
                                        ],
                                      )
                                    );
                                  },
                                  icon: Icon(Icons.delete, color: Colors.red)
                                );
                              }
                              
                              
                              if (percent > 0.0 && percent < 100.0) {
                                return LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: (percent / 100).clamp(0.0, 1.0),
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: Text("${(percent).toStringAsFixed(0)}%"),
                                );
                              }
                              
                              if (loadingIndexes.contains(index)) {
                                return LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: const SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              
                              return GestureDetector(
                                onTap: () async {
                                  
                                  if (!context.mounted) return;
                                  _startDownload(
                                    context,
                                    index,
                                    runtimeItems[index].url,
                                    runtimeItems[index].archiveName,
                                    downloadsDir,
                                    false, 
                                    packageParentName: runtimeItems[index].parentName,
                                  );
                                },
                                child: LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: Icon(Icons.download),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: extensionItems.isEmpty
                ? _buildCatalogStateView(
                    title: 'No extensions installed',
                    actionLabel: 'Refresh',
                    onRetry: () => context.read<PackageCatalogCubit>().refreshInstalledStatusOnly(),
                  )
                : ListView.builder(
                itemCount: extensionItems.length,
                itemBuilder: (_, index) {
                  final extensionIndex = index + runtimeItems.length;
                  final exten = extensionItems[index];
                  final hasUpdate = catalogState.extensionUpdates.contains(
                    exten.parentName,
                  );
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    child: Card(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: exten.icon,
                        ),
                        title: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(child: Text(exten.name)),
                              if (hasUpdate)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withAlpha(40),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'Update',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Text(
                                "Size: ${exten.archiveSize} MB",
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ),
                            Text(exten.details),
                            IconButton(
                              onPressed: () async{
                                await launchUrl(Uri.parse(exten.githubUrl));
                              },
                              icon: FaIcon(
                                FontAwesomeIcons.github,
                                color: appThemeState.appTheme.selectScreenCardTextColor,
                              )
                            )
                          ],
                        ),
                        trailing: SizedBox(
                          height: 50,
                          width: 100,
                          child: BlocBuilder<DownloadManagerBloc, DownloadManagerState>(
                            builder: (context, downloadState) {
                              final percent = downloadState.downloadProgress[extensionIndex] ?? 0;
                              final File archiveFile = File("$extensionDir/${extensionItems[index].archiveName}");
                              final Directory parentDir = Directory("$extensionDir/${extensionItems[index].parentName}");
                              final extensionPfdConfig = _runtimePfdConfig(
                                exten.parentName,
                                isExtension: true,
                              );
                              
                              final isExtracting = downloadState.isExtracting(extensionIndex);
                              final extractionPercent = downloadState.extractionProgress[extensionIndex] ?? 0;
                              final displayExtractionPercent = extensionPfdConfig != null
                                  ? _mergeProgress(extensionPfdConfig.weight, extractionPercent)
                                  : extractionPercent;
                              
                              if (isExtracting) {
                                if (displayExtractionPercent > 0.0 && displayExtractionPercent < 100.0) {
                                  return LinearPercentIndicator(
                                    progressColor: Colors.greenAccent.withAlpha(180),
                                    percent: (displayExtractionPercent / 100).clamp(0.0, 1.0),
                                    width: 95,
                                    lineHeight: 40,
                                    barRadius: Radius.circular(20),
                                    center: Text("${(displayExtractionPercent).toStringAsFixed(0)}%",
                                      style: const TextStyle(fontSize: 12)),
                                  );
                                } else {
                                  
                                  return LinearPercentIndicator(
                                    progressColor: Colors.greenAccent.withAlpha(180),
                                    percent: 0.0,
                                    width: 95,
                                    lineHeight: 40,
                                    barRadius: Radius.circular(20),
                                    center: const SizedBox(
                                      height: 25,
                                      width: 25,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                              }
                              
                              final zipExistsButNotExtracted = archiveFile.existsSync() && !parentDir.existsSync();
                              if (zipExistsButNotExtracted && !isExtracting) {
                                
                                return LinearPercentIndicator(
                                  progressColor: Colors.orangeAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: const SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              }
                              
                              final isFullyInstalled = parentDir.existsSync() || downloadState.isFullyCompleted(extensionIndex);
                              final isUpdateAvailable = hasUpdate;

                              if (isFullyInstalled && isUpdateAvailable) {
                                return IconButton(
                                  onPressed: () async {
                                    if (!context.mounted) return;
                                    _startDownload(
                                      context,
                                      extensionIndex,
                                      extensionItems[index].url,
                                      extensionItems[index].archiveName,
                                      downloadsDir,
                                      true,
                                      packageParentName: extensionItems[index].parentName,
                                      extensionMetadata: extensionItems[index],
                                    );
                                  },
                                  icon: Icon(Icons.system_update, color: Colors.orange),
                                  tooltip: 'Update to latest version',
                                );
                              }

                              if (isFullyInstalled) {
                                return IconButton(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        backgroundColor: appThemeState.appTheme.isDark ? appThemeState.appTheme.scaffoldBg : null,
                                        title: Text(
                                          exten.name,
                                          style: TextStyle(
                                            color: appThemeState.appTheme.selectScreenCardTextColor,
                                            fontSize: 20
                                          ),
                                        ),
                                        content: Text(
                                          "Are you sure you want to delete this extension?",
                                          style: TextStyle(
                                            color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                            fontSize: 16
                                          )
                                        ),
                                        actions: [
                                          ElevatedButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: Text('Cancel')
                                          ),
                                          ElevatedButton(
                                            onPressed: () {
                                              if (archiveFile.existsSync()) {
                                                archiveFile.deleteSync(recursive: true);
                                              }
                                              if (parentDir.existsSync()) {
                                                parentDir.deleteSync(recursive: true);
                                              }
                                              if (exten.parentName.toLowerCase() == 'ty') {
                                                _deletePathIfExistsSync('$binDir/ty');
                                              }
                                              if (extensionPfdConfig != null) {
                                                NativeChannel.uninstallModule(
                                                  extensionPfdConfig.moduleName,
                                                );
                                              }
                                              context.read<DownloadManagerBloc>().removeDownload(extensionIndex);
                                              setState(() {
                                                loadingIndexes.remove(extensionIndex);
                                              });
                                              Navigator.of(context).pop(true);
                                            },
                                            style: ButtonStyle(
                                              backgroundColor: WidgetStateProperty.all<Color>(Colors.red)
                                            ),
                                            child: Text('Delete', style: TextStyle(color: Colors.white))
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                  icon: Icon(Icons.delete, color: Colors.red),
                                );
                              }
                              
                              
                              if (percent > 0.0 && percent < 100.0) {
                                return LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: (percent / 100).clamp(0.0, 1.0),
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: Text("${(percent).toStringAsFixed(0)}%"),
                                );
                              }
                              
                              if (loadingIndexes.contains(extensionIndex)) {
                                return LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: const SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              
                              return GestureDetector(
                                onTap: () async {
                                  if (!context.mounted) return;
                                  await _startDownload(
                                    context,
                                    extensionIndex,
                                    extensionItems[index].url,
                                    extensionItems[index].archiveName,
                                    downloadsDir,
                                    true,
                                    packageParentName: extensionItems[index].parentName,
                                    extensionMetadata: extensionItems[index],
                                  );
                                },
                                child: LinearPercentIndicator(
                                  progressColor: Colors.blueAccent.withAlpha(180),
                                  percent: 0.0,
                                  width: 95,
                                  lineHeight: 40,
                                  barRadius: Radius.circular(20),
                                  center: Icon(Icons.download),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogStateView({
    required String title,
    required String actionLabel,
    required VoidCallback onRetry,
  }) {
    final catalogState = context.watch<PackageCatalogCubit>().state;
    final textColor = appThemeState.appTheme.selectScreenCardTextColor;

    if (catalogState.isSyncing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: appThemeState.appTheme.isDark
                ? const Color(0xff5090c8)
                : const Color(0xff2c6fa8),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading package data...',
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      );
    }

    if (catalogState.remoteFetchFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 36,
                color: textColor.withAlpha(170),
              ),
              const SizedBox(height: 10),
              Text(
                'Failed to fetch latest package data.',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(color: textColor.withAlpha(170)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Text(
        title,
        style: TextStyle(color: textColor.withAlpha(190)),
      ),
    );
  }
}

class _ComingSoonRuntimeItem {
  final String name;
  final String details;
  final dynamic icon;

  _ComingSoonRuntimeItem({
    required this.name,
    required this.details,
    required this.icon,
  });
}