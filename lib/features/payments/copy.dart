/// Tahsilat Türkçe metinleri.
library;

import 'package:flutter/material.dart';

import '../../core/models/enums.dart';

abstract final class PaymentsCopy {
  static const title = 'Tahsilat';
  static const paymentsTab = 'Ödemeler';
  static const instrumentsTab = 'Çek / senet';
  static const searchPayments = 'Sipariş no ya da cari ara';
  static const searchInstruments = 'Seri no, banka ya da cari ara';

  /// Süzgeç çipleri.
  static const allCustomers = 'Cari: tümü';
  static const overdue = 'Gecikenler';
  static const statusFilters = [
    PaymentStatus.pending,
    PaymentStatus.documentUploaded,
    PaymentStatus.collected,
    PaymentStatus.bounced,
    PaymentStatus.refunded,
    PaymentStatus.cancelled,
  ];

  /// Liste sonu cümleleri (§7.7: kayıtların nereye gittiği).
  static const paymentsFootnote =
      'Tahsil edilen, iade ve iptal edilen ödemeleri görmek için durum filtrelerini kullanın.';
  static const instrumentsFootnote =
      'Tahsil edilen ve sonuçlanan belgeler Tümü filtresinde.';

  static const emptyPaymentsTitle = 'Açık ödeme yok';
  static const emptyPaymentsMessage =
      'Bekleyen ve belgesi yüklenen ödemeler burada listelenir.';
  static const emptyInstrumentsTitle = 'Portföyde belge yok';
  static const emptyInstrumentsMessage =
      'Alınan çek, senet ve teminat mektupları vadeleriyle burada listelenir.';
  static const filteredTitle = 'Filtreye uyan kayıt yok';
  static const filteredMessage =
      'Filtreleri değiştirin ya da temizleyip tüm kayıtları görün.';
  static const clearFilters = 'Filtreleri temizle';
  static const notFoundTitle = 'Bu ödeme artık görüntülenemiyor';

  static const offline =
      'Çevrimdışısınız. Durumu değiştirmek için bağlantı gerekli.';

  /// Ödeme ayrıntısının eylemleri (§7.14).
  static const markCollected = 'Tahsil edildi olarak işaretle';
  static const changeStatus = 'Durumu değiştir';
  static const checkDocument = 'Belgeyi kontrol et';
  static const openOrder = 'Siparişi aç';

  /// Ödeme durumunun açıklaması (durum sayfası).
  static String paymentHint(PaymentStatus s) => switch (s) {
    PaymentStatus.pending => 'Ödeme bekleniyor.',
    PaymentStatus.documentUploaded =>
      'Belge (dekont, çek görseli) alındı; kontrol bekliyor.',
    PaymentStatus.collected => 'Ödeme hesaba geçti.',
    PaymentStatus.bounced => 'Çek / senet karşılıksız çıktı. Gerekçe zorunlu.',
    PaymentStatus.refunded =>
      'Tahsil edilen tutar iade edildi. Gerekçe zorunlu.',
    PaymentStatus.cancelled => 'Ödeme iptal edildi. Gerekçe zorunlu.',
    _ => '',
  };

  /// Portföy durumunun açıklaması.
  static String instrumentHint(InstrumentStatus s) => switch (s) {
    InstrumentStatus.received => 'Belge alındı.',
    InstrumentStatus.inPortfolio => 'Belge portföyde, vadesi bekleniyor.',
    InstrumentStatus.deposited => 'Belge tahsil için bankaya verildi.',
    InstrumentStatus.collected =>
      'Belge tahsil edildi; bağlı siparişlerin ödemesi kapanır.',
    InstrumentStatus.bounced => 'Belge karşılıksız çıktı. Açıklama zorunlu.',
    InstrumentStatus.returned => 'Belge cariye iade edildi. Açıklama zorunlu.',
    InstrumentStatus.protested => 'Belge protesto edildi. Açıklama zorunlu.',
    InstrumentStatus.unknown => '',
  };

  static IconData methodIcon(String? code) => switch (code) {
    'CEK' => Icons.money_rounded,
    'SENET' => Icons.description_rounded,
    'HAVALE' => Icons.account_balance_rounded,
    'KART' => Icons.credit_card_rounded,
    'NAKIT' => Icons.payments_rounded,
    'DBS' => Icons.handshake_rounded,
    'ACIK_HESAP' => Icons.receipt_long_rounded,
    'TEMINAT' => Icons.verified_rounded,
    'AVANS' => Icons.savings_rounded,
    'UTTS' => Icons.local_gas_station_rounded,
    _ => Icons.payments_outlined,
  };
}
