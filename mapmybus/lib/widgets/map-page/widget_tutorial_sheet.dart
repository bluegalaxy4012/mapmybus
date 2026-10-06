import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapmybus/widgets/common-page/simple_snackbar.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

// de modificat, partea cu android e copiata si nu am testat
const String kWidgetApiHost = 'mapmybus.40004444.xyz';

const String kScriptableAppStoreUrl = 'https://apps.apple.com/app/id1405459188';
const String kKwgtPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=org.kustom.widget';

// -> api
Future<void> showWidgetTutorialSheet(
  BuildContext context, {
  required String agencyId,
  required String stopId,
  required String stopName,
}) {
  final apiUrl = Uri.https(kWidgetApiHost, '/api/widgets/$agencyId', {
    'stop_id': stopId,
  }).toString();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _WidgetTutorialSheet(apiUrl: apiUrl, stopName: stopName),
    ),
  );
}

const String _scriptableTemplate = r'''
// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: yellow; icon-glyph: bus;

const API_URL = __API_URL__;
const MAX_ROWS_SMALL = 3;
const MAX_ROWS_MEDIUM = 5;

async function loadData() {
  try {
    const req = new Request(API_URL);
    req.timeoutInterval = 10;
    return await req.loadJSON();
  } catch (e) {
    return null;
  }
}

function pad(n) {
  return n < 10 ? "0" + n : "" + n;
}

function buildWidget(data) {
  const w = new ListWidget();
  w.backgroundColor = new Color("#fc9b3f");
  w.setPadding(12, 12, 12, 12);
  w.refreshAfterDate = new Date(Date.now() + 2 * 60 * 1000);

  if (!data || !data.stop_name) {
    const err = w.addText("Nu am putut incarca datele");
    err.textColor = Color.white();
    err.font = Font.semiboldSystemFont(13);
    err.centerAlignText();
    return w;
  }

  const title = w.addText(data.stop_name);
  title.textColor = Color.white();
  title.font = Font.boldSystemFont(15);
  title.lineLimit = 2;
  title.minimumScaleFactor = 0.7;
  title.centerAlignText();

  w.addSpacer();

  const max = config.widgetFamily === "small" ? MAX_ROWS_SMALL : MAX_ROWS_MEDIUM;
  const arrivals = (data.arrivals || []).slice(0, max);

  if (arrivals.length === 0) {
    const none = w.addText("Niciun vehicul pornit spre statie");
    none.textColor = Color.white();
    none.font = Font.systemFont(12);
    none.centerAlignText();
  }

  for (const a of arrivals) {
    const row = w.addStack();
    row.centerAlignContent();

    const line = row.addText(a.route_short_name || "?");
    line.font = Font.boldSystemFont(14);
    line.textColor = Color.white();

    row.addSpacer();

    const eta = row.addText(a.eta_message || "?");
    eta.font = Font.systemFont(13);
    eta.textColor = new Color("#edebe8");

    w.addSpacer(3);
  }

  w.addSpacer();

  const now = new Date();
  const stamp = w.addText(
    "Actualizat " + new Date(data.ts).toLocaleTimeString("ro-RO", {
      hour: "2-digit",
      minute: "2-digit",
    })
  );
  stamp.font = Font.systemFont(9);
  stamp.textColor = Color.white();
  stamp.centerAlignText();

  return w;
}

const data = await loadData();
const widget = buildWidget(data);

if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}

Script.complete();
''';

String _buildScriptableScript(String apiUrl) =>
    _scriptableTemplate.replaceFirst('__API_URL__', jsonEncode(apiUrl));

// android

const String _kwgtStopNameFormula = r'$wg(gv(url), json, ".stop_name")$';

String _kwgtArrivalFormula(int i) {
  final route = '.arrivals[$i].route_short_name';
  final eta = '.arrivals[$i].eta_message';
  return '\$wg(gv(url), json, "$route")\$ - \$wg(gv(url), json, "$eta")\$';
}

// tutorial

class _StepAction {
  const _StepAction({
    required this.label,
    required this.icon,
    required this.run,
  });

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context) run;
}

class _Step {
  const _Step({
    required this.title,
    required this.body,
    required this.imageLabel,
    required this.icon,
    this.actions = const [],
  });

  final String title;
  final String body;
  final String imageLabel;
  final IconData icon;
  final List<_StepAction> actions;
}

Future<bool> _open(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

Future<void> _copy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSimpleSnackbar(context, message);
}

Future<void> _copyAndOpenScriptable(BuildContext context, String script) async {
  await Clipboard.setData(ClipboardData(text: script));

  final opened = await _open('scriptable:///add');
  if (!context.mounted) return;

  showSimpleSnackbar(
    context,
    opened
        ? 'Script copiat. In Scriptable, lipeste-l in editor.'
        : 'Script copiat, dar nu am putut deschide Scriptable. Deschide-l manual si apasa +.',
  );
}

List<_Step> _iosSteps(String apiUrl) {
  final script = _buildScriptableScript(apiUrl);

  return [
    _Step(
      title: 'Instaleaza Scriptable',
      body:
          'Scriptable e o aplicatie gratuita care deseneaza widgetul din datele aplicatiei noastre prin intermediul unui script pe care il oferim. Daca o ai deja, treci la pasul urmator.',
      imageLabel: 'Scriptable App Store',
      icon: Icons.download_rounded,
      actions: [
        _StepAction(
          label: 'Deschide App Store',
          icon: Icons.open_in_new,
          run: (ctx) async {
            final ok = await _open(kScriptableAppStoreUrl);
            if (!ok && ctx.mounted) {
              showSimpleSnackbar(ctx, 'Nu am putut deschide App Store');
            }
          },
        ),
      ],
    ),
    _Step(
      title: 'Copiaza scriptul',
      body:
          'Apasa butonul de mai jos. Copiem scriptul pentru aceasta statie si deschidem Scriptable direct pe un script nou, gol. Aplicatia nu poate pune codul singura in script, il lipesti tu la pasul urmator.',
      imageLabel: 'Script nou din Scriptable',
      icon: Icons.copy_all_rounded,
      actions: [
        _StepAction(
          label: 'Copiaza si deschide Scriptable',
          icon: Icons.open_in_new,
          run: (ctx) => _copyAndOpenScriptable(ctx, script),
        ),
        _StepAction(
          label: 'Doar copiaza scriptul',
          icon: Icons.copy,
          run: (ctx) => _copy(ctx, script, 'Script copiat'),
        ),
      ],
    ),
    const _Step(
      title: 'Lipeste si salveaza',
      body:
          'In editorul gol, tine apasat pe ecran si alege Paste (Lipeste). Apoi apasa Done. Daca vrei, redenumeste scriptul apasand pe numele sau actual (probabil Untitled Script). Apasa Play (triunghiul) ca sa vezi o previzualizare: ar trebui sa vezi numele statiei si urmatoarele sosiri.',
      imageLabel: 'Editorul cu scriptul si Play',
      icon: Icons.content_paste_rounded,
    ),
    const _Step(
      title: 'Adauga widgetul pe ecran',
      body:
          'Tine apasat pe un spatiu gol de pe ecranul de start, apasa + (stanga sus), cauta Scriptable, alege dimensiunea (mic sau mediu) si apasa Add Widget.',
      imageLabel: 'Widgeturi iOS cu Scriptable acolo',
      icon: Icons.add_to_home_screen_rounded,
    ),
    const _Step(
      title: 'Alege scriptul',
      body:
          'Atinge widgetul nou (sau tine apasat si alege Edit Widget). La Script alege scriptul tau. Optional, la When Interacting alege Run Script si astfel fiecare apasare va reactualiza datele. Gata, widgetul apare cu statia ta.',
      imageLabel: 'Config widget Scriptable',
      icon: Icons.tune_rounded,
    ),
    const _Step(
      title: 'Bine de stiut',
      body:
          'iOS decide singur cand se reimprospateaza widgeturile, deci timpii pot fi vechi. Ora de jos din widget arata cand au fost preluate datele. Pentru date proaspete, reruleaza scriptul.',
      imageLabel: 'Widgetul gata pe ecran',
      icon: Icons.info_outline_rounded,
    ),
  ];
}

List<_Step> _androidSteps(String apiUrl) {
  return [
    _Step(
      title: 'Instaleaza KWGT',
      body:
          'KWGT (Kustom Widget Maker) deseneaza widgetul pe Android. Versiunea gratuita ajunge daca iti construiesti widgetul singur, cum e descris aici. Importul de preseturi gata facute cere versiunea Pro.',
      imageLabel: 'Pagina KWGT din Play Store',
      icon: Icons.download_rounded,
      actions: [
        _StepAction(
          label: 'Deschide Play Store',
          icon: Icons.open_in_new,
          run: (ctx) async {
            final ok = await _open(kKwgtPlayStoreUrl);
            if (!ok && ctx.mounted) {
              showSimpleSnackbar(ctx, 'Nu am putut deschide Play Store');
            }
          },
        ),
      ],
    ),
    const _Step(
      title: 'Adauga un widget KWGT',
      body:
          'Tine apasat pe ecranul de start, alege Widgets, cauta KWGT si trage un widget gol pe ecran (de ex. 4x2). Pasii exacti difera putin de la un launcher la altul [placeholder: adauga captura de la launcherul tau].',
      imageLabel: 'Lista de widgeturi Android cu KWGT',
      icon: Icons.add_to_home_screen_rounded,
    ),
    _Step(
      title: 'Salveaza adresa ca variabila',
      body:
          'Atinge widgetul gol ca sa deschizi editorul. Creeaza o variabila globala de tip text cu numele url [placeholder: verifica numele exact al tabului sau al butonului pentru variabile globale in versiunea ta de KWGT]. La valoare lipeste adresa copiata cu butonul de mai jos.',
      imageLabel: 'Editorul KWGT, sectiunea de variabile globale',
      icon: Icons.link_rounded,
      actions: [
        _StepAction(
          label: 'Copiaza adresa',
          icon: Icons.copy,
          run: (ctx) => _copy(ctx, apiUrl, 'Adresa copiata'),
        ),
      ],
    ),
    _Step(
      title: 'Adauga numele statiei',
      body:
          'Adauga un element de tip Text. Atinge-l, deschide editorul de formule (textul Text) si lipeste formula de mai jos.',
      imageLabel: 'Editorul de formule KWGT cu formula lipita',
      icon: Icons.title_rounded,
      actions: [
        _StepAction(
          label: 'Copiaza formula',
          icon: Icons.copy,
          run: (ctx) => _copy(ctx, _kwgtStopNameFormula, 'Formula copiata'),
        ),
      ],
    ),
    _Step(
      title: 'Adauga randurile cu sosiri',
      body:
          'Creeaza cate un Text pentru fiecare sosire si lipeste formula corespunzatoare (linia si timpul pe acelasi rand). Daca sunt mai putine sosiri decat randuri, un rand poate ramane gol sau poate arata o eroare [placeholder: verifica ce afiseaza KWGT in acest caz si adauga aici o formula cu valoare implicita].',
      imageLabel: 'Widget cu trei randuri de sosiri in editor',
      icon: Icons.format_list_numbered_rounded,
      actions: [
        for (var i = 0; i < 3; i++)
          _StepAction(
            label: 'Copiaza randul ${i + 1}',
            icon: Icons.copy,
            run: (ctx) => _copy(
              ctx,
              _kwgtArrivalFormula(i),
              'Formula randului ${i + 1} copiata',
            ),
          ),
      ],
    ),
    const _Step(
      title: 'Salveaza si bine de stiut',
      body:
          'Apasa iconita de salvare din editor. KWGT tine datele descarcate in cache, deci widgetul nu se reimprospateaza in timp real [placeholder: verifica unde se regleaza frecventa de actualizare in KWGT]. Timpii sunt estimari si pot fi vechi cateva minute.',
      imageLabel: 'Widgetul gata facut pe ecranul de start',
      icon: Icons.info_outline_rounded,
    ),
  ];
}

class _WidgetTutorialSheet extends StatelessWidget {
  const _WidgetTutorialSheet({required this.apiUrl, required this.stopName});

  final String apiUrl;
  final String stopName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      initialIndex: defaultTargetPlatform == TargetPlatform.android ? 1 : 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Widget pentru $stopName',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'IOS'),
              Tab(text: 'ANDROID'),
            ],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _TutorialPager(steps: _iosSteps(apiUrl)),
                _TutorialPager(steps: _androidSteps(apiUrl)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialPager extends StatefulWidget {
  const _TutorialPager({required this.steps});

  final List<_Step> steps;

  @override
  State<_TutorialPager> createState() => _TutorialPagerState();
}

class _TutorialPagerState extends State<_TutorialPager>
    with AutomaticKeepAliveClientMixin {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final steps = widget.steps;
    final isFirst = _index == 0;
    final isLast = _index == steps.length - 1;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: steps.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) =>
                _StepPage(step: steps[i], number: i + 1, total: steps.length),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SmoothPageIndicator(
            controller: _controller,
            count: steps.length,
            effect: WormEffect(
              dotHeight: 8,
              dotWidth: 8,
              activeDotColor: primary,
            ),
            onDotClicked: _go,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: isFirst ? null : () => _go(_index - 1),
                child: const Text('Inapoi'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: isLast
                    ? () => Navigator.of(context).pop()
                    : () => _go(_index + 1),
                child: Text(isLast ? 'Gata' : 'Urmatorul'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.step,
    required this.number,
    required this.total,
  });

  final _Step step;
  final int number;
  final int total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pasul $number din $total', style: textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            step.title,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _ImagePlaceholder(label: step.imageLabel, icon: step.icon),
          const SizedBox(height: 12),
          Text(step.body, style: textTheme.bodyMedium),
          if (step.actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in step.actions)
                  FilledButton.tonalIcon(
                    onPressed: () => action.run(context),
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              '[PLACEHOLDER captura: $label]',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
