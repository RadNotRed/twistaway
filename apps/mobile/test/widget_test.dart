import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:twistaway_app/main.dart';

void main() {
  testWidgets('planner opens full-screen with a collapsed destination sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Twistaway'), findsNothing);
    expect(find.byKey(const ValueKey('search-field-Go to location')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('search-field-Start')), findsNothing);
    expect(find.text('Set your ride'), findsNothing);

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

    await tester.tap(find.byTooltip('Settings'));
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
    expect(find.text('Blue bike'), findsOneWidget);
    expect(find.text('Red bike'), findsOneWidget);
    expect(find.text('Map & appearance'), findsOneWidget);
    expect(find.text('Navigation voice'), findsOneWidget);
    expect(find.text('Spoken directions'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('service-connection-mode')), findsOneWidget);
    expect(find.text('Route processing'), findsOneWidget);

    await tester.tap(find.text('Red bike'));
    await tester.pump();
    final redBikeChip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Red bike'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(redBikeChip.selected, isTrue);

    final settingsScroll = find.descendant(
      of: find.byKey(const ValueKey('settings-scroll')),
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(settingsScroll);
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

  testWidgets('collapsed sheet spacing stays balanced on a short screen', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

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
    expect(500 - destination.bottom, inInclusiveRange(12, 28));

    await tester.tap(find.byKey(const ValueKey('planner-sheet-handle')));
    await tester.pumpAndSettle();

    final expandedSurface = tester.getRect(
      find.byKey(const ValueKey('planner-sheet-surface')),
    );
    final mapControls = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('map-controls-visibility')),
    );

    expect(expandedSurface.bottom, closeTo(500, 0.1));
    expect(expandedSurface.height, greaterThan(470));
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

  testWidgets('planner sheet expands and collapses with handle swipes', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const TwistawayApp());
    await tester.pump(const Duration(milliseconds: 300));

    final sheet = find.byKey(const ValueKey('planner-sheet-surface'));
    final handle = find.byKey(const ValueKey('planner-sheet-handle'));
    expect(tester.getSize(sheet).height, closeTo(108, 1));

    await tester.drag(handle, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheet).height, greaterThan(800));

    await tester.drag(handle, const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheet).height, closeTo(108, 1));
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
    expect(find.byKey(const ValueKey('search-field-Start')), findsNothing);
  });
}
