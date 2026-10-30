import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/dialog.dart';
import 'package:fl_clash/widgets/update_download_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  late ValueNotifier<DownloadProgress> progress;
  late Completer<void> download;
  late int cancels;

  setUp(() {
    progress = ValueNotifier((received: 0, total: 0));
    cancels = 0;
  });

  tearDown(() => progress.dispose());

  // Created inside the test body: a future from setUp settles in the real zone,
  // which the fake-async pumps never drain.
  Future<void> open(WidgetTester tester, {String? tip}) async {
    download = Completer();
    await tester.pumpWidget(
      TestApp(
        includeNavigatorKey: false,
        child: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showFloatingDialog<void>(
                context: context,
                dismissible: false,
                child: UpdateDownloadDialog(
                  download: download.future,
                  progress: progress,
                  onCancel: () => cancels++,
                  tip: tip,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // An indeterminate bar animates for as long as it shows.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  LinearProgressIndicator bar(WidgetTester tester) {
    return tester.widget(find.byType(LinearProgressIndicator));
  }

  testWidgets('follows the bytes received', (tester) async {
    await open(tester, tip: 'restarts');

    expect(bar(tester).value, isNull);
    expect(find.text('0B'), findsOneWidget);
    expect(find.text('restarts'), findsOneWidget);

    progress.value = (received: 1024 * 1024, total: 4 * 1024 * 1024);
    await tester.pump();

    expect(bar(tester).value, 0.25);
    expect(find.text('1MB / 4MB'), findsOneWidget);
  });

  testWidgets('closes itself once the download settles', (tester) async {
    await open(tester);

    download.completeError(Exception('offline'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDownloadDialog), findsNothing);
    expect(cancels, 0);
  });

  testWidgets('cancels the download when closed first', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(UpdateDownloadDialog), findsNothing);
    expect(cancels, 1);
  });
}
