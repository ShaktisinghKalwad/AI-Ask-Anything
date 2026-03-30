import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class SettingsPage extends StatefulWidget {
  final String exportText;
  final ThemeMode initialThemeMode;
  final double initialFontScale;

  const SettingsPage({
    super.key,
    required this.exportText,
    required this.initialThemeMode,
    required this.initialFontScale,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ThemeMode _themeMode;
  late double _fontScale;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _fontScale = widget.initialFontScale.clamp(0.8, 1.4);
  }

  void _saveAndClose() {
    Navigator.of(context).pop({
      'theme': _themeToString(_themeMode),
      'fontScale': _fontScale,
    });
  }

  String _themeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  Future<void> _copyExportText() async {
    await Clipboard.setData(ClipboardData(text: widget.exportText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation copied to clipboard')),
    );
  }

  Future<void> _shareExportText() async {
    if (widget.exportText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export yet')),
      );
      return;
    }
    await Share.share(widget.exportText, subject: 'AI:Ask Anything - Conversation');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _saveAndClose,
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: _themeMode,
                  onChanged: (v) => setState(() => _themeMode = v ?? ThemeMode.system),
                  title: const Text('System'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: _themeMode,
                  onChanged: (v) => setState(() => _themeMode = v ?? ThemeMode.system),
                  title: const Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: _themeMode,
                  onChanged: (v) => setState(() => _themeMode = v ?? ThemeMode.system),
                  title: const Text('Dark'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Chat font size', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${_fontScale.toStringAsFixed(2)}x'),
            ],
          ),
          Slider(
            value: _fontScale,
            min: 0.8,
            max: 1.4,
            divisions: 12,
            label: '${(_fontScale * 100).round()}%',
            onChanged: (v) => setState(() => _fontScale = v),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Preview message text',
              style: TextStyle(fontSize: 16 * _fontScale),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Export', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Copy conversation (TXT)'),
            subtitle: const Text('Copies the current conversation to clipboard'),
            onTap: _copyExportText,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Share conversation (TXT)'),
            subtitle: const Text('Opens share dialog with the conversation text'),
            onTap: _shareExportText,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}
