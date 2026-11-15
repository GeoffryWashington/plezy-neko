import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/screens/libraries/filters/filter_value_page.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/widgets/focusable_list_tile.dart';

import '../../test_helpers/prefs.dart';

/// The order the page renders in, read from the rows it built rather than from
/// the list it was handed.
List<String> _renderedTitles(WidgetTester tester) => [
  for (final row in tester.widgetList<FocusableCheckboxListTile>(find.byType(FocusableCheckboxListTile)))
    (row.title! as Text).data!,
];

Future<void> _pumpPage(
  WidgetTester tester, {
  required MediaFilter filter,
  required List<MediaFilterValue> values,
}) async {
  final focusNode = FocusNode();
  addTearDown(focusNode.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FilterValuePage(
          filter: filter,
          values: values,
          clause: null,
          serverId: 'plex-server',
          libraryKey: 'plex-server:movies',
          onChanged: (_) {},
          initialFocusNode: focusNode,
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('a non-genre picker keeps the order the server listed', (tester) async {
    // Plex lists content ratings in its own ranking order; sorting them A-Z
    // would relabel the picker `G, NC-17, PG, PG-13, R`, which is not the
    // order the rating scale has.
    final filter = MediaFilter(
      filter: MediaFilterField.contentRating,
      filterType: MediaFilterType.tag,
      key: '/library/sections/11/contentRating',
      title: t.libraries.filterCategories.contentRating,
      type: 'filter',
    );
    await _pumpPage(
      tester,
      filter: filter,
      values: [
        for (final (key, title) in [
          ('1', 'G'),
          ('2', 'PG'),
          ('3', 'PG-13'),
          ('4', 'R'),
          ('5', 'NC-17'),
        ])
          MediaFilterValue(key: key, title: title),
      ],
    );

    expect(_renderedTitles(tester), ['G', 'PG', 'PG-13', 'R', 'NC-17']);
  });

  testWidgets('the genre picker is A-Z and drops a duplicated id', (tester) async {
    final filter = MediaFilter(
      filter: MediaFilterField.genre,
      filterType: MediaFilterType.tag,
      key: '/library/sections/11/genre',
      title: t.libraries.filterCategories.genre,
      type: 'filter',
    );
    await _pumpPage(
      tester,
      filter: filter,
      values: [
        MediaFilterValue(key: '1278', title: 'Zebra'),
        MediaFilterValue(key: '1594', title: 'Action'),
        MediaFilterValue(key: '1592', title: 'Mime'),
        MediaFilterValue(key: '1278', title: 'Zebra'),
      ],
    );

    expect(_renderedTitles(tester), ['Action', 'Mime', 'Zebra']);
  });
}
