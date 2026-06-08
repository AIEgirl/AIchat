import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

class UpdateService {
  static const _remoteUrl = 'https://raw.githubusercontent.com/AIEgirl/AIchat/main/vision.json';
  static bool _checked = false;

  static Future<void> checkUpdate(BuildContext context) async {
    if (_checked) return;
    _checked = true;

    try {
      final localData = await _loadLocalVision();
      if (localData == null) return;
      final localSw = _parseVersion(localData['Software version']);
      final localIt = _parseVersion(localData['Iteration version']);
      debugPrint('[Update] local: SW=$localSw IT=$localIt');
      if (localSw == 0 && localIt == 0) {
        debugPrint('[Update] local version is 0.0, skipping check');
        return;
      }

      final response = await http.get(Uri.parse(_remoteUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final remoteJson = jsonDecode(response.body) as Map<String, dynamic>;
      final vision = remoteJson['vision'] as Map<String, dynamic>?;
      if (vision == null) return;

      final remoteSw = _parseVersion(vision['Software version']);
      final remoteIt = _parseVersion(vision['Iteration version']);
      final importance = vision['importance'] as bool? ?? false;
      final packageUrl = vision['package'] as String? ?? '';
      final describe = vision['describe'] as Map<String, dynamic>?;
      final descEn = describe?['English'] as String? ?? '';
      final descZh = describe?['Chinese'] as String? ?? '';

      final needUpdate = remoteSw > localSw || (remoteSw == localSw && remoteIt > localIt);
      debugPrint('[Update] remote: SW=$remoteSw IT=$remoteIt importance=$importance');
      debugPrint('[Update] needUpdate: $needUpdate');
      if (needUpdate) {
        if (!context.mounted) return;
        _showUpdateDialog(context, importance: importance, packageUrl: packageUrl, descEn: descEn, descZh: descZh);
      }
    } catch (_) {
      // Silently fail — network error or parse error
    }
  }

  static Future<Map<String, dynamic>?> _loadLocalVision() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/vision.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return (data['vision'] as Map<String, dynamic>?);
    } catch (_) {
      return null;
    }
  }

  static int _parseVersion(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static Future<void> _showUpdateDialog(BuildContext context, {
    required bool importance,
    required String packageUrl,
    required String descEn,
    required String descZh,
  }) async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final desc = locale == 'zh' ? descZh : descEn;

    await showDialog(
      context: context,
      barrierDismissible: !importance,
      builder: (ctx) => PopScope(
        canPop: !importance,
        child: AlertDialog(
          icon: Icon(
            importance ? Icons.warning_amber_rounded : Icons.system_update,
            color: importance ? scheme.error : scheme.primary,
            size: 32,
          ),
          title: Text(importance ? l10n.get('updateRequired') : l10n.get('updateOptional')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desc.isNotEmpty) ...[
                Text(desc, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
              ],
              if (importance)
                Text(l10n.get('forceUpdateTips'),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            if (!importance)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.get('later')),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (packageUrl.isNotEmpty) {
                  final uri = Uri.parse(packageUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
              child: Text(l10n.get('download')),
            ),
          ],
        ),
      ),
    );
  }
}
