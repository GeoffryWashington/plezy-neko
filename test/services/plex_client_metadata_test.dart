import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/metadata_edit/plex_metadata_edit_adapter.dart';
import 'package:plezy/services/plex_api_cache.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/media_items.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(database);
  });

  tearDown(() => database.close());

  test('metadata preference request uses includePreferences and canonicalizes server values', () async {
    Uri? requestedUri;
    final client = testPlexClient(
      handler: (request) async {
        requestedUri = request.url;
        return _metadataResponse([
          {'id': 'episodeSort', 'value': 0},
          {'id': 'autoDeletionItemPolicyUnwatchedLibrary', 'value': 3},
          {'id': 'autoDeletionItemPolicyWatchedLibrary', 'value': 7},
          {'id': 'flattenSeasons', 'value': 1},
          {'id': 'showOrdering', 'value': 'tvdbAbsolute'},
          {'id': 'languageOverride', 'value': 'fr-FR'},
          {'id': 'useOriginalTitle', 'value': true},
          {'id': 'audioLanguage', 'value': 'ja'},
          {'id': 'subtitleLanguage', 'value': 'en'},
          {'id': 'subtitleMode', 'value': 2},
        ]);
      },
    );
    addTearDown(client.close);

    final draft = await PlexMetadataEditAdapter(client).load(_show());

    expect(requestedUri?.path, '/library/metadata/show-1');
    expect(requestedUri?.queryParameters['includePreferences'], '1');
    expect(draft.value<String>('originalTitle'), 'Original show title');
    expect(draft.value<String>('pref:episodeSort'), '0');
    expect(draft.value<String>('pref:autoDeletionItemPolicyUnwatchedLibrary'), '3');
    expect(draft.value<String>('pref:autoDeletionItemPolicyWatchedLibrary'), '7');
    expect(draft.value<String>('pref:flattenSeasons'), '1');
    expect(draft.value<String>('pref:showOrdering'), 'tvdbAbsolute');
    expect(draft.value<String>('pref:languageOverride'), 'fr-FR');
    expect(draft.value<String>('pref:useOriginalTitle'), '1');
    expect(draft.value<String>('pref:audioLanguage'), 'ja');
    expect(draft.value<String>('pref:subtitleLanguage'), 'en');
    expect(draft.value<String>('pref:subtitleMode'), '2');
  });

  test('missing preference rows remain unset instead of becoming fabricated defaults', () async {
    final client = testPlexClient(
      handler: (_) async => _metadataResponse([
        {'id': 'episodeSort', 'value': 0},
      ]),
    );
    addTearDown(client.close);

    final draft = await PlexMetadataEditAdapter(client).load(_show());

    expect(draft.value<String>('pref:episodeSort'), '0');
    expect(draft.value<String>('pref:flattenSeasons'), isNull);
    expect(draft.value<String>('pref:showOrdering'), isNull);
    expect(draft.value<String>('pref:languageOverride'), isNull);
    expect(draft.value<String>('pref:useOriginalTitle'), isNull);
    expect(draft.value<String>('pref:audioLanguage'), isNull);
    expect(draft.value<String>('pref:subtitleMode'), isNull);
  });

  test('metadata preference request failures preserve the editable basic fields', () async {
    final client = testPlexClient(
      handler: (request) async => request.url.queryParameters.containsKey('includePreferences')
          ? http.Response('{}', 503)
          : _metadataResponse(const []),
    );
    addTearDown(client.close);

    final draft = await PlexMetadataEditAdapter(client).load(_show());

    expect(draft.value<String>('title'), 'Show');
    expect(draft.value<String>('originalTitle'), 'Original show title');
    expect(draft.value<String>('pref:episodeSort'), isNull);
  });

  test('the editor loads full metadata even for a row that has a summary and library id', () async {
    final client = testPlexClient(handler: (_) async => _metadataResponse(const []));
    addTearDown(client.close);

    // A list row: summary and library id present, genres absent.
    final draft = await PlexMetadataEditAdapter(client).load(_show());

    // save() diffs tag edits against these originals, so they must be the
    // server's, not the row's empty list.
    expect(draft.value<List<String>>('genre'), ['Drama', 'Science Fiction']);
    expect(draft.originalValues['genre'], ['Drama', 'Science Fiction']);
  });

  test('the editor refuses to start from a partial row when the item cannot be fetched', () async {
    final client = testPlexClient(handler: (_) async => http.Response('not found', 404));
    addTearDown(client.close);

    await expectLater(PlexMetadataEditAdapter(client).load(_show()), throwsStateError);
  });

  test('removed tags are emitted single-encoded because the transport encodes exactly once', () async {
    Uri? requestedUri;
    final client = testPlexClient(
      handler: (request) async {
        requestedUri = request.url;
        return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
      },
    );
    addTearDown(client.close);

    final ok = await client.updateMetadata(
      sectionId: 1,
      ratingKey: 'show-1',
      typeNumber: 2,
      tagChanges: {
        'genre': (current: ['Drama'], original: ['Drama', 'Science Fiction']),
      },
    );

    expect(ok, isTrue);
    expect(requestedUri, isNotNull);
    // Decoding the emitted query once must yield the original tag. The old
    // Uri.encodeComponent pre-pass double-encoded it ('Science%2520Fiction'
    // on the wire), so the server deleted a tag that doesn't exist.
    expect(requestedUri!.queryParameters['genre[].tag.tag-'], 'Science Fiction');
    expect(requestedUri!.query, contains('Science%20Fiction'));
    expect(requestedUri!.query, isNot(contains('%2520')));
  });

  test('a removed tag containing a comma travels one removal per request', () async {
    final requestedUris = <Uri>[];
    final client = testPlexClient(
      handler: (request) async {
        requestedUris.add(request.url);
        return http.Response('{}', 200, headers: const {'content-type': 'application/json'});
      },
    );
    addTearDown(client.close);

    final ok = await client.updateMetadata(
      sectionId: 1,
      ratingKey: 'show-1',
      typeNumber: 2,
      tagChanges: {
        'genre': (current: ['Drama'], original: ['Drama', 'Action, Comedy', 'Science Fiction']),
      },
    );

    expect(ok, isTrue);
    // Plex's tag.tag- removes "comma separated tags" with no escape, so a
    // joined value would split 'Action, Comedy' and could over-remove tags
    // named 'Action'/'Comedy'. The whole field defers to one removal per
    // request; the main request still locks the field and restates keeps.
    expect(requestedUris, hasLength(3));
    expect(requestedUris[0].queryParameters.containsKey('genre[].tag.tag-'), isFalse);
    expect(requestedUris[0].queryParameters['genre[0].tag.tag'], 'Drama');
    expect(requestedUris[0].queryParameters['genre.locked'], '1');
    expect(requestedUris[1].queryParameters['genre[].tag.tag-'], 'Action, Comedy');
    expect(requestedUris[1].query, contains('Action%2C%20Comedy'));
    expect(requestedUris[1].queryParameters['genre[0].tag.tag'], 'Drama');
    expect(requestedUris[2].queryParameters['genre[].tag.tag-'], 'Science Fiction');
  });

  // ---------------------------------------------------------------------------
  // Captured filter metadata (2026-11-14, the owner's Plex server).
  //
  // The two constants below are `MediaContainer.Meta` verbatim from
  // `evidence/plex-metadata-{movies,tv}-before.json` in the job folder
  // (section 11 `type=1` and section 10 `type=2`, `X-Plex-Token` redacted).
  // They are the fixture for the genre data path: the live capture is what
  // decides whether a genre field exists and how it is typed, not a guess.
  // ---------------------------------------------------------------------------
  group('captured Plex filter metadata', () {
    test('movie capture: the movie node is active and serves genre as a tag', () {
      final meta = jsonDecode(_capturedMoviesMeta) as Map<String, dynamic>;
      final active = (meta['Type'] as List)
          .whereType<Map<String, dynamic>>()
          .where((type) => type['active'] == true)
          .toList();

      expect(active, hasLength(1));
      expect(active.single['type'], 'movie');
      final fields = (active.single['Field'] as List).whereType<Map<String, dynamic>>();
      expect(fields.firstWhere((field) => field['key'] == 'genre'), {'key': 'genre', 'title': 'Genre', 'type': 'tag'});
    });

    test('movie section: genre parses to a tag filter whose value list is /genre?type=1', () async {
      final client = testPlexClient(handler: (_) async => _filterMetadataResponse(_capturedMoviesMeta));
      addTearDown(client.close);

      final result = await client.fetchLibraryFiltersWithValues('11', libraryKind: MediaKind.movie);
      final genre = result.filters.singleWhere((filter) => filter.filter == 'genre');

      expect(genre.filterType, MediaFilterType.tag);
      expect(genre.title, 'Genre');
      expect(genre.key, '/library/sections/11/genre?type=1');
      expect(genre.hasValueList, isTrue);
      expect(genre.editorKind, FilterEditorKind.valueList);
      expect(genre.operators, const [LibraryFilterOperator.is_, LibraryFilterOperator.isNot]);
      // The public helper the editor calls must resolve the same path the parse
      // recorded, so the category list and the editor cannot drift.
      expect(client.filterValuesKeyFor(genre, libraryId: '11', typeId: 1), genre.key);
    });

    test('show section: show.genre loses its type prefix and lists /genre?type=2', () async {
      final client = testPlexClient(handler: (_) async => _filterMetadataResponse(_capturedTvMeta));
      addTearDown(client.close);

      final result = await client.fetchLibraryFiltersWithValues('10', libraryKind: MediaKind.show);
      final genre = result.filters.singleWhere((filter) => filter.filter == 'genre');

      expect(genre.filterType, MediaFilterType.tag);
      expect(genre.title, 'Genre');
      expect(genre.key, '/library/sections/10/genre?type=2');
      expect(result.filters.where((filter) => filter.filter.endsWith('.genre')), isEmpty);
      expect(client.filterValuesKeyFor(genre, libraryId: '10', typeId: 2), genre.key);
    });

    test('show capture: the season and episode nodes serve no genre field', () {
      final meta = jsonDecode(_capturedTvMeta) as Map<String, dynamic>;
      final byType = {
        for (final type in (meta['Type'] as List).whereType<Map<String, dynamic>>()) type['type'] as String: type,
      };

      for (final grouping in const ['season', 'episode']) {
        final keys = ((byType[grouping]!['Field'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((field) => field['key'])
            .toList();
        expect(keys.where((key) => key.toString().endsWith('genre')), isEmpty, reason: '$grouping must not declare genre');
      }
      // Hence /library/sections/10/genre?type=3 and ?type=4 answer an empty
      // Directory list (measured: evidence/plex-values-tv-type{3,4}-before.json)
      // while type=2 answers 24 rows.
    });

    test('filterValuesKeyFor: the browsed grouping decides the type=, unlisted fields get null', () {
      final client = testPlexClient();
      addTearDown(client.close);
      MediaFilter filter(String field, String filterType) =>
          MediaFilter(filter: field, filterType: filterType, key: '', title: '', type: 'filter');

      final genre = filter('genre', MediaFilterType.tag);
      expect(client.filterValuesKeyFor(genre, libraryId: '10', typeId: 1), '/library/sections/10/genre?type=1');
      expect(client.filterValuesKeyFor(genre, libraryId: '10', typeId: 2), '/library/sections/10/genre?type=2');
      expect(client.filterValuesKeyFor(genre, libraryId: '10', typeId: 3), '/library/sections/10/genre?type=3');
      expect(client.filterValuesKeyFor(genre, libraryId: '10', typeId: 4), '/library/sections/10/genre?type=4');
      expect(client.filterValuesKeyFor(genre, libraryId: '10'), '/library/sections/10/genre');

      // A qualified wire name addresses the bare endpoint.
      expect(
        client.filterValuesKeyFor(filter('show.genre', MediaFilterType.tag), libraryId: '10', typeId: 2),
        '/library/sections/10/genre?type=2',
      );
      // Only year/decade integers are enumerable; the rest have no list.
      expect(
        client.filterValuesKeyFor(filter('year', MediaFilterType.integer), libraryId: '10', typeId: 1),
        '/library/sections/10/year?type=1',
      );
      expect(client.filterValuesKeyFor(filter('duration', MediaFilterType.integer), libraryId: '10', typeId: 1), isNull);
      expect(client.filterValuesKeyFor(filter('title', MediaFilterType.string), libraryId: '10', typeId: 1), isNull);
      expect(client.filterValuesKeyFor(filter('unwatched', MediaFilterType.boolean), libraryId: '10', typeId: 1), isNull);
      expect(client.filterValuesKeyFor(filter('addedAt', MediaFilterType.date), libraryId: '10', typeId: 1), isNull);
    });
  });
}

http.Response _filterMetadataResponse(String metaJson) => http.Response(
  jsonEncode({
    'MediaContainer': {'size': 0, 'Meta': jsonDecode(metaJson)},
  }),
  200,
  headers: const {'content-type': 'application/json'},
);

/// `MediaContainer.Meta` captured from the owner's Plex server — see the fixture
/// comment in `main()`.
const _capturedMoviesMeta = r'''{"Type":[{"key":"/library/sections/11/all?type=1","type":"movie","title":"Movies","active":true,"Filter":[{"filter":"genre","filterType":"string","key":"/library/sections/11/genre","title":"Genre","type":"filter"},{"filter":"year","filterType":"integer","key":"/library/sections/11/year","title":"Year","type":"filter"},{"filter":"decade","filterType":"integer","key":"/library/sections/11/decade","title":"Decade","type":"filter"},{"filter":"contentRating","filterType":"string","key":"/library/sections/11/contentRating","title":"Content Rating","type":"filter"},{"filter":"collection","filterType":"string","key":"/library/sections/11/collection","title":"Collection","type":"filter"},{"filter":"director","filterType":"string","key":"/library/sections/11/director","title":"Director","type":"filter"},{"filter":"actor","filterType":"string","key":"/library/sections/11/actor","title":"Actor","type":"filter"},{"filter":"writer","filterType":"string","key":"/library/sections/11/writer","title":"Writer","type":"filter"},{"filter":"producer","filterType":"string","key":"/library/sections/11/producer","title":"Producer","type":"filter"},{"filter":"country","filterType":"string","key":"/library/sections/11/country","title":"Country","type":"filter"},{"filter":"studio","filterType":"string","key":"/library/sections/11/studio","title":"Studio","type":"filter"},{"filter":"resolution","filterType":"string","key":"/library/sections/11/resolution","title":"Resolution","type":"filter"},{"filter":"hdr","filterType":"boolean","key":"/library/sections/11/hdr","title":"HDR","type":"filter"},{"filter":"dovi","filterType":"boolean","key":"/library/sections/11/dovi","title":"DOVI","type":"filter"},{"filter":"hdr10plus","filterType":"boolean","key":"/library/sections/11/hdr10plus","title":"HDR10+","type":"filter"},{"filter":"atmos","filterType":"boolean","key":"/library/sections/11/atmos","title":"Atmos","type":"filter"},{"filter":"unwatched","filterType":"boolean","key":"/library/sections/11/unwatched","title":"Unwatched","type":"filter"},{"filter":"inProgress","filterType":"boolean","key":"/library/sections/11/inProgress","title":"In Progress","type":"filter"},{"filter":"unmatched","filterType":"boolean","key":"/library/sections/11/unmatched","title":"Unmatched","type":"filter"},{"filter":"videoCodec","filterType":"string","key":"/library/sections/11/videoCodec","title":"Video Codec","type":"filter"},{"filter":"audioCodec","filterType":"string","key":"/library/sections/11/audioCodec","title":"Audio Codec","type":"filter"},{"filter":"subtitleCodec","filterType":"string","key":"/library/sections/11/subtitleCodec","title":"Subtitle Codec","type":"filter"},{"filter":"audioLayout","filterType":"string","key":"/library/sections/11/audioLayout","title":"Audio Layout","type":"filter"},{"filter":"audioLanguage","filterType":"string","key":"/library/sections/11/audioLanguage","title":"Audio Language","type":"filter"},{"filter":"subtitleLanguage","filterType":"string","key":"/library/sections/11/subtitleLanguage","title":"Subtitle Language","type":"filter"},{"filter":"editionTitle","filterType":"string","key":"/library/sections/11/editionTitle","title":"Edition","type":"filter"},{"filter":"label","filterType":"string","key":"/library/sections/11/label","title":"Labels","type":"filter"},{"filter":"location","filterType":"string","key":"/library/sections/11/location","title":"Folder Location","type":"filter"}],"Sort":[{"active":true,"activeDirection":"asc","default":"asc","defaultDirection":"asc","descKey":"titleSort:desc","firstCharacterKey":"/library/sections/11/firstCharacter","key":"titleSort","title":"Title"},{"defaultDirection":"desc","descKey":"originallyAvailableAt:desc","key":"originallyAvailableAt","title":"Release Date"},{"defaultDirection":"desc","descKey":"rating:desc","key":"rating","title":"Critic Rating"},{"defaultDirection":"desc","descKey":"audienceRating:desc","key":"audienceRating","title":"Audience Rating"},{"defaultDirection":"desc","descKey":"duration:desc","key":"duration","title":"Duration"},{"defaultDirection":"desc","descKey":"addedAt:desc","key":"addedAt","title":"Date Added"},{"defaultDirection":"desc","descKey":"lastViewedAt:desc","key":"lastViewedAt","title":"Date Viewed"},{"defaultDirection":"asc","descKey":"mediaHeight:desc","key":"mediaHeight","title":"Resolution"},{"defaultDirection":"desc","descKey":"random:desc","key":"random","title":"Randomly"}],"Field":[{"key":"title","title":"Title","type":"string"},{"key":"studio","title":"Studio","type":"string"},{"key":"userRating","subType":"rating","title":"Rating","type":"integer"},{"key":"contentRating","title":"Content Rating","type":"tag"},{"key":"year","subType":"year","title":"Year","type":"integer"},{"key":"decade","subType":"decade","title":"Decade","type":"integer"},{"key":"originallyAvailableAt","title":"Release Date","type":"date"},{"key":"duration","subType":"duration","title":"Duration","type":"integer"},{"key":"unmatched","title":"Unmatched","type":"boolean"},{"key":"duplicate","title":"Duplicate","type":"boolean"},{"key":"genre","title":"Genre","type":"tag"},{"key":"collection","title":"Collection","type":"tag"},{"key":"director","title":"Director","type":"tag"},{"key":"writer","title":"Writer","type":"tag"},{"key":"producer","title":"Producer","type":"tag"},{"key":"actor","title":"Actor","type":"tag"},{"key":"country","title":"Country","type":"tag"},{"key":"addedAt","title":"Date Added","type":"date"},{"key":"viewCount","title":"Plays","type":"integer"},{"key":"lastViewedAt","title":"Last Watched","type":"date"},{"key":"unwatched","title":"Unwatched","type":"boolean"},{"key":"resolution","title":"Resolution","type":"resolution"},{"key":"hdr","subType":"hdr","title":"HDR","type":"boolean"},{"key":"dovi","subType":"dovi","title":"DOVI","type":"boolean"},{"key":"hdr10plus","subType":"hdr10plus","title":"HDR10+","type":"boolean"},{"key":"atmos","subType":"atmos","title":"Atmos","type":"boolean"},{"key":"mediaSize","subType":"fileSize","title":"File Size","type":"integer"},{"key":"mediaBitrate","subType":"bitrate","title":"Bitrate","type":"integer"},{"key":"videoCodec","subType":"videoCodec","title":"Video Codec","type":"tag"},{"key":"audioCodec","subType":"audioCodec","title":"Audio Codec","type":"tag"},{"key":"subtitleCodec","subType":"subtitleCodec","title":"Subtitle Codec","type":"tag"},{"key":"audioLayout","subType":"audioLayout","title":"Audio Layout","type":"tag"},{"key":"subtitleLanguage","title":"Subtitle Language","type":"subtitleLanguage"},{"key":"audioLanguage","title":"Audio Language","type":"audioLanguage"},{"key":"inProgress","title":"In Progress","type":"boolean"},{"key":"trash","title":"Trash","type":"boolean"},{"key":"location","title":"Folder Location","type":"tag"},{"key":"editionTitle","title":"Edition","type":"string"},{"key":"contentRatingAge","title":"Common Sense Media Age Rating","type":"integer"},{"key":"label","title":"Label","type":"tag"}]},{"key":"/library/sections/11/folder","type":"folder","title":"Folders","active":false}],"FieldType":[{"type":"tag","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"integer","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"},{"key":">>=","title":"is greater than"},{"key":"<<=","title":"is less than"}]},{"type":"string","Operator":[{"key":"=","title":"contains"},{"key":"!=","title":"does not contain"},{"key":"==","title":"is"},{"key":"!==","title":"is not"},{"key":"<=","title":"begins with"},{"key":">=","title":"ends with"}]},{"type":"boolean","Operator":[{"key":"=","title":"is true"},{"key":"!=","title":"is false"}]},{"type":"date","Operator":[{"key":"<<=","title":"is before"},{"key":">>=","title":"is after"}]},{"type":"subtitleLanguage","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"audioLanguage","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"resolution","Operator":[{"key":"=","title":"is"}]}]}''';

const _capturedTvMeta = r'''{"Type":[{"key":"/library/sections/10/all?type=2","type":"show","title":"TV Shows","active":true,"Filter":[{"filter":"genre","filterType":"string","key":"/library/sections/10/genre?type=2","title":"Genre","type":"filter"},{"filter":"year","filterType":"integer","key":"/library/sections/10/year?type=2","title":"Year","type":"filter"},{"filter":"contentRating","filterType":"string","key":"/library/sections/10/contentRating?type=2","title":"Content Rating","type":"filter"},{"filter":"studio","filterType":"string","key":"/library/sections/10/studio?type=2","title":"Studio","type":"filter"},{"filter":"network","filterType":"string","key":"/library/sections/10/network?type=2","title":"Network","type":"filter"},{"filter":"country","filterType":"string","key":"/library/sections/10/country","title":"Country","type":"filter"},{"filter":"collection","filterType":"string","key":"/library/sections/10/collection?type=2","title":"Collection","type":"filter"},{"filter":"director","filterType":"string","key":"/library/sections/10/director?type=2","title":"Director","type":"filter"},{"filter":"actor","filterType":"string","key":"/library/sections/10/actor?type=2","title":"Actor","type":"filter"},{"filter":"writer","filterType":"string","key":"/library/sections/10/writer?type=2","title":"Writer","type":"filter"},{"filter":"producer","filterType":"string","key":"/library/sections/10/producer?type=2","title":"Producer","type":"filter"},{"filter":"unwatchedLeaves","filterType":"boolean","key":"/library/sections/10/unwatchedLeaves?type=2","title":"Unwatched","type":"filter"},{"filter":"unmatched","filterType":"boolean","key":"/library/sections/10/unmatched","title":"Unmatched","type":"filter"},{"filter":"editionTitle","filterType":"string","key":"/library/sections/10/editionTitle","title":"Edition","type":"filter"},{"filter":"label","filterType":"string","key":"/library/sections/10/label?type=2","title":"Labels","type":"filter"}],"Sort":[{"active":true,"activeDirection":"asc","default":"asc","defaultDirection":"asc","descKey":"titleSort:desc","firstCharacterKey":"/library/sections/10/firstCharacter","key":"titleSort","title":"Title"},{"defaultDirection":"desc","descKey":"originallyAvailableAt:desc","key":"originallyAvailableAt","title":"Release Date"},{"defaultDirection":"desc","descKey":"rating:desc","key":"rating","title":"Critic Rating"},{"defaultDirection":"desc","descKey":"audienceRating:desc","key":"audienceRating","title":"Audience Rating"},{"defaultDirection":"desc","descKey":"unviewedLeafCount:desc","key":"unviewedLeafCount","title":"Unwatched"},{"defaultDirection":"desc","descKey":"episode.addedAt:desc","key":"episode.addedAt","title":"Last Episode Date Added"},{"defaultDirection":"desc","descKey":"lastViewedAt:desc","key":"lastViewedAt","title":"Date Viewed"},{"defaultDirection":"desc","descKey":"random:desc","key":"random","title":"Randomly"}],"Field":[{"key":"show.title","title":"Show Title","type":"string"},{"key":"show.studio","title":"Studio","type":"string"},{"key":"show.network","title":"Network","type":"tag"},{"key":"show.country","title":"Country","type":"tag"},{"key":"show.userRating","subType":"rating","title":"Show Rating","type":"integer"},{"key":"show.contentRating","title":"Content Rating","type":"tag"},{"key":"show.year","subType":"year","title":"Show Year","type":"integer"},{"key":"show.viewCount","title":"Show Plays","type":"integer"},{"key":"show.lastViewedAt","title":"Show Last Watched","type":"date"},{"key":"show.genre","title":"Genre","type":"tag"},{"key":"show.collection","title":"Show Collection","type":"tag"},{"key":"show.director","title":"Show Director","type":"tag"},{"key":"show.writer","title":"Show Writer","type":"tag"},{"key":"show.producer","title":"Show Producer","type":"tag"},{"key":"show.actor","title":"Show Actor","type":"tag"},{"key":"show.addedAt","title":"Date Show Added","type":"date"},{"key":"show.unmatched","title":"Show Unmatched","type":"boolean"},{"key":"show.unwatchedLeaves","title":"Unwatched Episodes","type":"boolean"},{"key":"show.editionTitle","title":"Show Edition","type":"string"},{"key":"show.contentRatingAge","title":"Common Sense Media Age Rating","type":"integer"},{"key":"show.label","title":"Label","type":"tag"}]},{"key":"/library/sections/10/all?type=3","type":"season","title":"Seasons","active":false,"Sort":[{"default":"asc","defaultDirection":"asc","descKey":"show.titleSort:desc,index","key":"show.titleSort,index","title":"Show"},{"defaultDirection":"desc","descKey":"random:desc","key":"random","title":"Randomly"}]},{"key":"/library/sections/10/all?type=4","type":"episode","title":"Episodes","active":false,"Filter":[{"filter":"year","filterType":"integer","key":"/library/sections/10/year?type=4","title":"Year","type":"filter"},{"filter":"collection","filterType":"string","key":"/library/sections/10/collection?type=4","title":"Collection","type":"filter"},{"filter":"resolution","filterType":"string","key":"/library/sections/10/resolution?type=4","title":"Resolution","type":"filter"},{"filter":"hdr","filterType":"boolean","key":"/library/sections/10/hdr?type=4","title":"HDR","type":"filter"},{"filter":"dovi","filterType":"boolean","key":"/library/sections/10/dovi?type=4","title":"DOVI","type":"filter"},{"filter":"hdr10plus","filterType":"boolean","key":"/library/sections/10/hdr10plus?type=4","title":"HDR10+","type":"filter"},{"filter":"atmos","filterType":"boolean","key":"/library/sections/10/atmos?type=4","title":"Atmos","type":"filter"},{"filter":"unwatched","filterType":"boolean","key":"/library/sections/10/unwatched?type=4","title":"Unwatched","type":"filter"},{"filter":"inProgress","filterType":"boolean","key":"/library/sections/10/inProgress?type=4","title":"In Progress","type":"filter"},{"filter":"videoCodec","filterType":"string","key":"/library/sections/10/videoCodec","title":"Video Codec","type":"filter"},{"filter":"audioCodec","filterType":"string","key":"/library/sections/10/audioCodec","title":"Audio Codec","type":"filter"},{"filter":"subtitleCodec","filterType":"string","key":"/library/sections/10/subtitleCodec","title":"Subtitle Codec","type":"filter"},{"filter":"audioLayout","filterType":"string","key":"/library/sections/10/audioLayout","title":"Audio Layout","type":"filter"},{"filter":"audioLanguage","filterType":"string","key":"/library/sections/10/audioLanguage","title":"Audio Language","type":"filter"},{"filter":"subtitleLanguage","filterType":"string","key":"/library/sections/10/subtitleLanguage","title":"Subtitle Language","type":"filter"},{"filter":"unmatched","filterType":"boolean","key":"/library/sections/10/unmatched","title":"Unmatched","type":"filter"},{"filter":"location","filterType":"string","key":"/library/sections/10/location","title":"Folder Location","type":"filter"}],"Sort":[{"default":"asc","defaultDirection":"asc","descKey":"show.titleSort:desc,season.index:nullsLast,episode.index:nullsLast,episode.originallyAvailableAt:nullsLast,episode.titleSort,episode.id","key":"show.titleSort,season.index:nullsLast,episode.index:nullsLast,episode.originallyAvailableAt:nullsLast,episode.titleSort,episode.id","title":"Show"},{"defaultDirection":"desc","descKey":"originallyAvailableAt:desc","key":"originallyAvailableAt","title":"Release Date"},{"defaultDirection":"desc","descKey":"rating:desc","key":"rating","title":"Critic Rating"},{"defaultDirection":"desc","descKey":"audienceRating:desc","key":"audienceRating","title":"Audience Rating"},{"defaultDirection":"desc","descKey":"addedAt:desc","key":"addedAt","title":"Date Added"},{"defaultDirection":"desc","descKey":"lastViewedAt:desc","key":"lastViewedAt","title":"Date Viewed"},{"defaultDirection":"desc","descKey":"random:desc","key":"random","title":"Randomly"}],"Field":[{"key":"episode.title","title":"Episode Title","type":"string"},{"key":"episode.addedAt","title":"Date Episode Added","type":"date"},{"key":"episode.originallyAvailableAt","title":"Episode Air Date","type":"date"},{"key":"episode.year","subType":"year","title":"Episode Year","type":"integer"},{"key":"episode.userRating","subType":"rating","title":"Episode Rating","type":"integer"},{"key":"episode.viewCount","title":"Episode Plays","type":"integer"},{"key":"episode.lastViewedAt","title":"Episode Last Watched","type":"date"},{"key":"episode.unwatched","title":"Episode Unwatched","type":"boolean"},{"key":"episode.inProgress","title":"Episode In Progress","type":"boolean"},{"key":"episode.duplicate","title":"Episode Duplicate","type":"boolean"},{"key":"episode.hdr","subType":"hdr","title":"HDR","type":"boolean"},{"key":"episode.dovi","subType":"dovi","title":"DOVI","type":"boolean"},{"key":"episode.hdr10plus","subType":"hdr10plus","title":"HDR10+","type":"boolean"},{"key":"episode.atmos","subType":"Atmos","title":"Atmos","type":"boolean"},{"key":"episode.resolution","title":"Resolution","type":"resolution"},{"key":"episode.mediaSize","subType":"fileSize","title":"File size","type":"integer"},{"key":"episode.mediaBitrate","subType":"bitrate","title":"Bitrate","type":"integer"},{"key":"episode.videoCodec","subType":"videoCodec","title":"Video Codec","type":"tag"},{"key":"episode.audioCodec","subType":"audioCodec","title":"Audio Codec","type":"tag"},{"key":"episode.subtitleCodec","subType":"subtitleCodec","title":"Subtitle Codec","type":"tag"},{"key":"episode.audioLayout","subType":"audioLayout","title":"Audio Layout","type":"tag"},{"key":"episode.subtitleLanguage","title":"Subtitle Language","type":"subtitleLanguage"},{"key":"episode.audioLanguage","title":"Audio Language","type":"audioLanguage"},{"key":"episode.trash","title":"Trash","type":"boolean"},{"key":"episode.unmatched","title":"Episode Unmatched","type":"boolean"},{"key":"episode.location","title":"Folder Location","type":"tag"}]},{"key":"/library/sections/10/folder","type":"folder","title":"Folders","active":false}],"FieldType":[{"type":"tag","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"integer","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"},{"key":">>=","title":"is greater than"},{"key":"<<=","title":"is less than"}]},{"type":"string","Operator":[{"key":"=","title":"contains"},{"key":"!=","title":"does not contain"},{"key":"==","title":"is"},{"key":"!==","title":"is not"},{"key":"<=","title":"begins with"},{"key":">=","title":"ends with"}]},{"type":"boolean","Operator":[{"key":"=","title":"is true"},{"key":"!=","title":"is false"}]},{"type":"date","Operator":[{"key":"<<=","title":"is before"},{"key":">>=","title":"is after"}]},{"type":"subtitleLanguage","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"audioLanguage","Operator":[{"key":"=","title":"is"},{"key":"!=","title":"is not"}]},{"type":"resolution","Operator":[{"key":"=","title":"is"}]}]}''';

http.Response _metadataResponse(List<Object?> settings) {
  return http.Response(
    jsonEncode({
      'MediaContainer': {
        'Metadata': [
          {
            'ratingKey': 'show-1',
            'type': 'show',
            'title': 'Show',
            'originalTitle': 'Original show title',
            'summary': 'Summary',
            'librarySectionID': 1,
            'Genre': [
              {'tag': 'Drama'},
              {'tag': 'Science Fiction'},
            ],
            'Setting': settings,
          },
        ],
      },
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

MediaItem _show() => testMediaItem(
  id: 'show-1',
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: 'Show',
  originalTitle: 'Original show title',
  summary: 'Summary',
  libraryId: '1',
);
