import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anivault/services/logger_service.dart';
import 'package:anivault/ui/ani_glass_theme.dart';

class SettingsScreen extends StatelessWidget {
  final Future<void> Function()? onLibraryRefresh;

  const SettingsScreen({super.key, this.onLibraryRefresh});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      background: AniGlassTheme.background(),
      statusBarStyle: GlassStatusBarStyle.dark,
      settings: AniGlassTheme.chrome,
      appBar: GlassAppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Color(0xFF0F172A)),
        ),
        leading: GlassButton(
          quality: GlassQuality.premium,
          settings: AniGlassTheme.chrome,
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

  const SettingsContent({
    super.key,
    this.topPadding = 0,
    this.onLibraryRefresh,
  });

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  final _clientCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAniDb();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAniDb() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _clientCtrl.text = prefs.getString('anidb_client') ?? '';
      _versionCtrl.text = '${prefs.getInt('anidb_clientver') ?? 1}';
    });
  }

  Future<void> _saveAniDb() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anidb_client', _clientCtrl.text.trim());
    await prefs.setInt(
      'anidb_clientver',
      int.tryParse(_versionCtrl.text.trim()) ?? 1,
    );
    await widget.onLibraryRefresh?.call();
    LoggerService().log('[Settings] AniDB API settings saved.');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('AniDB settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 36),
      children: [
        _SettingsPanel(
          icon: Icons.cloud_sync_rounded,
          title: 'AniDB API',
          subtitle: 'Metadata matching for imported anime',
          child: Column(
            children: [
              GlassTextField(
                quality: GlassQuality.premium,
                useOwnLayer: true,
                controller: _clientCtrl,
                placeholder: 'Client name',
                textStyle: const TextStyle(color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),
              GlassTextField(
                quality: GlassQuality.premium,
                useOwnLayer: true,
                controller: _versionCtrl,
                placeholder: 'Client version',
                keyboardType: TextInputType.number,
                textStyle: const TextStyle(color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton.custom(
                  quality: GlassQuality.premium,
                  settings: AniGlassTheme.chrome,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                  onTap: _saveAniDb,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'Save',
                      style: TextStyle(color: Color(0xFF0F172A)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsPanel(
          icon: Icons.diamond_rounded,
          title: 'Premium Glass',
          subtitle: 'Adaptive fallback is disabled for this build',
          child: _PremiumStatus(),
        ),
        const SizedBox(height: 16),
        const LogViewerPanel(),
      ],
    );
  }
}

class _PremiumStatus extends StatelessWidget {
  const _PremiumStatus();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusRow(label: 'Quality', value: 'GlassQuality.premium'),
        SizedBox(height: 8),
        _StatusRow(label: 'Adaptive', value: 'Disabled'),
        SizedBox(height: 8),
        _StatusRow(label: 'Fallback', value: 'Blocked by policy'),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: Color(0x990F172A))),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w600,
            ),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSearchBar(
                quality: GlassQuality.premium,
                useOwnLayer: true,
                controller: _searchCtrl,
                placeholder: 'Filter logs',
                onChanged: (_) => setState(() {}),
                textStyle: const TextStyle(color: Color(0xFF0F172A)),
                searchIconColor: const Color(0x990F172A),
                clearIconColor: const Color(0x990F172A),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['All', 'MPV', 'FFI', 'Shader', 'Error'].map((tag) {
                  return GlassChip(
                    quality: GlassQuality.premium,
                    label: tag,
                    selected: _tag == tag,
                    labelStyle: const TextStyle(
                      color: Color(0xFF0F172A),
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
                    style: const TextStyle(
                      color: Color(0x990F172A),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  GlassButton(
                    quality: GlassQuality.premium,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onTap: () => _copyVisible(visible),
                  ),
                  const SizedBox(width: 8),
                  GlassButton(
                    quality: GlassQuality.premium,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onTap: _confirmClear,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 360,
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching logs',
                          style: TextStyle(color: Color(0x990F172A)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Color(0x1A0F172A)),
                        itemBuilder: (context, index) =>
                            _LogLine(line: visible[index]),
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

  const _LogLine({required this.line});

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
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
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
                style: const TextStyle(
                  color: Color(0xCC0F172A),
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
    return GlassCard(
      quality: GlassQuality.premium,
      useOwnLayer: true,
      settings: AniGlassTheme.hero,
      padding: const EdgeInsets.all(18),
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0F172A), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0x990F172A),
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
    );
  }
}
