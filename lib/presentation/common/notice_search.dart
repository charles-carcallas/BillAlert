import '../../domain/repositories/notice_repository.dart';

/// Whether a loaded disconnection notice matches the Admin's local search.
bool noticeMatchesSearch(ActiveNotice notice, String rawQuery) {
  final String query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;

  return notice.consumerLabel.toLowerCase().contains(query) ||
      (notice.consumerNo?.toLowerCase().contains(query) ?? false) ||
      notice.noticeNo.toLowerCase().contains(query);
}
