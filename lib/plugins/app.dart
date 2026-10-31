import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken, ProgressCallback;
import 'package:fl_clash/common/boot_record.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

const _platformProbeTimeout = Duration(seconds: 2);

// The status codes of Android's PackageInstaller and DownloadManager.
const _packageInstallSucceeded = 0;
const _packageInstallAborted = 3;
const _downloadSuccessful = 8;
const _downloadFailed = 16;
const _downloadPollInterval = Duration(milliseconds: 500);

bool packageInstallFailed(int status) =>
    status != _packageInstallSucceeded && status != _packageInstallAborted;

class App {
  static App? _instance;
  late MethodChannel methodChannel;
  Function()? onExit;
  Function()? onPackagesChanged;
  final floatingKeyboard = ValueNotifier(false);

  App._internal() {
    methodChannel = const MethodChannel('$packageName/app');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'exit':
          if (onExit != null) {
            await onExit!();
          }
        case 'packagesChanged':
          onPackagesChanged?.call();
        case 'floatingImeChanged':
          floatingKeyboard.value = call.arguments as bool;
        default:
          throw MissingPluginException();
      }
    });
  }

  factory App() {
    _instance ??= App._internal();
    return _instance!;
  }

  Future<bool?> moveTaskToBack() async {
    return methodChannel.invokeMethod<bool>('moveTaskToBack');
  }

  Future<List<Package>> getPackages() async {
    final packagesString = await methodChannel.invokeMethod<String>(
      'getPackages',
    );
    final List<dynamic> packagesRaw =
        (await packagesString?.decodeJson<List<dynamic>>()) ?? [];
    return packagesRaw.map((e) => Package.fromJson(e)).toSet().toList();
  }

  Future<bool> isInstalledAppsPermissionGranted() async {
    return await methodChannel.invokeMethod<bool>(
          'isInstalledAppsPermissionGranted',
        ) ??
        true;
  }

  Future<bool> requestInstalledAppsPermission() async {
    return await methodChannel.invokeMethod<bool>(
          'requestInstalledAppsPermission',
        ) ??
        false;
  }

  /// Android 17 drops traffic between the app and the local network until the
  /// user grants this; earlier versions answer true.
  Future<bool> requestLocalNetworkPermission() async {
    return await methodChannel.invokeMethod<bool>(
          'requestLocalNetworkPermission',
        ) ??
        false;
  }

  Future<List<String>> getChinaPackageNames() async {
    final packageNamesString = await methodChannel.invokeMethod<String>(
      'getChinaPackageNames',
    );
    final List<dynamic> packageNamesRaw =
        await packageNamesString?.decodeJson<List<dynamic>>() ?? [];
    return packageNamesRaw.map((e) => e.toString()).toList();
  }

  final Map<String, ImageProvider?> _packageIcons = {};
  final Map<String, Future<ImageProvider?>> _packageIconTasks = {};
  final TaskPool _packageIconPool = TaskPool(maxConcurrentIconLoads);

  ImageProvider? getCachedPackageIcon(String packageName) {
    return _packageIcons[packageName];
  }

  Future<ImageProvider?> getPackageIcon(String packageName) {
    if (_packageIcons.containsKey(packageName)) {
      return Future.value(_packageIcons[packageName]);
    }
    return _packageIconTasks[packageName] ??= _loadPackageIcon(packageName);
  }

  Future<ImageProvider?> _loadPackageIcon(String packageName) async {
    var icon = await _requestPackageIcon(packageName);
    if (icon == null && packageName.isNotEmpty) {
      icon = await getPackageIcon('');
    }
    _packageIcons[packageName] = icon;
    unawaited(_packageIconTasks.remove(packageName));
    return icon;
  }

  Future<ImageProvider?> _requestPackageIcon(String packageName) async {
    try {
      final path = await _packageIconPool.run(
        () => methodChannel.invokeMethod<String>('getPackageIcon', {
          'packageName': packageName,
        }),
      );
      if (path == null || path.isEmpty) {
        return null;
      }
      return FileImage(File(path));
    } catch (error) {
      commonPrint.log('getPackageIcon error: $error');
      return null;
    }
  }

  @visibleForTesting
  void clearPackageIconCache() {
    _packageIcons.clear();
    _packageIconTasks.clear();
  }

  Future<bool?> tip(String? message) async {
    return methodChannel.invokeMethod<bool>('tip', {'message': '$message'});
  }

  Future<bool?> initShortcuts() async {
    return methodChannel.invokeMethod<bool>('initShortcuts', {
      'start': currentAppLocalizations.start,
      'stop': currentAppLocalizations.stop,
      'toggle': currentAppLocalizations.toggle,
    });
  }

  Future<bool?> updateExcludeFromRecents(bool value) async {
    return methodChannel.invokeMethod<bool>('updateExcludeFromRecents', {
      'value': value,
    });
  }

  Future<void> extractAsset(String asset, String path) async {
    await methodChannel.invokeMethod<bool>('extractAsset', {
      'asset': asset,
      'path': path,
    });
  }

  Future<void> downloadFile(
    Uri uri,
    String path, {
    required String title,
    required ProgressCallback onReceiveProgress,
    required CancelToken cancelToken,
  }) async {
    final int id;
    try {
      id = (await methodChannel.invokeMethod<int>('enqueueDownload', {
        'url': uri.toString(),
        'path': path,
        'title': title,
        'userAgent': browserUa,
      }))!;
    } on PlatformException catch (error) {
      commonPrint.log(
        'System download unavailable: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      throw const SystemDownloadException(null);
    }
    while (true) {
      await Future.any([
        Future<void>.delayed(_downloadPollInterval),
        cancelToken.whenCancel,
      ]);
      if (cancelToken.cancelError case final error?) {
        throw error;
      }
      final state = await methodChannel.invokeMapMethod<String, Object?>(
        'queryDownload',
        {'id': id},
      );
      if (state == null) {
        throw const SystemDownloadException(null);
      }
      onReceiveProgress(state['received'] as int, state['total'] as int);
      switch (state['status']) {
        case _downloadSuccessful:
          return;
        case _downloadFailed:
          throw SystemDownloadException(state['reason'] as int?);
      }
    }
  }

  Future<void> clearDownloads() async {
    await methodChannel.invokeMethod<bool>('clearDownloads');
  }

  /// An accepted update ends this process before its status can arrive.
  Future<int?> installPackage(String path) {
    return methodChannel.invokeMethod<int>('installPackage', {'path': path});
  }

  Future<bool?> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openAppSettings');
  }

  Future<AppExitInfo?> getLastExitInfo() async {
    try {
      final raw = await methodChannel
          .invokeMapMethod<String, Object?>('getLastExitInfo')
          .timeout(_platformProbeTimeout);
      return AppExitInfo.fromJson(raw);
    } catch (error) {
      commonPrint.log(
        'Failed to read the last process exit info: ${compactError(error)}',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }
}

final app = system.isAndroid ? App() : null;
