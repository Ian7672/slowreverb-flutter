import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slowreverb/native/native_audio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SlowReverbApp());
}

class SlowReverbApp extends StatefulWidget {
  const SlowReverbApp({super.key});

  @override
  State<SlowReverbApp> createState() => _SlowReverbAppState();
}

class _SlowReverbAppState extends State<SlowReverbApp> {
  static const _prefsKeyAppLanguage = 'app_language_code';
  static const _prefsKeyThemeMode = 'app_theme_mode';
  Locale? _overrideLocale;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsKeyAppLanguage);
    final savedTheme = prefs.getString(_prefsKeyThemeMode);
    if (!mounted) return;
    setState(() {
      if (savedCode != null && savedCode.isNotEmpty) {
        _overrideLocale = Locale(savedCode);
      }
      _themeMode = _themeModeFromString(savedTheme);
    });
  }

  Future<void> _handleLocaleChanged(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAppLanguage, locale.languageCode);
    setState(() {
      _overrideLocale = locale;
    });
  }

  Future<void> _handleThemeChanged(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyThemeMode, _themeModeToString(mode));
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
    });
  }

  ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slow Reverb Studio',
      debugShowCheckedModeBanner: false,
      locale: _overrideLocale,
      themeMode: _themeMode,
      localizationsDelegates: const [
        SlowReverbLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: SlowReverbLanguage.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) return supportedLocales.first;
        for (final supported in supportedLocales) {
          if (supported.languageCode == locale.languageCode) {
            return supported;
          }
        }
        return supportedLocales.first;
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: SlowReverbHomePage(
        onLocaleChanged: _handleLocaleChanged,
        onThemeChanged: _handleThemeChanged,
        themeMode: _themeMode,
      ),
    );
  }
}

class SlowReverbHomePage extends StatefulWidget {
  const SlowReverbHomePage({
    super.key,
    required this.onLocaleChanged,
    required this.onThemeChanged,
    required this.themeMode,
  });

  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode themeMode;

  @override
  State<SlowReverbHomePage> createState() => _SlowReverbHomePageState();
}

enum _HomeMenuAction { preview }

class _HelpDialogContent {
  const _HelpDialogContent({
    required this.title,
    required this.description,
    required this.closeLabel,
    required this.sections,
  });

  final String title;
  final String description;
  final String closeLabel;
  final List<_HelpDialogSection> sections;
}

class _HelpDialogSection {
  const _HelpDialogSection({
    required this.heading,
    required this.body,
  });

  final String heading;
  final String body;
}

class _SettingsRadioTile extends StatelessWidget {
  const _SettingsRadioTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      onTap: onTap,
    );
  }
}

const Map<String, _HelpDialogContent> _helpDialogContent =
    <String, _HelpDialogContent>{
  'id': _HelpDialogContent(
    title: 'Panduan Slow Reverb',
    description:
        'SlowReverb memproses file audio secara offline: tempo diperlambat, '
        'pitch diseimbangkan ulang, lalu efek reverb + echo diterapkan melalui FFmpeg '
        'atau mesin native realtime. Gunakan panduan ini untuk memahami alur kerja '
        'teknis setiap menu.',
    closeLabel: 'Tutup',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'Area Drop & Daftar File',
        body:
            'Tarik file audio atau tekan tombol pilih file untuk membangun antrian. '
            'Setiap entri menunjukkan ukuran, estimasi durasi output, dan status proses.',
      ),
      _HelpDialogSection(
        heading: 'Pengaturan Tempo & Preset',
        body:
            'Pilih mode otomatis atau manual untuk faktor tempo. Preset membantu '
            'menentukan campuran wet/dry dan karakter reverb dengan sekali klik.',
      ),
      _HelpDialogSection(
        heading: 'Kontrol Reverb Lanjutan',
        body:
            'Slider mengatur decay, pre-delay, high/low cut, stereo width, tone, '
            'dan echo tambahan. Semua perubahan otomatis mengantre pembaruan preview.',
      ),
      _HelpDialogSection(
        heading: 'Menu Preview',
        body:
            'Pada Android dengan mesin native tersedia preview realtime. Platform lain '
            'menggunakan FFmpeg untuk merender potongan pendek. Gunakan menu ini untuk '
            'memastikan karakter suara sebelum batch process.',
      ),
      _HelpDialogSection(
        heading: 'Output & FFmpeg',
        body:
            'Set output base folder, nama folder hasil, dan path FFmpeg. Data ini wajib '
            'agar file akhir dapat diekspor dengan sukses.',
      ),
      _HelpDialogSection(
        heading: 'Pengaturan & Kredit',
        body:
            'Menu pengaturan menyediakan tautan donasi Trakteer/Ko-fi, kredit GitHub dan ikon, '
            'serta sakelar bahasa dan tema terang/gelap permanen.',
      ),
      _HelpDialogSection(
        heading: 'Proses Batch & Monitoring',
        body:
            'Tekan "Proses Slow Reverb" untuk memulai. Progress bar menampilkan jumlah '
            'worker paralel, estimasi ukuran, dan pesan error bila terjadi kegagalan.',
      ),
    ],
  ),
  'en': _HelpDialogContent(
    title: 'Slow Reverb Guide',
    description:
        'SlowReverb runs offline processing: audio tempo is stretched, pitch is rebalanced, '
        'then reverb + echo chains are rendered via FFmpeg or the native realtime engine. '
        'Use this help to understand the technical flow behind every menu.',
    closeLabel: 'Close',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'Drop Area & File Queue',
        body:
            'Drag audio here or press the picker to build the queue. Each row shows size, '
            'estimated output duration, and the live processing status.',
      ),
      _HelpDialogSection(
        heading: 'Tempo Settings & Presets',
        body:
            'Choose automatic or manual tempo factors. Presets instantly set wet/dry mix '
            'and reverb character so you can keep a consistent sound.',
      ),
      _HelpDialogSection(
        heading: 'Advanced Reverb Controls',
        body:
            'Fine-tune decay, pre-delay, EQ cuts, stereo width, tone, and optional echo. '
            'Every tweak automatically schedules a preview refresh.',
      ),
      _HelpDialogSection(
        heading: 'Preview Menu',
        body:
            'Android devices with the native bridge get realtime preview. Other platforms '
            'render short snippets through FFmpeg. Use it to confirm tone before batch runs.',
      ),
      _HelpDialogSection(
        heading: 'Output & FFmpeg',
        body:
            'Define the base destination, output folder name, and FFmpeg binary path. These '
            'inputs are required for reliable exports.',
      ),
      _HelpDialogSection(
        heading: 'Settings & Credits',
        body:
            'Use the settings button to open donation links (Trakteer/Ko-fi), GitHub + icon credits, '
            'and persistent language plus light/dark theme toggles.',
      ),
      _HelpDialogSection(
        heading: 'Batch Processing & Monitoring',
        body:
            'Press "Process Slow Reverb" to launch the queue. Progress bars reflect parallel '
            'workers, estimated totals, and any failure messages.',
      ),
    ],
  ),
  'zh': _HelpDialogContent(
    title: '慢速混响指南',
    description:
        'SlowReverb 通过离线方式处理音频：拉伸节奏、重新平衡音高，并通过 FFmpeg 或原生实时引擎渲染混响与回声。使用本指南了解每个菜单背后的技术流程。',
    closeLabel: '关闭',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: '拖放区与文件队列',
        body:
            '把音频拖入或使用选择按钮建立队列。每一行都会显示大小、预估输出时长以及当前处理状态。',
      ),
      _HelpDialogSection(
        heading: '速度设置与预设',
        body:
            '选择自动或手动速度因子。预设可一键设置湿/干比例与混响性格，方便保持一致的声调。',
      ),
      _HelpDialogSection(
        heading: '高级混响控制',
        body:
            '微调衰减、预延迟、均衡切除、立体声宽度、音色以及可选回声。每次调整都会自动排队刷新预览。',
      ),
      _HelpDialogSection(
        heading: '预览菜单',
        body:
            'Android 原生桥接提供实时预览，其它平台使用 FFmpeg 渲染短片段。批处理前先确认声音风格。',
      ),
      _HelpDialogSection(
        heading: '输出与 FFmpeg',
        body:
            '设置输出根目录、结果文件夹名称以及 FFmpeg 可执行文件路径。这些输入是成功导出的前提。',
      ),
      _HelpDialogSection(
        heading: '设置与致谢',
        body:
            '通过设置按钮可打开 Trakteer/Ko-fi 捐助链接、GitHub 与图标署名，并切换持久的语言与明暗主题。',
      ),
      _HelpDialogSection(
        heading: '批量处理与监控',
        body:
            '点击“处理 Slow Reverb”开始队列。进度条会显示并行 worker 数量、估算总量以及任何失败信息。',
      ),
    ],
  ),
  'ja': _HelpDialogContent(
    title: 'スローレリーブガイド',
    description:
        'SlowReverb はオフラインで処理を行い、テンポを引き伸ばしてピッチを整え、FFmpeg もしくはネイティブのリアルタイムエンジンでリバーブとエコーを合成します。各メニューの技術的な流れをこのガイドで確認してください。',
    closeLabel: '閉じる',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'ドロップ領域とファイルキュー',
        body:
            '音声ファイルをドラッグするかボタンで追加してキューを作成します。各行にサイズ、推定出力時間、処理状況が表示されます。',
      ),
      _HelpDialogSection(
        heading: 'テンポ設定とプリセット',
        body:
            '自動または手動テンポを選択できます。プリセットはワンクリックでウェット/ドライ比とリバーブキャラクターを設定します。',
      ),
      _HelpDialogSection(
        heading: '高度なリバーブ制御',
        body:
            'ディケイ、プリディレイ、EQ カット、ステレオ幅、トーン、オプションのエコーを細かく調整できます。変更は自動的にプレビュー更新をスケジュールします。',
      ),
      _HelpDialogSection(
        heading: 'プレビューメニュー',
        body:
            'Android ではネイティブブリッジでリアルタイムプレビューが可能です。その他のプラットフォームは FFmpeg で短いクリップをレンダリングします。',
      ),
      _HelpDialogSection(
        heading: '出力と FFmpeg',
        body:
            '出力先フォルダー、フォルダー名、FFmpeg 実行ファイルを設定してください。これらは正しく書き出すために必須です。',
      ),
      _HelpDialogSection(
        heading: '設定とクレジット',
        body:
            '設定ボタンから Trakteer/Ko-fi 寄付リンク、GitHub とアイコンのクレジット、言語・ライト/ダークテーマの切替にアクセスできます。',
      ),
      _HelpDialogSection(
        heading: 'バッチ処理とモニタリング',
        body:
            '「Slow Reverb を処理」を押すとキューが開始します。進行バーには並列ワーカー数、推定サイズ、エラーメッセージが表示されます。',
      ),
    ],
  ),
  'ko': _HelpDialogContent(
    title: '슬로 리버브 가이드',
    description:
        'SlowReverb는 오프라인으로 작업하여 템포를 늘리고 피치를 보정한 뒤, FFmpeg 또는 네이티브 실시간 엔진으로 리버브와 에코 체인을 렌더링합니다. 이 가이드를 통해 각 메뉴의 기술 흐름을 이해하세요.',
    closeLabel: '닫기',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: '드롭 영역 및 파일 대기열',
        body:
            '오디오를 끌어다 놓거나 버튼으로 선택해 대기열을 만듭니다. 각 행에 파일 크기, 예상 출력 길이, 처리 상태가 표시됩니다.',
      ),
      _HelpDialogSection(
        heading: '템포 설정 및 프리셋',
        body:
            '자동 또는 수동 템포를 선택하세요. 프리셋은 웻/드라이 비율과 리버브 캐릭터를 한 번에 설정해 일정한 사운드를 유지합니다.',
      ),
      _HelpDialogSection(
        heading: '고급 리버브 제어',
        body:
            '디케이, 프리딜레이, EQ 컷, 스테레오 폭, 톤, 선택형 에코를 미세 조정합니다. 모든 변경 사항은 자동으로 프리뷰를 새로 고칩니다.',
      ),
      _HelpDialogSection(
        heading: '프리뷰 메뉴',
        body:
            'Android는 네이티브 브리지를 통해 실시간 프리뷰를 제공하며, 다른 플랫폼은 FFmpeg로 짧은 클립을 렌더링합니다.',
      ),
      _HelpDialogSection(
        heading: '출력 및 FFmpeg',
        body:
            '출력 기준 경로, 결과 폴더 이름, FFmpeg 실행 파일 경로를 지정하세요. 이는 내보내기 성공을 위한 필수 항목입니다.',
      ),
      _HelpDialogSection(
        heading: '설정 및 크레딧',
        body:
            '설정 버튼에서 Trakteer/Ko-fi 후원 링크, GitHub/아이콘 출처, 그리고 영구적인 언어·라이트/다크 테마 전환을 사용할 수 있습니다.',
      ),
      _HelpDialogSection(
        heading: '배치 처리 및 모니터링',
        body:
            '"Slow Reverb 처리"를 누르면 큐가 시작됩니다. 진행 막대는 병렬 작업자 수, 예상 총량, 실패 메시지를 보여 줍니다.',
      ),
    ],
  ),
  'ar': _HelpDialogContent(
    title: 'دليل SlowReverb',
    description:
        'يعالج SlowReverb الصوت دون اتصال عبر إطالة الإيقاع، وضبط طبقة الصوت، ثم توليد تأثيرات الريفربو والإيكو بواسطة FFmpeg أو المحرك الأصلي الفوري. استخدم هذا الدليل لفهم تدفق العمل التقني لكل قائمة.',
    closeLabel: 'إغلاق',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'منطقة الإسقاط وقائمة الملفات',
        body:
            'اسحب ملفات الصوت أو استخدم زر الاختيار لبناء قائمة الانتظار. كل صف يعرض الحجم، والمدة المتوقعة، وحالة المعالجة الحالية.',
      ),
      _HelpDialogSection(
        heading: 'إعدادات الإيقاع والقوالب الجاهزة',
        body:
            'اختر بين الإيقاع التلقائي أو اليدوي. القوالب تضبط نسبة المزج وشخصية الريفربو بلمسة واحدة للحفاظ على طابع موحد.',
      ),
      _HelpDialogSection(
        heading: 'ضوابط الريفربو المتقدمة',
        body:
            'اضبط زمن التلاشي، وتأخير البداية، ومرشحات التردد، وعرض الستريو، والنغمة، وخيار الإيكو. أي تغيير يضيف تحديثاً تلقائياً للمعاينة.',
      ),
      _HelpDialogSection(
        heading: 'قائمة المعاينة',
        body:
            'على أجهزة Android يوفر المحرك الأصلي معاينة فورية، بينما تستخدم باقي المنصات FFmpeg لتوليد مقاطع قصيرة.',
      ),
      _HelpDialogSection(
        heading: 'الإخراج و FFmpeg',
        body:
            'حدد مجلد الإخراج الأساسي، واسم مجلد النتائج، ومسار ملف FFmpeg التنفيذي. هذه الخطوات ضرورية لإنجاح عملية التصدير.',
      ),
      _HelpDialogSection(
        heading: 'الإعدادات والاعتمادات',
        body:
            'زر الإعدادات يفتح روابط التبرع Trakteer/Ko-fi، واعتمادات GitHub والأيقونة، بالإضافة إلى مفاتيح اللغة والوضع الفاتح/الداكن الدائمة.',
      ),
      _HelpDialogSection(
        heading: 'المعالجة الدفعية والمراقبة',
        body:
            'اضغط على "تشغيل Slow Reverb" لبدء قائمة الانتظار. تعرض أشرطة التقدم عدد العمال المتوازيين، والتقديرات الكلية، وأي رسائل خطأ.',
      ),
    ],
  ),
  'ru': _HelpDialogContent(
    title: 'Справочник по SlowReverb',
    description:
        'SlowReverb работает офлайн: растягивает темп, выравнивает питч и рендерит цепочку реверберации и эха через FFmpeg или нативный движок. Этот гид объясняет технический поток каждой панели.',
    closeLabel: 'Закрыть',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'Область перетаскивания и очередь файлов',
        body:
            'Перетащите аудио или добавьте через кнопку, чтобы сформировать очередь. В каждой строке отображаются размер, оценка длительности и статус обработки.',
      ),
      _HelpDialogSection(
        heading: 'Настройки темпа и пресеты',
        body:
            'Выберите автоматический или ручной коэффициент темпа. Пресеты мгновенно задают баланс wet/dry и характер реверберации.',
      ),
      _HelpDialogSection(
        heading: 'Расширенные настройки реверберации',
        body:
            'Точно настройте затухание, предзадержку, фильтры, ширину стерео, тембр и дополнительное эхо. Любое изменение автоматически планирует обновление предпросмотра.',
      ),
      _HelpDialogSection(
        heading: 'Меню предпросмотра',
        body:
            'На Android доступен нативный режим реального времени, на других платформах отрисовываются короткие клипы через FFmpeg.',
      ),
      _HelpDialogSection(
        heading: 'Вывод и FFmpeg',
        body:
            'Укажите базовую папку, имя папки результата и путь к исполняемому FFmpeg. Это обязательные параметры для успешного экспорта.',
      ),
      _HelpDialogSection(
        heading: 'Настройки и кредиты',
        body:
            'Кнопка настроек открывает ссылки на пожертвования Trakteer/Ko-fi, кредиты GitHub и иконки, а также постоянные переключатели языка и светлой/тёмной темы.',
      ),
      _HelpDialogSection(
        heading: 'Пакетная обработка и мониторинг',
        body:
            'Нажмите «Обработать Slow Reverb», чтобы запустить очередь. Индикаторы показывают число параллельных потоков, общий прогноз и сообщения об ошибках.',
      ),
    ],
  ),
  'hi': _HelpDialogContent(
    title: 'स्लो रिवर्ब मार्गदर्शिका',
    description:
        'SlowReverb ऑफ़लाइन तरीके से ऑडियो को प्रोसेस करता है: टेम्पो को खींचता है, पिच को संतुलित करता है और FFmpeg या नेटिव रियलटाइम इंजन से रीवरब व इको चेन रेंडर करता है। हर मेनू की तकनीकी प्रक्रिया समझने के लिए यह गाइड उपयोग करें।',
    closeLabel: 'बंद करें',
    sections: <_HelpDialogSection>[
      _HelpDialogSection(
        heading: 'ड्रॉप एरिया और फ़ाइल कतार',
        body:
            'ऑडियो फ़ाइलों को यहां खींचें या बटन से चुनें और कतार बनाएं। हर पंक्ति में आकार, अनुमानित आउटपुट अवधि और प्रोसेस की स्थिति दिखती है।',
      ),
      _HelpDialogSection(
        heading: 'टेम्पो सेटिंग्स और प्रीसेट',
        body:
            'ऑटो या मैनुअल टेम्पो चुनें। प्रीसेट एक क्लिक में वेट/ड्राई मिक्स और रीवरब कैरेक्टर सेट करते हैं ताकि टोन स्थिर रहे।',
      ),
      _HelpDialogSection(
        heading: 'एडवांस्ड रीवरब कंट्रोल',
        body:
            'डिके, प्री-डिले, EQ कट, स्टीरियो चौड़ाई, टोन और वैकल्पिक इको को बारीकी से समायोजित करें। हर बदलाव स्वतः प्रीव्यू अपडेट में जुड़ता है।',
      ),
      _HelpDialogSection(
        heading: 'प्रीव्यू मेनू',
        body:
            'Android पर नेटिव ब्रिज रियलटाइम प्रीव्यू देता है। अन्य प्लेटफॉर्म पर FFmpeg छोटे क्लिप रेंडर करता है, जिससे बैच प्रोसेस से पहले ध्वनि की पुष्टि हो सके।',
      ),
      _HelpDialogSection(
        heading: 'आउटपुट और FFmpeg',
        body:
            'आउटपुट बेस फ़ोल्डर, परिणाम फ़ोल्डर का नाम और FFmpeg पाथ सेट करें। सफल निर्यात के लिए ये आवश्यक है।',
      ),
      _HelpDialogSection(
        heading: 'सेटिंग्स और श्रेय',
        body:
            'सेटिंग्स बटन से Trakteer/Ko-fi दान लिंक, GitHub व आइकन क्रेडिट, और स्थायी भाषा तथा लाइट/डार्क थीम स्विच उपलब्ध हैं।',
      ),
      _HelpDialogSection(
        heading: 'बैच प्रोसेस और मॉनिटरिंग',
        body:
            '"Slow Reverb प्रोसेस" बटन दबाते ही कतार शुरू हो जाती है। प्रोग्रेस बार समानांतर वर्कर, अनुमानित आकार और किसी भी त्रुटि संदेश को दिखाता है।',
      ),
    ],
  ),
};

class _SlowReverbHomePageState extends State<SlowReverbHomePage> {
  static const _prefsKeyMusic = 'last_music_dir';
  static const _prefsKeyFfmpeg = 'last_ffmpeg_path';
  static const _defaultTempoFactor = 0.78;
  static const _maxParallelWorkers = 4;
  static const _defaultWetMix = 0.24;
  static const _defaultDecaySeconds = 6.0;
  static const _defaultPreDelayMs = 35.0;
  static const _defaultRoomSize = 0.8;
  static const _defaultHighCutHz = 6000.0;
  static const _defaultLowCutHzUser = 200.0;
  static const _defaultStereoWidth = 1.2;
  static const _defaultTone = 0.6;
  static const _defaultEchoMs = 0.0;
  static const _livePreviewDebounce = Duration(milliseconds: 600);
  static const _defaultFfmpegPath =
      r'D:\mylib\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe';
  static const _logFilePath = r'C:\Users\Luqman\Downloads\slowreverb-logs.txt';
  static const _allowedExtensions = <String>[
    'mp3',
    'wav',
    'flac',
    'aac',
    'm4a',
    'ogg',
    'wma',
    'aiff',
  ];
  static const _donationTrakteerUrl = 'https://trakteer.id/Ian7672';
  static const _donationKoFiUrl = 'https://ko-fi.com/Ian7672';
  static const _githubProfileUrl = 'https://github.com/Ian7672';
  static const _iconSourceUrl =
      'https://www.flaticon.com/free-icon/slow-down_2326176?term=slowed+music&page=1&position=35&origin=search&related_id=2326176';

  final List<AudioJob> _jobs = [];
  final Queue<AudioJob> _jobQueue = Queue<AudioJob>();
  final TextEditingController _outputFolderController = TextEditingController();
  final TextEditingController _ffmpegController = TextEditingController();
  final AudioPlayer _previewPlayer = AudioPlayer();
  final NativeAudioBridge _nativeAudio = NativeAudioBridge.instance;

  bool _isProcessing = false;
  bool _isDragging = false;
  bool _useManualSettings = false;
  double _manualTempo = _defaultTempoFactor;
  AudioJob? _selectedPreviewJob;
  AudioJob? _previewingJob;
  double _mixLevel = _defaultWetMix;
  double _decayTimeSeconds = _defaultDecaySeconds;
  double _preDelayMsSetting = _defaultPreDelayMs;
  double _roomSize = _defaultRoomSize;
  double _highCutHz = _defaultHighCutHz;
  double _lowCutHz = _defaultLowCutHzUser;
  double _stereoWidth = _defaultStereoWidth;
  double _toneBalance = _defaultTone;
  double _echoBeforeReverbMs = _defaultEchoMs;
  ReverbPreset? _activePreset = ReverbPreset.chill;
  bool _isGeneratingPreview = false;
  bool _isPreviewing = false;
  Duration? _previewTotalDuration;
  Duration? _previewPosition;
  Timer? _previewUpdateTimer;
  Timer? _nativeProgressTimer;
  StreamSubscription<PlayerState>? _previewStateSub;
  StreamSubscription<Duration?>? _previewDurationSub;
  StreamSubscription<Duration>? _previewPositionSub;
  Directory? _previewTempDirectory;
  String? _previewTempPath;
  String? _previewStatusMessage;
  SharedPreferences? _prefs;
  String? _outputBaseDirectory;
  String? _lastMusicDirectory;
  String? _ffmpegPath;
  String? _cachedFfprobePath;
  bool _ffprobeChecked = false;
  int _estimatedTotalBytes = 0;
  int _nativePreviewHandle = 0;
  bool _nativePreviewActive = false;

  double get _currentTempo =>
      _useManualSettings ? _manualTempo : _defaultTempoFactor;
  String? get _resolvedOutputDirectory {
    final base = _outputBaseDirectory;
    final folder = _outputFolderController.text.trim();
    if (base == null || base.isEmpty || folder.isEmpty) return null;
    return p.join(base, folder);
  }
  bool get _supportsNativeRealtimePreview =>
      !kIsWeb && Platform.isAndroid && _nativeAudio.isAvailable;
  bool get _isRealtimePreviewPlaying =>
      _supportsNativeRealtimePreview && _nativePreviewActive;

  double get _wetMix => _mixLevel.clamp(0.0, 1.0);
  double get _dryMix => (1 - _wetMix).clamp(0.0, 1.0);
  double get _padSecondsValue =>
      math.max(3.0, _decayTimeSeconds * 0.45 + _roomSize * 2.2);
  double get _wetHighCut =>
      (_highCutHz * (0.75 + _toneBalance * 0.45)).clamp(3000.0, 12000.0);
  double get _wetLowCut =>
      (_lowCutHz * (0.9 - _toneBalance * 0.3)).clamp(120.0, 420.0);
  double get _antiAliasCutoff =>
      math.max(6000, math.min(12000, _highCutHz + 800));
  static const double _subsonicCutHz = 30.0;

  String get _currentLanguageCode {
    final locale = Localizations.localeOf(context);
    return SlowReverbLocalizations._normalizeLanguageCode(locale.languageCode);
  }

  String _sanitizeFolderName(String name) {
    final sanitized = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return sanitized.isEmpty
        ? 'SlowReverb_${_timestampString(DateTime.now())}'
        : sanitized;
  }

  Future<void> _setFolderNameIfEmpty(String suggestion) async {
    if (_outputFolderController.text.trim().isNotEmpty) return;
    final sanitized = _sanitizeFolderName(suggestion);
    if (!mounted) return;
    setState(() {
      _outputFolderController.text = sanitized;
    });
  }

  Future<void> _logError(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message\n';
    try {
      final file = File(_logFilePath);
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // ignore logging failures
    }
  }

  void _setManualMode(bool manual) {
    if (_useManualSettings == manual) return;
    setState(() {
      _useManualSettings = manual;
    });
    _recalculateEstimates();
    _queuePreviewUpdate();
  }

  void _onManualTempoChanged(double value) {
    setState(() {
      _manualTempo = value;
    });
    _recalculateEstimates();
    _queuePreviewUpdate();
  }

  _HelpDialogContent _resolveHelpContent(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (_helpDialogContent.containsKey(code)) {
      return _helpDialogContent[code]!;
    }
    if (code.startsWith('id')) {
      return _helpDialogContent['id']!;
    }
    return _helpDialogContent['en']!;
  }

  String _localeDisplayTag(Locale locale) {
    final country = locale.countryCode;
    return country != null && country.isNotEmpty
        ? '${locale.languageCode}-$country'
        : locale.languageCode;
  }

  void _showHelpDialog() {
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final content = _resolveHelpContent(locale);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text('${content.title} (${_localeDisplayTag(locale)})'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(content.description),
                const SizedBox(height: 12),
                ...content.sections.map(
                  (section) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.heading,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(section.body),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(content.closeLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchExternalLink(String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnack(context.tr('settings.openLinkError'));
      }
    } catch (_) {
      if (mounted) {
        _showSnack(context.tr('settings.openLinkError'));
      }
    }
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final langCode =
            SlowReverbLocalizations._normalizeLanguageCode(_currentLanguageCode);
        final themeMode = widget.themeMode;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetContext.tr('settings.title'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  sheetContext.tr('settings.supportHeading'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  sheetContext.tr('settings.supportDescription'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.volunteer_activism_outlined),
                        title: Text(sheetContext.tr('settings.trakteerTitle')),
                        subtitle:
                            Text(sheetContext.tr('settings.trakteerSubtitle')),
                        onTap: () => _launchExternalLink(_donationTrakteerUrl),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.coffee_outlined),
                        title: Text(sheetContext.tr('settings.kofiTitle')),
                        subtitle:
                            Text(sheetContext.tr('settings.kofiSubtitle')),
                        onTap: () => _launchExternalLink(_donationKoFiUrl),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  sheetContext.tr('settings.creditHeading'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.code_outlined),
                        title: Text(sheetContext.tr('settings.githubTitle')),
                        subtitle:
                            Text(sheetContext.tr('settings.githubSubtitle')),
                        onTap: () => _launchExternalLink(_githubProfileUrl),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.image_outlined),
                        title: Text(sheetContext.tr('settings.iconCreditTitle')),
                        subtitle: Text(
                          sheetContext.tr('settings.iconCreditSubtitle'),
                        ),
                        onTap: () => _launchExternalLink(_iconSourceUrl),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sheetContext.tr('settings.creditNote'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  sheetContext.tr('settings.themeHeading'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  sheetContext.tr('settings.themeDescription'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      _SettingsRadioTile(
                        icon: Icons.brightness_auto_outlined,
                        label: sheetContext.tr('settings.themeSystem'),
                        selected: themeMode == ThemeMode.system,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onThemeChanged(ThemeMode.system);
                        },
                      ),
                      const Divider(height: 0),
                      _SettingsRadioTile(
                        icon: Icons.light_mode_outlined,
                        label: sheetContext.tr('settings.themeLight'),
                        selected: themeMode == ThemeMode.light,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onThemeChanged(ThemeMode.light);
                        },
                      ),
                      const Divider(height: 0),
                      _SettingsRadioTile(
                        icon: Icons.dark_mode_outlined,
                        label: sheetContext.tr('settings.themeDark'),
                        selected: themeMode == ThemeMode.dark,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onThemeChanged(ThemeMode.dark);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  sheetContext.tr('settings.languageHeading'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  sheetContext.tr('settings.languageDescription'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: SlowReverbLanguage.supported.map((language) {
                      void selectLanguage() {
                        Navigator.of(sheetContext).pop();
                        widget.onLocaleChanged(Locale(language.code));
                      }

                      final selected = language.code == langCode;
                      return ListTile(
                        dense: true,
                        onTap: selectLanguage,
                        leading: Text(language.code.toUpperCase()),
                        title: Text(language.displayName),
                        trailing: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _previewStateSub = _previewPlayer.playerStateStream.listen(
      _handlePreviewState,
    );
    _previewDurationSub = _previewPlayer.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        _previewTotalDuration = duration;
      });
    });
    _previewPositionSub = _previewPlayer.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _previewPosition = position;
      });
    });
    _loadPreferences();
    if (_supportsNativeRealtimePreview) {
      _nativePreviewHandle = _nativeAudio.createHandle();
    }
  }

  @override
  void dispose() {
    _outputFolderController.dispose();
    _ffmpegController.dispose();
    _previewStateSub?.cancel();
    _previewDurationSub?.cancel();
    _previewPositionSub?.cancel();
    _previewUpdateTimer?.cancel();
    _nativeProgressTimer?.cancel();
    unawaited(_previewPlayer.dispose());
    unawaited(_cleanupPreviewFiles());
    if (_supportsNativeRealtimePreview && _nativePreviewHandle != 0) {
      _nativeAudio.stop(_nativePreviewHandle);
      _nativeAudio.dispose(_nativePreviewHandle);
      _nativePreviewHandle = 0;
    }
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _lastMusicDirectory = prefs.getString(_prefsKeyMusic);
      _ffmpegPath = prefs.getString(_prefsKeyFfmpeg) ?? _defaultFfmpegPath;
    });
    _outputBaseDirectory = null;
    _outputFolderController.text = '';
    _ffmpegController.text = _ffmpegPath ?? '';
  }

  void _handlePreviewState(PlayerState state) {
    if (state.processingState == ProcessingState.completed) {
      _handlePreviewFinished();
      return;
    }
    if (!mounted) return;
    setState(() {
      _isPreviewing =
          state.playing &&
          state.processingState != ProcessingState.idle &&
          state.processingState != ProcessingState.completed;
    });
  }

  void _handlePreviewFinished() {
    unawaited(_cleanupPreviewFiles());
    _previewUpdateTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _previewingJob = null;
      _previewStatusMessage = context.tr('preview.status.completed');
      _previewPosition = Duration.zero;
      _isPreviewing = false;
    });
  }

  Future<void> _cleanupPreviewFiles() async {
    final tempPath = _previewTempPath;
    final tempDir = _previewTempDirectory;
    _previewTempPath = null;
    _previewTempDirectory = null;
    if (tempPath != null) {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    if (tempDir != null) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _stopNativePreview() async {
    if (!_supportsNativeRealtimePreview) return;
    _nativeProgressTimer?.cancel();
    if (_nativePreviewHandle != 0) {
      _nativeAudio.stop(_nativePreviewHandle);
    }
    if (!mounted) return;
    setState(() {
      _nativePreviewActive = false;
      _isPreviewing = false;
      _previewingJob = null;
    });
  }

  void _handleNativePreviewFinished() {
    if (!_supportsNativeRealtimePreview) return;
    _nativeProgressTimer?.cancel();
    if (_nativePreviewHandle != 0) {
      _nativeAudio.stop(_nativePreviewHandle);
    }
    if (!mounted) return;
    setState(() {
      _nativePreviewActive = false;
      _isPreviewing = false;
      _previewingJob = null;
      _previewStatusMessage = context.tr('preview.status.completed');
    });
  }

  void _startNativeProgressTimer() {
    if (!_supportsNativeRealtimePreview || _nativePreviewHandle == 0) return;
    _nativeProgressTimer?.cancel();
    _nativeProgressTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_nativePreviewActive || !mounted) return;
      final positionMs =
          _nativeAudio.positionMs(_nativePreviewHandle).round();
      final durationMs =
          _nativeAudio.durationMs(_nativePreviewHandle).round();
      if (!mounted) return;
      setState(() {
        _previewPosition = Duration(milliseconds: positionMs);
        if (durationMs > 0) {
          _previewTotalDuration = Duration(milliseconds: durationMs);
        }
      });
      final total = _previewTotalDuration;
      final position = _previewPosition;
      if (total != null &&
          position != null &&
          total.inMilliseconds > 0 &&
          position >= total) {
        _handleNativePreviewFinished();
      }
    });
  }

  void _applyNativeRealtimeParameters() {
    if (!_isRealtimePreviewPlaying || _nativePreviewHandle == 0) return;
    final tempo = _currentTempo.clamp(0.5, 1.5);
    final pitchRatio = _pitchFactorForTempo(tempo);
    final pitchSemi = _ratioToSemitone(pitchRatio);
    _nativeAudio.setTempo(_nativePreviewHandle, tempo);
    _nativeAudio.setPitch(_nativePreviewHandle, pitchSemi);
    _nativeAudio.setMix(_nativePreviewHandle, _wetMix);
    _nativeAudio.setReverb(
      _nativePreviewHandle,
      decay: _decayTimeSeconds,
      tone: _toneBalance,
      room: _roomSize,
      echoMs: _echoBeforeReverbMs,
    );
    if (mounted) {
      setState(() {
        _previewStatusMessage = context.tr('preview.status.parameters');
      });
    }
  }

  Future<void> _startNativePreview(
    AudioJob job, {
    bool triggeredByLiveUpdate = false,
  }) async {
    if (!_supportsNativeRealtimePreview) return;
    if (_nativePreviewHandle == 0) {
      _nativePreviewHandle = _nativeAudio.createHandle();
      if (_nativePreviewHandle == 0) {
        _showSnack(context.tr('preview.status.nativeFallback'));
        await _preparePreview(
          job,
          triggeredByLiveUpdate: triggeredByLiveUpdate,
        );
        return;
      }
    }
    if (triggeredByLiveUpdate &&
        _nativePreviewActive &&
        _previewingJob?.inputPath == job.inputPath) {
      _applyNativeRealtimeParameters();
      return;
    }
    await _stopNativePreview();
    final startResult = _nativeAudio.start(
      _nativePreviewHandle,
      job.inputPath,
    );
    if (startResult != 0) {
      if (!mounted) return;
      _showSnack(
        context.tr(
          'preview.status.nativeFailed',
          params: {'code': '$startResult'},
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _nativePreviewActive = true;
      _isPreviewing = true;
      _previewingJob = job;
      _previewStatusMessage = triggeredByLiveUpdate
          ? context.tr(
              'preview.status.updatingRealtime',
              params: {'file': job.fileName},
            )
          : context.tr(
              'preview.status.playRealtime',
              params: {'file': job.fileName},
            );
      _previewTotalDuration =
          _estimatedDurationForJob(job) ?? _previewTotalDuration;
      _previewPosition = Duration.zero;
      _isGeneratingPreview = false;
    });
    _applyNativeRealtimeParameters();
    _startNativeProgressTimer();
  }

  void _queuePreviewUpdate() {
    if (_isRealtimePreviewPlaying) {
      _applyNativeRealtimeParameters();
      return;
    }
    if (_previewingJob == null || _isGeneratingPreview) return;
    _previewUpdateTimer?.cancel();
    _previewUpdateTimer = Timer(_livePreviewDebounce, () {
      if (!mounted) return;
      final job = _previewingJob ?? _selectedPreviewJob;
      if (job == null) return;
      unawaited(_startPreview(job: job, triggeredByLiveUpdate: true));
    });
  }

  Future<void> _stopPreview() async {
    _previewUpdateTimer?.cancel();
    if (_isRealtimePreviewPlaying) {
      await _stopNativePreview();
    } else {
      await _previewPlayer.stop();
      await _previewPlayer.seek(Duration.zero);
      await _cleanupPreviewFiles();
    }
    if (!mounted) return;
    setState(() {
      if (_previewingJob != null || _isPreviewing || _isGeneratingPreview) {
        _previewStatusMessage = context.tr('preview.status.stopped');
      }
      _previewingJob = null;
      _isPreviewing = false;
      _isGeneratingPreview = false;
      _previewPosition = Duration.zero;
      _previewTotalDuration = null;
    });
  }

  void _applyPreset(ReverbPreset preset) {
    final config = _presetConfigs[preset]!;
    setState(() {
      _mixLevel = config.mix;
      _decayTimeSeconds = config.decaySeconds;
      _preDelayMsSetting = config.preDelayMs;
      _roomSize = config.roomSize;
      _highCutHz = config.highCutHz;
      _lowCutHz = config.lowCutHz;
      _stereoWidth = config.stereoWidth;
      _toneBalance = config.tone;
      _echoBeforeReverbMs = config.echoMs;
      _activePreset = preset;
    });
    _queuePreviewUpdate();
  }

  void _restoreDefaultReverb() {
    _applyPreset(ReverbPreset.chill);
  }

  void _updateReverbValue(void Function() updates) {
    setState(() {
      updates();
      _activePreset = null;
    });
    _queuePreviewUpdate();
  }

  String _roomSizeLabel(double value) {
    if (value < 0.25) return 'Ruang Mini';
    if (value < 0.5) return 'Studio';
    if (value < 0.75) return 'Hall';
    if (value < 0.9) return 'Katedral';
    return 'Huge';
  }

  String _toneLabel(double value) {
    if (value < 0.33) return 'Gelap';
    if (value > 0.66) return 'Cerah';
    return 'Netral';
  }

  Future<void> _startPreview({
    AudioJob? job,
    bool triggeredByLiveUpdate = false,
  }) async {
    final targetJob = job ?? _selectedPreviewJob;
    if (targetJob == null) {
      _showSnack('Tambahkan dan pilih file musik terlebih dahulu.');
      return;
    }
    if (_supportsNativeRealtimePreview) {
      await _startNativePreview(
        targetJob,
        triggeredByLiveUpdate: triggeredByLiveUpdate,
      );
      return;
    }
    if (_isGeneratingPreview) {
      _showSnack(context.tr('preview.status.preparing'));
      return;
    }
    await _preparePreview(
      targetJob,
      triggeredByLiveUpdate: triggeredByLiveUpdate,
    );
  }

  Future<void> _preparePreview(
    AudioJob job, {
    bool triggeredByLiveUpdate = false,
  }) async {
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath == null || !await File(ffmpegPath).exists()) {
      _showSnack('Path FFmpeg tidak valid. Atur terlebih dahulu.');
      return;
    }
    if (!mounted) return;
    _previewUpdateTimer?.cancel();
    setState(() {
      _isGeneratingPreview = true;
      _previewStatusMessage = triggeredByLiveUpdate
          ? 'Memperbarui preview ${job.fileName}...'
          : 'Menyiapkan preview untuk ${job.fileName}...';
      _previewingJob = job;
    });
    final shouldResume = triggeredByLiveUpdate && _previewPosition != null;
    final lastKnownDuration = _previewTotalDuration;
    final lastKnownPosition = shouldResume
        ? _previewPlayer.position
        : Duration.zero;
    final lastRatio = (shouldResume &&
            lastKnownDuration != null &&
            lastKnownDuration.inMilliseconds > 0)
        ? lastKnownPosition.inMilliseconds /
            lastKnownDuration.inMilliseconds
        : null;
    await _previewPlayer.stop();
    await _previewPlayer.seek(Duration.zero);
    await _cleanupPreviewFiles();
    try {
      final tempDir = await Directory.systemTemp.createTemp(
        'slowreverb_preview_',
      );
      final previewPath = p.join(
        tempDir.path,
        '${p.basenameWithoutExtension(job.fileName)}_preview.wav',
      );
      _previewTempDirectory = tempDir;
      _previewTempPath = previewPath;
      final filter = _buildFilterChain(job);
      final args = <String>[
        '-y',
        '-i',
        job.inputPath,
        '-filter_complex',
        filter,
        '-acodec',
        'pcm_s16le',
        '-ar',
        '48000',
        '-ac',
        '2',
        previewPath,
      ];
      final previewResult = await _executeFfmpegOnce(ffmpegPath, args);
      final exitCode = previewResult['exitCode'] as int? ?? -1;
      final stderrMessage = (previewResult['stderr'] as String?)?.trim() ?? '';
      if (exitCode != 0) {
        throw Exception(
          stderrMessage.isNotEmpty
              ? stderrMessage
              : 'FFmpeg gagal dengan kode $exitCode.',
        );
      }
      final loadedDuration = await _previewPlayer.setFilePath(previewPath);
      Duration targetSeek = Duration.zero;
      if (shouldResume) {
        final referenceDuration = loadedDuration ?? lastKnownDuration;
        if (referenceDuration != null &&
            referenceDuration.inMilliseconds > 0) {
          final ratio = lastRatio ??
              (lastKnownDuration != null &&
                      lastKnownDuration.inMilliseconds > 0
                  ? lastKnownPosition.inMilliseconds /
                      lastKnownDuration.inMilliseconds
                  : null);
          if (ratio != null && ratio.isFinite && ratio >= 0) {
            final clampedMs = ratio.clamp(0.0, 1.0) *
                referenceDuration.inMilliseconds;
            targetSeek = Duration(milliseconds: clampedMs.round());
          } else {
            targetSeek = lastKnownPosition;
          }
        } else {
          targetSeek = lastKnownPosition;
        }
      }
      if (targetSeek > Duration.zero) {
        await _previewPlayer.seek(targetSeek);
      }
      await _previewPlayer.play();
      if (!mounted) return;
      setState(() {
      _previewStatusMessage = triggeredByLiveUpdate
          ? context.tr('preview.status.updatedLive')
          : context.tr(
              'preview.status.rendered',
              params: {'file': job.fileName},
            );
        _previewTotalDuration =
            loadedDuration ?? _estimatedDurationForJob(job);
        _previewPosition = targetSeek;
      });
    } catch (error) {
      await _cleanupPreviewFiles();
      if (!mounted) return;
      setState(() {
        _previewingJob = null;
      final message =
          context.tr('preview.status.error', params: {'error': '$error'});
      _previewStatusMessage = message;
      });
      _showSnack(
        context.tr('preview.status.error', params: {'error': '$error'}),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPreview = false;
        });
      }
    }
  }

  bool get _dropSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> _pickAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      initialDirectory: _lastMusicDirectory,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
    );
    if (result == null) return;
    final paths = result.paths.whereType<String>();
    await _ingestPaths(paths);
  }

  Future<void> _ingestPaths(Iterable<String> rawPaths) async {
    final expanded = await _expandDroppedPaths(rawPaths);
    final additions = <AudioJob>[];
    for (final path in expanded) {
      if (!_isSupportedExtension(path)) continue;
      if (_jobs.any((job) => job.inputPath == path)) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final size = await file.length();
      final metadata = await _readAudioMetadata(path);
      additions.add(
        AudioJob(
          inputPath: path,
          originalSize: size,
          durationMs: metadata?.durationMs,
          bitRate: metadata?.bitRate,
        ),
      );
    }
    if (additions.isEmpty) {
      if (mounted) _showSnack('Tidak ada file audio baru yang bisa diproses.');
      return;
    }
    additions.sort((a, b) => a.fileName.compareTo(b.fileName));
    final parentDir = p.dirname(additions.first.inputPath);
    if (!mounted) return;
    setState(() {
      _jobs.addAll(additions);
      _estimatedTotalBytes = _calculateEstimatedBytes();
      _selectedPreviewJob ??= _jobs.first;
    });
    _lastMusicDirectory = parentDir;
    await _prefs?.setString(_prefsKeyMusic, parentDir);
    await _setOutputBaseDirectory(parentDir);
    final folderSuggestion = p.basenameWithoutExtension(
      additions.first.fileName,
    );
    if (mounted) {
      setState(() {
        _outputFolderController.text = _sanitizeFolderName(folderSuggestion);
      });
    }
  }

  Future<List<String>> _expandDroppedPaths(Iterable<String> paths) async {
    final results = <String>[];
    for (final path in paths) {
      if (path.isEmpty) continue;
      FileSystemEntityType type;
      try {
        type = FileSystemEntity.typeSync(path, followLinks: false);
      } catch (_) {
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        final dir = Directory(path);
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && _isSupportedExtension(entity.path)) {
            results.add(entity.path);
          }
        }
      } else if (type == FileSystemEntityType.file) {
        results.add(path);
      }
    }
    return results;
  }

  bool _isSupportedExtension(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _allowedExtensions.contains(ext);
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    final paths = details.files.map((f) => f.path).whereType<String>();
    await _ingestPaths(paths);
  }

  Future<void> _browseOutput() async {
    final path = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _outputBaseDirectory ?? _lastMusicDirectory,
    );
    if (path == null) return;
    await _setOutputBaseDirectory(path);
  }

  Future<void> _setOutputBaseDirectory(String path) async {
    if (!mounted) return;
    setState(() {
      _outputBaseDirectory = path;
    });
    await _ensureDefaultFolderName();
  }

  Future<void> _handleFolderNameSubmitted(String name) async {
    final sanitized = _sanitizeFolderName(name);
    if (sanitized.isEmpty) {
      _showSnack('Masukkan nama folder output terlebih dahulu.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _outputFolderController.text = sanitized;
    });
  }

  Future<void> _setFfmpegPath(String path) async {
    if (!mounted) return;
    setState(() {
      _ffmpegPath = path;
      _cachedFfprobePath = null;
      _ffprobeChecked = false;
    });
    _ffmpegController.text = path;
    await _prefs?.setString(_prefsKeyFfmpeg, path);
  }

  Future<void> _handleManualFfmpegSubmitted(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      await _logError('Path FFmpeg kosong dimasukkan.');
      _showSnack('Masukkan path FFmpeg terlebih dahulu.');
      return;
    }
    final file = File(trimmed);
    if (!await file.exists()) {
      await _logError('Path FFmpeg tidak ditemukan: $trimmed');
      _showSnack('File FFmpeg tidak ditemukan.');
      return;
    }
    await _setFfmpegPath(trimmed);
  }

  Future<void> _browseFfmpegExecutable() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih FFmpeg',
      type: FileType.custom,
      allowedExtensions: Platform.isWindows ? ['exe'] : null,
      initialDirectory: _ffmpegPath != null
          ? p.dirname(_ffmpegPath!)
          : _lastMusicDirectory,
    );
    final path = result?.files.first.path;
    if (path == null) return;
    await _handleManualFfmpegSubmitted(path);
  }

  Future<AudioMetadata?> _readAudioMetadata(String path) async {
    final ffprobePath = await _getFfprobePath();
    if (ffprobePath == null) return null;
    try {
      final result = await Process.run(
        ffprobePath,
        ['-v', 'quiet', '-print_format', 'json', '-show_format', path],
        runInShell: Platform.isWindows,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        return null;
      }
      final Map<String, dynamic> data = jsonDecode(result.stdout);
      final format = data['format'] as Map<String, dynamic>?;
      final durationStr = format?['duration']?.toString();
      final bitrateStr = format?['bit_rate']?.toString();
      final duration = durationStr != null
          ? double.tryParse(durationStr)
          : null;
      final bitrate = bitrateStr != null ? int.tryParse(bitrateStr) : null;
      return AudioMetadata(
        durationMs: duration != null ? (duration * 1000).round() : null,
        bitRate: bitrate,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getFfprobePath() async {
    if (_cachedFfprobePath != null) {
      return _cachedFfprobePath;
    }
    if (_ffprobeChecked && _cachedFfprobePath == null) {
      return null;
    }
    final ffmpegPath = _ffmpegPath;
    if (ffmpegPath != null) {
      final ffmpegFile = File(ffmpegPath);
      final dir = ffmpegFile.parent.path;
      final candidate = p.join(
        dir,
        Platform.isWindows ? 'ffprobe.exe' : 'ffprobe',
      );
      if (await File(candidate).exists()) {
        _cachedFfprobePath = candidate;
        _ffprobeChecked = true;
        return candidate;
      }
    }
    final fallback = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    try {
      final result = await Process.run(fallback, [
        '-version',
      ], runInShell: Platform.isWindows);
      if (result.exitCode == 0) {
        _cachedFfprobePath = fallback;
        _ffprobeChecked = true;
        return fallback;
      }
    } catch (_) {
      _ffprobeChecked = true;
      _cachedFfprobePath = null;
      return null;
    }
    _ffprobeChecked = true;
    return null;
  }

  Future<void> _removeJob(AudioJob job) async {
    if (_isProcessing) return;
    final wasPreviewing = _previewingJob == job;
    setState(() {
      _jobs.remove(job);
      _estimatedTotalBytes = _calculateEstimatedBytes();
      if (_jobs.isEmpty) {
        _selectedPreviewJob = null;
      } else if (_selectedPreviewJob == job) {
        _selectedPreviewJob = _jobs.first;
      }
    });
    if (wasPreviewing) {
      await _stopPreview();
    }
  }

  Future<void> _clearJobs() async {
    if (_isProcessing) return;
    await _stopPreview();
    setState(() {
      _jobs.clear();
      _estimatedTotalBytes = 0;
      _outputBaseDirectory = null;
      _selectedPreviewJob = null;
    });
  }

  Future<void> _startProcessing() async {
    if (_jobs.isEmpty) {
      _showSnack('Pilih file musik terlebih dahulu.');
      return;
    }
    if (_outputFolderController.text.trim().isEmpty) {
      await _logError('Nama folder output kosong saat mulai proses.');
      _showSnack('Masukkan nama folder output terlebih dahulu.');
      return;
    }
    try {
      await _ensureOutputDirectoryAvailable(p.dirname(_jobs.first.inputPath));
    } catch (_) {
      return;
    }
    final resolvedOutput = _resolvedOutputDirectory;
    if (resolvedOutput == null) {
      await _logError('Folder output belum ditentukan setelah validasi.');
      _showSnack('Gagal menyiapkan folder output.');
      return;
    }
    if (_ffmpegPath == null || !await File(_ffmpegPath!).exists()) {
      await _logError('FFmpeg path tidak valid: ${_ffmpegPath ?? '(null)'}');
      _showSnack('Path FFmpeg tidak valid. Atur terlebih dahulu.');
      return;
    }
    setState(() {
      _isProcessing = true;
      for (final job in _jobs) {
        job
          ..status = JobStatus.pending
          ..errorMessage = null
          ..outputPath = null
          ..producedSize = 0
          ..progress = 0.0;
      }
      _jobQueue
        ..clear()
        ..addAll(_jobs);
    });
    final parallelism = math.max(
      1,
      math.min(_maxParallelWorkers, Platform.numberOfProcessors),
    );
    final workers = <Future<void>>[];
    for (var i = 0; i < parallelism; i++) {
      workers.add(_consumeQueue());
    }
    await Future.wait(workers);
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _consumeQueue() async {
    while (_jobQueue.isNotEmpty) {
      final job = _jobQueue.removeFirst();
      await _processJob(job);
    }
  }

  Future<void> _processJob(AudioJob job) async {
    if (!mounted) return;
    setState(() {
      job.status = JobStatus.processing;
      job.progress = 0.0;
    });
    final outputDir = _resolvedOutputDirectory;
    if (outputDir == null) {
      await _logError('Folder output tidak tersedia untuk ${job.fileName}.');
      setState(() {
        job
          ..status = JobStatus.failed
          ..errorMessage = 'Folder output tidak tersedia.'
          ..progress = 1.0;
      });
      return;
    }
    final fileName =
        '${p.basenameWithoutExtension(job.inputPath)}_slowreverb${p.extension(job.inputPath)}';
    final outputPath = p.join(outputDir, fileName);
    job.outputPath = outputPath;
    final filter = _buildFilterChain(job);
    final args = <String>[
      '-y',
      '-i',
      job.inputPath,
      '-filter_complex',
      filter,
      ..._codecArgsForOutput(outputPath, job),
      '-progress',
      'pipe:1',
      '-nostats',
      outputPath,
    ];
    Process? process;
    try {
      process = await Process.start(_ffmpegPath!, args, runInShell: false);
    } catch (error) {
      await _logError('Gagal menjalankan FFmpeg untuk ${job.fileName}: $error');
      if (!mounted) return;
      setState(() {
        job.status = JobStatus.failed;
        job.errorMessage = 'Gagal menjalankan FFmpeg: $error';
      });
      return;
    }

    final stderrBuffer = StringBuffer();
    final totalDurationMs = job.estimatedOutputDurationMs(_currentTempo);
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.contains('=')) return;
          final parts = trimmed.split('=');
          if (parts.length != 2) return;
          final key = parts[0];
          final value = parts[1];
          if (key == 'out_time_ms') {
            final currentMs = int.tryParse(value) ?? 0;
            if (totalDurationMs > 0) {
              final fraction = currentMs / totalDurationMs;
              _updateJobProgress(job, fraction);
            }
          } else if (key == 'progress' && value == 'end') {
            _updateJobProgress(job, 1.0);
          }
        });

    process.stderr
        .transform(utf8.decoder)
        .listen((line) => stderrBuffer.writeln(line));

    final exitCode = await process.exitCode;
    await stdoutSub.cancel();
    if (exitCode == 0) {
      final producedSize = await _readFileSize(outputPath);
      if (!mounted) return;
      setState(() {
        job.status = JobStatus.completed;
        job.producedSize = producedSize;
        job.progress = 1.0;
      });
    } else {
      final stderrMessage = stderrBuffer.toString().trim();
      await _logError(
        'FFmpeg gagal (${job.fileName}) kode $exitCode: ${stderrMessage.isEmpty ? 'unknown' : stderrMessage}',
      );
      if (!mounted) return;
      setState(() {
        job.status = JobStatus.failed;
        job.errorMessage = stderrMessage.isNotEmpty
            ? stderrMessage
            : 'FFmpeg gagal (kode $exitCode).';
        job.progress = 1.0;
      });
    }
  }

  List<String> _codecArgsForOutput(String outputPath, AudioJob job) {
    final ext = p.extension(outputPath).toLowerCase();
    const lossyExtensions = {'.mp3', '.aac', '.m4a', '.ogg', '.wma'};
    if (!lossyExtensions.contains(ext)) {
      return const [];
    }
    final bitrate = job.effectiveBitRate() ?? 192000;
    final kbps = math.max(64, (bitrate / 1000).round());
    return ['-b:a', '${kbps}k'];
  }

  String _buildFilterChain(AudioJob job) {
    final tempo = _currentTempo.clamp(0.4, 0.95);
    final pitchFactor = _pitchFactorForTempo(tempo);
    final correctedTempo = (tempo / pitchFactor).clamp(0.5, 2.0);
    final wetRatio = _wetMix;
    final dryRatio = _dryMix;
    final padSeconds = _padSecondsValue;
    final preDelay = _preDelayMsSetting.round();
    final echoDelay = _echoBeforeReverbMs.round();
    final hasEchoTap = echoDelay >= 5;
    final wetHighCut = _wetHighCut.round();
    final wetLowCut = _wetLowCut.round();
    const sampleRate = 48000;

    final wetPrefilterList = <String>[
      if (preDelay > 0) 'adelay=$preDelay|$preDelay',
      if (hasEchoTap)
        'aecho=0.4:0.55:$echoDelay:${(0.25 + wetRatio * 0.15).toStringAsFixed(2)}',
      'lowpass=f=$wetHighCut',
      'highpass=f=$wetLowCut',
    ];
    final baseDelay = 140 + _roomSize * 520;
    final hallDelay = baseDelay * (1.6 + _roomSize * 0.3);
    final tailDelay = baseDelay * (2.3 + _roomSize * 0.4);
    final baseDecay = (0.32 + (_decayTimeSeconds / 12) * 0.4)
        .clamp(0.18, 0.92)
        .toStringAsFixed(2);
    final hallDecay = (0.26 + (_decayTimeSeconds / 12) * 0.35)
        .clamp(0.15, 0.85)
        .toStringAsFixed(2);
    final tailDecay = (0.22 + (_decayTimeSeconds / 12) * 0.3)
        .clamp(0.12, 0.8)
        .toStringAsFixed(2);
    final multiTapChain = [
      'aecho=0.55:0.68:${baseDelay.round()}:$baseDecay',
      'aecho=0.4:0.6:${hallDelay.round()}:$hallDecay',
      'aecho=0.3:0.5:${tailDelay.round()}:$tailDecay',
    ];
    final wetChainSteps = [
      ...wetPrefilterList,
      ...multiTapChain,
      'apad=pad_dur=${(padSeconds * 1.2).toStringAsFixed(2)},alimiter=limit=0.97',
    ]..removeWhere((step) => step.isEmpty);
    final wetChain = wetChainSteps.join(',');

    final baseChain = [
      'aformat=sample_fmts=fltp:channel_layouts=stereo:sample_rates=$sampleRate',
      'highpass=f=$_subsonicCutHz',
      'aresample=$sampleRate:async=1:first_pts=0',
      'asetrate=${(sampleRate * pitchFactor).round()}',
      'aresample=$sampleRate',
      ..._tempoFilters(correctedTempo),
      'lowpass=f=${_antiAliasCutoff.round()}',
      ..._correctiveEqFilters(),
      'dynaudnorm=f=250:g=14',
      'acompressor=threshold=-16dB:ratio=1.8:attack=25:release=320',
      'asplit=2[dry][pre]',
    ].join(',');

    final width = _stereoWidth.clamp(0.0, 2.0);
    final leftLeft = 0.5 * (1 + width);
    final leftRight = 0.5 * (1 - width);
    final rightLeft = leftRight;
    final rightRight = leftLeft;
    final panFilter =
        'pan=stereo|c0=${leftLeft.toStringAsFixed(3)}*FL+${leftRight.toStringAsFixed(3)}*FR|c1=${rightLeft.toStringAsFixed(3)}*FL+${rightRight.toStringAsFixed(3)}*FR';

    final buffer = StringBuffer()
      ..write('[0:a]$baseChain;')
      ..write('[pre]$wetChain[wet];')
      ..write('[dry]volume=${dryRatio.toStringAsFixed(3)}[drymix];')
      ..write('[wet]volume=${wetRatio.toStringAsFixed(3)}[wetmix];')
      ..write('[drymix][wetmix]amix=inputs=2:normalize=0[mixout];')
      ..write(
        '[mixout]$panFilter,alimiter=limit=0.97,apad=pad_dur=${padSeconds.toStringAsFixed(2)}',
      );
    return buffer.toString();
  }

  double _pitchFactorForTempo(double tempo) {
    final drop = 0.08 + (1 - tempo) * 0.12;
    final candidate = tempo - drop;
    final minPitch = math.max(0.35, tempo * 0.55);
    const maxPitch = 0.92;
    return math.max(minPitch, math.min(candidate, maxPitch));
  }

  double _ratioToSemitone(double ratio) {
    if (ratio <= 0) return 0;
    return 12 * (math.log(ratio) / math.log(2));
  }

  List<String> _tempoFilters(double tempo) {
    final filters = <String>[];
    double remaining = tempo;
    while (remaining < 0.5) {
      filters.add('atempo=0.5');
      remaining /= 0.5;
    }
    while (remaining > 2.0) {
      filters.add('atempo=2.0');
      remaining /= 2.0;
    }
    filters.add('atempo=${remaining.toStringAsFixed(3)}');
    return filters;
  }

  Future<int> _readFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  void _updateJobProgress(AudioJob job, double value) {
    if (!mounted) return;
    setState(() {
      job.progress = value.clamp(0.0, 1.0);
    });
  }

  Future<void> _ensureOutputDirectoryAvailable(String fallbackBase) async {
    try {
      if ((_outputBaseDirectory ?? '').trim().isEmpty) {
        await _setOutputBaseDirectory(fallbackBase);
      }
      if (_outputFolderController.text.trim().isEmpty) {
        await _ensureDefaultFolderName();
      }
      final resolved = _resolvedOutputDirectory;
      if (resolved == null) {
        throw Exception('Folder output belum ditentukan.');
      }
      final baseDir = Directory(_outputBaseDirectory!);
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      final dir = Directory(resolved);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (error) {
      await _logError('Gagal menyiapkan folder output: $error');
      _showSnack('Gagal menyiapkan folder output: $error');
      rethrow;
    }
  }

  Future<void> _ensureDefaultFolderName() async {
    if (_outputFolderController.text.trim().isNotEmpty) return;
    final suggestion = 'SlowReverb_${_timestampString(DateTime.now())}';
    await _setFolderNameIfEmpty(suggestion);
  }

  int _calculateEstimatedBytes() {
    return _jobs.fold<int>(
      0,
      (total, job) => total + job.estimatedOutputBytes(_currentTempo),
    );
  }

  void _recalculateEstimates() {
    if (!mounted) return;
    setState(() {
      _estimatedTotalBytes = _calculateEstimatedBytes();
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    final digitGroups = (math.log(bytes) / math.log(1024)).floor();
    final value = bytes / math.pow(1024, digitGroups);
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[digitGroups]}';
  }

  String _formatDurationLabel(Duration? duration) {
    if (duration == null) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes
        .remainder(60)
        .abs()
        .toString()
        .padLeft(2, '0');
    final seconds = duration.inSeconds
        .remainder(60)
        .abs()
        .toString()
        .padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  List<String> _correctiveEqFilters() {
    final bassCut = (-2.2 - _roomSize * 2.0).clamp(-5.0, -1.5);
    final harshCut = (-1.2 - (1 - _toneBalance) * 1.5).clamp(-3.5, -0.8);
    final airBoost = (_toneBalance * 1.4).clamp(0.0, 1.2);
    return [
      'equalizer=f=250:t=q:w=1.1:g=${bassCut.toStringAsFixed(1)}',
      'equalizer=f=4200:t=q:w=1.0:g=${harshCut.toStringAsFixed(1)}',
      'equalizer=f=10500:t=h:w=0.8:g=${airBoost.toStringAsFixed(1)}',
    ];
  }

  Duration? _estimatedDurationForJob(AudioJob job) {
    final ms = job.estimatedOutputDurationMs(_currentTempo);
    if (ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  @override
  Widget build(BuildContext context) {
    final finishedJobs = _jobs
        .where(
          (job) =>
              job.status == JobStatus.completed ||
              job.status == JobStatus.failed,
        )
        .length;
    final failedJobs = _jobs
        .where((job) => job.status == JobStatus.failed)
        .length;
    final fileProgress = _jobs.isEmpty
        ? 0.0
        : _jobs.fold<double>(0, (total, job) => total + job.progress) /
              _jobs.length;
    final parallelism = math.max(
      1,
      math.min(_maxParallelWorkers, Platform.numberOfProcessors),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        actions: [
          IconButton(
            tooltip: context.tr('settings.tooltip'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettingsSheet,
          ),
          IconButton(
            tooltip: context.tr('help.tooltip'),
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          PopupMenuButton<_HomeMenuAction>(
            tooltip: context.tr('menu.more'),
            onSelected: (action) {
              if (action == _HomeMenuAction.preview) {
                _openPreviewSheet();
              }
            },
            itemBuilder: (menuContext) => [
              PopupMenuItem(
                value: _HomeMenuAction.preview,
                child: Text(menuContext.tr('menu.openPreview')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final jobListHeight = math.max(
              220.0,
              constraints.maxHeight - 420.0,
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropZone(context),
                  const SizedBox(height: 16),
                  _buildTempoSettings(),
                  const SizedBox(height: 16),
                  _buildReverbControls(),
                  const SizedBox(height: 16),
                  _buildOutputSelector(context),
                  const SizedBox(height: 16),
                  _buildFfmpegSelector(context),
                  const SizedBox(height: 16),
                  _buildPreviewMenu(context),
                  const SizedBox(height: 16),
                  _buildProgressSummary(
                    fileProgress,
                    finishedJobs,
                    failedJobs,
                    parallelism,
                    _jobs.length,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(height: jobListHeight, child: _buildJobList()),
                  const SizedBox(height: 16),
                  _buildActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openPreviewSheet() {
    if (_jobs.isEmpty) {
      _showSnack(context.tr('error.addFilesFirst'));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildPreviewMenu(context, embedded: false),
          ),
        );
      },
    );
  }

  Widget _buildDropZone(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = _isDragging
        ? colorScheme.secondary
        : Theme.of(context).dividerColor;
    final zone = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
        color: colorScheme.surfaceContainerHighest.withValues(
          alpha: _isDragging ? 0.4 : 0.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            _dropSupported
                ? context.tr('drop.supported')
                : context.tr('drop.unsupported'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _pickAudioFiles,
                icon: const Icon(Icons.folder_open),
                label: Text(context.tr('drop.browse')),
              ),
              TextButton.icon(
                onPressed: _isProcessing || _jobs.isEmpty
                    ? null
                    : () => _clearJobs(),
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('drop.clear')),
              ),
            ],
          ),
        ],
      ),
    );
    if (!_dropSupported) {
      return zone;
    }
    return DropTarget(
      enable: !_isProcessing,
      onDragDone: _handleDrop,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: zone,
    );
  }

  Widget _buildTempoSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pengaturan Slow Reverb'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Default'),
                  selected: !_useManualSettings,
                  onSelected: _isProcessing
                      ? null
                      : (_) => _setManualMode(false),
                ),
                ChoiceChip(
                  label: const Text('Manual'),
                  selected: _useManualSettings,
                  onSelected: _isProcessing
                      ? null
                      : (_) => _setManualMode(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Tempo: ${(_currentTempo * 100).toStringAsFixed(0)}%'),
            if (_useManualSettings)
              Slider(
                value: _manualTempo,
                min: 0.4,
                max: 1.0,
                divisions: 12,
                label: '${(_manualTempo * 100).round()}%',
                onChanged: _isProcessing ? null : _onManualTempoChanged,
              )
            else
              const Text('Preset bawaan: tempo 78%, reverb halus yang nyaman.'),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledSlider({
    required String title,
    required String subtitle,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              Text(valueLabel, style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.textTheme.bodySmall),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildReverbControls() {
    final theme = Theme.of(context);
    final toneLabel = _toneLabel(_toneBalance);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Karakter Slow Reverb',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _restoreDefaultReverb,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Pilih preset favorit, lalu sesuaikan slider dengan istilah yang mudah dimengerti.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _buildPresetSelector(),
            const Divider(height: 32),
            _buildLabeledSlider(
              title: 'Kekuatan Efek (Wet/Dry)',
              subtitle: '0% = kering, 100% = penuh reverb',
              valueLabel: '${(_mixLevel * 100).round()}%',
              value: _mixLevel,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => _updateReverbValue(() => _mixLevel = v),
            ),
            _buildLabeledSlider(
              title: 'Panjang Gema',
              subtitle: 'Durasi ekor reverb dalam detik',
              valueLabel: '${_decayTimeSeconds.toStringAsFixed(1)} dtk',
              value: _decayTimeSeconds,
              min: 1,
              max: 12,
              divisions: 22,
              onChanged: (v) => _updateReverbValue(() => _decayTimeSeconds = v),
            ),
            _buildLabeledSlider(
              title: 'Pre-Delay (Jeda sebelum gema)',
              subtitle: 'Jaga vokal tetap jelas',
              valueLabel: '${_preDelayMsSetting.round()} ms',
              value: _preDelayMsSetting,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) =>
                  _updateReverbValue(() => _preDelayMsSetting = v),
            ),
            _buildLabeledSlider(
              title: 'Ukuran Ruang',
              subtitle: 'Small → Huge (${_roomSizeLabel(_roomSize)})',
              valueLabel: '${(_roomSize * 100).round()}%',
              value: _roomSize,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => _updateReverbValue(() => _roomSize = v),
            ),
            _buildLabeledSlider(
              title: 'High Cut (Low-pass)',
              subtitle: 'Lembutkan frekuensi tinggi pada efek',
              valueLabel: '${_highCutHz.round()} Hz',
              value: _highCutHz,
              min: 3000,
              max: 12000,
              divisions: 30,
              onChanged: (v) => _updateReverbValue(() => _highCutHz = v),
            ),
            _buildLabeledSlider(
              title: 'Low Cut (High-pass)',
              subtitle: 'Kurangi frekuensi rendah yang bikin muddy',
              valueLabel: '${_lowCutHz.round()} Hz',
              value: _lowCutHz,
              min: 80,
              max: 400,
              divisions: 32,
              onChanged: (v) => _updateReverbValue(() => _lowCutHz = v),
            ),
            _buildLabeledSlider(
              title: 'Stereo Width',
              subtitle: 'Lebar ruang (100% = natural)',
              valueLabel: '${(_stereoWidth * 100).round()}%',
              value: _stereoWidth,
              min: 0,
              max: 2,
              divisions: 40,
              onChanged: (v) => _updateReverbValue(() => _stereoWidth = v),
            ),
            _buildLabeledSlider(
              title: 'Reverb Tone',
              subtitle: 'Dark ↔ Bright ($toneLabel)',
              valueLabel: '${(_toneBalance * 100).round()}%',
              value: _toneBalance,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => _updateReverbValue(() => _toneBalance = v),
            ),
            _buildLabeledSlider(
              title: 'Delay Tambahan (Echo)',
              subtitle: 'Aktifkan untuk preset Dreamy atau efek luas',
              valueLabel: _echoBeforeReverbMs <= 1
                  ? 'Off'
                  : '${_echoBeforeReverbMs.round()} ms',
              value: _echoBeforeReverbMs,
              min: 0,
              max: 200,
              divisions: 40,
              onChanged: (v) =>
                  _updateReverbValue(() => _echoBeforeReverbMs = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ReverbPreset.values.map((preset) {
        final config = _presetConfigs[preset]!;
        final selected = _activePreset == preset;
        return ChoiceChip(
          label: Text('${config.emoji} ${config.label}'),
          selected: selected,
          tooltip: config.description,
          onSelected: (_) => _applyPreset(preset),
        );
      }).toList(),
    );
  }

  Widget _buildPreviewMenu(BuildContext context, {bool embedded = true}) {
    final hasJobs = _jobs.isNotEmpty;
    final theme = Theme.of(context);
    final AudioJob? activeSelection =
        hasJobs &&
            _selectedPreviewJob != null &&
            _jobs.contains(_selectedPreviewJob)
        ? _selectedPreviewJob
        : (hasJobs ? _jobs.first : null);

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              context.tr('preview.title'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (embedded)
            IconButton(
              tooltip: context.tr('preview.openInSheet'),
              onPressed: hasJobs ? _openPreviewSheet : null,
              icon: const Icon(Icons.open_in_new),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        _supportsNativeRealtimePreview
            ? context.tr('preview.realtimeDescription')
            : context.tr('preview.ffmpegDescription'),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (!hasJobs)
        Text(context.tr('preview.emptyPrompt'))
      else
        DropdownButtonFormField<AudioJob>(
          initialValue: activeSelection,
          decoration: InputDecoration(
            labelText: context.tr('preview.dropdownLabel'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: _jobs
              .map(
                (job) => DropdownMenuItem<AudioJob>(
                  value: job,
                  child: Text(job.fileName, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _isGeneratingPreview
              ? null
              : (job) {
                  if (job == null) return;
                  setState(() {
                    _selectedPreviewJob = job;
                  });
                },
        ),
      if (hasJobs) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _isGeneratingPreview ? null : () => _startPreview(),
              icon: _isGeneratingPreview
                  ? const Icon(Icons.hourglass_bottom)
                  : const Icon(Icons.play_arrow),
              label: Text(
                _isGeneratingPreview
                    ? context.tr('preview.buttonPreparing')
                    : context.tr('preview.buttonPlay'),
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  (!_isGeneratingPreview &&
                      !_isPreviewing &&
                      _previewingJob == null)
                  ? null
                  : () => _stopPreview(),
              icon: const Icon(Icons.stop),
              label: Text(context.tr('preview.buttonStop')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isGeneratingPreview) const LinearProgressIndicator(),
        if (_previewStatusMessage?.isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text(
            _previewStatusMessage!,
            style: TextStyle(
              color: _previewStatusMessage!.toLowerCase().contains('gagal')
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_isPreviewing ||
            (_previewPosition != null && _previewTotalDuration != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildPreviewProgressIndicator(),
          ),
      ],
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    if (!embedded) {
      return content;
    }

    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: content),
    );
  }

  Widget _buildPreviewProgressIndicator() {
    final total = _previewTotalDuration;
    final position = _previewPosition ?? Duration.zero;
    double? value;
    if (total != null && total.inMilliseconds > 0) {
      value = (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    } else {
      value = _isPreviewing ? null : 0.0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: value),
        const SizedBox(height: 4),
        Text(
          '${_formatDurationLabel(position)} / ${_formatDurationLabel(total)}',
        ),
      ],
    );
  }

  Widget _buildOutputSelector(BuildContext context) {
    final basePath = _outputBaseDirectory;
    final baseDisplay = basePath ??
        (_jobs.isEmpty
            ? context.tr('output.baseEmptyBefore')
            : context.tr('output.baseUnset'));
    final folderEmpty = _outputFolderController.text.trim().isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('output.baseTitle')),
                      const SizedBox(height: 4),
                      Text(
                        baseDisplay,
                        style: TextStyle(
                          color: basePath == null ? Colors.orange : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _browseOutput,
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.tr('output.changeButton')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _outputFolderController,
              enabled: !_isProcessing,
              decoration: InputDecoration(
                labelText: context.tr('output.folderLabel'),
                hintText: context.tr('output.folderHint'),
                border: const OutlineInputBorder(),
                errorText: basePath != null && folderEmpty
                    ? context.tr('output.folderError')
                    : null,
                isDense: true,
              ),
              onChanged: (value) {
                if (mounted) {
                  setState(() {});
                }
              },
              onSubmitted: _isProcessing ? null : _handleFolderNameSubmitted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFfmpegSelector(BuildContext context) {
    final missing = _ffmpegPath == null || !File(_ffmpegPath!).existsSync();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('ffmpeg.title')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ffmpegController,
                    enabled: !_isProcessing,
                    decoration: InputDecoration(
                      hintText: context.tr('ffmpeg.hint'),
                      border: const OutlineInputBorder(),
                      errorText:
                          missing ? context.tr('ffmpeg.errorMissing') : null,
                      isDense: true,
                    ),
                    onSubmitted: _isProcessing
                        ? null
                        : (value) => _handleManualFfmpegSubmitted(value),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _browseFfmpegExecutable,
              icon: const Icon(Icons.build),
              label: Text(context.tr('ffmpeg.browse')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSummary(
    double fileProgress,
    int finishedJobs,
    int failedJobs,
    int parallelism,
    int totalJobs,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'File selesai: $finishedJobs/$totalJobs (gagal: $failedJobs)',
                  ),
                ),
                Text('Worker paralel: $parallelism'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: fileProgress),
            const SizedBox(height: 12),
            Text('Progres file: ${(fileProgress * 100).toStringAsFixed(0)}%'),
            Text('Estimasi total: ${_formatBytes(_estimatedTotalBytes)}'),
          ],
        ),
      ),
    );
  }

  Widget _buildJobList() {
    if (_jobs.isEmpty) {
      return const Center(child: Text('Belum ada file yang siap diproses.'));
    }
    return ListView.separated(
      itemCount: _jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final job = _jobs[index];
        return Card(
          child: ListTile(
            leading: Icon(
              _iconForStatus(job.status),
              color: _colorForStatus(job.status),
            ),
            title: Text(job.fileName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asal: ${p.dirname(job.inputPath)}'),
                Text(
                  'Estimasi output: ${_formatBytes(job.estimatedOutputBytes(_currentTempo))}',
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: job.progress),
                if (job.status == JobStatus.completed)
                  Text('Hasil: ${_formatBytes(job.producedSize)}'),
                if (job.status == JobStatus.failed && job.errorMessage != null)
                  Text(
                    job.errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Hapus',
              onPressed: _isProcessing ? null : () => _removeJob(job),
            ),
          ),
        );
      },
    );
  }

  IconData _iconForStatus(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return Icons.hourglass_empty;
      case JobStatus.processing:
        return Icons.sync;
      case JobStatus.completed:
        return Icons.check_circle;
      case JobStatus.failed:
        return Icons.error_outline;
    }
  }

  Color? _colorForStatus(JobStatus status) {
    switch (status) {
      case JobStatus.pending:
        return Colors.grey;
      case JobStatus.processing:
        return Colors.blueAccent;
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.failed:
        return Colors.red;
    }
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isProcessing ? null : _startProcessing,
            icon: const Icon(Icons.slow_motion_video),
            label: Text(
              _isProcessing
                  ? context.tr('actions.processing')
                  : context.tr('actions.process'),
            ),
          ),
        ),
      ],
    );
  }
}

class AudioJob {
  AudioJob({
    required this.inputPath,
    required this.originalSize,
    this.durationMs,
    this.bitRate,
  });

  final String inputPath;
  final int originalSize;
  final int? durationMs;
  final int? bitRate;
  JobStatus status = JobStatus.pending;
  String? errorMessage;
  String? outputPath;
  int producedSize = 0;
  double progress = 0.0;

  String get fileName => p.basename(inputPath);

  int estimatedOutputBytes(double tempoFactor) {
    if (tempoFactor <= 0) return originalSize;
    final duration = estimatedOutputDurationMs(tempoFactor);
    if (duration > 0) {
      final effectiveBitrate = bitRate ?? derivedBitRate();
      if (effectiveBitrate != null && effectiveBitrate > 0) {
        final bytes = (effectiveBitrate / 8.0) * (duration / 1000.0);
        return bytes.round();
      }
    }
    return (originalSize / tempoFactor).round();
  }

  int estimatedOutputDurationMs(double tempoFactor) {
    if (durationMs == null || tempoFactor <= 0) return 0;
    return (durationMs! / tempoFactor).round();
  }

  int? effectiveBitRate() {
    if (bitRate != null && bitRate! > 0) {
      return bitRate;
    }
    return derivedBitRate();
  }

  int? derivedBitRate() {
    if (durationMs == null || durationMs! <= 0) return null;
    final seconds = durationMs! / 1000.0;
    if (seconds <= 0) return null;
    final bits = originalSize * 8;
    return (bits / seconds).round();
  }
}

class AudioMetadata {
  const AudioMetadata({this.durationMs, this.bitRate});

  final int? durationMs;
  final int? bitRate;
}

enum JobStatus { pending, processing, completed, failed }

String _timestampString(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}_${two(time.hour)}${two(time.minute)}${two(time.second)}';
}

Future<Map<String, Object?>> _executeFfmpegOnce(
  String ffmpegPath,
  List<String> args,
) async {
  final process = await Process.run(
    ffmpegPath,
    args,
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return <String, Object?>{
    'exitCode': process.exitCode,
    'stderr': (process.stderr ?? '').toString(),
  };
}

enum ReverbPreset { chill, sad, dreamy, vocal, extreme }

class _ReverbPresetConfig {
  const _ReverbPresetConfig({
    required this.label,
    required this.emoji,
    required this.description,
    required this.mix,
    required this.decaySeconds,
    required this.preDelayMs,
    required this.roomSize,
    required this.highCutHz,
    required this.lowCutHz,
    required this.stereoWidth,
    required this.tone,
    required this.echoMs,
  });

  final String label;
  final String emoji;
  final String description;
  final double mix;
  final double decaySeconds;
  final double preDelayMs;
  final double roomSize;
  final double highCutHz;
  final double lowCutHz;
  final double stereoWidth;
  final double tone;
  final double echoMs;
}

const Map<ReverbPreset, _ReverbPresetConfig> _presetConfigs =
    <ReverbPreset, _ReverbPresetConfig>{
      ReverbPreset.chill: _ReverbPresetConfig(
        label: 'Chill',
        emoji: '🎧',
        description: 'Lembut dan santai untuk hampir semua lagu.',
        mix: 0.40,
        decaySeconds: 6.0,
        preDelayMs: 35,
        roomSize: 0.8,
        highCutHz: 6000,
        lowCutHz: 200,
        stereoWidth: 1.2,
        tone: 0.6,
        echoMs: 0,
      ),
      ReverbPreset.sad: _ReverbPresetConfig(
        label: 'Sad / Melancholy',
        emoji: '🌙',
        description: 'Sedikit lebih gelap & panjang untuk nuansa sendu.',
        mix: 0.45,
        decaySeconds: 7.5,
        preDelayMs: 28,
        roomSize: 0.85,
        highCutHz: 5600,
        lowCutHz: 220,
        stereoWidth: 1.25,
        tone: 0.5,
        echoMs: 0,
      ),
      ReverbPreset.dreamy: _ReverbPresetConfig(
        label: 'Dreamy',
        emoji: '🌌',
        description: 'Ekor panjang + echo pendek untuk efek mimpi.',
        mix: 0.55,
        decaySeconds: 9.0,
        preDelayMs: 40,
        roomSize: 0.95,
        highCutHz: 5200,
        lowCutHz: 160,
        stereoWidth: 1.5,
        tone: 0.55,
        echoMs: 40,
      ),
      ReverbPreset.vocal: _ReverbPresetConfig(
        label: 'Vocal Focus',
        emoji: '🎤',
        description: 'Jaga mid tetap jernih untuk cover vokal.',
        mix: 0.35,
        decaySeconds: 5.0,
        preDelayMs: 25,
        roomSize: 0.7,
        highCutHz: 7000,
        lowCutHz: 230,
        stereoWidth: 1.1,
        tone: 0.65,
        echoMs: 0,
      ),
      ReverbPreset.extreme: _ReverbPresetConfig(
        label: 'Extreme',
        emoji: '🔥',
        description: 'Slow reverb super panjang untuk eksperimen.',
        mix: 0.65,
        decaySeconds: 11.0,
        preDelayMs: 50,
        roomSize: 1.0,
        highCutHz: 5200,
        lowCutHz: 180,
        stereoWidth: 1.6,
        tone: 0.5,
        echoMs: 60,
      ),
    };

class SlowReverbLanguage {
  const SlowReverbLanguage({
    required this.code,
    required this.displayName,
  });

  final String code;
  final String displayName;

  static const List<SlowReverbLanguage> supported = <SlowReverbLanguage>[
    SlowReverbLanguage(code: 'en', displayName: 'English'),
    SlowReverbLanguage(code: 'id', displayName: 'Bahasa Indonesia'),
    SlowReverbLanguage(code: 'zh', displayName: '中文'),
    SlowReverbLanguage(code: 'ja', displayName: '日本語'),
    SlowReverbLanguage(code: 'ko', displayName: '한국어'),
    SlowReverbLanguage(code: 'ar', displayName: 'العربية'),
    SlowReverbLanguage(code: 'ru', displayName: 'Русский'),
    SlowReverbLanguage(code: 'hi', displayName: 'हिन्दी'),
  ];
  static List<Locale> get supportedLocales =>
      supported.map((lang) => Locale(lang.code)).toList(growable: false);
}

class SlowReverbLocalizations {
  SlowReverbLocalizations(this.locale);

  final Locale locale;

  static const Map<String, Map<String, String>> _localizedValues =
      <String, Map<String, String>>{
    'app.title': {
      'en': 'Slow Reverb Studio',
      'id': 'Slow Reverb Musik',
      'zh': '慢速混响工作室',
      'ja': 'スローレリーブスタジオ',
      'ko': '슬로 리버브 스튜디오',
      'ar': 'استوديو Slow Reverb',
      'ru': 'Студия Slow Reverb',
      'hi': 'स्लो रिवर्ब स्टूडियो',
    },
    'settings.tooltip': {
      'en': 'Settings',
      'id': 'Pengaturan',
      'zh': '设置',
      'ja': '設定',
      'ko': '설정',
      'ar': 'الإعدادات',
      'ru': 'Настройки',
      'hi': 'सेटिंग्स',
    },
    'help.tooltip': {
      'en': 'Help',
      'id': 'Bantuan',
      'zh': '帮助',
      'ja': 'ヘルプ',
      'ko': '도움말',
      'ar': 'مساعدة',
      'ru': 'Справка',
      'hi': 'मदद',
    },
    'menu.more': {
      'en': 'More options',
      'id': 'Menu lainnya',
      'zh': '更多选项',
      'ja': 'その他のメニュー',
      'ko': '추가 옵션',
      'ar': 'خيارات إضافية',
      'ru': 'Дополнительно',
      'hi': 'अधिक विकल्प',
    },
    'menu.openPreview': {
      'en': 'Open preview panel',
      'id': 'Buka panel preview',
      'zh': '打开预览面板',
      'ja': 'プレビューパネルを開く',
      'ko': '프리뷰 패널 열기',
      'ar': 'فتح لوحة المعاينة',
      'ru': 'Открыть панель превью',
      'hi': 'प्रीव्यू पैनल खोलें',
    },
    'settings.openLinkError': {
      'en': 'Unable to open the link.',
      'id': 'Tidak bisa membuka tautan.',
      'zh': '无法打开该链接。',
      'ja': 'リンクを開けませんでした。',
      'ko': '링크를 열 수 없습니다.',
      'ar': 'تعذر فتح الرابط.',
      'ru': 'Не удалось открыть ссылку.',
      'hi': 'लिंक नहीं खुल सका।',
    },
    'settings.title': {
      'en': 'Settings',
      'id': 'Pengaturan',
      'zh': '设置',
      'ja': '設定',
      'ko': '설정',
      'ar': 'الإعدادات',
      'ru': 'Настройки',
      'hi': 'सेटिंग्स',
    },
    'settings.supportHeading': {
      'en': 'Support SlowReverb',
      'id': 'Dukung SlowReverb',
      'zh': '支持 SlowReverb',
      'ja': 'SlowReverb を支援',
      'ko': 'SlowReverb 후원',
      'ar': 'ادعم SlowReverb',
      'ru': 'Поддержать SlowReverb',
      'hi': 'SlowReverb को समर्थन दें',
    },
    'settings.supportDescription': {
      'en': 'Donations keep the project alive.',
      'id': 'Donasi membantu proyek tetap berjalan.',
      'zh': '捐助能让项目持续发展。',
      'ja': '寄付がプロジェクト継続の力になります。',
      'ko': '후원이 프로젝트를 지속시킵니다.',
      'ar': 'التبرعات تبقي المشروع مستمراً.',
      'ru': 'Пожертвования поддерживают проект.',
      'hi': 'दान से परियोजना चालू रहती है।',
    },
    'settings.trakteerTitle': {
      'en': 'Trakteer (IDR)',
      'id': 'Trakteer (IDR)',
      'zh': 'Trakteer（印尼盾）',
      'ja': 'Trakteer（IDR）',
      'ko': 'Trakteer (루피아)',
      'ar': 'Trakteer (روبية)',
      'ru': 'Trakteer (IDR)',
      'hi': 'Trakteer (IDR)',
    },
    'settings.trakteerSubtitle': {
      'en': 'Local support for Indonesia.',
      'id': 'Dukungan lokal untuk Indonesia.',
      'zh': '面向印尼的本地支持。',
      'ja': 'インドネシア向けのローカル支援です。',
      'ko': '인도네시아 이용자를 위한 후원 채널입니다.',
      'ar': 'دعم محلي لمستخدمي إندونيسيا.',
      'ru': 'Локальная поддержка для Индонезии.',
      'hi': 'इंडोनेशिया के समर्थकों के लिए।',
    },
    'settings.kofiTitle': {
      'en': 'Ko-fi (USD)',
      'id': 'Ko-fi (USD)',
      'zh': 'Ko-fi（美元）',
      'ja': 'Ko-fi（USD）',
      'ko': 'Ko-fi (달러)',
      'ar': 'Ko-fi (دولار أمريكي)',
      'ru': 'Ko-fi (USD)',
      'hi': 'Ko-fi (USD)',
    },
    'settings.kofiSubtitle': {
      'en': 'Global donations via Ko-fi.',
      'id': 'Donasi global melalui Ko-fi.',
      'zh': '通过 Ko-fi 接受全球捐助。',
      'ja': 'Ko-fi で世界中から支援できます。',
      'ko': '전 세계 어디서나 Ko-fi로 후원하세요.',
      'ar': 'تبرعات عالمية عبر Ko-fi.',
      'ru': 'Глобальные пожертвования через Ko-fi.',
      'hi': 'Ko-fi से वैश्विक दान स्वीकार करें।',
    },
    'settings.creditHeading': {
      'en': 'Credits & Licensing',
      'id': 'Kredit & Lisensi',
      'zh': '致谢与授权',
      'ja': 'クレジットとライセンス',
      'ko': '크레딧 및 라이선스',
      'ar': 'اعتمادات وترخيص',
      'ru': 'Благодарности и лицензия',
      'hi': 'श्रेय और लाइसेंस',
    },
    'settings.githubTitle': {
      'en': 'GitHub – Ian7672',
      'id': 'GitHub – Ian7672',
      'zh': 'GitHub – Ian7672',
      'ja': 'GitHub – Ian7672',
      'ko': 'GitHub – Ian7672',
      'ar': 'GitHub – Ian7672',
      'ru': 'GitHub – Ian7672',
      'hi': 'GitHub – Ian7672',
    },
    'settings.githubSubtitle': {
      'en': 'Visit the author’s profile.',
      'id': 'Kunjungi profil pembuat.',
      'zh': '访问作者的个人主页。',
      'ja': '制作者のプロフィールを確認。',
      'ko': '제작자 프로필을 방문하세요.',
      'ar': 'قم بزيارة ملف المطور.',
      'ru': 'Посетите профиль автора.',
      'hi': 'निर्माता की प्रोफ़ाइल देखें।',
    },
    'settings.iconCreditTitle': {
      'en': 'Icon attribution',
      'id': 'Kredit ikon',
      'zh': '图标署名',
      'ja': 'アイコン表記',
      'ko': '아이콘 출처',
      'ar': 'نَسب الأيقونة',
      'ru': 'Атрибуция значка',
      'hi': 'आइकन श्रेय',
    },
    'settings.iconCreditSubtitle': {
      'en': 'Slow Down icon by Flaticon.',
      'id': 'Ikon Slow Down oleh Flaticon.',
      'zh': 'Flaticon 提供的 Slow Down 图标。',
      'ja': 'Flaticon の Slow Down アイコン。',
      'ko': 'Flaticon의 Slow Down 아이콘.',
      'ar': 'أيقونة Slow Down من Flaticon.',
      'ru': 'Значок Slow Down от Flaticon.',
      'hi': 'Flaticon द्वारा Slow Down आइकन।',
    },
    'settings.creditNote': {
      'en': 'Remember to credit Ian7672 and Flaticon when you share the project.',
      'id':
          'Saat membagikan proyek, cantumkan kredit Ian7672 dan Flaticon secara berdampingan.',
      'zh': '分发项目时请同时标注 Ian7672 与 Flaticon。',
      'ja': 'プロジェクトを共有する際は Ian7672 と Flaticon を併記してください。',
      'ko': '프로젝트를 배포할 때 Ian7672와 Flaticon을 함께 표기하세요.',
      'ar': 'عند مشاركة المشروع اذكر Ian7672 و Flaticon معاً.',
      'ru':
          'При распространении проекта указывайте авторство Ian7672 и Flaticon.',
      'hi':
          'प्रोजेक्ट साझा करते समय Ian7672 और Flaticon दोनों को श्रेय दें।',
    },
    'settings.languageHeading': {
      'en': 'Language',
      'id': 'Bahasa',
      'zh': '语言',
      'ja': '言語',
      'ko': '언어',
      'ar': 'اللغة',
      'ru': 'Язык',
      'hi': 'भाषा',
    },
    'settings.languageDescription': {
      'en': 'Pick your preferred language.',
      'id': 'Pilih bahasa yang ingin digunakan.',
      'zh': '选择偏好的语言。',
      'ja': 'お好みの言語を選択してください。',
      'ko': '선호하는 언어를 선택하세요.',
      'ar': 'اختر لغتك المفضلة.',
      'ru': 'Выберите предпочитаемый язык.',
      'hi': 'अपनी पसंदीदा भाषा चुनें।',
    },
    'settings.themeHeading': {
      'en': 'Theme',
      'id': 'Tema',
      'zh': '主题',
      'ja': 'テーマ',
      'ko': '테마',
      'ar': 'السمة',
      'ru': 'Тема',
      'hi': 'थीम',
    },
    'settings.themeDescription': {
      'en': 'Choose system default, light, or dark appearance.',
      'id': 'Pilih tampilan sesuai sistem, mode terang, atau gelap.',
      'zh': '选择系统默认、浅色或深色外观。',
      'ja': 'システム/ライト/ダークのいずれかを選択します。',
      'ko': '시스템 기본, 라이트, 다크 모드 중에서 선택하세요.',
      'ar': 'اختر الوضع التلقائي أو الفاتح أو الداكن.',
      'ru': 'Выберите системную, светлую или тёмную схему.',
      'hi': 'सिस्टम, हल्का या डार्क रूप चुनें.',
    },
    'settings.themeSystem': {
      'en': 'Follow system',
      'id': 'Ikuti sistem',
      'zh': '跟随系统',
      'ja': 'システムに合わせる',
      'ko': '시스템 기본값',
      'ar': 'اتبع النظام',
      'ru': 'Как в системе',
      'hi': 'सिस्टम के अनुसार',
    },
    'settings.themeLight': {
      'en': 'Light mode',
      'id': 'Mode terang',
      'zh': '浅色模式',
      'ja': 'ライトモード',
      'ko': '라이트 모드',
      'ar': 'وضع فاتح',
      'ru': 'Светлая тема',
      'hi': 'हल्का मोड',
    },
    'settings.themeDark': {
      'en': 'Dark mode',
      'id': 'Mode gelap',
      'zh': '深色模式',
      'ja': 'ダークモード',
      'ko': '다크 모드',
      'ar': 'وضع داكن',
      'ru': 'Тёмная тема',
      'hi': 'डार्क मोड',
    },
    'drop.supported': {
      'en': 'Drop audio files here or use the buttons below.',
      'id': 'Letakkan file audio di sini atau gunakan tombol di bawah.',
      'zh': '将音频拖到此处或使用下方按钮。',
      'ja': 'ここに音声をドロップするか下のボタンを使ってください。',
      'ko': '오디오를 여기로 끌어놓거나 아래 버튼을 사용하세요.',
      'ar': 'أسقط ملفات الصوت هنا أو استخدم الأزرار بالأسفل.',
      'ru': 'Перетащите аудио сюда или воспользуйтесь кнопками ниже.',
      'hi': 'ऑडियो फ़ाइलों को यहाँ छोड़ें या नीचे दिए बटन का उपयोग करें।',
    },
    'drop.unsupported': {
      'en': 'Use the buttons to choose audio files.',
      'id': 'Gunakan tombol untuk memilih file audio.',
      'zh': '请使用按钮选择音频文件。',
      'ja': 'ボタンを使って音声ファイルを選択してください。',
      'ko': '버튼으로 오디오 파일을 선택하세요.',
      'ar': 'استخدم الأزرار لاختيار ملفات الصوت.',
      'ru': 'Выберите аудио с помощью кнопок.',
      'hi': 'बटन का उपयोग करके ऑडियो चुनें।',
    },
    'drop.browse': {
      'en': 'Browse Files',
      'id': 'Pilih File',
      'zh': '浏览文件',
      'ja': 'ファイルを選択',
      'ko': '파일 탐색',
      'ar': 'تصفح الملفات',
      'ru': 'Выбрать файлы',
      'hi': 'फ़ाइल ब्राउज़ करें',
    },
    'drop.clear': {
      'en': 'Clear Queue',
      'id': 'Kosongkan Daftar',
      'zh': '清空队列',
      'ja': 'キューをクリア',
      'ko': '목록 비우기',
      'ar': 'مسح القائمة',
      'ru': 'Очистить очередь',
      'hi': 'सूची खाली करें',
    },
    'preview.title': {
      'en': 'Preview Menu',
      'id': 'Menu Preview',
      'zh': '预览菜单',
      'ja': 'プレビュー',
      'ko': '프리뷰 메뉴',
      'ar': 'قائمة المعاينة',
      'ru': 'Меню предпросмотра',
      'hi': 'प्रीव्यू मेनू',
    },
    'preview.openInSheet': {
      'en': 'Open preview in a sheet',
      'id': 'Buka preview di panel bawah',
      'zh': '在底部面板中打开预览',
      'ja': '下部シートで開く',
      'ko': '시트에서 프리뷰 열기',
      'ar': 'افتح المعاينة في لوحة',
      'ru': 'Открыть предпросмотр в шторке',
      'hi': 'शीट में प्रीव्यू खोलें',
    },
    'preview.realtimeDescription': {
      'en': 'Realtime preview applies every slider change instantly (Android).',
      'id':
          'Preview realtime menerapkan setiap perubahan slider secara instan (Android).',
      'zh': 'Android 上的实时预览会立即反映滑块更改。',
      'ja': 'Android ではリアルタイムプレビューがスライダー変更を即時反映します。',
      'ko': 'Android에서는 실시간 프리뷰가 슬라이더 변경을 즉시 반영합니다.',
      'ar': 'على أندرويد تُطبق المعاينة الفورية كل تغيير في الحال.',
      'ru':
          'На Android режим реального времени мгновенно реагирует на изменения слайдеров.',
      'hi':
          'Android पर रियलटाइम प्रीव्यू हर स्लाइडर बदलाव तुरंत लागू करता है।',
    },
    'preview.ffmpegDescription': {
      'en':
          'FFmpeg preview renders a short clip whenever the parameters change.',
      'id':
          'Preview FFmpeg merender potongan pendek setiap parameter berubah.',
      'zh': 'FFmpeg 预览会在参数变化时渲染短片段。',
      'ja': 'FFmpeg プレビューは値が変わるたび短いクリップを生成します。',
      'ko': 'FFmpeg 프리뷰는 매개변수가 바뀔 때마다 짧은 클립을 렌더링합니다.',
      'ar': 'معاينة FFmpeg تنشئ مقطعاً قصيراً عند تغيّر الإعدادات.',
      'ru': 'Предпросмотр FFmpeg создаёт короткий клип при каждом изменении.',
      'hi': 'FFmpeg प्रीव्यू हर बदलाव पर छोटा क्लिप रेंडर करता है।',
    },
    'preview.emptyPrompt': {
      'en': 'Add audio files to enable preview.',
      'id': 'Tambahkan file audio untuk memakai preview.',
      'zh': '添加音频文件后即可预览。',
      'ja': '音声ファイルを追加するとプレビューできます。',
      'ko': '오디오 파일을 추가하면 프리뷰를 사용할 수 있습니다.',
      'ar': 'أضف ملفات صوت لتفعيل المعاينة.',
      'ru': 'Добавьте аудио, чтобы включить предпросмотр.',
      'hi': 'प्रीव्यू के लिए ऑडियो फ़ाइलें जोड़ें।',
    },
    'preview.dropdownLabel': {
      'en': 'Choose a file to preview',
      'id': 'Pilih file untuk dipreview',
      'zh': '选择要预览的文件',
      'ja': 'プレビューするファイルを選択',
      'ko': '프리뷰할 파일 선택',
      'ar': 'اختر ملفاً للمعاينة',
      'ru': 'Выберите файл для предпросмотра',
      'hi': 'जिस फ़ाइल का प्रीव्यू चाहिए उसे चुनें',
    },
    'preview.buttonPreparing': {
      'en': 'Preparing...',
      'id': 'Menyiapkan...',
      'zh': '准备中…',
      'ja': '準備中…',
      'ko': '준비 중...',
      'ar': 'جارٍ التحضير...',
      'ru': 'Подготовка...',
      'hi': 'तैयार किया जा रहा है...',
    },
    'preview.buttonPlay': {
      'en': 'Play preview',
      'id': 'Putar preview',
      'zh': '播放预览',
      'ja': 'プレビュー再生',
      'ko': '프리뷰 재생',
      'ar': 'تشغيل المعاينة',
      'ru': 'Запустить предпросмотр',
      'hi': 'प्रीव्यू चलाएं',
    },
    'preview.buttonStop': {
      'en': 'Stop',
      'id': 'Stop',
      'zh': '停止',
      'ja': '停止',
      'ko': '정지',
      'ar': 'إيقاف',
      'ru': 'Стоп',
      'hi': 'रोकें',
    },
    'error.addFilesFirst': {
      'en': 'Add audio files first.',
      'id': 'Tambahkan file audio terlebih dahulu.',
      'zh': '请先添加音频文件。',
      'ja': '先に音声ファイルを追加してください。',
      'ko': '먼저 오디오 파일을 추가하세요.',
      'ar': 'أضف ملفات صوت أولاً.',
      'ru': 'Сначала добавьте аудио.',
      'hi': 'पहले ऑडियो फ़ाइलें जोड़ें।',
    },
    'output.baseTitle': {
      'en': 'Output base folder',
      'id': 'Lokasi dasar output',
      'zh': '输出基础文件夹',
      'ja': '出力ベースフォルダー',
      'ko': '출력 기본 폴더',
      'ar': 'مجلد الإخراج الأساسي',
      'ru': 'Базовая папка вывода',
      'hi': 'आउटपुट का बेस फ़ोल्डर',
    },
    'output.changeButton': {
      'en': 'Change location',
      'id': 'Ganti lokasi',
      'zh': '更改位置',
      'ja': '場所を変更',
      'ko': '위치 변경',
      'ar': 'تغيير الموقع',
      'ru': 'Изменить путь',
      'hi': 'स्थान बदलें',
    },
    'output.baseEmptyBefore': {
      'en': 'Not set (add audio files first)',
      'id': 'Belum ada (tambahkan file musik dahulu)',
      'zh': '尚未设置（请先添加音频）',
      'ja': '未設定（先に音声を追加）',
      'ko': '미설정(먼저 오디오를 추가)',
      'ar': 'غير محدد (أضف ملفات الصوت أولاً)',
      'ru': 'Не задано (сначала добавьте аудио)',
      'hi': 'सेट नहीं (पहले ऑडियो जोड़ें)',
    },
    'output.baseUnset': {
      'en': 'Not set',
      'id': 'Belum diatur',
      'zh': '尚未设置',
      'ja': '未設定',
      'ko': '미설정',
      'ar': 'غير محدد',
      'ru': 'Не задано',
      'hi': 'सेट नहीं',
    },
    'output.folderLabel': {
      'en': 'Output folder name',
      'id': 'Nama folder output',
      'zh': '输出文件夹名称',
      'ja': '出力フォルダー名',
      'ko': '출력 폴더 이름',
      'ar': 'اسم مجلد الإخراج',
      'ru': 'Имя папки вывода',
      'hi': 'आउटपुट फ़ोल्डर का नाम',
    },
    'output.folderHint': {
      'en': 'Example: SlowReverb_20250101_120000',
      'id': 'Contoh: SlowReverb_20250101_120000',
      'zh': '示例：SlowReverb_20250101_120000',
      'ja': '例: SlowReverb_20250101_120000',
      'ko': '예: SlowReverb_20250101_120000',
      'ar': 'مثال: SlowReverb_20250101_120000',
      'ru': 'Например: SlowReverb_20250101_120000',
      'hi': 'उदाहरण: SlowReverb_20250101_120000',
    },
    'output.folderError': {
      'en': 'Fill the output folder name.',
      'id': 'Isi nama folder output.',
      'zh': '请填写输出文件夹名称。',
      'ja': '出力フォルダー名を入力してください。',
      'ko': '출력 폴더 이름을 입력하세요.',
      'ar': 'يرجى إدخال اسم مجلد الإخراج.',
      'ru': 'Укажите имя папки вывода.',
      'hi': 'आउटपुट फ़ोल्डर का नाम भरें।',
    },
    'ffmpeg.title': {
      'en': 'FFmpeg path',
      'id': 'Path FFmpeg',
      'zh': 'FFmpeg 路径',
      'ja': 'FFmpeg パス',
      'ko': 'FFmpeg 경로',
      'ar': 'مسار FFmpeg',
      'ru': 'Путь к FFmpeg',
      'hi': 'FFmpeg पथ',
    },
    'ffmpeg.hint': {
      'en': 'Example: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'id': 'Contoh: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'zh': '示例：D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'ja': '例: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'ko': '예: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'ar': 'مثال: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'ru': 'Например: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
      'hi': 'उदाहरण: D:\\tools\\ffmpeg\\bin\\ffmpeg.exe',
    },
    'ffmpeg.errorMissing': {
      'en': 'FFmpeg not found.',
      'id': 'FFmpeg tidak ditemukan.',
      'zh': '未找到 FFmpeg。',
      'ja': 'FFmpeg が見つかりません。',
      'ko': 'FFmpeg을 찾을 수 없습니다.',
      'ar': 'لم يتم العثور على FFmpeg.',
      'ru': 'FFmpeg не найден.',
      'hi': 'FFmpeg नहीं मिला।',
    },
    'ffmpeg.browse': {
      'en': 'Browse',
      'id': 'Browse',
      'zh': '浏览',
      'ja': '参照',
      'ko': '찾아보기',
      'ar': 'استعراض',
      'ru': 'Обзор',
      'hi': 'ब्राउज़',
    },
    'actions.process': {
      'en': 'Process Slow Reverb',
      'id': 'Proses Slow Reverb',
      'zh': '开始处理 Slow Reverb',
      'ja': 'Slow Reverb を処理',
      'ko': 'Slow Reverb 처리',
      'ar': 'تشغيل Slow Reverb',
      'ru': 'Запустить Slow Reverb',
      'hi': 'Slow Reverb प्रोसेस करें',
    },
    'actions.processing': {
      'en': 'Processing...',
      'id': 'Memproses...',
      'zh': '处理中…',
      'ja': '処理中…',
      'ko': '처리 중...',
      'ar': 'جارٍ المعالجة...',
      'ru': 'Обработка...',
      'hi': 'प्रोसेस हो रहा है...',
    },
    'preview.status.completed': {
      'en': 'Preview complete.',
      'id': 'Preview selesai.',
      'zh': '预览完成。',
      'ja': 'プレビュー完了。',
      'ko': '프리뷰 완료.',
      'ar': 'اكتملت المعاينة.',
      'ru': 'Предпросмотр завершён.',
      'hi': 'प्रीव्यू पूरा।',
    },
    'preview.status.parameters': {
      'en': 'Live parameters updated.',
      'id': 'Parameter live diperbarui.',
      'zh': '实时参数已更新。',
      'ja': 'ライブパラメーターを更新しました。',
      'ko': '라이브 매개변수를 업데이트했습니다.',
      'ar': 'تم تحديث المعلمات الفورية.',
      'ru': 'Параметры обновлены.',
      'hi': 'लाइव पैरामीटर अपडेट किए गए।',
    },
    'preview.status.stopped': {
      'en': 'Preview stopped.',
      'id': 'Preview dihentikan.',
      'zh': '预览已停止。',
      'ja': 'プレビューを停止しました。',
      'ko': '프리뷰가 중지되었습니다.',
      'ar': 'تم إيقاف المعاينة.',
      'ru': 'Предпросмотр остановлен.',
      'hi': 'प्रीव्यू रोका गया।',
    },
    'preview.status.preparing': {
      'en': 'Preparing preview. Please wait.',
      'id': 'Preview sedang disiapkan. Mohon tunggu.',
      'zh': '正在准备预览，请稍候。',
      'ja': 'プレビューを準備中です。お待ちください。',
      'ko': '프리뷰를 준비 중입니다. 잠시만 기다려 주세요.',
      'ar': 'يتم تحضير المعاينة، الرجاء الانتظار.',
      'ru': 'Подготовка предпросмотра. Подождите.',
      'hi': 'प्रीव्यू तैयार किया जा रहा है, कृपया प्रतीक्षा करें।',
    },
    'preview.status.nativeFallback': {
      'en': 'Realtime engine unavailable, falling back to FFmpeg preview.',
      'id':
          'Mesin preview realtime tidak siap, kembali ke preview FFmpeg.',
      'zh': '实时引擎不可用，回退到 FFmpeg 预览。',
      'ja': 'リアルタイムエンジンが使えないため FFmpeg プレビューに切り替えます。',
      'ko': '실시간 엔진을 사용할 수 없어 FFmpeg 프리뷰로 전환합니다.',
      'ar': 'المحرك الفوري غير متاح، سيتم استخدام معاينة FFmpeg.',
      'ru': 'Реальный движок недоступен, используем предпросмотр FFmpeg.',
      'hi': 'रियलटाइम इंजन उपलब्ध नहीं, FFmpeg प्रीव्यू का उपयोग किया गया।',
    },
    'preview.status.nativeFailed': {
      'en': 'Realtime preview failed (code {code}).',
      'id': 'Preview realtime gagal dijalankan (kode {code}).',
      'zh': '实时预览失败（代码 {code}）。',
      'ja': 'リアルタイムプレビューが失敗しました（コード {code}）。',
      'ko': '실시간 프리뷰 실패 (코드 {code}).',
      'ar': 'فشلت المعاينة الفورية (رمز {code}).',
      'ru': 'Реальный предпросмотр не запустился (код {code}).',
      'hi': 'रियलटाइम प्रीव्यू विफल (कोड {code})।',
    },
    'preview.status.updatingRealtime': {
      'en': 'Updating realtime preview for {file}',
      'id': 'Memperbarui preview realtime {file}',
      'zh': '更新 {file} 的实时预览',
      'ja': '{file} のリアルタイムプレビューを更新',
      'ko': '{file} 실시간 프리뷰를 업데이트하는 중',
      'ar': 'تحديث المعاينة الفورية لـ {file}',
      'ru': 'Обновляем realtime-просмотр для {file}',
      'hi': '{file} का रियलटाइम प्रीव्यू अपडेट हो रहा है',
    },
    'preview.status.playRealtime': {
      'en': 'Playing realtime preview for {file}',
      'id': 'Memutar preview realtime {file}',
      'zh': '播放 {file} 的实时预览',
      'ja': '{file} のリアルタイムプレビューを再生',
      'ko': '{file} 실시간 프리뷰 재생',
      'ar': 'تشغيل معاينة فورية لـ {file}',
      'ru': 'Воспроизводим realtime-просмотр {file}',
      'hi': '{file} का रियलटाइम प्रीव्यू चल रहा है',
    },
    'preview.status.updatedLive': {
      'en': 'Preview updated (live).',
      'id': 'Preview diperbarui (live).',
      'zh': '预览已更新（实时）。',
      'ja': 'プレビューを更新しました（ライブ）。',
      'ko': '프리뷰 업데이트 완료 (라이브).',
      'ar': 'تم تحديث المعاينة (لحظياً).',
      'ru': 'Предпросмотр обновлён (live).',
      'hi': 'प्रीव्यू अपडेट हुआ (लाइव)।',
    },
    'preview.status.rendered': {
      'en': 'Playing preview for {file}',
      'id': 'Memutar preview {file}',
      'zh': '播放 {file} 的预览',
      'ja': '{file} のプレビューを再生',
      'ko': '{file} 프리뷰 재생',
      'ar': 'تشغيل معاينة لـ {file}',
      'ru': 'Воспроизводим предпросмотр {file}',
      'hi': '{file} का प्रीव्यू चल रहा है',
    },
    'preview.status.error': {
      'en': 'Preview failed: {error}',
      'id': 'Preview gagal: {error}',
      'zh': '预览失败：{error}',
      'ja': 'プレビュー失敗: {error}',
      'ko': '프리뷰 실패: {error}',
      'ar': 'فشلت المعاينة: {error}',
      'ru': 'Ошибка предпросмотра: {error}',
      'hi': 'प्रीव्यू विफल: {error}',
    },
  };

  static SlowReverbLocalizations of(BuildContext context) {
    return Localizations.of<SlowReverbLocalizations>(
          context,
          SlowReverbLocalizations,
        ) ??
        SlowReverbLocalizations(const Locale('en'));
  }

  String translate(String key, {Map<String, String>? params}) {
    final languageCode = _normalizeLanguageCode(locale.languageCode);
    final values = _localizedValues[key];
    String resolved = values?[languageCode] ?? values?['en'] ?? key;
    if (params != null) {
      params.forEach((paramKey, paramValue) {
        resolved = resolved.replaceAll('{$paramKey}', paramValue);
      });
    }
    return resolved;
  }

  static String _normalizeLanguageCode(String code) {
    if (code.contains('-')) {
      return code.split('-').first;
    }
    return code;
  }
}

class SlowReverbLocalizationsDelegate
    extends LocalizationsDelegate<SlowReverbLocalizations> {
  const SlowReverbLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    final code = SlowReverbLocalizations._normalizeLanguageCode(
      locale.languageCode,
    );
    return SlowReverbLanguage.supported
        .any((language) => language.code == code);
  }

  @override
  Future<SlowReverbLocalizations> load(Locale locale) async {
    return SlowReverbLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate old) => false;
}

extension SlowReverbLocalizationX on BuildContext {
  SlowReverbLocalizations get l10n => SlowReverbLocalizations.of(this);

  String tr(String key, {Map<String, String>? params}) =>
      l10n.translate(key, params: params);
}
