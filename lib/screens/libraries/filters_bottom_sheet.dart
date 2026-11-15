import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_button.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../media/library_filter_selection.dart';
import '../../media/library_query.dart';
import '../../media/media_filter.dart';
import '../../utils/app_logger.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_page_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/overlay_sheet.dart';
import 'filters/filter_operator_row.dart';
import 'filters/filter_range_page.dart';
import 'filters/filter_summary.dart';
import 'filters/filter_text_page.dart';
import 'filters/filter_value_page.dart';
import 'state_messages.dart';

typedef FilterValuesLoader = Future<List<MediaFilterValue>> Function(MediaFilter filter);

/// The library filter editor.
///
/// Two pages: the category list, and one editor per category chosen by the
/// field's [MediaFilter.editorKind]. Every edit is staged locally and pushed
/// to [onFiltersChanged] so the host can commit once on dismissal — a
/// multi-select page cannot apply-and-close on each tap, and reloading the
/// grid per checkbox would issue a request per keystroke.
///
/// Hosted by `OverlaySheetHost` on touch/TV and by `showAnchoredFilterPanel`
/// on pointer platforms; both paths render this same widget, so the surfaces
/// cannot drift apart.
class FiltersBottomSheet extends StatefulWidget {
  final List<MediaFilter> filters;
  final List<LibraryFilter> selectedFilters;
  final ValueChanged<List<LibraryFilter>> onFiltersChanged;
  final String serverId;
  final String libraryKey;
  final FilterValuesLoader loadFilterValues;
  final VoidCallback? onBack;

  /// Optional pre-fetched values per filter name. When non-null the editor
  /// reads from this instead of calling [loadFilterValues] — used for
  /// MediaBrowser libraries where values arrive with the category listing.
  final Map<String, List<MediaFilterValue>>? cachedValues;

  /// Filter key (e.g. `genre`) whose editor page the sheet opens on arrival.
  ///
  /// Lets an entry point that names one category — the genre chip — reuse this
  /// editor instead of growing a second picker. Null opens the category list.
  final String? initialFilter;

  const FiltersBottomSheet({
    super.key,
    required this.filters,
    required this.selectedFilters,
    required this.onFiltersChanged,
    required this.serverId,
    required this.libraryKey,
    required this.loadFilterValues,
    this.onBack,
    this.cachedValues,
    this.initialFilter,
  });

  @override
  State<FiltersBottomSheet> createState() => _FiltersBottomSheetState();
}

class _FiltersBottomSheetState extends State<FiltersBottomSheet> {
  MediaFilter? _currentFilter;
  List<MediaFilterValue> _filterValues = [];
  bool _isLoadingValues = false;
  String? _filterValuesError;
  int _filterValuesLoadGeneration = 0;
  final _contentKey = GlobalKey();
  double? _transitionMinHeight;
  late List<LibraryFilter> _selection;
  late List<MediaFilter> _sortedFilters;
  late final FocusNode _initialFocusNode;

  /// Scroll position of the category list. Owned so the list can carry a
  /// permanent scrollbar thumb — the sheet is used from a menu-sized anchored
  /// panel, where the server's 40 categories never fit at once.
  final ScrollController _categoryScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _selection = List<LibraryFilter>.of(widget.selectedFilters);
    _sortFilters();
    _initialFocusNode = FocusNode(debugLabel: 'FiltersBottomSheetInitialFocus');
    _openInitialFilter();
  }

  /// Open the page [FiltersBottomSheet.initialFilter] names on arrival.
  ///
  /// Deferred a frame: the swap measures the outgoing page's height (see
  /// [_loadFilterValues]), which needs this sheet laid out first.
  void _openInitialFilter() {
    final filter = _filterForInitialPage(widget.initialFilter);
    if (filter == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openFilter(filter));
    });
  }

  /// The filter [key] names, or null when the sheet was asked for no page.
  ///
  /// A Plex section that publishes no genre field still offers the genre
  /// editor: the values come from the section's own `/genre` listing, never
  /// from a hard-coded name list, and this filter is only the page —
  /// the category rows stay data-driven, so no row appears for it. The `key`
  /// marks the field enumerable (so the page is a value list and summaries
  /// resolve names); the host's loader derives the real per-grouping path.
  MediaFilter? _filterForInitialPage(String? key) {
    if (key == null) return null;
    for (final filter in widget.filters) {
      if (filter.filter == key) return filter;
    }
    if (key != MediaFilterField.genre) return null;
    return MediaFilter.genreFallback(title: t.libraries.filterCategories.genre);
  }

  @override
  void didUpdateWidget(covariant FiltersBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged = oldWidget.serverId != widget.serverId || oldWidget.libraryKey != widget.libraryKey;
    if (ownerChanged) {
      _filterValuesLoadGeneration++;
      _currentFilter = null;
      _filterValues = [];
      _isLoadingValues = false;
      _filterValuesError = null;
      _selection = List<LibraryFilter>.of(widget.selectedFilters);
    }
    if (ownerChanged || !identical(oldWidget.filters, widget.filters)) {
      _sortFilters();
    }
  }

  @override
  void dispose() {
    _filterValuesLoadGeneration++;
    _initialFocusNode.dispose();
    _categoryScroll.dispose();
    super.dispose();
  }

  void _sortFilters() {
    // Booleans first: they are one-touch on the category list, so keeping
    // them above the drill-in rows puts the cheapest controls in reach.
    final booleanFilters = widget.filters.where((f) => f.isBoolean).toList();
    final regularFilters = widget.filters.where((f) => !f.isBoolean).toList();
    _sortedFilters = [...booleanFilters, ...regularFilters];
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  void _commitSelection(List<LibraryFilter> next) {
    setState(() => _selection = next);
    widget.onFiltersChanged(List<LibraryFilter>.of(next));
  }

  void _setField(String field, List<LibraryFilter> clauses) => _commitSelection(_selection.withField(field, clauses));

  void _clearFilters() {
    _filterValuesLoadGeneration++;
    _commitSelection(const []);
  }

  // ---------------------------------------------------------------------
  // Values
  // ---------------------------------------------------------------------

  Future<void> _openFilter(MediaFilter filter) async {
    if (filter.editorKind != FilterEditorKind.valueList) {
      // Nothing to fetch, so no transient state to hold a height for.
      final generation = ++_filterValuesLoadGeneration;
      setState(() {
        _currentFilter = filter;
        _filterValues = [];
        _isLoadingValues = false;
        _filterValuesError = null;
      });
      _requestInitialFocus(generation, widget.serverId, widget.libraryKey, filter.filter);
      return;
    }
    await _loadFilterValues(filter);
  }

  Future<void> _loadFilterValues(MediaFilter filter) async {
    final generation = ++_filterValuesLoadGeneration;
    final filterKey = filter.filter;
    final serverId = widget.serverId;
    final libraryKey = widget.libraryKey;
    final cachedValues = widget.cachedValues;
    final loader = widget.loadFilterValues;
    // Drilling in is a setState page swap inside one sheet, and sheets are
    // bottom-anchored, so any height change during the load drags the header
    // and its Back button. Hold the outgoing page's height for the transient
    // spinner; the settled states below are free to hug again.
    _transitionMinHeight = _contentHeight();
    setState(() {
      _currentFilter = filter;
      _filterValues = [];
      _isLoadingValues = true;
      _filterValuesError = null;
    });

    try {
      // Cached path (MediaBrowser) — the category listing carried the values.
      final cached = cachedValues?[filterKey];
      final values = cached ?? await loader(filter);
      if (!_isCurrentFilterValuesLoad(generation, serverId, libraryKey, filterKey)) return;
      setState(() {
        _filterValues = values;
        _isLoadingValues = false;
      });
      _requestInitialFocus(generation, serverId, libraryKey, filterKey);
    } catch (e, stackTrace) {
      if (!_isCurrentFilterValuesLoad(generation, serverId, libraryKey, filterKey)) return;
      appLogger.w('Failed to load values for filter $filterKey', error: e, stackTrace: stackTrace);
      setState(() {
        _filterValues = [];
        _isLoadingValues = false;
        _filterValuesError = t.errors.unableToLoad(context: filter.title);
      });
      _requestInitialFocus(generation, serverId, libraryKey, filterKey);
    }
  }

  bool _isCurrentFilterValuesLoad(int generation, String serverId, String libraryKey, String? filterKey) {
    return mounted &&
        generation == _filterValuesLoadGeneration &&
        widget.serverId == serverId &&
        widget.libraryKey == libraryKey &&
        _currentFilter?.filter == filterKey;
  }

  void _goBack() {
    final generation = ++_filterValuesLoadGeneration;
    final serverId = widget.serverId;
    final libraryKey = widget.libraryKey;
    _transitionMinHeight = _contentHeight();
    setState(() {
      _currentFilter = null;
      _filterValues = [];
      _isLoadingValues = false;
      _filterValuesError = null;
    });
    _requestInitialFocus(generation, serverId, libraryKey, null);
  }

  void _requestInitialFocus(int generation, String serverId, String libraryKey, String? filterKey) {
    if (!InputModeTracker.isKeyboardMode(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentFilterValuesLoad(generation, serverId, libraryKey, filterKey)) return;
      if (_initialFocusNode.context != null) {
        _initialFocusNode.requestFocus();
      } else {
        OverlaySheetController.maybeOf(context)?.refocus();
      }
    });
  }

  /// Height held by the transient spinner when the outgoing page never
  /// reported one.
  static const double _fallbackTransitionHeight = 160;

  /// Height the content area currently occupies, used to hold the sheet steady
  /// across a page swap. Null before first layout.
  double? _contentHeight() {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize == true ? box!.size.height : null;
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final currentFilter = _currentFilter;
    return BottomSheetPageScaffold(
      title: currentFilter?.title ?? t.libraries.filters,
      icon: Symbols.filter_alt_rounded,
      onBack: currentFilter != null ? _goBack : widget.onBack,
      action: currentFilter == null && _selection.isNotEmpty
          ? FocusableButton(
              onPressed: _clearFilters,
              child: TextButton.icon(
                onPressed: _clearFilters,
                icon: const AppIcon(Symbols.clear_all_rounded, fill: 1),
                label: Text(t.libraries.clearAll),
              ),
            )
          : null,
      child: KeyedSubtree(
        key: _contentKey,
        child: currentFilter != null ? _buildFilterPage(currentFilter) : _buildFiltersView(),
      ),
    );
  }

  Widget _buildFilterPage(MediaFilter filter) {
    final error = _filterValuesError;
    if (error != null) {
      // The StateMessageWidget family is filling by design, so the unbounded
      // scroll axis is what lets its inner Center shrink to content instead of
      // stretching the sheet to the height cap for one line of text.
      return SingleChildScrollView(
        primary: false,
        child: ErrorStateWidget(
          message: error,
          onRetry: () => _loadFilterValues(filter),
          actionFocusNode: _initialFocusNode,
          onActionBack: _goBack,
          actionAutofocus: InputModeTracker.isKeyboardMode(context),
          actionUseBackgroundFocus: true,
        ),
      );
    }
    if (_isLoadingValues) {
      // Held at the outgoing page's height (see [_loadFilterValues]) so the
      // transient spinner cannot move the header. Settled states below hug.
      // The fallback covers a drill-in before the outgoing page has been laid
      // out: an unsized box here would inflate the sheet to its cap and back.
      return Focus(
        autofocus: InputModeTracker.isKeyboardMode(context),
        child: SizedBox(
          height: _transitionMinHeight ?? _fallbackTransitionHeight,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final clauses = _selection.clausesFor(filter.filter);
    return switch (filter.editorKind) {
      FilterEditorKind.valueList => FilterValuePage(
        filter: filter,
        values: _filterValues,
        clause: clauses.firstOrNull,
        serverId: widget.serverId,
        libraryKey: widget.libraryKey,
        initialFocusNode: _initialFocusNode,
        onBack: _goBack,
        onChanged: (next) => _setField(filter.filter, next),
        emptyValuesMessage: filter.filter == MediaFilterField.genre ? t.libraries.genreValuesEmpty : null,
      ),
      FilterEditorKind.number => FilterNumberPage(
        filter: filter,
        clauses: clauses,
        initialFocusNode: _initialFocusNode,
        onBack: _goBack,
        onChanged: (next) => _setField(filter.filter, next),
      ),
      FilterEditorKind.date => FilterDatePage(
        filter: filter,
        clauses: clauses,
        initialFocusNode: _initialFocusNode,
        onBack: _goBack,
        onChanged: (next) => _setField(filter.filter, next),
      ),
      FilterEditorKind.text => FilterTextPage(
        filter: filter,
        clause: clauses.firstOrNull,
        initialFocusNode: _initialFocusNode,
        onBack: _goBack,
        onChanged: (next) => _setField(filter.filter, next),
      ),
      // Booleans are edited in place on the category list.
      FilterEditorKind.toggle => const SizedBox.shrink(),
    };
  }

  Widget _buildFiltersView() {
    final autofocusFirst = InputModeTracker.isKeyboardMode(context);
    // A Plex section declares its whole filter schema — the measured Movies
    // section publishes 40 fields — so this list is always taller than the
    // panel that hosts it. Two things keep the categories that start below the
    // fold from being invisible on a first open:
    //
    // * the mouse is a drag device here. Flutter leaves `PointerDeviceKind
    //   .mouse` out of `dragDevices` on every platform, so without this a
    //   left-button drag on the list moves it 0 px (measured: two cold starts
    //   with pixel-identical frames) and a desktop user cannot reach row 12;
    // * the thumb is visible before the first scroll, because a list with no
    //   scrollbar reads as a complete list.
    //
    // `scrollbars: false` on the behaviour suppresses the implicit Material
    // scrollbar this subtree would otherwise also get on desktop.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.unknown,
        },
      ),
      child: Scrollbar(
        controller: _categoryScroll,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _categoryScroll,
          primary: false,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _sortedFilters.length,
          itemBuilder: (context, index) {
            final filter = _sortedFilters[index];
            final focusNode = index == 0 ? _initialFocusNode : null;
            final autofocus = index == 0 && autofocusFirst;

            if (filter.isBoolean) {
              final clause = _selection.clauseFor(filter.filter);
              return FilterBooleanRow(
                filter: filter,
                value: clause == null ? null : !clause.op.isNegated,
                focusNode: focusNode,
                autofocus: autofocus,
                onChanged: (value) => _setField(
                  filter.filter,
                  value == null
                      ? const []
                      : [
                          LibraryFilter(
                            field: filter.filter,
                            op: value ? LibraryFilterOperator.is_ : LibraryFilterOperator.isNot,
                            values: const ['1'],
                          ),
                        ],
                ),
              );
            }

            final summary = filterFieldSummary(
              filter: filter,
              clauses: _selection,
              serverId: widget.serverId,
              libraryKey: widget.libraryKey,
            );
            return FocusableListTile(
              focusNode: focusNode,
              autofocus: autofocus,
              title: Text(filter.title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (summary != null)
                    Flexible(
                      child: Text(
                        summary,
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (summary != null) const SizedBox(width: 8),
                  const AppIcon(Symbols.chevron_right_rounded, fill: 1),
                ],
              ),
              onTap: () => unawaited(_openFilter(filter)),
            );
          },
        ),
      ),
    );
  }
}
