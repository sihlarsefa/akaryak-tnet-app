import '../../core/auth/permissions.dart';
import '../../core/models/enums.dart';
import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/turkish_text.dart';

/// Asistan sahte uçlarının anahtarları (sunucu örneği başına; dev menüsü ve testler).
class AssistantFakeControls {
  AssistantFakeControls._();

  static final _byServer = Expando<AssistantFakeControls>(
    'assistantFakeControls',
  );

  static AssistantFakeControls of(FakeServer server) =>
      _byServer[server] ??= AssistantFakeControls._();

  /// Güncel aydınlatma sürümü (`Ai:ConsentVersion`).
  String version = '1';

  /// 503 `assistant_disabled` (anahtar yok / kapalı).
  bool disabled = false;

  /// Sonraki sohbet 429 `rate_limited` döner.
  bool rateLimitNext = false;

  /// Sonraki sohbet `isError: true` döner (model yanıt veremedi).
  bool modelErrorNext = false;

  int chatCalls = 0;
  JsonMap? lastChat;
  final List<JsonMap> feedback = [];
}

/// Asistan sahte uçları (sahibi A8; spec B.11 + B8 notları):
/// - `GET assistant/disclosure` → `{version, title, text, sections[], provider, providerCountry,
///   retentionDays, legalUrl, accepted, acceptedAt}`,
/// - `POST assistant/consent {version}` → 204 (yalnızca güncel sürüm), `DELETE assistant/consent` → 204,
/// - `GET assistant/suggestions` → persona başına sorular,
/// - `POST assistant/chat {message, history, consentVersion}` → `{reply, chatLogId, isError}`; onay
///   yoksa 400 `consent_required`, kapalıysa 503 `assistant_disabled`,
/// - `POST assistant/feedback {chatLogId, helpful, comment}` → 204 (yalnızca kendi kayıtları).
void registerAssistantFakes(FakeServer s) {
  final ctl = AssistantFakeControls.of(s);

  Map<String, ({String version, DateTime at})> consents(FakeWorld w) =>
      w.bag<Map<String, ({String version, DateTime at})>>(
        'assistant.consents',
        () => {},
      );
  Map<int, String> logs(FakeWorld w) =>
      w.bag<Map<int, String>>('assistant.logs', () => {});

  FakeResponse disabledResponse() => FakeResponse.problem(
    503,
    'assistant_disabled',
    'Asistan şu an kullanılamıyor.',
  );

  s.get('assistant/disclosure', (req) {
    final p = req.requireUser();
    final c = consents(req.world)[p.userId];
    final accepted = c != null && c.version == ctl.version;
    final sections = _sections(90);
    return {
      'version': ctl.version,
      'title': 'Yapay zekâ asistanı aydınlatma metni',
      'text': [
        for (final x in sections) '${x['title']}\n${x['body']}',
      ].join('\n\n'),
      'sections': sections,
      'provider': 'OpenAI, L.L.C.',
      'providerCountry': 'ABD',
      'retentionDays': 90,
      'legalUrl': 'http://fake.akaryakitnet.local/legal/ai',
      'accepted': accepted,
      'acceptedAt': accepted ? c.at.toIso8601String() : null,
    };
  });

  s.post('assistant/consent', (req) {
    final p = req.requireUser();
    final version = req.json.str('version');
    if (version != ctl.version) {
      throw FakeResponse.validation({
        'version': ['Aydınlatma metni güncellendi; lütfen yeniden okuyun.'],
      });
    }
    consents(req.world)[p.userId] = (
      version: version,
      at: DateTime.now().toUtc(),
    );
    return FakeResponse.noContent();
  });

  s.delete('assistant/consent', (req) {
    final p = req.requireUser();
    consents(req.world).remove(p.userId);
    return FakeResponse.noContent();
  });

  s.get('assistant/suggestions', (req) {
    final p = req.requireUser();
    if (ctl.disabled) throw disabledResponse();
    return _suggestions(p);
  });

  s.post('assistant/chat', (req) {
    final p = req.requireUser();
    ctl.chatCalls++;
    ctl.lastChat = JsonReader.asMap(req.body);
    if (ctl.disabled) throw disabledResponse();
    final r = req.json;
    final c = consents(req.world)[p.userId];
    if (c == null ||
        c.version != ctl.version ||
        r.str('consentVersion') != ctl.version) {
      throw FakeResponse.problem(
        400,
        'consent_required',
        'Asistanı kullanmadan önce aydınlatma metnini onaylayın.',
      );
    }
    final message = r.str('message').trim();
    if (message.isEmpty || message.length > 1000) {
      throw FakeResponse.validation({
        'message': ['Mesaj 1-1000 karakter olmalıdır.'],
      });
    }
    if (ctl.rateLimitNext) {
      ctl.rateLimitNext = false;
      throw FakeResponse.problem(
        429,
        'rate_limited',
        'Çok fazla soru gönderdiniz. Lütfen biraz bekleyin.',
        headers: {'retry-after': '20'},
      );
    }
    final id = req.world.nextId('assistant.log', start: 7001);
    if (ctl.modelErrorNext) {
      ctl.modelErrorNext = false;
      logs(req.world)[id] = p.userId;
      return {
        'reply':
            'Asistan şu an yanıt veremiyor; lütfen daha sonra tekrar deneyin.',
        'chatLogId': id,
        'isError': true,
      };
    }
    logs(req.world)[id] = p.userId;
    return {
      'reply': _answer(req.world, p, message),
      'chatLogId': id,
      'isError': false,
    };
  });

  s.post('assistant/feedback', (req) {
    final p = req.requireUser();
    final r = req.json;
    final id = r.integer('chatLogId');
    if (logs(req.world)[id] != p.userId) {
      throw FakeResponse.notFound('Sohbet kaydı bulunamadı.');
    }
    ctl.feedback.add({
      'chatLogId': id,
      'helpful': r.boolean('helpful'),
      'comment': r.nonEmpty('comment'),
    });
    return FakeResponse.noContent();
  });
}

List<JsonMap> _sections(int days) => [
  {
    'title': 'Asistan ne yapar?',
    'body':
        'Asistan, AkaryakıtNet uygulamasının kullanımıyla ilgili sorularınızı yanıtlar: sipariş, teklif, '
        'ödeme, teslimat, onay ve ekranların nasıl kullanıldığı. Yanıtlar yapay zekâ ile oluşturulur ve hatalı '
        'olabilir; işlem yapmadan önce ekrandaki bilgileri esas alın. Asistan hesabınızda işlem yapmaz.',
  },
  {
    'title': 'Hangi bilgiler gönderilir?',
    'body':
        'Yazdığınız mesaj, aynı sohbetteki son mesajlarınız ve hesabınızla ilgili kısa bir özet: kullanıcı '
        'türünüz ve rolleriniz, son siparişlerinizin numarası, durumu, litresi ve tarihleri, açık teslimat ve '
        'bekleyen onay sayıları. Adınız, telefonunuz, e-postanız, vergi / kimlik numaranız ve adresleriniz '
        'gönderilmez.',
  },
  {
    'title': 'Kime ve neden aktarılır?',
    'body':
        'Yanıtın oluşturulması için mesajınız ve özet bilgiler yapay zekâ hizmet sağlayıcısı OpenAI, L.L.C. '
        'şirketine (ABD) aktarılır. Yurt dışına aktarım, bu metni onaylayarak verdiğiniz açık rızaya dayanır.',
  },
  {
    'title': 'Ne kadar saklanır?',
    'body':
        'Sohbet kayıtlarınız hizmetin güvenliği ve kalitesi için sunucularımızda $days gün saklanır, ardından '
        'silinir. Hesabınızı silerseniz sohbet metinleriniz de silinir.',
  },
  {
    'title': 'Dikkat edin',
    'body':
        'Kart numarası, şifre, SMS doğrulama kodu, kimlik ya da vergi numarası yazmayın. Onayınızı Profil > '
        'Gizlilik bölümünden istediğiniz zaman geri alabilirsiniz.',
  },
  {
    'title': 'Haklarınız',
    'body':
        'KVKK\'nın 11. maddesindeki haklarınız ve başvuru yolları KVKK aydınlatma metninde yer alır. '
        'Başvurularınız en geç 30 gün içinde ücretsiz yanıtlanır.',
  },
];

List<JsonMap> _suggestions(FakePersona p) {
  JsonMap g(String category, List<String> questions) => {
    'category': category,
    'questions': questions,
  };
  if (p.persona == Persona.customer) {
    return [
      g('Siparişler', ['Siparişim nerede?', 'Teklifi nasıl onaylarım?']),
      g('Ödeme', ['Çek nasıl yüklerim?', 'Finans onayı ne demek?']),
      g('Teslimat', ['Teslimata nasıl itiraz ederim?']),
    ];
  }
  if (p.persona == Persona.platform) {
    return [
      g('Onaylar', ['Onaylarım\'da neler bekliyor?', 'Koşullu onay ne demek?']),
    ];
  }
  final driverOnly =
      p.capabilities.containsKey(Caps.shipmentOwnOnly) &&
      !p.can(Pg.stationQuoteDesk) &&
      !p.can(Pg.stationOrders) &&
      !p.can(Pg.stationShipmentBoard) &&
      !p.can(Pg.stationApprovals);
  if (driverOnly) {
    return [
      g('Teslimat', [
        'Teslimatta imza zorunlu mu?',
        'Teslimatı nasıl başlatırım?',
        'İnternet yokken teslimat kaydedebilir miyim?',
      ]),
    ];
  }
  return [
    if (p.can(Pg.stationQuoteDesk) || p.can(Pg.stationQuotes))
      g('Teklifler', [
        'Bugün kaç teklif bekliyor?',
        'Önerilen fiyat nasıl belirleniyor?',
      ]),
    if (p.can(Pg.stationApprovals))
      g('Onaylar', ['Koşullu onay ne demek?', 'Ek bilgi istediğimde ne olur?']),
    if (p.can(Pg.stationPayments))
      g('Tahsilat', ['Çek durumunu nasıl güncellerim?']),
    if (p.can(Pg.stationFieldOrders) || p.can(Pg.stationLeads))
      g('Saha', ['Saha formu neden onaya düştü?']),
    if (!p.can(Pg.stationQuoteDesk) && !p.can(Pg.stationApprovals))
      g('Genel', ['Uygulamada neler yapabilirim?']),
  ];
}

String _answer(FakeWorld w, FakePersona p, String message) {
  final q = TurkishText.searchKey(message);
  bool has(String k) => q.contains(TurkishText.searchKey(k));

  if (has('nerede') || (has('siparis') && has('durum'))) {
    final orders = p.customerId == null
        ? const <JsonMap>[]
        : w.ordersOfCustomer(p.customerId!);
    if (orders.isNotEmpty) {
      final last = orders.last;
      final status = OrderStatus.fromCode(JsonReader.toInt(last['status']));
      return 'Son siparişiniz ${last['orderNumber']} şu an '
          '"${status.isUnknown ? 'işlemde' : status.label}" durumunda. Ayrıntılar ve teslimat takibi için Siparişlerim '
          'ekranında siparişe dokunun; araç yola çıkınca size bildirim gelir.';
    }
    return 'Siparişlerinizin durumunu Siparişlerim ekranında görebilirsiniz. Teklif hazır olduğunda, '
        'sipariş onaylandığında ve araç yola çıktığında bildirim alırsınız.';
  }
  if (has('cek') || has('senet')) {
    return 'Çek ya da senet ödemesinde siparişi verdikten sonra uygulama sizden belgenin fotoğrafını ister: '
        '"Fotoğraf çek" ile belgeyi çerçeveye hizalayın, net olduğundan emin olup gönderin. Belge yüklenene '
        'kadar ana sayfada hatırlatma görürsünüz.';
  }
  if (has('kosullu')) {
    return 'Koşullu onay, finans biriminin talebi belirli şartlarla (ör. farklı ödeme yöntemi ya da vade) '
        'onaylamasıdır. Şartlar onay ayrıntısında görünür; sipariş bu şartlarla devam eder.';
  }
  if (has('imza')) {
    return 'İmza zorunluluğu bayinizin ayarına bağlıdır. İmza alınamıyorsa "İmza alınamıyor"u seçip nedeni '
        'belirtin; bu durumda en az bir teslimat fotoğrafı ve konum gerekir.';
  }
  if (has('kac teklif') || (has('teklif') && has('bekliyor'))) {
    final n = p.stationId == null
        ? 0
        : w.ordersOfStation(p.stationId!).where((o) => o['status'] == 1).length;
    return 'Şu an teklif bekleyen $n sipariş var. Teklif masasında süresi en yakın olanlar en üsttedir; '
        'önerilen fiyatı tek dokunuşla uygulayabilirsiniz.';
  }
  if (has('itiraz')) {
    return 'Teslimatı kabul etmeden önce Teslimatlar ekranında teslim kanıtını kontrol edin. Sorun varsa '
        '"İtiraz et" ile önce fotoğraf ekleyin, sonra kısa bir not yazın; itirazınız bayiye iletilir.';
  }
  if (has('internet') || has('cevrimdisi')) {
    return 'Evet. İnternet yokken kaydettiğiniz teslimat cihazda saklanır ve bağlantı gelince otomatik '
        'gönderilir. Bekleyen işlemleri Profil > Bekleyen işlemler bölümünde görebilirsiniz.';
  }
  if (has('teklif') && has('onay')) {
    return 'Teklif hazır olunca siparişin ayrıntısında teklif kartı açılır: birim fiyatı, toplam tutarı ve '
        'teslim tarihini kontrol edip "Onayla"ya dokunun. Fiyat uygun değilse "Revize iste" ya da "Reddet" '
        'seçebilirsiniz.';
  }
  return 'Bu konuda size yardımcı olabilirim. Sorunuzu biraz daha ayrıntılı yazar mısınız? Örneğin hangi '
      'ekranda ya da hangi adımda olduğunuzu belirtebilirsiniz.';
}
