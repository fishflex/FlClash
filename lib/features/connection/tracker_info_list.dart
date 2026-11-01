import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tracker_info_item.dart';
import 'tracker_info_table.dart';

class TrackerInfoListController extends ValueNotifier<TrackerInfosState> {
  TrackerInfoListController() : super(const TrackerInfosState());

  void search(String query) {
    value = value.copyWith(query: query);
  }

  void setTrackerInfos(List<TrackerInfo> trackerInfos) {
    if (identical(trackerInfos, value.trackerInfos)) {
      return;
    }
    value = value.copyWith(
      trackerInfos: value.autoScrollToEnd
          ? trackerInfos
          : retainTrimmedHead(
              value.trackerInfos,
              trackerInfos,
              pausedMaxRequestsLength,
              keyOf: (trackerInfo) => trackerInfo.id,
            ),
    );
  }

  void setAutoScrollToEnd(bool autoScrollToEnd) {
    value = value.copyWith(autoScrollToEnd: autoScrollToEnd);
  }

  void resumeAutoScrollToEnd(List<TrackerInfo> trackerInfos) {
    value = value.copyWith(autoScrollToEnd: true, trackerInfos: trackerInfos);
  }
}

RecordFilterController<TrackerInfo> trackerInfoFilterController(
  WidgetRef ref,
  String pageId,
) {
  return RecordFilterController(
    facets: trackerInfoFacets,
    groupers: trackerInfoGroupers,
    grouping: savedRecordGrouping(ref, pageId),
    onGroupingChanged: (grouping) => saveRecordGrouping(ref, pageId, grouping),
  );
}

class TrackerInfoList extends StatelessWidget {
  final List<TrackerInfo> trackerInfos;
  final String detailTitle;
  final RecordTable<TrackerInfo>? table;
  final ScrollController? controller;
  final bool reverse;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;
  final ValueChanged<TrackerInfo>? onClose;

  const TrackerInfoList({
    super.key,
    required this.trackerInfos,
    required this.detailTitle,
    this.table,
    this.controller,
    this.reverse = false,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return PrismListView(
      reverse: reverse,
      shrinkWrap: shrinkWrap,
      physics: physics,
      controller: controller,
      padding: padding,
      itemCount: trackerInfos.length,
      gap: table == null ? recordListGap : 0,
      estimatedItemExtent: table?.rowHeight ?? recordListEstimatedExtent,
      itemBuilder: (_, index) {
        final trackerInfo = trackerInfos[index];
        final striped = index.isOdd;
        return MemoBuilder(
          key: Key(trackerInfo.id),
          inputs: [
            trackerInfo,
            ...table == null ? [detailTitle] : [table, striped],
          ],
          builder: (_) => _buildTrackerInfoItem(
            trackerInfo,
            isLive: false,
            detailTitle: detailTitle,
            table: table,
            striped: striped,
            onClose: onClose,
          ),
        );
      },
    );
  }
}

/// Same rows as [TrackerInfoList], but diffed by connection id so closed
/// connections collapse out and surviving rows slide to their new slot.
class TrackerInfoAnimatedList extends StatelessWidget {
  final List<TrackerInfo> trackerInfos;
  final String detailTitle;
  final RecordTable<TrackerInfo>? table;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final ValueChanged<TrackerInfo>? onClose;

  const TrackerInfoAnimatedList({
    super.key,
    required this.trackerInfos,
    required this.detailTitle,
    this.table,
    this.controller,
    this.padding,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final table = this.table;
    final positions = table == null
        ? const <String, int>{}
        : {
            for (final (index, trackerInfo) in trackerInfos.indexed)
              trackerInfo.id: index,
          };
    return KeyedAnimatedList<TrackerInfo>(
      controller: controller,
      padding: padding,
      items: trackerInfos,
      keyOf: (trackerInfo) => trackerInfo.id,
      estimatedItemExtent: table?.rowHeight ?? recordListEstimatedExtent,
      separator: table == null ? const SizedBox(height: recordListGap) : null,
      itemBuilder: (itemContext, trackerInfo) {
        final striped = positions[trackerInfo.id]?.isOdd ?? false;
        return MemoBuilder(
          key: Key(trackerInfo.id),
          // A live row reads its age off the clock, which moves on its own.
          inputs: [
            trackerInfo,
            ...table == null
                ? [
                    detailTitle,
                    trackerInfo.start.getLastUpdateTimeDesc(
                      itemContext,
                      compact: true,
                    ),
                  ]
                : [table, striped],
          ],
          builder: (_) => _buildTrackerInfoItem(
            trackerInfo,
            isLive: true,
            detailTitle: detailTitle,
            table: table,
            striped: striped,
            onClose: onClose,
          ),
        );
      },
    );
  }
}

class TrackerInfoGroupedList extends ConsumerWidget {
  final List<RecordGroup<TrackerInfo>> groups;
  final RecordGrouping grouping;
  final bool isLive;
  final String detailTitle;
  final RecordTable<TrackerInfo>? table;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final ValueChanged<TrackerInfo>? onClose;

  const TrackerInfoGroupedList({
    super.key,
    required this.groups,
    required this.grouping,
    required this.isLive,
    required this.detailTitle,
    this.table,
    this.controller,
    this.padding,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showIcon =
        grouping == RecordGrouping.app &&
        ref.watch(
          patchClashConfigProvider.select(
            (state) =>
                state.findProcessMode == FindProcessMode.always &&
                system.isAndroid,
          ),
        );
    final table = this.table;
    return RecordGroupedList<TrackerInfo>(
      groups: groups,
      grouping: grouping,
      controller: controller,
      padding: padding,
      estimatedItemExtent: table?.rowHeight ?? recordListEstimatedExtent,
      leadingOf: (group) => showIcon && group.key.isNotEmpty
          ? PackageIcon(packageName: group.key, size: 24)
          : null,
      trailingOf: isLive ? (group) => _buildSpeed(context, group.items) : null,
      itemBuilder: (_, trackerInfo, index) {
        final row = _buildTrackerInfoItem(
          trackerInfo,
          isLive: isLive,
          detailTitle: detailTitle,
          table: table,
          striped: index.isOdd,
          onClose: onClose,
        );
        return table == null
            ? Padding(
                padding: const EdgeInsets.only(top: recordListGap),
                child: row,
              )
            : row;
      },
    );
  }

  Widget _buildSpeed(BuildContext context, List<TrackerInfo> trackerInfos) {
    var upload = 0;
    var download = 0;
    for (final trackerInfo in trackerInfos) {
      upload += trackerInfo.uploadSpeed ?? 0;
      download += trackerInfo.downloadSpeed ?? 0;
    }
    final color = context.colorScheme.onSurfaceVariant;
    WidgetSpan arrow(Glyph glyph) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GlyphIcon(glyph, size: 12, color: color),
    );
    return Text.rich(
      TextSpan(
        children: [
          arrow(AppGlyphs.arrowUp),
          TextSpan(text: ' ${upload.traffic.show}/s   '),
          arrow(AppGlyphs.arrowDown),
          TextSpan(text: ' ${download.traffic.show}/s'),
        ],
      ),
    );
  }
}

Widget _buildTrackerInfoItem(
  TrackerInfo trackerInfo, {
  required bool isLive,
  required String detailTitle,
  required RecordTable<TrackerInfo>? table,
  required bool striped,
  ValueChanged<TrackerInfo>? onClose,
}) {
  if (table != null) {
    return TrackerInfoTableRow(
      key: Key(trackerInfo.id),
      trackerInfo: trackerInfo,
      table: table,
      striped: striped,
      detailTitle: detailTitle,
      onClose: onClose,
    );
  }
  return TrackerInfoItem(
    key: Key(trackerInfo.id),
    trackerInfo: trackerInfo,
    isLive: isLive,
    onClose: onClose,
    detailTitle: detailTitle,
  );
}
