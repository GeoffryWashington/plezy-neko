import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_text_field.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/library_query.dart';
import '../../../media/media_filter.dart';
import '../../../utils/scroll_utils.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/focusable_list_tile.dart';
import 'filter_operator_row.dart';
import 'filter_summary.dart';

/// Multi-select page for a field whose values the backend can enumerate.
///
/// Values inside the page OR (`genre=1,2`), and the include/exclude row flips
/// the whole clause when the backend can evaluate the negation. A field is
/// therefore always at most one clause here; ANDing two tags would need two
/// clauses on one field, which no supported backend evaluates for tags the
/// way the user would read it in a single list.
class FilterValuePage extends StatefulWidget {
  final MediaFilter filter;
  final List<MediaFilterValue> values;
  final LibraryFilter? clause;
  final String serverId;
  final String libraryKey;
  final ValueChanged<List<LibraryFilter>> onChanged;
  final FocusNode initialFocusNode;
  final VoidCallback onBack;

  /// Shown when the backend lists no values at all, so an empty picker
  /// explains itself instead of reading as broken.
  final String? emptyValuesMessage;

  const FilterValuePage({
    super.key,
    required this.filter,
    required this.values,
    required this.clause,
    required this.serverId,
    required this.libraryKey,
    required this.onChanged,
    required this.initialFocusNode,
    required this.onBack,
    this.emptyValuesMessage,
  });

  @override
  State<FilterValuePage> createState() => _FilterValuePageState();
}

class _FilterValuePageState extends State<FilterValuePage> {
  /// Above this many values a list is unusable without a filter box.
  static const int _searchThreshold = 15;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _firstItemKey = GlobalKey();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim();
      if (next == _search) return;
      setState(() => _search = next);
    });
    _rememberValueTitles();
    final selected = widget.clause?.values ?? const [];
    if (selected.isEmpty) return;
    final index = _orderedValues.indexWhere((value) => _idOf(value) == selected.first);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Offset by the header rows so the first selected value lands in view.
      final headers = widget.filter.supportsExclusion ? 2 : 1;
      scrollToCurrentItem(_scrollController, _firstItemKey, index + headers, isCurrent: () => mounted);
    });
  }

  @override
  void didUpdateWidget(FilterValuePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The host fetches the listing asynchronously, so the first build usually
    // has no rows yet; remember them on the build that finally carries them.
    if (!identical(oldWidget.values, widget.values)) _rememberValueTitles();
  }

  /// Record the title behind every row the page offers.
  ///
  /// Ids are what a clause stores, so the chip and the sheet can only name a
  /// selection whose listing has been seen. Recording on pick alone leaves a
  /// restored selection reading `1 selected` until the viewer re-picks it, so
  /// the listing itself is enough — no tap required.
  void _rememberValueTitles() {
    for (final value in _orderedValues) {
      FilterValueNames.remember(
        serverId: widget.serverId,
        libraryKey: widget.libraryKey,
        field: widget.filter.filter,
        value: _idOf(value),
        title: value.title,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _idOf(MediaFilterValue value) => libraryFilterValueId(value.key, widget.filter.filter);

  /// The rows this page offers: one per value id.
  ///
  /// A-Z for genre (the genre picker's own requirement), the server's order for
  /// every other field; ids are de-duplicated in all cases. A backend normally
  /// lists values unique, but a duplicated row would be counted twice in the
  /// header, so normalising keeps the count, the search and the rows describing
  /// one and the same set.
  List<MediaFilterValue> get _orderedValues {
    final byId = <String, MediaFilterValue>{};
    for (final value in widget.values) {
      byId.putIfAbsent(_idOf(value), () => value);
    }
    final rows = byId.values.toList();
    if (widget.filter.filter == MediaFilterField.genre) {
      rows.sort((a, b) => a.title.compareTo(b.title));
    }
    return rows;
  }

  /// Count line the genre page shows when its host supplies none: the number
  /// of rows actually rendered.
  String? get _defaultCountLabel {
    if (widget.filter.filter != MediaFilterField.genre) return null;
    final rows = _orderedValues.length;
    if (rows == 0) return null;
    return t.libraries.genreValuesCount(count: rows);
  }

  bool get _showSearch => _orderedValues.length > _searchThreshold;

  List<MediaFilterValue> get _visibleValues {
    final values = _orderedValues;
    if (_search.isEmpty) return values;
    final needle = _search.toLowerCase();
    return values.where((value) => value.title.toLowerCase().contains(needle)).toList();
  }

  LibraryFilterOperator get _operator => widget.clause?.op ?? LibraryFilterOperator.is_;

  void _emit(List<String> values, LibraryFilterOperator op) {
    widget.onChanged(values.isEmpty ? const [] : [LibraryFilter(field: widget.filter.filter, op: op, values: values)]);
  }

  void _toggle(MediaFilterValue value) {
    final id = _idOf(value);
    final selected = List<String>.from(widget.clause?.values ?? const []);
    if (!selected.remove(id)) {
      selected.add(id);
      FilterValueNames.remember(
        serverId: widget.serverId,
        libraryKey: widget.libraryKey,
        field: widget.filter.filter,
        value: id,
        title: value.title,
      );
    }
    _emit(selected, _operator);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.clause?.values ?? const <String>[];
    final visible = _visibleValues;
    final autofocusFirst = InputModeTracker.isKeyboardMode(context);
    final showOperatorRow = widget.filter.supportsExclusion;
    final headerCount = showOperatorRow ? 2 : 1;
    final list = ListView.builder(
      controller: _scrollController,
      primary: false,
      shrinkWrap: !_showSearch,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length + headerCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return FilterClearRow(
            key: _firstItemKey,
            selected: selected.isEmpty,
            focusNode: widget.initialFocusNode,
            autofocus: autofocusFirst,
            onPressed: () => _emit(const [], LibraryFilterOperator.is_),
          );
        }
        if (showOperatorRow && index == 1) {
          return FilterIncludeExcludeRow(
            filter: widget.filter,
            operator: _operator,
            onChanged: (op) => _emit(selected, op),
          );
        }
        final value = visible[index - headerCount];
        final id = _idOf(value);
        return FocusableCheckboxListTile(
          value: selected.contains(id),
          onChanged: (_) => _toggle(value),
          title: Text(value.title),
        );
      },
    );

    final countText = _defaultCountLabel;
    final emptyMessage = widget.values.isEmpty ? widget.emptyValuesMessage : null;
    final themes = Theme.of(context);
    final header = <Widget>[
      if (countText != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            countText,
            style: themes.textTheme.labelMedium?.copyWith(color: themes.colorScheme.onSurfaceVariant),
          ),
        ),
    ];
    // The Clear row above already says "nothing selected"; this says why there
    // is nothing else to choose, so the page never reads as a dead list.
    final notice = <Widget>[
      if (emptyMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(emptyMessage, style: themes.textTheme.bodyMedium),
        ),
    ];

    if (!_showSearch) {
      if (header.isEmpty && notice.isEmpty) return list;
      return Column(mainAxisSize: MainAxisSize.min, children: [...header, list, ...notice]);
    }

    // Deliberately filling: the list refilters as the user types, and a
    // content-sized sheet would drag the search field up and down under the
    // caret on every keystroke (same reason as SubtitleSearchSheet).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: FocusableTextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1, size: 20),
              hintText: t.libraries.advancedFilters.searchValues,
              border: const OutlineInputBorder(),
            ),
            onBack: widget.onBack,
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(t.libraries.advancedFilters.noValues))
              : Scrollbar(controller: _scrollController, child: list),
        ),
        ...notice,
      ],
    );
  }
}
