import 'package:flutter_test/flutter_test.dart';
import 'package:roxum/bloc/repo_bloc/repo_bloc.dart';
import 'package:roxum/utils/functions.dart';

void main() {
  test('a failed graph refresh keeps the previous commits', () async {
    final commits = [
      CommitNode(
        hash: 'a',
        parents: const [],
        author: 'A',
        message: 'first',
      ),
      CommitNode(
        hash: 'b',
        parents: const [],
        author: 'A',
        message: 'second',
      ),
    ];
    var calls = 0;
    final bloc = RepoStatusBloc(
      loadGraph: (_) async {
        calls++;
        if (calls == 2) throw const GitGraphException('boom');
        return commits;
      },
    );
    addTearDown(bloc.close);

    final firstLoaded = bloc.stream.firstWhere(
      (state) => state is RepoStatusLoaded && state.commits?.isNotEmpty == true,
    );
    bloc.add(const LoadCommitGraph('/repo'));
    final loaded = await firstLoaded as RepoStatusLoaded;
    expect(loaded.commits, same(commits));
    expect(loaded.graphError, isNull);

    final failure = bloc.stream.firstWhere(
      (state) => state is RepoStatusLoaded && state.graphError != null,
    );
    bloc.add(const LoadCommitGraph('/repo'));
    final failed = await failure as RepoStatusLoaded;
    expect(failed.commits, same(commits));
    expect(failed.graphError, contains('boom'));

    final recovered = bloc.stream.firstWhere(
      (state) => state is RepoStatusLoaded && state.graphError == null,
    );
    bloc.add(const LoadCommitGraph('/repo'));
    final recoveredState = await recovered as RepoStatusLoaded;
    expect(recoveredState.commits, same(commits));
    expect(recoveredState.graphError, isNull);
    expect(calls, 3);
  });
}
