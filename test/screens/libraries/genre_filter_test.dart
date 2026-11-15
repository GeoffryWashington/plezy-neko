import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/filters/filter_summary.dart';
import 'package:plezy/screens/libraries/filters/filter_value_page.dart';
import 'package:plezy/screens/libraries/filters_bottom_sheet.dart';
import 'package:plezy/screens/libraries/state_messages.dart';
import 'package:plezy/screens/libraries/tabs/library_browse_tab.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/widgets/focusable_filter_chip.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/overlay_sheet.dart';

import '../../test_helpers/backend_client_fixtures.dart';
import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

/// Genre ids as the captured server hands them out (`/genre?type=1`).
const String _actionId = '1278';
const String _comedyId = '1594';
const String _dramaId = '1592';

/// The mock server's catalogue: the genre clause the app sends decides which
/// of these come back, so the grid is the server's answer — not a list the test
/// picked to match the assertion.
///
/// `unwatched` is the second filter the composition test pairs with genre: the
/// two sets overlap partially (two genre matches, two unwatched, one in both),
/// so an intersection and a union are different numbers.
const List<({String key, String title, List<String> genreIds, bool unwatched})> _movies = [
  (key: 'movie-action', title: 'Action One', genreIds: [_actionId], unwatched: true),
  (key: 'movie-comedy', title: 'Comedy One', genreIds: [_comedyId], unwatched: true),
  (key: 'movie-drama', title: 'Drama One', genreIds: [_dramaId], unwatched: false),
  (key: 'movie-both', title: 'Action Comedy', genreIds: [_actionId, _comedyId], unwatched: false),
];

/// [_movies] plus [extraActionMovies] more Action titles — enough rows for the
/// paging test to need a real second page.
List<({String key, String title, List<String> genreIds, bool unwatched})> _catalogueWith(int extraActionMovies) => [
  ..._movies,
  for (var i = 0; i < extraActionMovies; i++)
    (key: 'bulk-$i', title: 'Action Bulk $i', genreIds: const [_actionId], unwatched: true),
];

/// Show-level catalogue for the TV harness. Two single-genre shows plus one
/// carrying both, so Action ∩ Comedy is a genuine partial overlap (2 / 2 / 1)
/// rather than a degenerate empty or subset pair.
const List<({String key, String title, List<String> genres})> _shows = [
  (key: 'show-action', title: 'Action Show', genres: [_actionId]),
  (key: 'show-comedy', title: 'Comedy Show', genres: [_comedyId]),
  (key: 'show-both', title: 'Action Comedy Show', genres: [_actionId, _comedyId]),
];

/// [_movies] plus [extraActionComedyMovies] titles carrying BOTH Action and
/// Comedy — the fixture that makes a two-genre intersection span pages.
List<({String key, String title, List<String> genreIds, bool unwatched})> _catalogueWithBoth(
  int extraActionMovies,
  int extraActionComedyMovies,
) => [
  ..._catalogueWith(extraActionMovies),
  for (var i = 0; i < extraActionComedyMovies; i++)
    (key: 'both-$i', title: 'Action Comedy Bulk $i', genreIds: const [_actionId, _comedyId], unwatched: true),
];

/// The server lists values in its own order; one row is repeated on purpose so
/// the picker has to de-duplicate and sort what it renders.
const List<Map<String, Object?>> _genreRows = [
  {'key': _comedyId, 'title': 'Comedy', 'type': 'genre'},
  {'key': _actionId, 'title': 'Action', 'type': 'genre'},
  {'key': _dramaId, 'title': 'Drama', 'type': 'genre'},
  {'key': _comedyId, 'title': 'Comedy', 'type': 'genre'},
];

/// Every filter field the owner's Plex server publishes for section 11,
/// replayed verbatim from `evidence/plex-metadata-movies-before.json`
/// (`Meta.Type[type=movie].Field[]`, captured 2026-11-14): 40 rows, `genre`
/// among them. The sheet's category list is the server's set and nothing else,
/// so the cold-start test below can say "these and no others".
const List<Map<String, Object?>> _capturedMetaFields = [
  {'key': 'title', 'title': 'Title', 'type': 'string'},
  {'key': 'studio', 'title': 'Studio', 'type': 'string'},
  {'key': 'userRating', 'title': 'Rating', 'type': 'integer', 'subType': 'rating'},
  {'key': 'contentRating', 'title': 'Content Rating', 'type': 'tag'},
  {'key': 'year', 'title': 'Year', 'type': 'integer', 'subType': 'year'},
  {'key': 'decade', 'title': 'Decade', 'type': 'integer', 'subType': 'decade'},
  {'key': 'originallyAvailableAt', 'title': 'Release Date', 'type': 'date'},
  {'key': 'duration', 'title': 'Duration', 'type': 'integer', 'subType': 'duration'},
  {'key': 'unmatched', 'title': 'Unmatched', 'type': 'boolean'},
  {'key': 'duplicate', 'title': 'Duplicate', 'type': 'boolean'},
  {'key': 'genre', 'title': 'Genre', 'type': 'tag'},
  {'key': 'collection', 'title': 'Collection', 'type': 'tag'},
  {'key': 'director', 'title': 'Director', 'type': 'tag'},
  {'key': 'writer', 'title': 'Writer', 'type': 'tag'},
  {'key': 'producer', 'title': 'Producer', 'type': 'tag'},
  {'key': 'actor', 'title': 'Actor', 'type': 'tag'},
  {'key': 'country', 'title': 'Country', 'type': 'tag'},
  {'key': 'addedAt', 'title': 'Date Added', 'type': 'date'},
  {'key': 'viewCount', 'title': 'Plays', 'type': 'integer'},
  {'key': 'lastViewedAt', 'title': 'Last Watched', 'type': 'date'},
  {'key': 'unwatched', 'title': 'Unwatched', 'type': 'boolean'},
  {'key': 'resolution', 'title': 'Resolution', 'type': 'resolution'},
  {'key': 'hdr', 'title': 'HDR', 'type': 'boolean', 'subType': 'hdr'},
  {'key': 'dovi', 'title': 'DOVI', 'type': 'boolean', 'subType': 'dovi'},
  {'key': 'hdr10plus', 'title': 'HDR10+', 'type': 'boolean', 'subType': 'hdr10plus'},
  {'key': 'atmos', 'title': 'Atmos', 'type': 'boolean', 'subType': 'atmos'},
  {'key': 'mediaSize', 'title': 'File Size', 'type': 'integer', 'subType': 'fileSize'},
  {'key': 'mediaBitrate', 'title': 'Bitrate', 'type': 'integer', 'subType': 'bitrate'},
  {'key': 'videoCodec', 'title': 'Video Codec', 'type': 'tag', 'subType': 'videoCodec'},
  {'key': 'audioCodec', 'title': 'Audio Codec', 'type': 'tag', 'subType': 'audioCodec'},
  {'key': 'subtitleCodec', 'title': 'Subtitle Codec', 'type': 'tag', 'subType': 'subtitleCodec'},
  {'key': 'audioLayout', 'title': 'Audio Layout', 'type': 'tag', 'subType': 'audioLayout'},
  {'key': 'subtitleLanguage', 'title': 'Subtitle Language', 'type': 'subtitleLanguage'},
  {'key': 'audioLanguage', 'title': 'Audio Language', 'type': 'audioLanguage'},
  {'key': 'inProgress', 'title': 'In Progress', 'type': 'boolean'},
  {'key': 'trash', 'title': 'Trash', 'type': 'boolean'},
  {'key': 'location', 'title': 'Folder Location', 'type': 'tag'},
  {'key': 'editionTitle', 'title': 'Edition', 'type': 'string'},
  {'key': 'contentRatingAge', 'title': 'Common Sense Media Age Rating', 'type': 'integer'},
  {'key': 'label', 'title': 'Label', 'type': 'tag'},
];

/// The same replay for a TV Shows section: `Meta.Type[type=show].Field[]` from
/// `evidence/plex-metadata-tv-before.json` — 21 show-level fields, `show.genre`
/// among them. Plex qualifies cross-type fields with their owner (`show.`), so
/// the sheet's row for it is the stripped `genre` clause with the declared
/// title.
const List<Map<String, Object?>> _capturedShowFields = [
  {'key': 'show.title', 'title': 'Show Title', 'type': 'string'},
  {'key': 'show.studio', 'title': 'Studio', 'type': 'string'},
  {'key': 'show.network', 'title': 'Network', 'type': 'tag'},
  {'key': 'show.country', 'title': 'Country', 'type': 'tag'},
  {'key': 'show.userRating', 'title': 'Show Rating', 'type': 'integer', 'subType': 'rating'},
  {'key': 'show.contentRating', 'title': 'Content Rating', 'type': 'tag'},
  {'key': 'show.year', 'title': 'Show Year', 'type': 'integer', 'subType': 'year'},
  {'key': 'show.viewCount', 'title': 'Show Plays', 'type': 'integer'},
  {'key': 'show.lastViewedAt', 'title': 'Show Last Watched', 'type': 'date'},
  {'key': 'show.genre', 'title': 'Genre', 'type': 'tag'},
  {'key': 'show.collection', 'title': 'Show Collection', 'type': 'tag'},
  {'key': 'show.director', 'title': 'Show Director', 'type': 'tag'},
  {'key': 'show.writer', 'title': 'Show Writer', 'type': 'tag'},
  {'key': 'show.producer', 'title': 'Show Producer', 'type': 'tag'},
  {'key': 'show.actor', 'title': 'Show Actor', 'type': 'tag'},
  {'key': 'show.addedAt', 'title': 'Date Show Added', 'type': 'date'},
  {'key': 'show.unmatched', 'title': 'Show Unmatched', 'type': 'boolean'},
  {'key': 'show.unwatchedLeaves', 'title': 'Unwatched Episodes', 'type': 'boolean'},
  {'key': 'show.editionTitle', 'title': 'Show Edition', 'type': 'string'},
  {'key': 'show.contentRatingAge', 'title': 'Common Sense Media Age Rating', 'type': 'integer'},
  {'key': 'show.label', 'title': 'Label', 'type': 'tag'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  testWidgets('AC1 the genre chip sits in the chips row and opens the genre page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    expect(find.widgetWithText(FocusableFilterChip, 'Genre'), findsOneWidget);

    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();

    // One editor, not a second picker: the chip opens the filter editor's
    // genre page.
    expect(find.byType(FilterValuePage), findsOneWidget);
    expect(tester.widget<FilterValuePage>(find.byType(FilterValuePage)).filter.filter, 'genre');
    expect(tester.takeException(), isNull);

    await _dismissPanel(tester);

    // The compact options sheet carries the same entry point, keyed so the
    // screen can name it without a hard-coded row label lookup.
    final tabState = tester.state(find.byType(LibraryBrowseTab));
    (tabState as dynamic).showBrowseOptionsSheet();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('libraryGenreRow')), findsOneWidget);

    await tester.tap(find.byKey(const Key('libraryGenreRow')));
    await tester.pumpAndSettle();
    expect(find.byType(FilterValuePage), findsOneWidget);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC2 the picker lists the library genres A-Z, de-duplicated, with a count', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();

    // The listing is the one the browse grouping queries.
    expect(harness.valueRequests, isNotEmpty);
    final request = harness.valueRequests.single;
    expect(request.path, '/library/sections/movies/genre');
    expect(request.queryParameters['type'], '1');

    final rows = tester.widgetList<FocusableCheckboxListTile>(find.byType(FocusableCheckboxListTile)).toList();
    final titles = [for (final row in rows) (row.title! as Text).data];
    expect(titles, ['Action', 'Comedy', 'Drama']);
    expect(titles.toSet(), hasLength(titles.length), reason: 'the duplicated server row must not render twice');
    expect(find.text('3 genres'), findsOneWidget, reason: 'the count matches the rows the page offers');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC3 choosing a genre filters the grid and shows it on the chip', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();

    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    final query = harness.pageRequests.last.queryParameters;
    expect(query['genre'], _actionId);
    expect(query['type'], '1', reason: 'the active grouping still decides the item type');

    // The grid is what the server answered for that clause, and the chip names
    // the selection the app committed.
    expect(find.text('Action One'), findsOneWidget);
    expect(find.text('Action Comedy'), findsOneWidget);
    expect(find.text('Comedy One'), findsNothing);
    expect(find.byType(FocusableMediaCard), findsNWidgets(2));
    expect(harness.lastTotalSize, 2, reason: 'the grid holds exactly what the server said that query totals');
    expect(find.widgetWithText(FocusableFilterChip, 'Genre: Action'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC6 the genre selection persists per library and clearing removes it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);
    final storage = await StorageService.getInstance();

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);
    await _selectGenre(tester, harness, 'Action');

    // The write goes through the tab's own commit path, so the round-trip is
    // graded on the section key, not on a literal preference name.
    final saved = storage.getLibraryFilters(sectionId: harness.library.globalKey);
    expect(saved, hasLength(1));
    expect(saved.single.field, 'genre');
    expect(saved.single.values, [_actionId]);

    // Another library sharing the same prefs owns nothing.
    final otherLibrary = MediaLibrary(
      id: 'shows',
      backend: MediaBackend.plex,
      title: 'TV Shows',
      kind: MediaKind.show,
      serverId: harness.serverId,
    );
    expect(storage.getLibraryFilters(sectionId: otherLibrary.globalKey), isEmpty);

    // A fresh tree over the same prefs restores the clause, the label and the
    // query — the selection is the library's, not the widget's.
    //
    // The name cache is process-wide, so the toggle above (and every earlier
    // leg of this file) warmed it: a "fresh tree" in the same process would
    // inherit `Action` for free, which is exactly how this assertion stayed
    // green while a real restart painted `Genre: 1 selected`. Drop the cache
    // first, so from here on the label can only come from the cold path.
    FilterValueNames.clearForTest();
    expect(
      _rememberedName(harness, MediaFilterField.genre, _actionId),
      isNull,
      reason: 'the restart leg has to start with a cold name cache',
    );

    await tester.pumpWidget(const SizedBox());
    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);
    // Nothing is tapped on this leg. `Genre: Action` can therefore only appear
    // if loading the restored clause's listing remembered `1278 -> Action`;
    // without that the summary falls back to `1 selected` (the defect).
    for (var i = 0; i < 400 && find.widgetWithText(FocusableFilterChip, 'Genre: Action').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(
      find.widgetWithText(FocusableFilterChip, 'Genre: Action'),
      findsOneWidget,
      reason:
          'a cold restart must name the restored value instead of counting it; '
          'chips=${[for (final chip in tester.widgetList<FocusableFilterChip>(find.byType(FocusableFilterChip))) chip.label]}',
    );
    expect(
      find.widgetWithText(FocusableFilterChip, 'Genre: 1 selected'),
      findsNothing,
      reason: 'a restored selection is summarised by title on a cold start',
    );
    expect(
      _rememberedName(harness, MediaFilterField.genre, _actionId),
      'Action',
      reason: 'the cold path resolved the id from the listing the tab fetched',
    );
    expect(
      harness.valueRequests,
      isNotEmpty,
      reason: 'resolving a restored clause asks the same listing the picker does',
    );
    expect(harness.pageRequests.last.queryParameters['genre'], _actionId);

    // The picker's Clear row is the same clear the editor offers.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre: Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    expect(storage.getLibraryFilters(sectionId: harness.library.globalKey), isEmpty);
    expect(find.widgetWithText(FocusableFilterChip, 'Genre'), findsOneWidget);
    expect(harness.pageRequests.last.queryParameters.containsKey('genre'), isFalse);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC6 loading a value list remembers every title without a pick', (tester) async {
    // The other half of the cold-start contract: the summary reads titles the
    // page recorded while rendering a listing, not titles a tap recorded. This
    // leg mounts the page directly and never taps a row, so it fails if
    // `remember` is only called from the tile's onChanged (which is what the
    // installed app was doing when it painted `Genre: 1 selected`).
    FilterValueNames.clearForTest();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    const libraryKey = 'plex-server:movies';
    final genreFilter = MediaFilter(
      filter: MediaFilterField.genre,
      filterType: MediaFilterType.tag,
      key: '/library/sections/movies/genre',
      title: 'Genre',
      type: 'filter',
    );
    const clause = LibraryFilter(field: MediaFilterField.genre, values: [_actionId]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterValuePage(
            filter: genreFilter,
            values: [
              for (final row in _genreRows)
                MediaFilterValue(key: row['key']! as String, title: row['title']! as String),
            ],
            clause: clause,
            serverId: 'plex-server',
            libraryKey: libraryKey,
            onChanged: (_) {},
            initialFocusNode: focusNode,
            onBack: () {},
          ),
        ),
      ),
    );

    // The page offered its rows and nothing was tapped.
    expect(find.text('Action'), findsOneWidget);
    for (final row in _genreRows) {
      expect(
        FilterValueNames.maybeLookup(
          serverId: 'plex-server',
          libraryKey: libraryKey,
          field: MediaFilterField.genre,
          value: row['key']! as String,
        ),
        row['title'],
        reason: 'every rendered row is remembered, not just the selected one',
      );
    }
    expect(
      filterFieldSummary(filter: genreFilter, clauses: const [clause], serverId: 'plex-server', libraryKey: libraryKey),
      'Action',
      reason: 'a restored clause summarises by title once its listing has loaded',
    );
  });

  testWidgets('AC7 the sheet genre row and the chip read one selection, both ways', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // The Filters sheet carries the Genre row because the parsed filter list
    // carries it — the screen hard-codes no row.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Filters'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FocusableListTile, 'Genre'), findsOneWidget);

    await tester.tap(find.widgetWithText(FocusableListTile, 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    expect(find.widgetWithText(FocusableFilterChip, 'Genre: Action'), findsOneWidget);
    expect(harness.pageRequests.last.queryParameters['genre'], _actionId);

    // The chip's page reads the same clause: the pick is already checked.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre: Action'));
    await tester.pumpAndSettle();
    final actionRow = tester.widget<FocusableCheckboxListTile>(
      find.ancestor(of: find.text('Action'), matching: find.byType(FocusableCheckboxListTile)),
    );
    expect(actionRow.value, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC7 a library that publishes no genre field gets no genre row', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness(publishesGenreField: false);
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // The control stays discoverable …
    expect(find.widgetWithText(FocusableFilterChip, 'Genre'), findsOneWidget);

    // … but the category list has no row the server did not publish.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusableListTile), findsWidgets);
    expect(find.widgetWithText(FocusableListTile, 'Genre'), findsNothing);
    await _dismissPanel(tester);

    // The chip's page still works: its values come from the section's own
    // /genre listing, not from a hard-coded name list.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();
    expect(harness.valueRequests, isNotEmpty);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Comedy'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('B1 a section that publishes no genre field still names its selection', (tester) async {
    // The chip's fallback filter must claim its value list. With `key: ''` the
    // summary prints the stored ids (`Genre: 1278, 1594`) and the cold-start
    // prefetch skips the field altogether.
    final fallback = MediaFilter.genreFallback(title: 'Genre');
    expect(fallback.hasValueList, isTrue, reason: 'the key is what marks the field enumerable');

    FilterValueNames.clearForTest();
    const restored = LibraryFilter(field: MediaFilterField.genre, values: [_actionId, _comedyId]);
    final coldSummary = filterFieldSummary(
      filter: fallback,
      clauses: const [restored],
      serverId: 'plex-server',
      libraryKey: 'plex-server:movies',
    );
    expect(coldSummary, '2 selected', reason: 'a value-list field counts an unresolved selection, it never prints ids');
    expect(coldSummary, isNot('1278, 1594'));

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness(publishesGenreField: false);
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // Two genres through the chip, on a section whose filter metadata has no
    // genre field at all: the control still edits a real clause.
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    String? genreLabel() {
      final chips = tester.widgetList<FocusableFilterChip>(_chipWhere((label) => label.startsWith('Genre')));
      return chips.isEmpty ? null : chips.first.label;
    }

    final picked = genreLabel();
    expect(picked, contains('Action'));
    expect(picked, contains('Comedy'));
    expect(picked, isNot(matches(RegExp(r'\b1278\b'))), reason: 'the chip names the values, never their ids');
    expect(picked, isNot(matches(RegExp(r'\b1594\b'))));

    // A cold restart: the name cache is empty and nothing is tapped, so the chip
    // can only be named if the tab asked the section for its own /genre listing.
    FilterValueNames.clearForTest();
    harness.valueRequests.clear();
    await tester.pumpWidget(const SizedBox());
    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    expect(
      harness.valueRequests,
      isNotEmpty,
      reason: 'a section that publishes no genre field still has a /genre listing to resolve the ids from',
    );
    for (var i = 0; i < 400 && !(genreLabel()?.contains('Comedy') ?? false); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    final coldLabel = genreLabel();
    expect(coldLabel, contains('Action'), reason: 'the restored clause is named from the listing the prefetch fetched');
    expect(coldLabel, contains('Comedy'));
    expect(coldLabel, isNot(matches(RegExp(r'\b1278\b'))));
    expect(coldLabel, isNot(matches(RegExp(r'\b1594\b'))));

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC9 failed values offer a retry and an empty listing explains itself', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness(failValues: true);
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorStateWidget), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'a failed listing must not throw');

    harness.failValues = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsOneWidget);

    // A section whose /genre listing is empty says so instead of showing a
    // dead list; the Clear row still works.
    await _dismissPanel(tester);
    harness.emptyValues = true;
    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();
    expect(find.text('This library lists no genres for this view'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  // -------------------------------------------------------------------------
  // AC4 / AC5 — measured on the owner's Plex server 2026-11-14, re-measured on
  // section 11 on 2026-11-15:
  //   genre=1278 -> 836, genre=1277 -> 878, genre=1278,1277 -> 1236 = |union|
  //   (836 + 878 - 478, and the id set equals A ∪ B exactly)
  //   genre=1278&genre=1277 -> 478 = |intersection| (Plex ANDs a repeated key)
  //   genre=1278 & unwatched=1 -> 823 = |A ∩ unwatched|, a subset of both
  // A multi-select is an INTERSECTION (the recorded decision), so the app
  // sends one `genre` PAIR PER ID and never the comma form. These tests hold it
  // to that shape and to the server answer the fixture models.
  // -------------------------------------------------------------------------

  testWidgets('AC4 a multi-select repeats the genre key so the grid is the intersection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await tester.tap(_chipWhere((label) => label == 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    final query = harness.pageRequests.last;
    // The URL actually sent carries TWO genre parameters, in selection order.
    expect(
      query.queryParametersAll['genre'],
      [_actionId, _comedyId],
      reason: 'one Plex `genre` pair per selected id — Plex ANDs a repeated key',
    );
    expect(_genrePairs(query), ['genre=$_actionId', 'genre=$_comedyId']);
    expect(
      query.query,
      contains('genre=$_actionId&genre=$_comedyId'),
      reason: 'proved on the recorded URL string, not on a map keyed by field name',
    );
    expect(
      query.query,
      isNot(contains('%2C')),
      reason: 'the comma form is the measured union (1236); it must never be produced for genre again',
    );
    expect(query.queryParameters['type'], '1');
    // The grid shows the server's answer to that query: the one fixture title
    // carrying BOTH genres, not the union's three.
    expect(harness.lastTotalSize, 1);
    expect(find.text('Action Comedy'), findsOneWidget);
    expect(find.text('Action One'), findsNothing, reason: 'Action-only is not in the intersection');
    expect(find.text('Comedy One'), findsNothing, reason: 'Comedy-only is not in the intersection');
    expect(find.widgetWithText(FocusableFilterChip, 'Genre: Action, Comedy'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('A4 two-genre paging keeps both keys on page 2 with no duplicate and no gap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    // 101 titles carry BOTH genres, so the grid needs a real second page.
    final harness = _GenreHarness(extraActionComedyMovies: 100);
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntilLong(tester, () => harness.pageRequests.isNotEmpty);

    harness.servedIds.clear();
    await tester.tap(_chipWhere((label) => label == 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntilLong(tester, () => harness.pageRequests.length > pagesBefore);

    expect(
      harness.pageRequests.skip(1).every((uri) => _genrePairs(uri).join('&') == 'genre=$_actionId&genre=$_comedyId'),
      isTrue,
      reason: 'every page of the run carries both genre keys',
    );

    final state = tester.state(find.byType(LibraryBrowseTab)) as dynamic;
    final total = state.totalSize as int;
    final expected = [
      for (final movie in harness.catalogue)
        if (movie.genreIds.contains(_actionId) && movie.genreIds.contains(_comedyId)) movie.key,
    ];
    expect(expected.length, 101);
    expect(total, expected.length, reason: 'the grid total is the server total for the repeated-key query');
    var loaded = (state.loadedItems as Map).length;
    expect(loaded, lessThan(total), reason: 'the fixture has to need a second page');

    var pageNumber = 1;
    while (loaded < total) {
      await state.ensureRangeLoaded(loaded, 100, buffer: 0);
      await tester.pump();
      final next = (state.loadedItems as Map).length;
      expect(next, greaterThan(loaded), reason: 'page ${++pageNumber} must advance the loaded set');
      loaded = next;
    }

    final starts = [
      for (final uri in harness.pageRequests.skip(1))
        int.parse(uri.queryParameters['X-Plex-Container-Start'] ?? '0'),
    ];
    expect(starts.length, greaterThan(1), reason: 'the run has to cross more than one page');
    expect(starts.toSet(), hasLength(starts.length), reason: 'no page is fetched twice');
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThan(starts[i - 1]));
    }
    expect(harness.servedIds, hasLength(expected.length), reason: 'every row of the query is served exactly once');
    expect(harness.servedIds.toSet(), hasLength(harness.servedIds.length), reason: 'no duplicate id across pages');
    expect(harness.servedIds.toSet(), expected.toSet(), reason: 'no gap: the pages cover the whole intersection');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('A5 TV shows: two show genres intersect, carried as two repeated genre keys', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _TvGenreHarness();
    addTearDown(harness.dispose);

    await pumpLibraryTab(
      tester,
      provider: harness.provider,
      tab: OverlaySheetHost(
        child: LibraryBrowseTab(library: harness.library, canGroupByFolders: true, isActive: true),
      ),
    );
    await pumpRequestFrames(tester);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await tester.tap(_chipWhere((label) => label == 'Genre'));
    await tester.pumpAndSettle();
    expect(harness.valueRequests.last.queryParameters['type'], '2');
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    final query = harness.pageRequests.last;
    expect(query.queryParameters['type'], '2');
    expect(_genrePairs(query), ['genre=$_actionId', 'genre=$_comedyId'], reason: 'show-level genres AND too');
    expect(find.text('Action Comedy Show'), findsOneWidget);
    expect(find.text('Action Show'), findsNothing);
    expect(find.text('Comedy Show'), findsNothing);
    expect(find.widgetWithText(FocusableFilterChip, 'Genre: Action, Comedy'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('A6 the Filters sheet and the chip send the identical two-key genre query', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // Path 1 — the Filters sheet's Genre row, which is its own entry point.
    await tester.tap(_chipWhere((label) => label.startsWith('Filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FocusableListTile, 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    var pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);
    final fromSheet = harness.pageRequests.last;
    expect(_genrePairs(fromSheet), ['genre=$_actionId', 'genre=$_comedyId']);

    // Clear through the chip's own page, then rebuild the same selection there.
    await tester.tap(_chipWhere((label) => label.startsWith('Genre:')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);
    expect(harness.pageRequests.last.queryParameters.containsKey('genre'), isFalse, reason: 'All clears the clause');

    await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy'));
    await tester.pumpAndSettle();
    pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);
    final fromChip = harness.pageRequests.last;
    expect(_genrePairs(fromChip), ['genre=$_actionId', 'genre=$_comedyId']);
    expect(fromChip.query, fromSheet.query, reason: 'the sheet and the chip are one state and one query path');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC5 genre and unwatched compose to their intersection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness();
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    await _selectGenre(tester, harness, 'Action');
    expect(harness.pageRequests.last.queryParameters['genre'], _actionId);
    final genreOnly = harness.lastTotalSize;
    expect(genreOnly, 2);

    // The second filter comes from the Filters sheet's own boolean row.
    await tester.tap(_chipWhere((label) => label.startsWith('Filters')));
    await tester.pumpAndSettle();
    final unwatchedRow = find.widgetWithText(FocusableListTile, 'Unwatched');
    expect(unwatchedRow, findsOneWidget);
    await tester.tap(find.descendant(of: unwatchedRow, matching: find.text('Yes')));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);

    final query = harness.pageRequests.last;
    expect(query.queryParameters['genre'], _actionId, reason: 'the genre clause survives a second filter');
    expect(query.queryParameters['unwatched'], '1');
    expect(query.queryParameters['type'], '1');

    // Intersection, not union: `Action Comedy` carries the genre but is watched,
    // `Comedy One` is unwatched but is not Action.
    expect(harness.lastTotalSize, 1);
    expect(harness.lastTotalSize, lessThanOrEqualTo(genreOnly));
    expect(find.text('Action One'), findsOneWidget);
    expect(find.text('Action Comedy'), findsNothing);
    expect(find.text('Comedy One'), findsNothing);
    expect(find.byType(FocusableMediaCard), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC5 paging keeps the genre clause on every page with no duplicate and no gap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    // Just past the first page (the grid asks for 100 rows): a real second
    // request, and small enough that the run stays fast.
    final harness = _GenreHarness(extraActionMovies: 100);
    addTearDown(harness.dispose);

    await _pumpGenreTab(tester, harness);
    await _pumpUntilLong(tester, () => harness.pageRequests.isNotEmpty);

    // Drop the unfiltered first load from the served-id record before the
    // selection: what this test grades is the pages of the *genre* query.
    harness.servedIds.clear();
    await _selectGenre(tester, harness, 'Action');
    // Request 0 is the unfiltered first load; everything the selection sends
    // from then on — including the page walk below — must carry the clause.
    expect(harness.pageRequests.skip(1).every((uri) => uri.queryParameters['genre'] == _actionId), isTrue);

    final state = tester.state(find.byType(LibraryBrowseTab)) as dynamic;
    final total = state.totalSize as int;
    var loaded = (state.loadedItems as Map).length;
    expect(loaded, lessThan(total), reason: 'the fixture has to need a second page');
    expect(total, harness.lastTotalSize);

    // Walk the remaining pages through the tab's own range loader — the path a
    // scroll ends up in — rather than re-asking the query builder directly.
    var pageNumber = 1;
    while (loaded < total) {
      await state.ensureRangeLoaded(loaded, 100, buffer: 0);
      await tester.pump();
      final next = (state.loadedItems as Map).length;
      expect(next, greaterThan(loaded), reason: 'page ${++pageNumber} must advance the loaded set');
      loaded = next;
    }

    // Page offsets of the *genre* run (request 0 is the unfiltered first load).
    final starts = [
      for (final uri in harness.pageRequests.skip(1))
        int.parse(uri.queryParameters['X-Plex-Container-Start'] ?? '0'),
    ];
    expect(starts.length, greaterThan(1), reason: 'the run has to cross more than one page');
    expect(starts.first, 0);
    expect(starts.toSet(), hasLength(starts.length), reason: 'no page is fetched twice');
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThan(starts[i - 1]), reason: 'each page starts after the one before it');
    }
    expect(
      harness.pageRequests.skip(1).every((uri) => uri.queryParameters['genre'] == _actionId),
      isTrue,
      reason: 'page 2 is exactly where a clause goes missing',
    );

    final expected = [
      for (final movie in harness.catalogue)
        if (movie.genreIds.contains(_actionId)) movie.key,
    ];
    expect(harness.servedIds, hasLength(expected.length), reason: 'every row of the query is served exactly once');
    expect(harness.servedIds.toSet(), hasLength(harness.servedIds.length), reason: 'no duplicate id across pages');
    expect(harness.servedIds.toSet(), expected.toSet(), reason: 'no gap: the pages cover the whole result');
    expect(loaded, expected.length);
    expect(harness.lastTotalSize, expected.length);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AC8 seasons and episodes keep the genre clause and report the empty result', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _TvGenreHarness();
    addTearDown(harness.dispose);

    await pumpLibraryTab(
      tester,
      provider: harness.provider,
      tab: OverlaySheetHost(
        child: LibraryBrowseTab(library: harness.library, canGroupByFolders: true, isActive: true),
      ),
    );
    await pumpRequestFrames(tester);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // Shows grouping: the value list is the section's own show-level list, and
    // the pick filters shows with `genre=` + `type=2`.
    await tester.tap(_chipWhere((label) => label == 'Genre'));
    await tester.pumpAndSettle();
    expect(harness.valueRequests.last.queryParameters['type'], '2');
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    final pagesBefore = harness.pageRequests.length;
    await _dismissPanel(tester);
    await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);
    var query = harness.pageRequests.last;
    expect(query.queryParameters['type'], '2');
    expect(query.queryParameters['genre'], _actionId);
    expect(find.text('Action Show'), findsOneWidget);

    // Seasons: the clause is never silently dropped, and the measured server
    // answer for `type=3&genre=` is zero rows — which the grid reports.
    await _switchGrouping(tester, 'Seasons');
    query = harness.pageRequests.last;
    expect(query.queryParameters['type'], '3');
    expect(query.queryParameters['genre'], _actionId, reason: 'the clause follows the grouping switch');
    expect(find.text('No items match the active filters'), findsOneWidget);
    expect(find.text('Reset filters'), findsOneWidget);
    expect(find.widgetWithText(FocusableFilterChip, 'Genre: Action'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The seasons picker asks its own type, and the empty listing explains
    // itself instead of rendering a dead list.
    await tester.tap(_chipWhere((label) => label.startsWith('Genre: Action')));
    await tester.pumpAndSettle();
    expect(harness.valueRequests.last.queryParameters['type'], '3');
    expect(find.text('This library lists no genres for this view'), findsOneWidget);
    await _dismissPanel(tester);

    // Episodes: the same contract with `type=4`.
    await _switchGrouping(tester, 'Episodes');
    query = harness.pageRequests.last;
    expect(query.queryParameters['type'], '4');
    expect(query.queryParameters['genre'], _actionId);
    expect(find.text('No items match the active filters'), findsOneWidget);
    expect(find.text('Reset filters'), findsOneWidget);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('K2 a cold start lists every category the server publishes, Genre included', (tester) async {
    // A 1724x961 window, so the sheet is measured at the height it is actually
    // used at.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final harness = _GenreHarness(serverFields: _capturedMetaFields);
    addTearDown(harness.dispose);

    await pumpLibraryTab(
      tester,
      provider: harness.provider,
      tab: OverlaySheetHost(
        child: LibraryBrowseTab(library: harness.library, canGroupByFolders: true, isActive: true),
      ),
      size: const Size(1724, 961),
    );
    await pumpRequestFrames(tester);
    await _pumpUntil(tester, () => harness.pageRequests.isNotEmpty);

    // First open of a cold session: nothing has been opened, scrolled or warmed.
    await tester.tap(_chipWhere((label) => label.startsWith('Filters')));
    await tester.pumpAndSettle();
    expect(find.byType(FiltersBottomSheet), findsOneWidget);

    final listScrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
    );

    // Every category title the sheet has painted so far.
    final rendered = <String>{};
    void collect() {
      for (final element in find.byType(FocusableListTile).evaluate()) {
        final title = (element.widget as FocusableListTile).title;
        if (title is Text && title.data != null) rendered.add(title.data!);
      }
    }

    collect();
    expect(rendered, isNotEmpty);

    // Walk to the end of the list the way a mouse user does: a left-button
    // drag. Desktop Flutter does not treat the mouse as a drag device, so this
    // gesture moves nothing until the sheet opts the mouse in.
    for (var step = 0; step < 12 && listScrollable.position.pixels < listScrollable.position.maxScrollExtent; step++) {
      final before = listScrollable.position.pixels;
      await tester.drag(find.byType(ListView).first, const Offset(0, -400), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      collect();
      if (listScrollable.position.pixels == before) break;
    }

    final expected = <String>{
      for (final field in _capturedMetaFields) field['title']! as String,
      // Plex-only row the parse path adds for movie queries; not a `Meta` row.
      'File Path',
    };
    expect(
      rendered,
      containsAll(expected),
      reason:
          'a cold start must list the server\'s own ${_capturedMetaFields.length} categories; '
          'reached ${rendered.length} of ${expected.length}',
    );
    expect(rendered, contains('Genre'));
    expect(rendered.length, expected.length, reason: 'the sheet lists the server set, not a subset of it');
    // And the sheet says there are more rows even when they do not all fit: a
    // thumb is on screen before the first scroll, so the categories past the
    // fold are discoverable instead of invisible.
    final scrollbar = tester.widget<Scrollbar>(
      find.descendant(of: find.byType(FiltersBottomSheet), matching: find.byType(Scrollbar)).first,
    );
    expect(scrollbar.thumbVisibility, isTrue, reason: 'a long category list needs a visible affordance');
    expect(tester.takeException(), isNull);

    // Same contract on a TV Shows library: the show-level set the server
    // declares (21 fields, `show.genre` among them), then the same list after a
    // grouping change — the categories belong to the library, not the grouping.
    await tester.pumpWidget(const SizedBox.shrink());
    final tv = _TvGenreHarness(serverFields: _capturedShowFields);
    addTearDown(tv.dispose);
    await pumpLibraryTab(
      tester,
      provider: tv.provider,
      tab: OverlaySheetHost(child: LibraryBrowseTab(library: tv.library, canGroupByFolders: true, isActive: true)),
      size: const Size(1724, 961),
    );
    await pumpRequestFrames(tester);
    await _pumpUntil(tester, () => tv.pageRequests.isNotEmpty);

    await tester.tap(_chipWhere((label) => label.startsWith('Filters')));
    await tester.pumpAndSettle();
    rendered.clear();
    final showScrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
    );
    collect();
    for (var step = 0; step < 12 && showScrollable.position.pixels < showScrollable.position.maxScrollExtent; step++) {
      final before = showScrollable.position.pixels;
      await tester.drag(find.byType(ListView).first, const Offset(0, -400), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      collect();
      if (showScrollable.position.pixels == before) break;
    }
    final expectedShow = <String>{for (final field in _capturedShowFields) field['title']! as String};
    expect(rendered, containsAll(expectedShow), reason: 'TV Shows lists the show-level categories the server publishes');
    expect(rendered.length, expectedShow.length);
    expect(tester.takeException(), isNull);
    await _dismissPanel(tester);

    // Grouping change: the category list is the library's, and it still opens.
    await _switchGrouping(tester, 'Seasons');
    await tester.tap(_chipWhere((label) => label.startsWith('Filters')));
    await tester.pumpAndSettle();
    final inSheet = find.descendant(of: find.byType(FiltersBottomSheet), matching: find.text('Genre'));
    expect(inSheet, findsOneWidget, reason: 'the sheet still lists Genre after the grouping change');
    expect(find.text('Show Year'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dismissPanel(tester);

    debugDefaultTargetPlatformOverride = null;
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<void> _pumpGenreTab(WidgetTester tester, _GenreHarness harness) async {
  await pumpLibraryTab(
    tester,
    provider: harness.provider,
    tab: OverlaySheetHost(
      child: LibraryBrowseTab(library: harness.library, canGroupByFolders: true, isActive: true),
    ),
  );
  await pumpRequestFrames(tester);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 30 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

/// [_pumpUntil] with room for a large first page (the paging fixture).
Future<void> _pumpUntilLong(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

/// A chips-row chip by its label. The chips row is the only place these live,
/// and `OptionsChipDescriptor` carries no key (SPEC AC1's decision), so the
/// label is the handle the screen itself exposes.
Finder _chipWhere(bool Function(String label) matches) =>
    find.byWidgetPredicate((widget) => widget is FocusableFilterChip && matches(widget.label));

/// The `genre=` pairs exactly as they ride on the wire, in request order —
/// the shape the intersection requires (one pair per selected id, never one comma pair).
List<String> _genrePairs(Uri uri) => [
  for (final value in uri.queryParametersAll['genre'] ?? const <String>[]) 'genre=$value',
];

/// The remembered title for a value, read straight from the label cache the
/// summary uses — on a restart this cache is the only thing that can turn
/// `1278` into `Action`.
String? _rememberedName(_GenreHarness harness, String field, String value) => FilterValueNames.maybeLookup(
  serverId: harness.serverId,
  libraryKey: harness.library.globalKey,
  field: field,
  value: value,
);

/// Opens the genre page from the chip, picks [title], and commits by
/// dismissing the panel (the editor's contract: stage every tap, apply once on
/// dismissal).
Future<void> _selectGenre(WidgetTester tester, _GenreHarness harness, String title) async {
  await tester.tap(find.widgetWithText(FocusableFilterChip, 'Genre'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  final pagesBefore = harness.pageRequests.length;
  await _dismissPanel(tester);
  await _pumpUntil(tester, () => harness.pageRequests.length > pagesBefore);
}

/// Dismiss the anchored panel by tapping its barrier.
Future<void> _dismissPanel(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

/// Switches the browse grouping through the chips row: the grouping chip is the
/// first chip in the bar (Grouping · Filters · Genre · Sort).
Future<void> _switchGrouping(WidgetTester tester, String label) async {
  await tester.tap(find.byType(FocusableFilterChip).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

http.Response _jsonResponse(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});

class _GenreHarness {
  static final _serverId = ServerId('plex-server');

  final AppDatabase database;
  final bool publishesGenreField;
  bool failValues;
  bool emptyValues = false;
  late final MediaLibrary library;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;
  final List<Uri> pageRequests = [];
  final List<Uri> valueRequests = [];
  final List<Uri> metadataRequests = [];

  /// Every `ratingKey` the page endpoint actually served, in the order it
  /// served them — the id list the paging test checks for duplicates and gaps.
  final List<String> servedIds = [];

  /// Rows this library owns. [_movies] unless a paging test asked for more.
  final List<({String key, String title, List<String> genreIds, bool unwatched})> catalogue;

  /// `totalSize` the last page request answered with.
  int lastTotalSize = 0;

  /// The `Meta.Type[active].Field[]` the mock publishes. Null keeps the small
  /// three-field fixture every other test in this file is written against;
  /// [_capturedMetaFields] is the server's own 40-row set.
  final List<Map<String, Object?>>? serverFields;

  _GenreHarness({
    this.publishesGenreField = true,
    this.failValues = false,
    this.serverFields,
    int extraActionMovies = 0,
    int extraActionComedyMovies = 0,
  })
    : catalogue = _catalogueWithBoth(extraActionMovies, extraActionComedyMovies),
      database = AppDatabase.forTesting(NativeDatabase.memory()) {
    PlexApiCache.initialize(database);
    library = MediaLibrary(
      id: 'movies',
      backend: MediaBackend.plex,
      title: 'Movies',
      kind: MediaKind.movie,
      serverId: _serverId,
    );
    final client = testPlexClient(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: 'test',
      ),
      serverId: _serverId,
      httpClient: MockClient(_handle),
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  ServerId get serverId => _serverId;

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    final params = url.queryParameters;
    switch (url.path) {
      case '/library/sections/movies/all':
        if (params['includeMeta'] == '1') {
          metadataRequests.add(url);
          return _jsonResponse({
            'MediaContainer': {
              'size': 0,
              'totalSize': catalogue.length,
              'Meta': {
                'Type': [
                  {
                    'type': 'movie',
                    'active': true,
                    'Field':
                        serverFields ??
                        [
                          if (publishesGenreField) {'key': 'genre', 'title': 'Genre', 'type': 'tag'},
                          {'key': 'unwatched', 'title': 'Unwatched', 'type': 'boolean'},
                          {'key': 'year', 'title': 'Year', 'type': 'integer'},
                        ],
                  },
                ],
                'FieldType': [
                  {
                    'type': 'tag',
                    'Operator': [
                      {'key': '=', 'title': 'is'},
                      {'key': '!=', 'title': 'is not'},
                    ],
                  },
                  {
                    'type': 'boolean',
                    'Operator': [
                      {'key': '=', 'title': 'is'},
                      {'key': '!=', 'title': 'is not'},
                    ],
                  },
                  {
                    'type': 'integer',
                    'Operator': [
                      {'key': '=', 'title': 'is'},
                      {'key': '>>=', 'title': 'is greater than'},
                      {'key': '<<=', 'title': 'is less than'},
                    ],
                  },
                ],
              },
            },
          });
        }
        pageRequests.add(url);
        // Plex's measured clause semantics (2026-11-14, re-measured 2026-11-15):
        // values inside ONE pair OR (the comma form is the union, 1236 for
        // 1278,1277) and REPEATED pairs AND — so a row must
        // carry a genre from every `genre=` pair the request sent.
        final genreGroups = [
          for (final entry in url.queryParametersAll['genre'] ?? const <String>[]) entry.split(','),
        ];
        final wantsUnwatched = params['unwatched'];
        final matched = [
          for (final movie in catalogue)
            if ((genreGroups.isEmpty || genreGroups.every((group) => movie.genreIds.any(group.contains))) &&
                (wantsUnwatched != '1' || movie.unwatched))
              movie,
        ];
        lastTotalSize = matched.length;
        final start = int.tryParse(params['X-Plex-Container-Start'] ?? '') ?? 0;
        final size = int.tryParse(params['X-Plex-Container-Size'] ?? '') ?? matched.length;
        final page = matched.skip(start).take(size).toList();
        servedIds.addAll(page.map((movie) => movie.key));
        return _jsonResponse({
          'MediaContainer': {
            'size': page.length,
            'totalSize': matched.length,
            'offset': start,
            'Metadata': [
              for (final movie in page) {'ratingKey': movie.key, 'type': 'movie', 'title': movie.title},
            ],
          },
        });
      case '/library/sections/movies/genre':
        valueRequests.add(url);
        if (failValues) return http.Response('boom', 500);
        final rows = emptyValues ? const <Map<String, Object?>>[] : _genreRows;
        return _jsonResponse({
          'MediaContainer': {'size': rows.length, 'Directory': rows},
        });
      case '/library/sections/movies/sorts':
        return _jsonResponse({
          'MediaContainer': {
            'Directory': [
              {'key': 'titleSort', 'descKey': 'titleSort:desc', 'title': 'Title', 'defaultDirection': 'asc'},
            ],
          },
        });
      case '/library/sections/movies/firstCharacter':
        return _jsonResponse({
          'MediaContainer': {
            'Directory': [
              {'key': 'A', 'title': 'A', 'size': '1'},
            ],
          },
        });
      default:
        return _jsonResponse({'MediaContainer': <String, Object?>{}});
    }
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
    await database.close();
  }
}

/// A Plex **TV Shows** library whose answers copy the owner's Plex server as
/// measured on 2026-11-14:
///
/// * `/genre?type=2` lists the show-level genre ids (24 rows on the real
///   section), `/genre?type=3|4` lists **nothing** — the capture is 0 rows;
/// * `type=3&genre=<id>` and `type=4&genre=<id>` answer **0** items, while the
///   qualified `show.genre=<id>` is the key that would select them (28 seasons /
///   483 episodes on the real section). The spec keeps the bare key for this
///   phase, so the grid's honest answer here is the filtered-empty state.
class _TvGenreHarness {
  static final _serverId = ServerId('plex-server');

  final AppDatabase database;
  late final MediaLibrary library;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;
  final List<Uri> pageRequests = [];
  final List<Uri> valueRequests = [];

  /// The `Meta.Type[active].Field[]` the mock publishes; null keeps the small
  /// two-field fixture the other TV tests use.
  final List<Map<String, Object?>>? serverFields;

  _TvGenreHarness({this.serverFields}) : database = AppDatabase.forTesting(NativeDatabase.memory()) {
    PlexApiCache.initialize(database);
    library = MediaLibrary(
      id: 'shows',
      backend: MediaBackend.plex,
      title: 'TV Shows',
      kind: MediaKind.show,
      serverId: _serverId,
    );
    final client = testPlexClient(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: 'test',
      ),
      serverId: _serverId,
      httpClient: MockClient(_handle),
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    final params = url.queryParameters;
    switch (url.path) {
      case '/library/sections/shows/all':
        if (params['includeMeta'] == '1') {
          return _jsonResponse({
            'MediaContainer': {
              'size': 0,
              'totalSize': 2,
              'Meta': {
                'Type': [
                  {
                    'type': 'show',
                    'active': true,
                    'Field':
                        serverFields ??
                        [
                          {'key': 'show.genre', 'title': 'Genre', 'type': 'tag'},
                          {'key': 'show.year', 'title': 'Year', 'type': 'integer'},
                        ],
                  },
                  {'type': 'season', 'active': false},
                  {'type': 'episode', 'active': false},
                ],
                'FieldType': [
                  {
                    'type': 'tag',
                    'Operator': [
                      {'key': '=', 'title': 'is'},
                      {'key': '!=', 'title': 'is not'},
                    ],
                  },
                  {
                    'type': 'integer',
                    'Operator': [
                      {'key': '=', 'title': 'is'},
                      {'key': '>>=', 'title': 'is greater than'},
                      {'key': '<<=', 'title': 'is less than'},
                    ],
                  },
                ],
              },
            },
          });
        }
        pageRequests.add(url);
        final type = params['type'];
        final genreGroups = [
          for (final entry in url.queryParametersAll['genre'] ?? const <String>[]) entry.split(','),
        ];
        final rows = <Map<String, Object?>>[];
        if (type == '3' || type == '4') {
          // Measured: the bare key selects nothing at season/episode level.
          if (genreGroups.isEmpty) {
            rows.add({'ratingKey': 'season-filler', 'type': type == '3' ? 'season' : 'episode', 'title': 'Filler'});
          }
        } else {
          // Show-level genres follow the same measured rule as movies: a row
          // must carry a genre from every repeated `genre=` pair.
          for (final show in _shows) {
            if (genreGroups.every((group) => show.genres.any(group.contains))) {
              rows.add({'ratingKey': show.key, 'type': 'show', 'title': show.title});
            }
          }
        }
        final start = int.tryParse(params['X-Plex-Container-Start'] ?? '') ?? 0;
        final size = int.tryParse(params['X-Plex-Container-Size'] ?? '') ?? rows.length;
        final page = rows.skip(start).take(size).toList();
        return _jsonResponse({
          'MediaContainer': {
            'size': page.length,
            'totalSize': rows.length,
            'offset': start,
            'Metadata': page,
          },
        });
      case '/library/sections/shows/genre':
        valueRequests.add(url);
        final type = url.queryParameters['type'];
        final rows = type == '2'
            ? const <Map<String, Object?>>[
                {'key': _comedyId, 'title': 'Comedy', 'type': 'genre'},
                {'key': _actionId, 'title': 'Action', 'type': 'genre'},
              ]
            // Measured: /genre?type=3 and ?type=4 answer no Directory rows.
            : const <Map<String, Object?>>[];
        return _jsonResponse({
          'MediaContainer': {'size': rows.length, 'Directory': rows},
        });
      case '/library/sections/shows/sorts':
        return _jsonResponse({
          'MediaContainer': {
            'Directory': [
              {'key': 'titleSort', 'descKey': 'titleSort:desc', 'title': 'Title', 'defaultDirection': 'asc'},
            ],
          },
        });
      case '/library/sections/shows/firstCharacter':
        return _jsonResponse({
          'MediaContainer': {'Directory': <Object?>[]},
        });
      default:
        return _jsonResponse({'MediaContainer': <String, Object?>{}});
    }
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
    await database.close();
  }
}
