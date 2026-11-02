part of 'repo_bloc.dart';

abstract class RepoStatusEvent extends Equatable {
  const RepoStatusEvent();
  @override
  List<Object?> get props => [];
}

class LoadRepoStatus extends RepoStatusEvent {
  final String workspace;
  const LoadRepoStatus(this.workspace);
  @override
  List<Object?> get props => [workspace];
}

class RefreshGitFileStatus extends RepoStatusEvent {
  final String workspace;
  const RefreshGitFileStatus(this.workspace);
  @override
  List<Object?> get props => [workspace];
}

class LoadCommitGraph extends RepoStatusEvent {
  final String workspace;
  const LoadCommitGraph(this.workspace);
  @override
  List<Object?> get props => [workspace];
}

class LoadGitExtendedStatus extends RepoStatusEvent {
  final String workspace;
  const LoadGitExtendedStatus(this.workspace);
  @override
  List<Object?> get props => [workspace];
}

class RefreshRemoteStatus extends RepoStatusEvent {
  final String workspace;
  const RefreshRemoteStatus(this.workspace);
  @override
  List<Object?> get props => [workspace];
}
