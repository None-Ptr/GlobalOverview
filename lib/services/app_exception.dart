/// 面向用户的应用异常：message 是可直接展示的中文，detail 放原始信息（折叠展示）。
class AppException implements Exception {
  final String code;
  final String message;
  final String? detail;
  final int? status;
  final bool retryable;

  const AppException(
    this.code,
    this.message, {
    this.detail,
    this.status,
    this.retryable = false,
  });

  @override
  String toString() {
    final d = detail;
    return (d == null || d.isEmpty) ? message : '$message · $d';
  }
}

String errText(Object e) => e is AppException ? e.message : '操作失败';

String errDetail(Object e) => e is AppException ? (e.detail ?? '') : '$e';

bool isRetryable(Object e) => e is AppException && e.retryable;
