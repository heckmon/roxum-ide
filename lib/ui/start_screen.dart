import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:roxum/bloc/ui_bloc/ui_bloc.dart';
import 'package:roxum/utils/constants.dart';
import '../ui/home.dart';
import '../utils/functions.dart';

const List<String> javaTools = [
  'jar',
  'jarsigner',
  'java',
  'javac',
  'javadoc',
  'javap',
  'jcmd',
  'jconsole',
  'jdb',
  'jdeprscan',
  'jdeps',
  'jfr',
  'jhsdb',
  'jinfo',
  'jlink',
  'jmap',
  'jmod',
  'jpackage',
  'jps',
  'jrunscript',
  'jstack',
  'jstat',
  'jstatd',
  'jwebserver',
  'keytool',
  'rmiregistry',
  'serialver'
];

const List<String> goToolBinaries = [
  'asm',
  'cgo',
  'compile',
  'cover',
  'fix',
  'link',
  'preprofile',
  'vet',
];

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  double progress = 0.0;
  bool isDone = false;
  
  @override
  void initState() {
    super.initState();
    _safeInitialize();
  }

  Future<void> _safeInitialize() async {
    try {
      await _initializeApp(context);
    } catch (e, stack) {
      debugPrint("Startup error: $e");
      debugPrint("$stack");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            "Startup failed: $e",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> _initializeApp(BuildContext context) async {
    await NativeChannel.getExternalMediaDir();
    final downdir = Directory(downloadsDir);
    final gitCore = "$binDir/git-core";
    final binDirectory = Directory(binDir);
    final libDirectory = Directory(libDir);
    final gitCoreDir = Directory(gitCore);
    final homeDirectory = Directory(homeDir);
    
    if(!homeDirectory.existsSync()) {
      await homeDirectory.create(recursive: true);
    }

    if (!binDirectory.existsSync()) {
      await binDirectory.create(recursive: true);
    }

    if (!libDirectory.existsSync()) {
      await libDirectory.create(recursive: true);
    }

    if(!gitCoreDir.existsSync()){
      await gitCoreDir.create(recursive: true);
    }

    if (await downdir.exists()) {
      for (final file in downdir.listSync()) {
        if (file is File && file.path.endsWith('.zip')) {
          await file.delete();
        }
      }
    }
    
    await setupFilesDir();
    await setupProjectDir();
    await setupTempDir();
    await ensureCopilotEnabledPrefInitialized();
    await ensureCopilotSignedPrefInitialized();
    if(context.mounted) await context.read<PackageCatalogCubit>().syncOnStartup();

    final String sharedPath = await NativeChannel.getLibraryPath();

    Map<String, dynamic> loader(String name, {String? loader, Map<String, String>? env}) => {
      'src': '$sharedPath/${loader ?? "libloader.so"}',
      'dst': '$binDir/$name',
      'env': ?env,
    };

    final loaderTools = [
      'clang', 'clang++', 'clangloader', 'node', 'python', 'python3',
      'npm', 'npx', 'pip', 'pip3', 'tsc', 'kotlinc', 'git', 'ruby',
      'lua'
    ];

    final symlinks = [
      {'src': '$sharedPath/libreadline.so', 'dst': '$libDir/libreadline.so.8'},
      {'src': '$sharedPath/libz.so', 'dst': '$libDir/libz.so.1'},
      {'src': '$sharedPath/libncursesw.so', 'dst': '$libDir/libncursesw.so.6'},
      {'src': '$sharedPath/libcrypto.so', 'dst': '$libDir/libcrypto.so.3'},
      {'src': '$sharedPath/libssl.so', 'dst': '$libDir/libssl.so.3'},
      {'src': '$sharedPath/libzstd.so', 'dst': '$libDir/libzstd.so.1'},
      {'src': '$sharedPath/libxml2.so', 'dst': '$libDir/libxml2.so.16'},
      {'src': '$sharedPath/libicuuc.so', 'dst': '$libDir/libicuuc.so.78'},
      {'src': '$sharedPath/libicudata.so', 'dst': '$libDir/libicudata.so.78'},
      {'src': '$sharedPath/libbash.so', 'dst': '$binDir/bash'},
      {'src': '$sharedPath/libbash.so', 'dst': '$binDir/sh'},
      {'src': '$sharedPath/librstloader.so', 'dst': '$binDir/rustloader'},
      {'src': '$sharedPath/libgit-remote-https.so', 'dst': '$gitCore/git-remote-https'},
      {'src': '$sharedPath/libgit-remote-https.so', 'dst': '$gitCore/git-remote-http'},
      {'src': '$sharedPath/libccls.so', 'dst': '$binDir/ccls'},
      {'src': '$sharedPath/libless.so', 'dst': '$binDir/less', 'env': {'LD_LIBRARY_PATH' : libDir}},
      {'src': '$sharedPath/libless.so', 'dst': '$binDir/pager', 'env': {'LD_LIBRARY_PATH' : libDir}},
      ...loaderTools.map((tool) => loader(tool, env: {'ROXUM_SHARED_PATH': sharedPath})),
      ...javaTools.map((tool) => loader(tool, env: {'ROXUM_SHARED_PATH': sharedPath})),
      {'src': '$binDir/clang', 'dst': '$binDir/aarch64-linux-android-clang'},
      {'src': '$binDir/clang++', 'dst': '$binDir/aarch64-linux-android-clang++'},
    ];

    final totalLinks = symlinks.length;
    int completedLinks = 0;

    for (final link in symlinks) {
      final dst = link['dst'] as String;
      final src = link['src'] as String;
      final linkFile = Link(dst);
      
      bool needsCreation = true;
      if (linkFile.existsSync()) {
        try {
          final target = linkFile.targetSync();
          if (target == src) {
            needsCreation = false;
          }
        } catch (_) {
        }
      }
      
      if (needsCreation) {
        await Process.run(
          "ln",
          ["-sf", src, dst],
          environment: link['env'] as Map<String, String>?,
        );
      }
      completedLinks++;
      setState(() {
        progress = completedLinks / totalLinks;
      });
    }

    await _refreshRustGoRuntimeSymlinks(sharedPath);
    await _refreshDartRuntimeSymlinks(sharedPath);
    await _refreshZigRuntimeSymlinks(sharedPath);

    if (!File('$certDir/cacert.pem').existsSync()) {
      Directory(certDir).createSync(recursive: true);
      final certBytes = await rootBundle.load('assets/certificates/cacert.pem');
      File('$certDir/cacert.pem').writeAsBytesSync(certBytes.buffer.asUint8List());
    }

    await Process.run(
      "$binDir/git",
      ["config", "--global", "--add", "safe.directory", "*"],
      environment: gitEnvs(sharedPath),
    );

    setState(() {
      isDone = true;
    });

    Future.delayed(Duration(milliseconds: 10), () {
      if (context.mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const SelectType(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ));
      }
    });
  }

  Future<void> _refreshZigRuntimeSymlinks(String sharedPath) async {
    final zigBinDir = Directory('$runtimesDir/dart/bin');
    if (!await zigBinDir.exists()) {
      return;
    }
    await _ensureSymlink(
      linkPath: '$binDir/zig',
      targetPath: '$sharedPath/libzig.so',
    );
  }

  Future<void> _refreshDartRuntimeSymlinks(String sharedPath) async {
    final dartBinDir = Directory('$runtimesDir/dart/bin');
    if (!await dartBinDir.exists()) {
      return;
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
  }

  Future<void> _refreshRustGoRuntimeSymlinks(String sharedPath) async {
    final rustRuntimeDir = Directory('$runtimesDir/rust');
    if (await rustRuntimeDir.exists()) {
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
    }

    final goRuntimeDir = Directory('$runtimesDir/go');
    if (await goRuntimeDir.exists()) {
      await _ensureSymlink(
        linkPath: '$binDir/go',
        targetPath: '$sharedPath/libgo.so',
      );

      await _ensureSymlink(
        linkPath: '$binDir/gofmt',
        targetPath: '$sharedPath/libgofmt.so',
      );

      final goToolDir = Directory('$runtimesDir/go/pkg/tool/android_arm64');
      if (await goToolDir.exists()) {
        for (final tool in goToolBinaries) {
          await _ensureSymlink(
            linkPath: '${goToolDir.path}/$tool',
            targetPath: '$sharedPath/lib$tool.so',
          );
        }
      }
    }
  }

  Future<void> _ensureSymlink({
    required String linkPath,
    required String targetPath,
  }) async {
    try {
      final existingType = await FileSystemEntity.type(
        linkPath,
        followLinks: false,
      );

      if (existingType == FileSystemEntityType.file) {
        await File(linkPath).delete();
      } else if (existingType == FileSystemEntityType.link) {
        await Link(linkPath).delete();
      } else if (existingType == FileSystemEntityType.directory) {
        await Directory(linkPath).delete(recursive: true);
      }

      await Link(linkPath).create(targetPath, recursive: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<AppThemeBloc>().state.appTheme;
    return Scaffold(
      body: Center(
        child: isDone
          ? const CircularProgressIndicator()
          : SizedBox(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Setting things up...",
                  style: TextStyle(
                    color: theme.selectScreenCardTextColor
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 300,
                    child: LinearPercentIndicator(
                      progressColor: Colors.blue,
                      percent: progress,
                      lineHeight: 10,
                      barRadius: const Radius.circular(15),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "${(progress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    color: theme.selectScreenCardTextColor
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}
