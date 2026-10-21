import 'package:flutter/foundation.dart';

import 'json.dart';

/// Sayfalı liste (`PagedResult<T>`: `{items, totalCount, pageNumber, pageSize, totalPages}`).
/// Sayfalama: `?page=1&pageSize=25` (en fazla 100).
@immutable
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.totalCount,
    required this.pageNumber,
    required this.pageSize,
    required this.totalPages,
  });

  /// Boş ilk sayfa.
  const PagedResult.empty({this.pageSize = 25})
    : items = const [],
      totalCount = 0,
      pageNumber = 1,
      totalPages = 0;

  factory PagedResult.fromJson(Object? json, T Function(JsonReader r) item) {
    final r = JsonReader.of(json);
    final items = r.list('items', item);
    final pageSize = r.integer('pageSize', items.length);
    final total = r.integer('totalCount', items.length);
    final pages =
        r.intOrNull('totalPages') ??
        (pageSize <= 0 ? 0 : (total / pageSize).ceil());
    return PagedResult(
      items: List.unmodifiable(items),
      totalCount: total,
      pageNumber: r.integer('pageNumber', 1),
      pageSize: pageSize,
      totalPages: pages,
    );
  }

  final List<T> items;
  final int totalCount;
  final int pageNumber;
  final int pageSize;
  final int totalPages;

  bool get hasMore => pageNumber < totalPages;
  bool get isEmpty => items.isEmpty;
  int get nextPage => pageNumber + 1;

  /// Sonsuz kaydırma: sonraki sayfayı bu sayfanın sonuna ekler.
  PagedResult<T> append(PagedResult<T> next) => PagedResult(
    items: List.unmodifiable([...items, ...next.items]),
    totalCount: next.totalCount,
    pageNumber: next.pageNumber,
    pageSize: next.pageSize,
    totalPages: next.totalPages,
  );

  PagedResult<R> map<R>(R Function(T item) convert) => PagedResult(
    items: List.unmodifiable(items.map(convert)),
    totalCount: totalCount,
    pageNumber: pageNumber,
    pageSize: pageSize,
    totalPages: totalPages,
  );

  /// Sahte API ve testler için JSON.
  static JsonMap toJson<T>(
    List<Object?> items, {
    required int totalCount,
    int pageNumber = 1,
    int pageSize = 25,
  }) => {
    'items': items,
    'totalCount': totalCount,
    'pageNumber': pageNumber,
    'pageSize': pageSize,
    'totalPages': pageSize <= 0 ? 0 : (totalCount / pageSize).ceil(),
  };
}
