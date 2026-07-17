import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:twistaway_app/features/planner/place_search_service.dart';
import 'package:twistaway_app/main.dart';

Future<void> openPlannerSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
  await tester.pumpAndSettle();
  final settings = find.byKey(const ValueKey('planner-settings-button'));
  await tester.ensureVisible(settings);
  await tester.pumpAndSettle();
  await tester.tap(settings);
}

void main() {
  testWidgets('clearing a route restores current location as the start', (
    WidgetTester tester,
  ) async {
    final currentPosition = Position(
      longitude: -73.0215,
      latitude: 40.8751,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlannerHome(
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          initialPosition: currentPosition,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();

    final start = find.byKey(const ValueKey('search-field-Start'));
    final destination =
        find.byKey(const ValueKey('search-field-Go to location'));
    await tester.enterText(start, 'My garage');
    await tester.enterText(destination, 'Coffee shop');
    await tester.ensureVisible(find.byTooltip('Clear route'));
    await tester.tap(find.byTooltip('Clear route'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        tester.widget<TextField>(start).controller!.text, 'Current location');
    expect(tester.widget<TextField>(destination).controller!.text, isEmpty);
    expect(
      find.text(
          'No places found. Try a city, road, landmark, or full address.'),
      findsNothing,
    );

    await tester.enterText(start, 'Another starting point');
    await tester.pump();
    expect(
      tester.widget<TextField>(start).controller!.text,
      'Another starting point',
    );
  });

  testWidgets('planner opens full-screen with a collapsed destination sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Twistaway'), findsNothing);
    expect(
      find.byKey(const ValueKey('planner-settings-button')),
      findsOneWidget,
    );
    expect(find.byTooltip('Map type'), findsNothing);
    expect(find.byTooltip('Theme'), findsNothing);
    expect(find.byKey(const ValueKey('search-field-Go to location')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    final collapsedSheet = tester.getRect(
      find.byKey(const ValueKey('planner-sheet-surface')),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('search-field-Start'))).top,
      greaterThanOrEqualTo(collapsedSheet.bottom),
    );
    expect(find.text('Set your ride'), findsOneWidget);
    expect(
      tester.getRect(find.text('Set your ride')).top,
      greaterThanOrEqualTo(collapsedSheet.bottom),
    );

    await tester.drag(
      find.byKey(const ValueKey('planner-sheet-handle')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    expect(find.text('Set your ride'), findsOneWidget);
    expect(find.text('Plan ride'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('draw mode hides the destination search field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-field-Go to location')),
        findsOneWidget);

    await tester.tap(find.text('Draw'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('search-field-Go to location')),
        findsNothing);
    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    expect(find.text('Drawing'), findsOneWidget);
    expect(find.text('Draw mode enabled.'), findsNothing);
  });

  testWidgets('saved routes panel has an empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Saved routes'), findsOneWidget);
    expect(find.text('No saved routes yet.'), findsOneWidget);
  });

  testWidgets('Spotify is reachable from the floating map header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('spotify-header-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('spotify-header-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('spotify-panel-content')),
      findsOneWidget,
    );
    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spotify-connect-button')),
      findsOneWidget,
    );
  });

  testWidgets('full-screen settings scroll and expose map credits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    await openPlannerSettings(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-screen')), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);
    expect(
      tester.getRect(find.byKey(const ValueKey('settings-screen'))),
      const Rect.fromLTWH(0, 0, 800, 600),
    );
    expect(find.text('Make every ride yours'), findsOneWidget);
    expect(find.text('Navigation marker'), findsOneWidget);
    expect(find.text('Triangle'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);
    expect(find.text('Truck'), findsOneWidget);
    expect(find.text('Bike'), findsOneWidget);
    expect(find.text('Icon'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-rider-color')), findsOneWidget);
    expect(find.byTooltip('Close settings'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Map & appearance'), findsOneWidget);
    expect(find.text('Speedometer'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('speedometer-enabled-setting')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('speed-alert-threshold-setting')),
      findsOneWidget,
    );
    expect(find.text('Navigation voice'), findsOneWidget);
    expect(find.text('Spoken directions'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('service-connection-mode')), findsOneWidget);
    expect(find.text('Route processing'), findsOneWidget);

    final defaultColor = find.byKey(
      const ValueKey('rider-color-#2475d0'),
    );
    final colorInk = tester.widget<InkResponse>(
      find.descendant(of: defaultColor, matching: find.byType(InkResponse)),
    );
    expect(colorInk.splashFactory, same(NoSplash.splashFactory));

    await tester.tap(find.text('Triangle'));
    await tester.pump();
    final triangleChip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Triangle'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(triangleChip.selected, isTrue);

    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-rider-color')));
    await tester.pumpAndSettle();
    expect(find.text('Custom marker color'), findsOneWidget);
    expect(find.text('Hue'), findsOneWidget);
    expect(find.text('Saturation'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    final colorSliderThemes = tester.widgetList<SliderTheme>(
      find.byType(SliderTheme),
    );
    expect(colorSliderThemes, hasLength(3));
    for (final sliderTheme in colorSliderThemes) {
      expect(
        sliderTheme.data.overlayShape,
        same(SliderComponentShape.noOverlay),
      );
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final settingsScroll = find.descendant(
      of: find.byKey(const ValueKey('settings-scroll')),
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(settingsScroll.first);
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, 0);
    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Privacy & storage'), findsOneWidget);
    expect(find.text('Legal & about'), findsOneWidget);
    await tester.tap(find.text('Map credits'));
    await tester.pumpAndSettle();

    expect(find.text('© OpenFreeMap'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('© OpenMapTiles'), findsOneWidget);
  });

  testWidgets('settings uses a smooth vertical transition and stable header', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    await openPlannerSettings(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    var fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('settings-entrance-fade')),
    );
    var slide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey('settings-entrance-slide')),
    );
    expect(fade.opacity.value, lessThan(0.05));
    expect(slide.position.value.dy, greaterThan(0.023));
    await tester.pump(const Duration(milliseconds: 80));

    fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('settings-entrance-fade')),
    );
    slide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey('settings-entrance-slide')),
    );
    expect(fade.opacity.value, allOf(greaterThan(0), lessThan(1)));
    expect(slide.position.value.dx, 0);
    expect(slide.position.value.dy, greaterThan(0));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.scrolledUnderElevation, 0);
    final headerColor = appBar.backgroundColor;

    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    final scrolledAppBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(scrolledAppBar.backgroundColor, headerColor);
    expect(scrolledAppBar.surfaceTintColor, Colors.transparent);

    await tester.tap(find.byTooltip('Close settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('settings-route-fade')),
    );
    slide = tester.widget<SlideTransition>(
      find.byKey(const ValueKey('settings-route-slide')),
    );
    expect(fade.opacity.value, allOf(greaterThan(0), lessThan(1)));
    expect(slide.position.value.dx, 0);
    expect(slide.position.value.dy, greaterThan(0));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-screen')), findsNothing);
  });

  testWidgets('collapsed sheet spacing stays balanced on a short screen', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    final handle = tester.getRect(
      find.byKey(const ValueKey('planner-sheet-handle')),
    );
    final destination = tester.getRect(
      find.byKey(const ValueKey('search-field-Go to location')),
    );

    expect(destination.left, 16);
    expect(destination.right, 374);
    expect(destination.top - handle.bottom, greaterThanOrEqualTo(0));
    expect(500 - destination.bottom - 24, inInclusiveRange(12, 28));
    expect(
      tester.getRect(find.byKey(const ValueKey('search-field-Start'))).top,
      greaterThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('planner-sheet-surface')))
            .bottom,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();

    final expandedSurface = tester.getRect(
      find.byKey(const ValueKey('planner-sheet-surface')),
    );
    final mapControls = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('map-controls-visibility')),
    );

    expect(expandedSurface.bottom, closeTo(500, 0.1));
    expect(expandedSurface.height, closeTo(428, 1));
    expect(mapControls.opacity, 0);

    final sheetScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('planner-sheet-scroll')),
    );
    expect(sheetScroll.controller!.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byKey(const ValueKey('planner-sheet-scroll')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(sheetScroll.controller!.position.pixels, greaterThan(0));
  });

  testWidgets('planner sheet expands and collapses with swipes anywhere', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    final sheet = find.byKey(const ValueKey('planner-sheet-surface'));
    final dragArea = find.byKey(const ValueKey('planner-sheet-drag-area'));
    final collapsedHeight = tester.getSize(sheet).height;
    expect(collapsedHeight, inInclusiveRange(88, 200));

    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('search-field-Start'))).top,
      greaterThanOrEqualTo(tester.getRect(sheet).bottom),
    );

    final openingGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('planner-sheet-handle'))),
    );
    await openingGesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await openingGesture.moveBy(const Offset(0, -70));
    await tester.pump();
    expect(tester.getSize(sheet).height, greaterThan(collapsedHeight));
    await openingGesture.moveBy(const Offset(0, -410));
    await openingGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    final expandedHeight = tester.getSize(sheet).height;
    expect(expandedHeight, greaterThan(collapsedHeight + 300));
    expect(expandedHeight, lessThan(700));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheet).height, closeTo(expandedHeight, 1));
    final sheetScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('planner-sheet-scroll')),
    );
    expect(sheetScroll.controller!.position.maxScrollExtent, closeTo(0, 1));
    expect(
      tester.getRect(find.byKey(const ValueKey('search-field-Start'))).bottom,
      lessThanOrEqualTo(tester.getRect(sheet).bottom),
    );

    await tester.drag(dragArea, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheet).height, closeTo(collapsedHeight, 1));
  });

  testWidgets('destination keyboard keeps the map surface mounted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    final map = find.byKey(const ValueKey('planner-map'));
    final mapState = tester.state(map);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.resizeToAvoidBottomInset, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('search-field-Go to location')),
    );
    await tester.pumpAndSettle();

    final destinationEditor = find.descendant(
      of: find.byKey(const ValueKey('search-control-destination')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(destinationEditor).focusNode.hasFocus,
        isTrue);
    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    expect(identical(tester.state(map), mapState), isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(identical(tester.state(map), mapState), isTrue);

    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-field-Start')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('search-field-Start'))).top,
      greaterThanOrEqualTo(
        tester
            .getRect(find.byKey(const ValueKey('planner-sheet-surface')))
            .bottom,
      ),
    );
  });

  testWidgets('keyboard search results use the sheet scroll space', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    final placeSearch = PlaceSearchService(
      client: MockClient((request) async => http.Response(
            '''{"features":[{"geometry":{"coordinates":[-73.428,40.752]},"properties":{"name":"Farmingdale State College","state":"New York","osm_value":"college"}}]}''',
            200,
          )),
      useDirectProviders: true,
    );
    await tester.pumpWidget(TwistawayApp(placeSearch: placeSearch));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const ValueKey('search-field-Go to location')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('search-field-Go to location')),
      'farmingdale',
    );
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('place-search-results')), findsOneWidget);
    final results = tester.widget<ListView>(
      find.byKey(const ValueKey('place-search-results')),
    );
    expect(results.padding, EdgeInsets.zero);
    expect(results.physics, isA<NeverScrollableScrollPhysics>());

    final searchButton = find.widgetWithText(FilledButton, 'Search');
    final firstResult = find.ancestor(
      of: find.text('Farmingdale State College, New York'),
      matching: find.byType(ListTile),
    );
    expect(
      tester.getRect(firstResult).top - tester.getRect(searchButton).bottom,
      lessThan(20),
    );
    expect(
      tester.getRect(firstResult).top,
      lessThan(844 - 320),
    );

    final sheetScroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('planner-sheet-scroll')),
    );
    expect(
      sheetScroll.controller!.position.maxScrollExtent,
      greaterThanOrEqualTo(320),
    );
  });
}
