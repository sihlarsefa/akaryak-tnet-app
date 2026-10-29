/// Push dokunuşunun açtığı blok (v4 §3.5, tur 2): Bildirimler'deki satırla aynı `?focus=` — teklif,
/// teslimat ya da talep; olayın türüne ve rotasına göre. Kilit ekranından, soğuk açılıştan ve
/// uygulama içi balonun "Aç"ından açılan sayfa da karar bloğuna kayar ve parlar. Bilgi veren olayda,
/// tanınmayan rotada ya da rotada zaten `focus` varsa rota olduğu gibi döner.
String withPushFocus(String route, String? type, {bool canQuote = true}) {
  final uri = Uri.tryParse(route);
  if (uri == null || type == null || uri.queryParameters.containsKey('focus')) {
    return route;
  }
  final path = uri.path;
  final focus = switch (type) {
    'order.quote_ready' ||
    'order.quote_expiring' when path.startsWith('/orders/') => 'quote',
    'order.created' when canQuote && path.startsWith('/bayi/orders/') =>
      'quote',
    'shipment.reported' when path.startsWith('/shipments/') => 'delivery',
    'approval.pending' ||
    'approval.reminder' ||
    'approval.escalated' ||
    'order.finance_info' ||
    'approval.info_requested' when path.startsWith('/approvals/') => 'request',
    _ => null,
  };
  if (focus == null) return route;
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'focus': focus})
      .toString();
}
