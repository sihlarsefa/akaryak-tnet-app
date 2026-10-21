import 'package:flutter/foundation.dart';

/// Belge tonları (web `is-ok`, `is-warn`, `is-danger`, `is-brand`, `is-info`).
enum DocTone { neutral, ok, warn, danger, brand, info }

/// Belge türü (dosya adı ve başlık).
enum DocKind {
  order('Sipariş formu', 'Siparis_Formu'),
  quote('Fiyat teklifi', 'Fiyat_Teklifi'),
  reconciliation('Teslimat mutabakatı', 'Teslimat_Mutabakati'),
  receipt('Teslim tutanağı', 'Teslim_Tutanagi'),
  waybill('Sevk belgesi', 'Sevk_Belgesi');

  const DocKind(this.title, this.fileSuffix);
  final String title;
  final String fileSuffix;

  /// Dosya adı (web `DocumentText.FileTitle`): `SIP-…_Siparis_Formu.pdf`.
  String fileName(String code) {
    final cleaned = '${code}_$fileSuffix'
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return '$cleaned.pdf';
  }
}

/// Başlık mührü (`DocumentStamps`): "ONAYLANDI 21.10.2026".
@immutable
class DocStamp {
  const DocStamp(this.text, {this.sub, this.tone = DocTone.neutral});
  final String text;
  final String? sub;
  final DocTone tone;
}

/// Etiket — değer çifti.
@immutable
class DocKv {
  const DocKv(this.label, this.value, {this.accent = false});
  final String label;
  final String value;

  /// Vurgulu değer (turuncu).
  final bool accent;
}

/// Taraf kartı (gönderen bayi / alıcı cari).
@immutable
class DocPartyCard {
  const DocPartyCard({
    required this.heading,
    required this.title,
    this.brand = false,
    this.code,
    this.subtitle,
    this.rows = const [],
  });

  final String heading;
  final bool brand;
  final String? code;
  final String title;
  final String? subtitle;
  final List<DocKv> rows;
}

/// Belge gövdesinin bir bloğu.
@immutable
sealed class DocBlock {
  const DocBlock();
}

/// Üst bilgi şeridi (Durum, Sipariş tarihi …).
final class DocMetaBlock extends DocBlock {
  const DocMetaBlock(this.cells);
  final List<DocKv> cells;
}

/// İki taraf kartı yan yana.
final class DocPartiesBlock extends DocBlock {
  const DocPartiesBlock(this.left, this.right);
  final DocPartyCard left;
  final DocPartyCard right;
}

/// Teslimat noktası kutusu: ad, adres, il (büyük harf) / ilçe ve isteğe bağlı saha bilgileri.
final class DocAddressBlock extends DocBlock {
  const DocAddressBlock({
    required this.heading,
    this.small,
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    this.details = const [],
  });

  final String heading;
  final String? small;
  final String name;
  final String address;
  final String city;
  final String district;
  final List<DocKv> details;
}

/// Tablo. [numeric] sütunları sağa yaslanır; [footer] toplam satırıdır.
final class DocTableBlock extends DocBlock {
  const DocTableBlock({
    this.heading,
    this.small,
    required this.headers,
    required this.rows,
    this.numeric = const {},
    this.footer,
    this.highlightRow,
    this.mutedRows = const {},
  });

  final String? heading;
  final String? small;
  final List<String> headers;
  final List<List<String>> rows;
  final Set<int> numeric;
  final List<String>? footer;
  final int? highlightRow;
  final Set<int> mutedRows;
}

/// Vurgulu toplam kutusu.
final class DocTotalBlock extends DocBlock {
  const DocTotalBlock({required this.label, required this.value, this.hint});
  final String label;
  final String value;
  final String? hint;
}

/// Başlıklı etiket — değer listesi (Ödeme şekli).
final class DocKvBlock extends DocBlock {
  const DocKvBlock({required this.heading, this.small, required this.rows});
  final String heading;
  final String? small;
  final List<DocKv> rows;
}

/// Gösterge kutuları (Sipariş · Teslim alınan · Süreçte · Kalan).
final class DocKpisBlock extends DocBlock {
  const DocKpisBlock(this.cells, {this.heading, this.small, this.progress});
  final String? heading;
  final String? small;
  final List<DocKpi> cells;

  /// Teslim alınan / süreçte çubuğu (0–1).
  final ({double accepted, double inProcess})? progress;
}

@immutable
class DocKpi {
  const DocKpi(
    this.label,
    this.value, {
    this.unit,
    this.tone = DocTone.neutral,
  });
  final String label;
  final String value;
  final String? unit;
  final DocTone tone;
}

/// Bilgi kutusu (ödeme şekli, onay, revizyon notu, uyarı).
final class DocCalloutBlock extends DocBlock {
  const DocCalloutBlock({required this.tone, required this.title, this.text});
  final DocTone tone;
  final String title;
  final String? text;
}

/// Düz paragraf; [fine] küçük yazı, [statement] tutanak beyanı.
final class DocTextBlock extends DocBlock {
  const DocTextBlock(this.text, {this.fine = false, this.statement = false});
  final String text;
  final bool fine;
  final bool statement;
}

/// Notlar (teklif hukuki notu).
final class DocNotesBlock extends DocBlock {
  const DocNotesBlock(this.lines);
  final List<String> lines;
}

/// El ile doldurulacak kutular (sayaç, mühür no …).
final class DocFillBlock extends DocBlock {
  const DocFillBlock(this.cells, {this.heading, this.small});
  final String? heading;
  final String? small;
  final List<DocFillCell> cells;
}

@immutable
class DocFillCell {
  const DocFillCell(
    this.label, {
    this.unit,
    this.wide = false,
    this.full = false,
  });
  final String label;
  final String? unit;
  final bool wide;
  final bool full;
}

/// Araç ve sürücü satırı (plaka + alanlar).
final class DocPlateBlock extends DocBlock {
  const DocPlateBlock({
    required this.heading,
    this.small,
    this.plate,
    required this.fields,
    this.fill = const [],
  });

  final String heading;
  final String? small;

  /// Biçimli plaka; boşsa "PLAKA" boş kutusu basılır.
  final String? plate;
  final List<DocKv> fields;
  final List<DocFillCell> fill;
}

/// Durum geçmişi.
final class DocTimelineBlock extends DocBlock {
  const DocTimelineBlock({
    required this.heading,
    this.small,
    required this.items,
    this.more,
  });

  final String heading;
  final String? small;
  final List<DocTimelineEntry> items;
  final String? more;
}

@immutable
class DocTimelineEntry {
  const DocTimelineEntry({
    required this.time,
    required this.what,
    this.note,
    this.who,
  });
  final String time;
  final String what;
  final String? note;
  final String? who;
}

/// İmza kutuları (`_DocSigns`): her kutuda "Ad soyad", "Tarih / saat", "İmza · Kaşe".
final class DocSignaturesBlock extends DocBlock {
  const DocSignaturesBlock(this.boxes);
  final List<DocSignBox> boxes;
}

@immutable
class DocSignBox {
  const DocSignBox(this.title, {this.sub, this.name});
  final String title;
  final String? sub;
  final String? name;
}

/// Uygulamada üretilen belgenin tam tanımı (web `Views/Documents/*.cshtml` portu).
/// Önce bu tanım kurulur (testler metinleri denetler), sonra PDF'e çizilir (`DocRenderer`).
@immutable
class DocSpec {
  const DocSpec({
    required this.kind,
    required this.code,
    required this.kicker,
    required this.title,
    this.subtitle,
    required this.numberLabel,
    required this.number,
    required this.barcode,
    this.qrUrl,
    this.qrCaption,
    required this.issuerTitle,
    this.issuerLine,
    this.brand,
    this.seq,
    this.stamp,
    this.watermark,
    required this.blocks,
    required this.printedAt,
    required this.printedBy,
  });

  final DocKind kind;

  /// Belge kodu (dosya adı, alt bilgi): sipariş no, `…-T2`, `TT-…`, `SVK-…`.
  final String code;
  final String kicker;
  final String title;
  final String? subtitle;
  final String numberLabel;
  final String number;

  /// Code 128 içeriği.
  final String barcode;
  final String? qrUrl;
  final String? qrCaption;
  final String issuerTitle;
  final String? issuerLine;

  /// Dağıtıcı markası çipi.
  final String? brand;

  /// "Sevkiyat 1/2".
  final String? seq;
  final DocStamp? stamp;

  /// Filigran: GEÇERSİZ, ONAYLANMAMIŞ, İPTAL.
  final String? watermark;
  final List<DocBlock> blocks;
  final DateTime? printedAt;
  final String printedBy;

  /// Tüm belgelerin alt bilgisindeki yasal not (spec A.4 A3).
  static const legalFooter =
      'Mali belge değildir; e-irsaliye/e-fatura yerine geçmez.';

  static const platformName = 'AkaryakıtNet';

  String get fileName => kind.fileName(code);
}

/// Belgedeki tüm görünür metinler (testler: Türkçe karakter ve "irsaliye" etiketi denetimi).
List<String> docTexts(DocSpec d, {bool includeFooter = true}) {
  final out = <String>[
    d.kicker,
    d.title,
    ?d.subtitle,
    d.numberLabel,
    d.number,
    ?d.qrCaption,
    d.issuerTitle,
    ?d.issuerLine,
    ?d.brand,
    ?d.seq,
    if (d.stamp != null) d.stamp!.text,
    ?d.stamp?.sub,
    ?d.watermark,
    if (includeFooter) DocSpec.legalFooter,
    d.printedBy,
  ];
  void kv(Iterable<DocKv> rows) {
    for (final r in rows) {
      out
        ..add(r.label)
        ..add(r.value);
    }
  }

  void party(DocPartyCard p) {
    out
      ..add(p.heading)
      ..add(p.title);
    if (p.code != null) out.add(p.code!);
    if (p.subtitle != null) out.add(p.subtitle!);
    kv(p.rows);
  }

  void fill(Iterable<DocFillCell> cells) {
    for (final c in cells) {
      out.add(c.label);
      if (c.unit != null) out.add(c.unit!);
    }
  }

  for (final b in d.blocks) {
    switch (b) {
      case DocMetaBlock(:final cells):
        kv(cells);
      case DocPartiesBlock(:final left, :final right):
        party(left);
        party(right);
      case DocAddressBlock():
        out.addAll([
          b.heading,
          ?b.small,
          b.name,
          b.address,
          b.city,
          b.district,
        ]);
        kv(b.details);
      case DocTableBlock():
        out.addAll([?b.heading, ?b.small, ...b.headers]);
        for (final r in b.rows) {
          out.addAll(r);
        }
        if (b.footer != null) out.addAll(b.footer!);
      case DocTotalBlock():
        out.addAll([b.label, b.value, ?b.hint]);
      case DocKvBlock():
        out.addAll([b.heading, ?b.small]);
        kv(b.rows);
      case DocKpisBlock():
        out.addAll([?b.heading, ?b.small]);
        for (final c in b.cells) {
          out.addAll([c.label, c.value, ?c.unit]);
        }
      case DocCalloutBlock():
        out.addAll([b.title, ?b.text]);
      case DocTextBlock():
        out.add(b.text);
      case DocNotesBlock():
        out.addAll(b.lines);
      case DocFillBlock():
        out.addAll([?b.heading, ?b.small]);
        fill(b.cells);
      case DocPlateBlock():
        out.addAll([b.heading, ?b.small, ?b.plate]);
        kv(b.fields);
        fill(b.fill);
      case DocTimelineBlock():
        out.addAll([b.heading, ?b.small, ?b.more]);
        for (final e in b.items) {
          out.addAll([e.time, e.what, ?e.note, ?e.who]);
        }
      case DocSignaturesBlock():
        for (final s in b.boxes) {
          out.addAll([s.title, ?s.sub, ?s.name]);
        }
        out.addAll(const ['Ad soyad', 'Tarih / saat', 'İmza · Kaşe']);
    }
  }
  return out;
}
