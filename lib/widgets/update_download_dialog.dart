import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

/// Closes itself once [download] settles; closing it first, by the button or
/// the back gesture, cancels the download.
class UpdateDownloadDialog extends StatefulWidget {
  final Future<void> download;
  final ValueListenable<DownloadProgress> progress;
  final VoidCallback onCancel;
  final String? tip;

  const UpdateDownloadDialog({
    super.key,
    required this.download,
    required this.progress,
    required this.onCancel,
    this.tip,
  });

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.download.then<void>((_) => _close(), onError: (_) => _close()),
    );
  }

  void _close() {
    _settled = true;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    if (!_settled) {
      widget.onCancel();
    }
    super.dispose();
  }

  String _progressText(DownloadProgress progress) {
    final received = progress.received.traffic.show;
    if (progress.total <= 0) {
      return received;
    }
    return '$received / ${progress.total.traffic.show}';
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final tip = widget.tip;
    return CommonDialog(
      title: appLocalizations.downloadingUpdate,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appLocalizations.cancel),
        ),
      ],
      child: ValueListenableBuilder(
        valueListenable: widget.progress,
        builder: (context, progress, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              LinearProgressIndicator(
                minHeight: 4,
                value: progress.total > 0
                    ? progress.received / progress.total
                    : null,
              ),
              const SizedBox(height: 8),
              Text(_progressText(progress)),
              if (tip != null) ...[const SizedBox(height: 8), Text(tip)],
            ],
          );
        },
      ),
    );
  }
}
