import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';
import '../services/neko_update_service.dart';

class NekoUpdateDialog extends StatefulWidget {
  final NekoRelease release;

  const NekoUpdateDialog({super.key, required this.release});

  static Future<void> show(BuildContext context, NekoRelease release) =>
      showDialog(context: context, builder: (_) => NekoUpdateDialog(release: release));

  @override
  State<NekoUpdateDialog> createState() => _NekoUpdateDialogState();
}

class _NekoUpdateDialogState extends State<NekoUpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.neko.updateTitle(version: widget.release.version)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.release.notes.isEmpty ? '' : widget.release.notes,
                ),
              ),
            ),
            if (_downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(t.neko.downloading),
            ],
            if (_error != null)
              Text(
                t.neko.updateFailed(error: _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: Text(t.neko.later),
        ),
        FilledButton(
          onPressed: _downloading
              ? null
              : () async {
                  setState(() => _downloading = true);
                  try {
                    await NekoUpdateService.instance.downloadAndInstall(
                      widget.release,
                      onProgress: (p) => setState(() => _progress = p),
                    );
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _error = e.toString();
                        _downloading = false;
                      });
                    }
                  }
                },
          child: Text(t.neko.updateNow),
        ),
      ],
    );
  }
}
