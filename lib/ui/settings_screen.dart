import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:anivault/services/ai_agent_service.dart';
import 'package:anivault/services/anime_library_service.dart';
import 'package:anivault/services/app_i18n.dart';
import 'package:anivault/services/logger_service.dart';
import 'package:anivault/services/theme_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';

class SettingsScreen extends StatelessWidget {
  final Future<void> Function()? onLibraryRefresh;

  const SettingsScreen({super.key, this.onLibraryRefresh});

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final textColor = AniGlassTheme.textColor(context);
    return GlassScaffold(
      background: AniGlassTheme.background(
        light: light,
        style: ThemeService().backgroundStyle,
      ),
      statusBarStyle: light
          ? GlassStatusBarStyle.dark
          : GlassStatusBarStyle.light,
      settings: AniGlassTheme.chromeFor(context),
      appBar: GlassAppBar(
        title: Text('Settings', style: TextStyle(color: textColor)),
        leading: GlassButton(
          quality: AniGlassTheme.quality,
          settings: AniGlassTheme.chromeFor(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: SettingsContent(
        topPadding: MediaQuery.paddingOf(context).top + 76,
        onLibraryRefresh: onLibraryRefresh,
      ),
    );
  }
}

class SettingsContent extends StatefulWidget {
  final double topPadding;
  final Future<void> Function()? onLibraryRefresh;
  final ScrollController? scrollController;

  const SettingsContent({
    super.key,
    this.topPadding = 0,
    this.onLibraryRefresh,
    this.scrollController,
  });

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  @override
  void initState() {
    super.initState();
    AiAgentService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 36),
      children: [
        const _SettingsPanel(
          icon: Icons.cloud_sync_rounded,
          title: 'AniList Metadata',
          subtitle: 'GraphQL search for imported anime',
          child: _AniListStatus(),
        ),
        const SizedBox(height: 16),
        const _SettingsPanel(
          icon: Icons.diamond_rounded,
          title: 'Premium Glass',
          subtitle: 'Adaptive fallback is disabled for this build',
          child: _PremiumStatus(),
        ),
        const SizedBox(height: 16),
        _SettingsPanel(
          icon: Icons.science_rounded,
          title: 'Experimental',
          subtitle: 'AI-assisted matching for difficult releases',
          child: _ExperimentalPanel(onLibraryRefresh: widget.onLibraryRefresh),
        ),
        const SizedBox(height: 16),
        const _AppearancePanel(),
        const SizedBox(height: 16),
        _SettingsLogButton(onTap: _showCompactLogs),
      ],
    );
  }

  void _showCompactLogs() {
    GlassModalSheet.show(
      context: context,
      initialState: GlassSheetState.half,
      halfSize: 0.46,
      fullSize: 0.82,
      quality: AniGlassTheme.quality,
      settings: AniGlassTheme.heroFor(context),
      barrierColor: Colors.black45,
      fillTransition: GlassFillTransition.instant,
      interactionScale: 1.01,
      stretch: 0.35,
      suppressInteractionOnChildren: true,
      builder: (context) => const _CompactLogSheet(),
    );
  }
}

class _AniListStatus extends StatelessWidget {
  const _AniListStatus();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusRow(label: 'Source', value: 'AniList GraphQL'),
        SizedBox(height: 8),
        _StatusRow(label: 'Matching', value: 'Anitomy-style filename parsing'),
        SizedBox(height: 8),
        _StatusRow(label: 'Choice', value: 'Glass action sheet on ambiguity'),
      ],
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      icon: Icons.palette_rounded,
      title: 'Appearance',
      subtitle: 'Theme and background style',
      child: ListenableBuilder(
        listenable: Listenable.merge([ThemeService(), AppI18n()]),
        builder: (context, _) {
          final service = ThemeService();
          final i18n = AppI18n();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SettingLabel('Language'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ThemeChip(
                    label: 'System',
                    selected: i18n.mode == AppLanguageMode.system,
                    onTap: () => i18n.setMode(AppLanguageMode.system),
                  ),
                  _ThemeChip(
                    label: '中文',
                    selected: i18n.mode == AppLanguageMode.zh,
                    onTap: () => i18n.setMode(AppLanguageMode.zh),
                  ),
                  _ThemeChip(
                    label: 'English',
                    selected: i18n.mode == AppLanguageMode.en,
                    onTap: () => i18n.setMode(AppLanguageMode.en),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SettingLabel('Theme'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ThemeChip(
                    label: 'System',
                    selected: service.themeMode == ThemeMode.system,
                    onTap: () => service.setThemeMode(ThemeMode.system),
                  ),
                  _ThemeChip(
                    label: 'White',
                    selected: service.themeMode == ThemeMode.light,
                    onTap: () => service.setThemeMode(ThemeMode.light),
                  ),
                  _ThemeChip(
                    label: 'Black',
                    selected: service.themeMode == ThemeMode.dark,
                    onTap: () => service.setThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SettingLabel('Background'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ThemeChip(
                    label: 'Dynamic',
                    selected:
                        service.backgroundStyle == AniBackgroundStyle.dynamic,
                    onTap: () =>
                        service.setBackgroundStyle(AniBackgroundStyle.dynamic),
                  ),
                  _ThemeChip(
                    label: 'Solid',
                    selected:
                        service.backgroundStyle == AniBackgroundStyle.solid,
                    onTap: () =>
                        service.setBackgroundStyle(AniBackgroundStyle.solid),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SettingLabel('Glass quality'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ThemeChip(
                    label: 'Minimal',
                    selected:
                        service.glassQuality == AniGlassQualityMode.minimal,
                    onTap: () =>
                        service.setGlassQuality(AniGlassQualityMode.minimal),
                  ),
                  _ThemeChip(
                    label: 'Standard',
                    selected:
                        service.glassQuality == AniGlassQualityMode.standard,
                    onTap: () =>
                        service.setGlassQuality(AniGlassQualityMode.standard),
                  ),
                  _ThemeChip(
                    label: 'Premium',
                    selected:
                        service.glassQuality == AniGlassQualityMode.premium,
                    onTap: () =>
                        service.setGlassQuality(AniGlassQualityMode.premium),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  final String label;

  const _SettingLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: AniGlassTheme.secondaryTextColor(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return GlassChip(
      quality: AniGlassTheme.quality,
      settings: AniGlassTheme.chromeFor(context),
      label: label,
      selected: selected,
      labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      onTap: onTap,
    );
  }
}

class _PremiumStatus extends StatelessWidget {
  const _PremiumStatus();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final quality = ThemeService().glassQuality.name;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(label: 'Quality', value: 'GlassQuality.$quality'),
            const SizedBox(height: 8),
            const _StatusRow(label: 'Adaptive', value: 'Disabled'),
            const SizedBox(height: 8),
            const _StatusRow(label: 'Mode', value: 'Forced by setting'),
          ],
        );
      },
    );
  }
}

class _ExperimentalPanel extends StatelessWidget {
  final Future<void> Function()? onLibraryRefresh;

  const _ExperimentalPanel({this.onLibraryRefresh});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiAgentService(),
      builder: (context, _) {
        final service = AiAgentService();
        final config = service.config;
        final textColor = AniGlassTheme.textColor(context);
        final secondary = AniGlassTheme.secondaryTextColor(context);
        return GlassButton.custom(
          quality: AniGlassTheme.quality,
          settings: AniGlassTheme.chromeFor(context),
          shape: const LiquidRoundedSuperellipse(borderRadius: 18),
          height: 64,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AiAgentSettingsScreen(onLibraryRefresh: onLibraryRefresh),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Agent',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.isReady ? config.model : 'Not configured',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: secondary),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsLogButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsLogButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return GlassButton.custom(
      quality: AniGlassTheme.quality,
      settings: AniGlassTheme.chromeFor(context),
      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
      height: 62,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.terminal_rounded, color: textColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logs',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ListenableBuilder(
                    listenable: LoggerService(),
                    builder: (context, _) => Text(
                      '${LoggerService().logs.length} recent lines',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_up_rounded, color: secondary),
          ],
        ),
      ),
    );
  }
}

class _CompactLogSheet extends StatelessWidget {
  const _CompactLogSheet();

  Future<void> _copyLogs(BuildContext context, List<String> logs) async {
    await Clipboard.setData(ClipboardData(text: logs.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied ${logs.length} log lines')));
  }

  Future<void> _copyErrors(BuildContext context) async {
    final errors = LoggerService().errorLogs;
    await Clipboard.setData(ClipboardData(text: errors.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${errors.length} error log lines')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scrollData = ScrollControllerProvider.of(context);
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return ListenableBuilder(
      listenable: LoggerService(),
      builder: (context, _) {
        final logs = LoggerService().logs.take(120).toList();
        return ListView(
          controller: scrollData?.controller,
          physics: scrollData?.physics,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Logs',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GlassButton(
                  quality: AniGlassTheme.quality,
                  settings: AniGlassTheme.chromeFor(context),
                  icon: const Icon(Icons.copy_rounded),
                  onTap: () => _copyLogs(context, logs),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  quality: AniGlassTheme.quality,
                  settings: AniGlassTheme.chromeFor(context),
                  icon: const Icon(Icons.close_rounded),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${logs.length} shown / ${LoggerService().logs.length} total',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 34),
                child: Center(
                  child: Text(
                    'No logs yet',
                    style: TextStyle(color: secondary),
                  ),
                ),
              )
            else
              ...logs.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LogLine(line: line, onCopyErrors: _copyErrors),
                ),
              ),
          ],
        );
      },
    );
  }
}

class AiAgentSettingsScreen extends StatefulWidget {
  final Future<void> Function()? onLibraryRefresh;

  const AiAgentSettingsScreen({super.key, this.onLibraryRefresh});

  @override
  State<AiAgentSettingsScreen> createState() => _AiAgentSettingsScreenState();
}

class _AiAgentSettingsScreenState extends State<AiAgentSettingsScreen> {
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  bool _enabled = false;
  String _model = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await AiAgentService().initialize();
    if (!mounted) return;
    final config = AiAgentService().config;
    setState(() {
      _enabled = config.enabled;
      _baseUrlCtrl.text = config.baseUrl;
      _apiKeyCtrl.text = config.apiKey;
      _model = config.model;
    });
  }

  Future<void> _save({bool refresh = false}) async {
    setState(() => _saving = true);
    await AiAgentService().saveConfig(
      enabled: _enabled,
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
      model: _model,
    );
    if (AiAgentService().config.isReady) {
      unawaited(AnimeLibraryService().retryUnresolvedQueue());
    }
    if (refresh) await widget.onLibraryRefresh?.call();
    if (!mounted) return;
    setState(() => _saving = false);
  }

  Future<void> _fetchModels() async {
    await _save();
    final models = await AiAgentService().fetchModels(
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
    );
    if (!mounted) return;
    setState(() => _model = AiAgentService().config.model);
    final message = models.isEmpty
        ? 'Model fetch failed'
        : 'Fetched ${models.length} models';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final textColor = AniGlassTheme.textColor(context);
    return GlassScaffold(
      background: AniGlassTheme.background(
        light: light,
        style: ThemeService().backgroundStyle,
      ),
      statusBarStyle: light
          ? GlassStatusBarStyle.dark
          : GlassStatusBarStyle.light,
      settings: AniGlassTheme.chromeFor(context),
      appBar: GlassAppBar(
        title: Text('AI Agent', style: TextStyle(color: textColor)),
        leading: GlassButton(
          quality: AniGlassTheme.quality,
          settings: AniGlassTheme.chromeFor(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onTap: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 76,
          20,
          36,
        ),
        children: [
          ListenableBuilder(
            listenable: AiAgentService(),
            builder: (context, _) {
              final service = AiAgentService();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AgentSwitchStrip(
                    title: 'AI Agent',
                    subtitle: 'Fallback when AniList has no match',
                    enabled: _enabled,
                    onChanged: (value) {
                      setState(() => _enabled = value);
                      _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  _AgentInputStrip(
                    controller: _baseUrlCtrl,
                    title: 'Base URL',
                    placeholder: 'https://api.openai.com/v1',
                    icon: Icons.link_rounded,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  _AgentPasswordStrip(
                    controller: _apiKeyCtrl,
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  _ModelGlassMenu(
                    models: service.config.models,
                    selectedModel: _model,
                    onSelected: (model) {
                      setState(() => _model = model);
                      _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _AgentActionStrip(
                          icon: Icons.cloud_download_rounded,
                          label: service.isFetchingModels
                              ? 'Fetching'
                              : 'Fetch Models',
                          onTap: () {
                            if (service.isFetchingModels) return;
                            _fetchModels();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AgentActionStrip(
                          icon: Icons.save_rounded,
                          label: _saving ? 'Saving' : 'Save',
                          onTap: () {
                            if (_saving) return;
                            _save(refresh: true);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (service.lastError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      service.lastError!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AgentSwitchStrip extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AgentSwitchStrip({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return _AgentStripShell(
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: _StripText(title: title, subtitle: subtitle),
          ),
          GlassSwitch(
            value: enabled,
            onChanged: onChanged,
            quality: AniGlassTheme.quality,
            settings: AniGlassTheme.chromeFor(context),
            activeColor: textColor.withValues(alpha: 0.72),
          ),
        ],
      ),
    );
  }
}

class _AgentStripShell extends StatelessWidget {
  final Widget child;

  const _AgentStripShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: child,
      ),
    );
    return _SettingsSurface(borderRadius: 18, child: content);
  }
}

class _StripText extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StripText({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: secondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _AgentInputStrip extends StatelessWidget {
  final TextEditingController controller;
  final String title;
  final String placeholder;
  final IconData icon;
  final ValueChanged<String> onSubmitted;

  const _AgentInputStrip({
    required this.controller,
    required this.title,
    required this.placeholder,
    required this.icon,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return _AgentStripShell(
      child: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Text(
              title,
              style: TextStyle(color: secondary, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: TextStyle(color: secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentPasswordStrip extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _AgentPasswordStrip({
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    return _AgentStripShell(
      child: Row(
        children: [
          Icon(Icons.key_rounded, color: textColor),
          const SizedBox(width: 12),
          SizedBox(
            width: 78,
            child: Text(
              'API Key',
              style: TextStyle(color: secondary, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: true,
              onSubmitted: onSubmitted,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'sk-...',
                hintStyle: TextStyle(color: secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelGlassMenu extends StatelessWidget {
  final List<String> models;
  final String selectedModel;
  final ValueChanged<String> onSelected;

  const _ModelGlassMenu({
    required this.models,
    required this.selectedModel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondary = AniGlassTheme.secondaryTextColor(context);
    final label = selectedModel.isEmpty ? 'Fetch models first' : selectedModel;
    final visibleModels = models.isEmpty
        ? <String>[if (selectedModel.isNotEmpty) selectedModel]
        : models;
    return _AgentStripShell(
      child: Row(
        children: [
          Icon(Icons.memory_rounded, color: textColor),
          const SizedBox(width: 12),
          Expanded(
            child: _StripText(title: 'Model', subtitle: label),
          ),
          SizedBox(
            width: 42,
            height: 42,
            child: GlassMenu(
              settings: AniGlassTheme.chromeFor(context),
              quality: AniGlassTheme.quality,
              menuWidth: 320,
              items: visibleModels
                  .map(
                    (model) => GlassMenuItem(
                      title: model,
                      height: 52,
                      maxLines: 1,
                      isSelected: model == selectedModel,
                      trailing: SizedBox(
                        width: 22,
                        child: model == selectedModel
                            ? Icon(
                                Icons.check_rounded,
                                color: textColor,
                                size: 18,
                              )
                            : null,
                      ),
                      titleStyle: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                      onTap: () => onSelected(model),
                    ),
                  )
                  .toList(),
              triggerBuilder: (context, toggle) {
                return Center(
                  child: GlassButton(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    shape: const LiquidOval(),
                    width: 42,
                    height: 42,
                    icon: Icon(Icons.expand_more_rounded, color: secondary),
                    onTap: () {
                      if (visibleModels.isEmpty) return;
                      toggle();
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentActionStrip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AgentActionStrip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    return _SettingsSurface(
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: textColor, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: TextStyle(color: secondaryTextColor)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class LogViewerPanel extends StatefulWidget {
  const LogViewerPanel({super.key});

  @override
  State<LogViewerPanel> createState() => _LogViewerPanelState();
}

class _LogViewerPanelState extends State<LogViewerPanel> {
  final _searchCtrl = TextEditingController();
  String _tag = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> _filter(List<String> logs) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return logs.where((line) {
      final lower = line.toLowerCase();
      final tagOk = switch (_tag) {
        'MPV' => lower.contains('[mpv]'),
        'FFI' => lower.contains('[ffi]'),
        'Shader' => lower.contains('shader'),
        'Error' => lower.contains('error') || lower.contains('failed'),
        _ => true,
      };
      return tagOk && (query.isEmpty || lower.contains(query));
    }).toList();
  }

  Future<void> _copyVisible(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied ${lines.length} log lines')));
  }

  Future<void> _copyErrors(BuildContext context) async {
    final errors = LoggerService().errorLogs;
    await Clipboard.setData(ClipboardData(text: errors.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${errors.length} error log lines')),
    );
  }

  Future<void> _confirmClear() async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Clear logs?'),
        content: const Text('This removes the in-memory log buffer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) LoggerService().clear();
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      icon: Icons.terminal_rounded,
      title: 'Logs',
      subtitle: 'Live MPV, FFI, shader, and app diagnostics',
      child: ListenableBuilder(
        listenable: LoggerService(),
        builder: (context, _) {
          final visible = _filter(LoggerService().logs);
          final textColor = AniGlassTheme.textColor(context);
          final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSearchBar(
                quality: AniGlassTheme.quality,
                useOwnLayer: true,
                settings: AniGlassTheme.chromeFor(context),
                controller: _searchCtrl,
                placeholder: 'Filter logs',
                onChanged: (_) => setState(() {}),
                textStyle: TextStyle(color: textColor),
                searchIconColor: secondaryTextColor,
                clearIconColor: secondaryTextColor,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['All', 'MPV', 'FFI', 'Shader', 'Error'].map((tag) {
                  return GlassChip(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    label: tag,
                    selected: _tag == tag,
                    labelStyle: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    onTap: () => setState(() => _tag = tag),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${visible.length} visible / ${LoggerService().logs.length} total',
                    style: TextStyle(color: secondaryTextColor, fontSize: 12),
                  ),
                  const Spacer(),
                  GlassButton(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onTap: () => _copyVisible(visible),
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    quality: AniGlassTheme.quality,
                    settings: AniGlassTheme.chromeFor(context),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onTap: _confirmClear,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          'No matching logs',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Color(0x1A0F172A)),
                        itemBuilder: (context, index) => _LogLine(
                          line: visible[index],
                          onCopyErrors: _copyErrors,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LogLine extends StatefulWidget {
  final String line;
  final Future<void> Function(BuildContext context)? onCopyErrors;

  const _LogLine({required this.line, this.onCopyErrors});

  @override
  State<_LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<_LogLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isError =
        widget.line.toLowerCase().contains('error') ||
        widget.line.toLowerCase().contains('failed');
    final textColor = AniGlassTheme.textColor(context);
    return InkWell(
      onTap: () {
        if (isError && widget.onCopyErrors != null) {
          unawaited(widget.onCopyErrors!(context));
          return;
        }
        setState(() => _expanded = !_expanded);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isError)
              Container(
                margin: const EdgeInsets.only(right: 8, top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'ERR',
                  style: TextStyle(color: Colors.redAccent, fontSize: 10),
                ),
              ),
            Expanded(
              child: Text(
                widget.line,
                maxLines: _expanded ? null : 2,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.82),
                  fontSize: 12,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  const _SettingsSurface({required this.child, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final light = AniGlassTheme.isLight(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.54)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: light
              ? Colors.black.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.08 : 0.24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = AniGlassTheme.textColor(context);
    final secondaryTextColor = AniGlassTheme.secondaryTextColor(context);
    return _SettingsSurface(
      borderRadius: 26,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: textColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
