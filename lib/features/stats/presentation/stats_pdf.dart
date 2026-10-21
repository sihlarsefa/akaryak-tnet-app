import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/akn_pdf.dart';
import '../copy.dart';
import '../data/stats_models.dart';
import 'stats_format.dart';

/// `/stats` sayfasının paylaşılan özeti (A4 PDF; uygulamanın ortak belge tabanı, gömülü Roboto).
/// Ekrandaki dönemin rakamları satır satır yazılır; maliyet ve kâr bilgisi yoktur.
abstract final class StatsPdf {
  /// Dosya adı: `Istatistikler-month.pdf`.
  static String fileName(StatsPeriod period) =>
      'Istatistikler-${period.key}.pdf';

  /// Bayi (ya da saha temsilcisinin portföyü) özeti.
  static Future<Uint8List> bayi(BayiStats d, {required bool own}) {
    final s = d.sales;
    return AknPdf.buildA4(
      title: StatsCopy.pageTitle,
      subtitle: [
        ?d.stationTitle,
        '${d.period.title}, ${StatsFmt.range(d.period.from, d.period.to)}',
      ].join('\n'),
      date: d.generatedAt,
      footerNote: StatsCopy.methodology,
      body: (t) => [
        if (s != null)
          AknPdf.section(own ? StatsCopy.cardSalesOwn : StatsCopy.kpiSales, [
            AknPdf.row(
              StatsCopy.metricAmount,
              StatsFmt.money(s.amount),
              bold: true,
            ),
            AknPdf.row(
              d.period.key.compareShort,
              _change(s.amount, s.prevAmount),
            ),
            AknPdf.row(StatsCopy.kpiLiters, StatsFmt.liters(s.liters)),
            AknPdf.row(StatsCopy.kpiOrders, StatsFmt.count(s.orders)),
            AknPdf.row(StatsCopy.kpiUnitPrice, StatsFmt.unitPrice(s.unitPrice)),
            if (s.activeCustomers != null)
              AknPdf.row(
                StatsCopy.kpiActiveCustomers,
                StatsFmt.count(s.activeCustomers),
              ),
          ]),
        ..._months(d.months),
        if (d.products.isNotEmpty)
          AknPdf.section(StatsCopy.mixTitle, [
            for (final p in d.products)
              AknPdf.row(
                p.name,
                '${StatsFmt.liters(p.liters)}, ${StatsFmt.rate(p.share)}',
              ),
          ]),
        if (d.funnel != null)
          AknPdf.section(StatsCopy.funnelTitle, [
            AknPdf.row(
              StatsCopy.funnelRequests,
              StatsFmt.count(d.funnel!.requests),
            ),
            AknPdf.row(
              StatsCopy.funnelQuoted,
              StatsFmt.count(d.funnel!.quoted),
            ),
            AknPdf.row(
              StatsCopy.funnelAccepted,
              StatsFmt.count(d.funnel!.accepted),
            ),
            AknPdf.row(
              StatsCopy.conversion,
              StatsFmt.rate(d.funnel!.conversion, decimals: 1),
            ),
            if (d.funnel!.avgFirstQuoteMinutes != null)
              AknPdf.row(
                StatsCopy.firstQuoteLine,
                StatsFmt.minutes(d.funnel!.avgFirstQuoteMinutes),
              ),
          ]),
        if (d.deliveries != null && !own)
          AknPdf.section(StatsCopy.deliveriesTitle, [
            AknPdf.row(
              StatsCopy.deliveredStatus,
              '${StatsFmt.count(d.deliveries!.delivered)}, '
              '${StatsFmt.liters(d.deliveries!.deliveredLiters)}',
            ),
            AknPdf.row(
              StatsCopy.onTime,
              StatsFmt.rate(d.deliveries!.onTimeRate),
            ),
            AknPdf.row(
              StatsCopy.inTransit,
              StatsFmt.count(d.deliveries!.inTransit),
            ),
            AknPdf.row(
              StatsCopy.planned,
              StatsFmt.count(d.deliveries!.planned),
            ),
            AknPdf.row(
              StatsCopy.disputes,
              StatsFmt.count(d.deliveries!.disputes),
            ),
          ]),
        if (d.collections != null && !own)
          AknPdf.section(StatsCopy.collectionsTitle, [
            AknPdf.row(
              StatsCopy.collectedRow,
              '${StatsFmt.money(d.collections!.collectedAmount)}, '
              '${StatsCopy.paymentsCount(d.collections!.collectedCount)}',
            ),
            AknPdf.row(
              StatsCopy.overdue,
              '${StatsFmt.money(d.collections!.overdueAmount)}, '
              '${StatsCopy.paymentsCount(d.collections!.overdueCount)}',
              bold: d.collections!.overdueCount > 0,
            ),
            AknPdf.row(
              StatsCopy.dueSoon(d.collections!.dueSoonDays),
              '${StatsFmt.money(d.collections!.dueSoonAmount)}, '
              '${StatsCopy.paymentsCount(d.collections!.dueSoonCount)}',
            ),
          ]),
        if (d.topCustomers.isNotEmpty)
          AknPdf.section(
            own ? StatsCopy.topCustomersOwnTitle : StatsCopy.topCustomersTitle,
            [
              for (final c in d.topCustomers)
                AknPdf.row(
                  c.title,
                  '${StatsFmt.money(c.amount)}, ${StatsFmt.rate(c.share)}',
                ),
            ],
          ),
        if (d.team.isNotEmpty)
          AknPdf.section(own ? StatsCopy.cardOwnForms : StatsCopy.teamTitle, [
            for (final m in d.team)
              AknPdf.row(m.name, StatsCopy.formsSummary(m.forms, m.converted)),
          ]),
        if (d.risk != null && d.risk!.nearLimitCount > 0 && !own)
          AknPdf.section(StatsCopy.riskTitle, [
            for (final r in d.risk!.nearLimit)
              AknPdf.row(r.title, StatsFmt.rate(r.usageRate)),
          ]),
      ],
    );
  }

  /// Müşteri özeti.
  static Future<Uint8List> customer(CustomerStats d) {
    final s = d.spending;
    return AknPdf.buildA4(
      title: StatsCopy.pageTitle,
      subtitle: [
        ?d.customerTitle,
        '${d.period.title}, ${StatsFmt.range(d.period.from, d.period.to)}',
      ].join('\n'),
      date: d.generatedAt,
      footerNote: StatsCopy.methodology,
      body: (t) => [
        if (s != null)
          AknPdf.section(StatsCopy.kpiSpending, [
            AknPdf.row(
              StatsCopy.metricAmount,
              StatsFmt.money(s.amount),
              bold: true,
            ),
            AknPdf.row(
              d.period.key.compareShort,
              _change(s.amount, s.prevAmount),
            ),
            AknPdf.row(StatsCopy.kpiLitersCustomer, StatsFmt.liters(s.liters)),
            AknPdf.row(StatsCopy.kpiOrders, StatsFmt.count(s.orders)),
            AknPdf.row(StatsCopy.kpiUnitPrice, StatsFmt.unitPrice(s.unitPrice)),
          ]),
        ..._months(d.months),
        if (d.products.isNotEmpty)
          AknPdf.section(StatsCopy.mixTitle, [
            for (final p in d.products)
              AknPdf.row(
                p.name,
                '${StatsFmt.liters(p.liters)}, ${StatsFmt.rate(p.share)}',
              ),
          ]),
        if (d.stations.isNotEmpty)
          AknPdf.section(StatsCopy.stationsTitle, [
            for (final x in d.stations)
              AknPdf.row(
                x.title,
                '${StatsFmt.money(x.amount)}, ${StatsFmt.liters(x.liters)}',
              ),
          ]),
        if (d.deliveryPoints.isNotEmpty)
          AknPdf.section(StatsCopy.pointsTitle, [
            for (final p in d.deliveryPoints)
              AknPdf.row(
                [p.name, ?p.city].join(', '),
                StatsFmt.liters(p.liters),
              ),
          ]),
        if (d.limits.isNotEmpty)
          AknPdf.section(StatsCopy.limitsTitle, [
            for (final l in d.limits)
              AknPdf.row(
                l.stationTitle,
                l.isUnlimited
                    ? StatsCopy.unlimited
                    : StatsCopy.limitCaption(
                        l.isLiters
                            ? StatsFmt.liters(l.available)
                            : StatsFmt.money(l.available),
                        l.isLiters
                            ? StatsFmt.liters(l.limit)
                            : StatsFmt.money(l.limit),
                      ),
              ),
          ]),
      ],
    );
  }

  static String _change(double current, double previous) {
    // Belgede ok karakteri yok (gömülü yazı tipinde bulunmayabilir): işaretle yazılır.
    final pct = StatsFmt.change(current, previous);
    if (pct == null) return StatsFmt.dash;
    if (pct.abs() < StatsFmt.flatThreshold) return '%0';
    return '${pct > 0 ? '+' : '-'}${StatsFmt.deltaPercent(pct)}';
  }

  static List<pw.Widget> _months(List<StatsMonth> months) => [
    if (months.isNotEmpty)
      AknPdf.section(StatsCopy.monthlyTitle, [
        for (final m in months)
          AknPdf.row(
            m.longLabel,
            '${StatsFmt.money(m.amount)}, ${StatsFmt.liters(m.liters)}, '
            '${StatsCopy.ordersCount(m.orders)}',
          ),
      ]),
  ];
}
