import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:roxum/utils/functions.dart';

part 'repo_event.dart';
part 'repo_state.dart';

class GithubUser extends Equatable {
  final String login;
  final String avatarUrl;
  final String name;
  final String? bio;

  const GithubUser({
    required this.login,
    required this.avatarUrl,
    required this.name,
    this.bio,
  });

  factory GithubUser.fromJson(Map<String, dynamic> json) {
    return GithubUser(
      login: json['login'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      name: json['name'] ?? json['login'] ?? '',
      bio: json['bio'],
    );
  }

  @override
  List<Object?> get props => [login, avatarUrl, name, bio];
}

class GithubAuthState extends Equatable {
  final bool isSignedIn;
  final GithubUser? user;

  const GithubAuthState({required this.isSignedIn, this.user});

  const GithubAuthState.signedOut() : this(isSignedIn: false, user: null);
  const GithubAuthState.signedIn(GithubUser user)
    : this(isSignedIn: true, user: user);

  @override
  List<Object?> get props => [isSignedIn, user];
}

class RepoStatusBloc extends Bloc<RepoStatusEvent, RepoStatusState> {
  RepoStatusBloc() : super(const RepoStatusInitial()) {
    on<LoadRepoStatus>(_onLoad);
    on<RefreshGitFileStatus>(_onRefreshGitFileStatus);
    on<LoadCommitGraph>(_onLoadCommitGraph);
    on<LoadGitExtendedStatus>(_onLoadExtendedStatus);
    on<RefreshRemoteStatus>(_onRefreshRemoteStatus);
  }

  Future<void> _onRefreshGitFileStatus(
    RefreshGitFileStatus event,
    Emitter<RepoStatusState> emit,
  ) async {
    try {
      final res = await getRepoStatus(event.workspace);
      final stdout = (res.stdout ?? '').toString();
      final lines = stdout.trimRight().isEmpty
          ? <String>[]
          : stdout.trimRight().split('\n');
      final staged = lines
          .where((line) => line.length >= 2 && line[0] != ' ' && line[0] != '?')
          .toList();
      final unstaged = lines
          .where((line) => line.length >= 2 && line[1] != ' ')
          .toList();

      if (state is RepoStatusLoaded) {
        emit(
          (state as RepoStatusLoaded).copyWith(
            staged: staged,
            unstaged: unstaged,
            rawOutput: stdout,
          ),
        );
      }
    } catch (e) {
      if (state is RepoStatusLoaded) {
        emit(RepoStatusError(message: e.toString()));
      }
    }
  }

  Future<void> _onLoad(
    LoadRepoStatus event,
    Emitter<RepoStatusState> emit,
  ) async {
    List<CommitNode>? existingCommits;
    if (state is RepoStatusLoaded) {
      existingCommits = (state as RepoStatusLoaded).commits;
    } else {
      emit(const RepoStatusLoading());
    }
    try {
      final res = await getRepoStatus(event.workspace);
      final stdout = (res.stdout ?? '').toString();
      final lines = stdout.trimRight().isEmpty
          ? <String>[]
          : stdout.trimRight().split('\n');

      final staged = lines.where((val) {
        if (val.length < 2) return false;
        final x = val[0];
        return x != ' ' && x != '?';
      }).toList();

      final unstaged = lines.where((val) {
        if (val.length < 2) return false;
        final y = val[1];
        return y != ' ';
      }).toList();

      final currentBranch = await gitCurrentBranch(event.workspace);
      final branches = await gitListBranches(event.workspace);
      final remoteBranches = await gitListBranches(
        event.workspace,
        remote: true,
      );
      final stashes = await gitListStashes(event.workspace);
      final tags = await gitListTags(event.workspace);
      final remotes = await gitListRemotes(event.workspace);
      final hasRemoteVal = remotes.isNotEmpty;
      final hasUpstreamVal = await hasUpstream(event.workspace);
      final unpushed = hasUpstreamVal
          ? await getUnpushedCommitCount(event.workspace)
          : 0;
      final unpulled = hasUpstreamVal
          ? await getUnpulledCommitCount(event.workspace)
          : 0;

      List<CommitNode>? commits;
      try {
        commits = await getGraph(event.workspace);
      } catch (_) {
        commits = existingCommits ?? [];
      }

      emit(
        RepoStatusLoaded(
          staged: staged,
          unstaged: unstaged,
          rawOutput: stdout,
          commits: commits,
          currentBranch: currentBranch,
          branches: branches,
          remoteBranches: remoteBranches,
          stashes: stashes,
          tags: tags,
          remotes: remotes,
          hasRemote: hasRemoteVal,
          hasUpstream: hasUpstreamVal,
          unpushedCount: unpushed,
          unpulledCount: unpulled,
        ),
      );
    } catch (e) {
      emit(RepoStatusError(message: e.toString()));
    }
  }

  Future<void> _onLoadCommitGraph(
    LoadCommitGraph event,
    Emitter<RepoStatusState> emit,
  ) async {
    try {
      final commits = await getGraph(event.workspace);
      if (state is RepoStatusLoaded) {
        final currentState = state as RepoStatusLoaded;
        emit(currentState.copyWith(commits: commits));
      } else {
        emit(
          RepoStatusLoaded(
            staged: [],
            unstaged: [],
            rawOutput: '',
            commits: commits,
          ),
        );
      }
    } catch (e) {
      if (state is RepoStatusLoaded) {
        final currentState = state as RepoStatusLoaded;
        emit(currentState.copyWith(commits: []));
      } else {
        emit(RepoStatusError(message: e.toString()));
      }
    }
  }

  Future<void> _onLoadExtendedStatus(
    LoadGitExtendedStatus event,
    Emitter<RepoStatusState> emit,
  ) async {
    try {
      final currentBranch = await gitCurrentBranch(event.workspace);
      final branches = await gitListBranches(event.workspace);
      final remoteBranches = await gitListBranches(
        event.workspace,
        remote: true,
      );
      final stashes = await gitListStashes(event.workspace);
      final tags = await gitListTags(event.workspace);
      final remotes = await gitListRemotes(event.workspace);
      final hasRemoteVal = remotes.isNotEmpty;
      final hasUpstreamVal = await hasUpstream(event.workspace);
      final unpushed = hasUpstreamVal
          ? await getUnpushedCommitCount(event.workspace)
          : 0;
      final unpulled = hasUpstreamVal
          ? await getUnpulledCommitCount(event.workspace)
          : 0;

      if (state is RepoStatusLoaded) {
        final currentState = state as RepoStatusLoaded;
        emit(
          currentState.copyWith(
            currentBranch: currentBranch,
            branches: branches,
            remoteBranches: remoteBranches,
            stashes: stashes,
            tags: tags,
            remotes: remotes,
            hasRemote: hasRemoteVal,
            hasUpstream: hasUpstreamVal,
            unpushedCount: unpushed,
            unpulledCount: unpulled,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _onRefreshRemoteStatus(
    RefreshRemoteStatus event,
    Emitter<RepoStatusState> emit,
  ) async {
    try {
      final hasUpstreamVal = await hasUpstream(event.workspace);
      final unpushed = hasUpstreamVal
          ? await getUnpushedCommitCount(event.workspace)
          : 0;
      final unpulled = hasUpstreamVal
          ? await getUnpulledCommitCount(event.workspace)
          : 0;
      final remotes = await gitListRemotes(event.workspace);
      final hasRemoteVal = remotes.isNotEmpty;

      if (state is RepoStatusLoaded) {
        final currentState = state as RepoStatusLoaded;
        emit(
          currentState.copyWith(
            hasRemote: hasRemoteVal,
            hasUpstream: hasUpstreamVal,
            unpushedCount: unpushed,
            unpulledCount: unpulled,
            remotes: remotes,
          ),
        );
      }
    } catch (_) {}
  }
}

class GithubAuthCubit extends Cubit<GithubAuthState> {
  static const String _userDataKey = 'github_user_data';

  GithubAuthCubit() : super(const GithubAuthState.signedOut()) {
    refresh();
  }

  Future<void> refresh() async {
    final token = await const FlutterSecureStorage().read(
      key: 'github_access_token',
    );

    if (token != null && token.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final cachedUserData = prefs.getString(_userDataKey);

      if (cachedUserData != null) {
        try {
          final userJson = jsonDecode(cachedUserData);
          final user = GithubUser.fromJson(userJson);
          emit(GithubAuthState.signedIn(user));
        } catch (e) {
          await _loadAndCacheUserInfo(token);
        }
      } else {
        await _loadAndCacheUserInfo(token);
      }
    } else {
      emit(const GithubAuthState.signedOut());
    }
  }

  Future<void> _loadAndCacheUserInfo(String token) async {
    try {
      final user = await _loadUserInfo(token);
      emit(GithubAuthState.signedIn(user));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _userDataKey,
        jsonEncode({
          'login': user.login,
          'avatar_url': user.avatarUrl,
          'name': user.name,
          'bio': user.bio,
        }),
      );
    } catch (e) {
      emit(const GithubAuthState(isSignedIn: true, user: null));
    }
  }

  Future<GithubUser> _loadUserInfo(String token) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return GithubUser.fromJson(json);
    } else {
      throw Exception('Failed to load user info');
    }
  }

  Future<void> logout() async {
    await const FlutterSecureStorage().delete(key: 'github_access_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDataKey);
    emit(const GithubAuthState.signedOut());
  }
}
