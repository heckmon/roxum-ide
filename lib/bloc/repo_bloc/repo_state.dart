part of 'repo_bloc.dart';

abstract class RepoStatusState extends Equatable {
  const RepoStatusState();
  @override
  List<Object?> get props => [];
}

class RepoStatusInitial extends RepoStatusState {
  const RepoStatusInitial();
}

class RepoStatusLoading extends RepoStatusState {
  const RepoStatusLoading();
}

class RepoStatusLoaded extends RepoStatusState {
  final List<String> staged;
  final List<String> unstaged;
  final String rawOutput;
  final List<CommitNode>? commits;

  /// Last graph loading error, if any. The previous [commits] are kept.
  final String? graphError;
  final String? currentBranch;
  final List<String> branches;
  final List<String> remoteBranches;
  final List<Map<String, String>> stashes;
  final List<String> tags;
  final List<String> remotes;
  final bool hasRemote;
  final bool hasUpstream;
  final int unpushedCount;
  final int unpulledCount;

  const RepoStatusLoaded({
    required this.staged,
    required this.unstaged,
    required this.rawOutput,
    this.commits,
    this.graphError,
    this.currentBranch,
    this.branches = const [],
    this.remoteBranches = const [],
    this.stashes = const [],
    this.tags = const [],
    this.remotes = const [],
    this.hasRemote = false,
    this.hasUpstream = false,
    this.unpushedCount = 0,
    this.unpulledCount = 0,
  });

  RepoStatusLoaded copyWith({
    List<String>? staged,
    List<String>? unstaged,
    String? rawOutput,
    List<CommitNode>? commits,
    String? graphError,
    bool clearGraphError = false,
    String? currentBranch,
    List<String>? branches,
    List<String>? remoteBranches,
    List<Map<String, String>>? stashes,
    List<String>? tags,
    List<String>? remotes,
    bool? hasRemote,
    bool? hasUpstream,
    int? unpushedCount,
    int? unpulledCount,
  }) {
    return RepoStatusLoaded(
      staged: staged ?? this.staged,
      unstaged: unstaged ?? this.unstaged,
      rawOutput: rawOutput ?? this.rawOutput,
      commits: commits ?? this.commits,
      graphError: clearGraphError ? null : (graphError ?? this.graphError),
      currentBranch: currentBranch ?? this.currentBranch,
      branches: branches ?? this.branches,
      remoteBranches: remoteBranches ?? this.remoteBranches,
      stashes: stashes ?? this.stashes,
      tags: tags ?? this.tags,
      remotes: remotes ?? this.remotes,
      hasRemote: hasRemote ?? this.hasRemote,
      hasUpstream: hasUpstream ?? this.hasUpstream,
      unpushedCount: unpushedCount ?? this.unpushedCount,
      unpulledCount: unpulledCount ?? this.unpulledCount,
    );
  }

  @override
  List<Object?> get props => [
    staged,
    unstaged,
    rawOutput,
    commits,
    graphError,
    currentBranch,
    branches,
    remoteBranches,
    stashes,
    tags,
    remotes,
    hasRemote,
    hasUpstream,
    unpushedCount,
    unpulledCount,
  ];
}

class RepoStatusError extends RepoStatusState {
  final String message;
  const RepoStatusError({required this.message});
  @override
  List<Object?> get props => [message];
}
