import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roxum/bloc/repo_bloc/repo_bloc.dart';
import 'package:roxum/ui/widgets.dart';
import 'package:roxum/utils/functions.dart';
import 'package:roxum/utils/themes.dart';

CommitNode _commit(String hash, List<String> parents) {
  return CommitNode(
    hash: hash,
    parents: parents,
    author: 'author',
    message: 'commit $hash',
  );
}

Set<int> _contiguous(int count) => {for (int i = 0; i < count; i++) i};

/// Creates a throwaway repository with a merge and an unmerged side commit.
Future<Directory> _createGraphRepository() async {
  final dir = await Directory.systemTemp.createTemp('roxum_graph_repo_');

  Future<void> git(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  await git(['init', '-q']);
  await git(['config', 'user.email', 'test@example.com']);
  await git(['config', 'user.name', 'Test']);
  await git(['commit', '--allow-empty', '-m', 'root']);
  await git(['branch', '-M', 'main']);
  await git(['checkout', '-q', '-b', 'side']);
  await git(['commit', '--allow-empty', '-m', 'side']);
  await git(['checkout', '-q', 'main']);
  await git(['commit', '--allow-empty', '-m', 'main']);
  await git(['merge', '--no-ff', 'side', '-m', 'merge']);
  await git(['checkout', '-q', '-b', 'upstream']);
  await git(['commit', '--allow-empty', '-m', 'upstream ahead']);
  await git(['checkout', '-q', 'main']);
  await git(['branch', '--set-upstream-to=upstream', 'main']);
  await git(['checkout', '-q', '-b', 'other']);
  await git(['commit', '--allow-empty', '-m', 'other only']);
  await git(['checkout', '-q', 'main']);
  return dir;
}

/// Checks the invariants the painter relies on:
///  - rows connect to each other (a row's top lanes are the previous bottom),
///  - every commit with a known parent has an edge for each parent,
///  - lanes are compact (no permanent empty columns),
///  - no lane is left open at the end of the graph.
void _expectValidLayout(List<CommitRowInfo> rows, List<CommitNode> commits) {
  expect(rows, hasLength(commits.length));
  final knownHashes = commits.map((c) => c.hash).toSet();
  Set<int> previousBottom = {};

  for (int i = 0; i < rows.length; i++) {
    final row = rows[i];

    final top = <int>{};
    final bottom = <int>{};
    int outgoingEdges = 0;

    for (final line in row.lines) {
      if (line.kind == GraphLineKind.passThrough) {
        top.add(line.fromLane);
        bottom.add(line.toLane);
      } else if (line.kind == GraphLineKind.incoming) {
        top.add(line.fromLane);
      } else {
        outgoingEdges++;
        bottom.add(line.toLane);
      }
    }
    if (row.hasIncoming) top.add(row.commitLane);

    expect(
      top,
      previousBottom,
      reason:
          'row $i (${row.commit.hash}) top lanes do not match the '
          'bottom lanes of the previous row',
    );
    expect(top, _contiguous(top.length), reason: 'row $i top lanes have holes');
    expect(
      bottom,
      _contiguous(bottom.length),
      reason: 'row $i bottom lanes have holes',
    );
    expect(
      row.hasIncoming,
      previousBottom.contains(row.commitLane),
      reason: 'row $i incoming edge flag is inconsistent',
    );

    final expectedParents = row.commit.parents
        .where(knownHashes.contains)
        .toSet();
    expect(
      outgoingEdges,
      expectedParents.length,
      reason: 'row $i (${row.commit.hash}) is missing parent edges',
    );

    // A pass-through lane must never merge with the commit's outgoing edge in
    // the commit's column: that is what used to look like a branch sprouting
    // from the node. When the commit has no outgoing edge (a root), another
    // lane may compact into its column below the node.
    final commitColumnEdges = row.lines
        .where(
          (line) =>
              line.kind == GraphLineKind.outgoing &&
              line.fromLane == row.commitLane,
        )
        .length;
    for (final line in row.lines) {
      if (line.kind == GraphLineKind.passThrough &&
          line.toLane == row.commitLane) {
        expect(
          commitColumnEdges,
          0,
          reason:
              'row $i (${row.commit.hash}) has a pass-through ending in '
              'the column of the commit edge',
        );
      }
    }

    int maxLane = row.commitLane;
    for (final line in row.lines) {
      if (line.fromLane > maxLane) maxLane = line.fromLane;
      if (line.toLane > maxLane) maxLane = line.toLane;
    }
    expect(row.laneCount, maxLane + 1);

    previousBottom = bottom;
  }

  expect(
    previousBottom,
    isEmpty,
    reason: 'lanes are still open after the last commit',
  );
}

void main() {
  group('assignGitGraphLanes', () {
    test('an empty history produces no rows', () {
      expect(assignGitGraphLanes(const []), isEmpty);
    });

    test('the layout is pure and its input stays immutable', () {
      final commits = [
        _commit('merge', ['a', 'b']),
        _commit('a', ['c']),
        _commit('b', ['c']),
        _commit('c', []),
      ];
      final parentsBefore = [
        for (final commit in commits) List<String>.of(commit.parents),
      ];
      final first = assignGitGraphLanes(commits);
      final second = assignGitGraphLanes(commits);

      expect(second, hasLength(first.length));
      for (var i = 0; i < commits.length; i++) {
        expect(commits[i].parents, parentsBefore[i]);
        expect(second[i].commitLane, first[i].commitLane);
        expect(second[i].colorIndex, first[i].colorIndex);
        expect(second[i].lines.length, first[i].lines.length);
      }
      expect(
        () => commits.first.parents.add('x'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => first.first.lines.clear(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseCommitGraph reads hashes, parents and flags', () {
      final commits = parseCommitGraph(
        'abc\x01def ghi\x01Alice\x01First\n'
        'def\x01\x01Bob\x01Second\n'
        'ghi\x01\x01Alice\x01Third\n',
        headHash: 'abc',
        upstreamHash: 'ghi',
      );

      expect(commits, hasLength(3));
      expect(commits[0].hash, 'abc');
      expect(commits[0].parents, ['def', 'ghi']);
      expect(commits[0].isMerge, isTrue);
      expect(commits[0].isHead, isTrue);
      expect(commits[0].isRemoteHead, isFalse);
      expect(commits[1].isMerge, isFalse);
      expect(commits[2].isRemoteHead, isTrue);
      expect(parseCommitGraph('malformed line'), isEmpty);
      expect(
        () => commits.clear(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('linear history stays in a single lane', () {
      final commits = [
        _commit('a', ['b']),
        _commit('b', ['c']),
        _commit('c', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      expect(rows.map((r) => r.commitLane), [0, 0, 0]);
      expect(rows.map((r) => r.laneCount), [1, 1, 1]);
    });

    test('merged branch converges back to the leftmost lane', () {
      final commits = [
        _commit('merge', ['a', 'b']),
        _commit('a', ['c']),
        _commit('b', ['c']),
        _commit('c', ['d']),
        _commit('d', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      // The branch occupies lane 1 while it is alive...
      expect(rows[2].commitLane, 1);
      // ...and the shared ancestor is back on lane 0 once it merges.
      expect(rows[3].commitLane, 0);
      expect(rows[4].commitLane, 0);
      expect(rows.last.laneCount, 1);
    });

    test('three parallel branches compact without dangling lanes', () {
      final commits = [
        _commit('merge', ['a', 'b', 'c']),
        _commit('a', ['d']),
        _commit('b', ['d']),
        _commit('c', ['d']),
        _commit('d', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      expect(rows[0].laneCount, 3);
      // Each child keeps its own column until the shared parent, then all of
      // them converge into the parent's node. They must not join an existing
      // lane in the middle of a row (that looked like a T).
      expect(rows[2].commitLane, 1);
      expect(rows[3].commitLane, 2);
      expect(rows[4].commitLane, 0);
      expect(rows.last.laneCount, 3);
    });

    test('criss-cross merges keep every edge and close every lane', () {
      final commits = [
        _commit('m', ['a', 'b']),
        _commit('a', ['c', 'd']),
        _commit('b', ['d', 'c']),
        _commit('c', ['e']),
        _commit('d', ['e']),
        _commit('e', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      expect(rows.last.commitLane, 0);
      // The criss-cross siblings keep their columns until "e" and converge
      // into its node from above.
      expect(rows.last.laneCount, 2);
    });

    test('the first-parent chain stays on lane 0', () {
      final commits = [
        _commit('merge', ['a', 'b']),
        _commit('a', ['c']),
        _commit('b', ['c']),
        _commit('c', ['d']),
        _commit('d', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      final rowByHash = {for (final row in rows) row.commit.hash: row};
      var current = commits.first;
      while (true) {
        expect(
          rowByHash[current.hash]!.commitLane,
          0,
          reason: '${current.hash} is on the mainline but left lane 0',
        );
        if (current.parents.isEmpty) break;
        current = commits.firstWhere((c) => c.hash == current.parents.first);
      }
    });

    test('a converging merge reuses a freed column for an extra parent', () {
      final commits = [
        _commit('m', ['a', 'b', 'x']),
        _commit('a', ['c']),
        _commit('b', ['c']),
        _commit('c', ['d', 'e']),
        _commit('d', []),
        _commit('e', []),
        _commit('x', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      final row = rows.firstWhere((row) => row.commit.hash == 'c');
      final parentEdges = row.lines
          .where((line) => line.kind == GraphLineKind.outgoing)
          .toList();
      expect(parentEdges, hasLength(2));
      expect(parentEdges.map((line) => line.toLane), containsAll([0, 1]));

      final passThrough = row.lines
          .where((line) => line.kind == GraphLineKind.passThrough)
          .toList();
      expect(passThrough, hasLength(1));
      expect(passThrough.single.toLane, 2);
      expect(row.laneCount, 3);
    });

    test('a second ref tip appears in its own lane and closes cleanly', () {
      final commits = [
        _commit('a', ['c']),
        _commit('b', ['c']),
        _commit('c', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      expect(rows[0].commitLane, 0);
      expect(rows[1].commitLane, 1);
      expect(rows[2].commitLane, 0);
    });

    test('a first-parent edge stays in its lane and meets the parent node', () {
      final commits = [
        _commit('m0', ['c', 'x', 'd']),
        _commit('c', ['d']),
        _commit('x', []),
        _commit('d', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      final row = rows[1];
      expect(row.commit.hash, 'c');
      final parentEdge = row.lines.singleWhere(
        (line) => line.kind != GraphLineKind.passThrough,
      );
      expect(parentEdge.fromLane, row.commitLane);
      // The edge must not jump to the parent's existing lane in the middle of
      // the row. It stays vertical and converges only at the parent commit.
      expect(parentEdge.toLane, row.commitLane);
      expect(parentEdge.colorIndex, row.colorIndex);

      final parentRow = rows[3];
      expect(parentRow.commit.hash, 'd');
      // The first-parent child (c) keeps its column, so the shared parent d
      // lands on the leftmost lane.
      expect(parentRow.commitLane, 0);
      final incoming = parentRow.lines
          .where((line) => line.kind == GraphLineKind.incoming)
          .toList();
      expect(incoming, hasLength(1));
      expect(incoming.single.fromLane, 1);
      expect(incoming.single.toLane, parentRow.commitLane);
      // The converging edge keeps the colour of the other child (m0's third
      // parent lane), not the colour of the leftmost lane.
      expect(incoming.single.colorIndex, 2);
    });

    test('parents missing from a shallow log are ignored safely', () {
      final commits = [
        _commit('a', ['missing']),
        _commit('b', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      expect(rows[0].lines, isEmpty);
      expect(rows[1].lines, isEmpty);
      expect(rows[0].laneCount, 1);
      expect(rows[1].laneCount, 1);
    });

    test('a duplicated parent opens only one lane', () {
      final commits = [
        _commit('a', ['b', 'b']),
        _commit('b', []),
      ];
      final rows = assignGitGraphLanes(commits);
      _expectValidLayout(rows, commits);

      final parentEdges = rows[0].lines.where(
        (line) => line.kind == GraphLineKind.outgoing,
      );
      expect(parentEdges, hasLength(1));
      expect(rows[0].laneCount, 1);
      expect(rows[1].commitLane, 0);
    });
  });

  test('readCommitGraph reads HEAD and its upstream', () async {
    Directory? dir;
    try {
      dir = await _createGraphRepository();
      final commits = await readCommitGraph(
        workspacePath: dir.path,
        gitExecutable: 'git',
      );

      final messages = commits.map((commit) => commit.message).toList();
      expect(
        messages,
        containsAll(['root', 'side', 'main', 'merge', 'upstream ahead']),
      );
      expect(messages, isNot(contains('other only')));
      expect(commits.any((commit) => commit.isHead), isTrue);
      expect(
        commits.any(
          (commit) => commit.isRemoteHead && commit.message == 'upstream ahead',
        ),
        isTrue,
      );
      _expectValidLayout(assignGitGraphLanes(commits), commits);
    } on ProcessException {
      markTestSkipped('git is not available');
    } finally {
      if (dir != null) await dir.delete(recursive: true);
    }
  });

  test('readCommitGraph returns empty for an unborn repository', () async {
    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('roxum_graph_unborn_');
      final init = await Process.run(
        'git',
        ['init', '-q'],
        workingDirectory: dir.path,
      );
      expect(init.exitCode, 0);

      final commits = await readCommitGraph(
        workspacePath: dir.path,
        gitExecutable: 'git',
      );
      expect(commits, isEmpty);
    } on ProcessException {
      markTestSkipped('git is not available');
    } finally {
      if (dir != null) await dir.delete(recursive: true);
    }
  });

  test('readCommitGraph throws for a non-repository directory', () async {
    final dir = await Directory.systemTemp.createTemp('roxum_graph_plain_');
    try {
      await expectLater(
        readCommitGraph(workspacePath: dir.path, gitExecutable: 'git'),
        throwsA(isA<GitGraphException>()),
      );
    } on ProcessException {
      markTestSkipped('git is not available');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('readCommitGraph throws when git log fails for a valid HEAD', () async {
    Directory? dir;
    try {
      dir = await _createGraphRepository();
      final head = await Process.run(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: dir.path,
      );
      final hash = (head.stdout as String).trim();
      final object = File(
        '${dir.path}/.git/objects/${hash.substring(0, 2)}/${hash.substring(2)}',
      );
      expect(await object.exists(), isTrue);
      await object.delete();

      await expectLater(
        readCommitGraph(workspacePath: dir.path, gitExecutable: 'git'),
        throwsA(isA<GitGraphException>()),
      );
    } on ProcessException {
      markTestSkipped('git is not available');
    } finally {
      if (dir != null) await dir.delete(recursive: true);
    }
  });

  test('graph errors preserve the old commits and clear on success', () {
    final state = RepoStatusLoaded(
      staged: const [],
      unstaged: const [],
      rawOutput: '',
      commits: const [],
      graphError: 'failed',
    );

    final preserved = state.copyWith(commits: const []);
    expect(preserved.graphError, 'failed');
    expect(preserved.commits, same(state.commits));

    final cleared = state.copyWith(clearGraphError: true);
    expect(cleared.graphError, isNull);
  });

  testWidgets('GitCommitGraph places text right after each row graph', (
    tester,
  ) async {
    final commits = [
      _commit('merge', ['a', 'b']),
      _commit('a', ['c']),
      _commit('b', ['c']),
      _commit('c', []),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitGraph(commits: commits, appTheme: DarkTheme()),
        ),
      ),
    );
    await tester.pump();

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GitGraphPainter>()
        .toList();

    expect(painters, hasLength(commits.length));
    for (final painter in painters) {
      expect(
        painter.graphWidth,
        painter.rowInfo.laneCount * painter.laneWidth + gitGraphTextGap,
        reason: 'each row must start its text right after its own lanes',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('graph width is capped at 16 lanes', (tester) async {
    final parents = [for (var i = 0; i < 20; i++) 'p$i'];
    final commits = [
      _commit('merge', parents),
      for (var i = 0; i < 20; i++) _commit('p$i', []),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitGraph(commits: commits, appTheme: DarkTheme()),
        ),
      ),
    );
    await tester.pump();

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GitGraphPainter>()
        .toList();
    final maxWidth = gitGraphMaxLanes * 12 + gitGraphTextGap;

    expect(painters, isNotEmpty);
    expect(painters.first.graphWidth, maxWidth);
    for (final painter in painters) {
      expect(painter.graphWidth, lessThanOrEqualTo(maxWidth));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty graph renders without painters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitCommitGraph(
            commits: const <CommitNode>[],
            appTheme: DarkTheme(),
          ),
        ),
      ),
    );
    await tester.pump();

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GitGraphPainter>();
    expect(painters, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a merge graph matches its golden', (tester) async {
    final key = GlobalKey();
    final commits = [
      _commit('merge', ['a', 'b']),
      _commit('a', ['c']),
      _commit('b', ['c']),
      _commit('c', ['d']),
      _commit('d', []),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xff181818),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 500,
                height: 180,
                child: GitCommitGraph(commits: commits, appTheme: DarkTheme()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/git_graph_merge.png'),
    );
  });

  testWidgets('an independent-root lane shift matches its golden', (
    tester,
  ) async {
    final key = GlobalKey();
    final commits = [
      _commit('merge', ['a', 'b']),
      _commit('a', []),
      _commit('b', []),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xff181818),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 500,
                height: 108,
                child: GitCommitGraph(commits: commits, appTheme: DarkTheme()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(key),
      matchesGoldenFile('goldens/git_graph_root_shift.png'),
    );
  });

  testWidgets('the graph error banner keeps the compact graph mounted', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final commits = [
      _commit('merge', ['a', 'b']),
      _commit('a', ['c']),
      _commit('b', ['c']),
    ];

    Widget build(String? error) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 600),
              child: CommitGraphView(
                commits: commits,
                graphError: error,
                appTheme: DarkTheme(),
                scrollController: controller,
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(null));
    final graphState = tester.state(find.byType(GitCommitGraph));
    final normalHeight = tester.getSize(find.byType(CommitGraphView)).height;

    await tester.pumpWidget(build('boom'));
    final errorHeight = tester.getSize(find.byType(CommitGraphView)).height;

    expect(normalHeight, lessThan(600));
    expect(errorHeight, greaterThan(normalHeight));
    expect(errorHeight, lessThan(600));
    expect(identical(tester.state(find.byType(GitCommitGraph)), graphState), isTrue);
    expect(tester.takeException(), isNull);
  });

  test('GitGraphPainter repaints when its style inputs change', () {
    final row = assignGitGraphLanes([
      _commit('a', ['b']),
      _commit('b', []),
    ]).first;

    GitGraphPainter painter({
      Color secondary = Colors.grey,
      double laneWidth = 12,
      double rowHeight = 36,
    }) {
      return GitGraphPainter(
        rowInfo: row,
        textColor: Colors.white,
        secondaryTextColor: secondary,
        backgroundColor: Colors.black,
        maxWidth: 400,
        graphWidth: 60,
        laneWidth: laneWidth,
        rowHeight: rowHeight,
      );
    }

    final base = painter();
    expect(base.shouldRepaint(painter()), isFalse);
    expect(base.shouldRepaint(painter(secondary: Colors.red)), isTrue);
    expect(base.shouldRepaint(painter(laneWidth: 14)), isTrue);
    expect(base.shouldRepaint(painter(rowHeight: 40)), isTrue);
  });
}
