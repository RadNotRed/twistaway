import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twistaway_app/integrations/spotify_service.dart';
import 'package:twistaway_app/main.dart';

void main() {
  test('map drops require explicit add-stop mode during navigation', () {
    expect(
      acceptsMapDrop(navigating: false, addingNavigationStop: false),
      isTrue,
    );
    expect(
      acceptsMapDrop(navigating: true, addingNavigationStop: false),
      isFalse,
    );
    expect(
      acceptsMapDrop(navigating: true, addingNavigationStop: true),
      isTrue,
    );
  });

  test('recenter only appears after navigation follow mode is lost', () {
    expect(
      shouldShowNavigationRecenter(navigating: true, following: false),
      isTrue,
    );
    expect(
      shouldShowNavigationRecenter(navigating: true, following: true),
      isFalse,
    );
    expect(
      shouldShowNavigationRecenter(navigating: false, following: false),
      isFalse,
    );
  });

  test('planned route live view preserves map space at phone height', () {
    final extent = plannedRouteLiveViewExtent(
      viewportHeight: 844,
      bottomPadding: 0,
      collapsedSheetHeight: 106,
      maxExtent: 0.92,
    );

    expect(extent, closeTo(520 / 844, 0.001));
    expect(extent, lessThan(0.68));
  });

  testWidgets('speedometer uses a unified card and changes rider speed to red',
      (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NavigationSpeedometer(
            speedMph: 64,
            roadSpeedLimitMph: 55,
            alertThresholdMph: 10,
          ),
        ),
      ),
    );

    var speed = tester.widget<Text>(
      find.byKey(const ValueKey('current-speed-mph')),
    );
    var limit = tester.widget<Text>(
      find.byKey(const ValueKey('road-speed-limit-mph')),
    );
    expect(speed.style?.color, Colors.white);
    expect(speed.style?.fontSize, limit.style?.fontSize);
    expect(find.text('SPEED LIMIT'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NavigationSpeedometer(
            speedMph: 65,
            roadSpeedLimitMph: 55,
            alertThresholdMph: 10,
          ),
        ),
      ),
    );
    speed = tester.widget<Text>(
      find.byKey(const ValueKey('current-speed-mph')),
    );
    limit = tester.widget<Text>(
      find.byKey(const ValueKey('road-speed-limit-mph')),
    );
    expect(speed.style?.color, const Color(0xffff4d4d));
    expect(speed.style?.fontSize, limit.style?.fontSize);
  });

  testWidgets('active navigation sheet shows ETA miles and ride controls', (
    WidgetTester tester,
  ) async {
    var addStopPressed = false;
    var settingsPressed = false;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationSheetContent(
            scrollController: controller,
            destinationName: 'Blue Ridge Parkway',
            distanceMeters: 16093.44,
            estimatedArrivalTime:
                DateTime.now().add(const Duration(minutes: 42)),
            addingStop: false,
            voiceGuidanceEnabled: true,
            spotify: const SpotifyPlayerState(),
            onToggleSheet: () {},
            onAddStop: () => addStopPressed = true,
            onCancelAddStop: () {},
            onOverview: () {},
            onRepeatDirection: () {},
            onVoiceGuidanceChanged: (_) {},
            onStopNavigation: () {},
            onPreviousSpotify: () {},
            onToggleSpotify: () {},
            onNextSpotify: () {},
            onOpenSpotify: () {},
            onConnectSpotify: () {},
            onOpenSettings: () => settingsPressed = true,
          ),
        ),
      ),
    );

    expect(find.text('ETA'), findsOneWidget);
    expect(find.text('TIME LEFT'), findsOneWidget);
    expect(find.text('42 min'), findsOneWidget);
    expect(find.text('MILES LEFT'), findsOneWidget);
    expect(find.text('10 mi'), findsOneWidget);
    expect(find.text('Blue Ridge Parkway'), findsOneWidget);
    expect(find.text('Add stop'), findsOneWidget);
    expect(find.text('Route overview'), findsOneWidget);
    expect(find.text('Voice on'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Repeat direction'), findsOneWidget);
    expect(find.text('Stop navigation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('navigation-settings-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('navigation-add-stop')));
    expect(addStopPressed, isTrue);
    await tester.tap(find.byKey(const ValueKey('navigation-settings-button')));
    expect(settingsPressed, isTrue);
    final settingsRect = tester.getRect(
      find.byKey(const ValueKey('navigation-settings-button')),
    );
    final stopRect = tester.getRect(
      find.byKey(const ValueKey('navigation-stop-button')),
    );
    expect(settingsRect.width, closeTo(stopRect.width, 0.1));
    expect(settingsRect.bottom, lessThan(stopRect.top));
  });

  testWidgets('navigation sheet expands and collapses from summary swipes', (
    WidgetTester tester,
  ) async {
    final sheetController = DraggableScrollableController();
    addTearDown(sheetController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggableScrollableSheet(
            controller: sheetController,
            initialChildSize: 0.24,
            minChildSize: 0.24,
            maxChildSize: 0.7,
            snap: true,
            snapSizes: const [0.24, 0.7],
            builder: (context, scrollController) => Material(
              child: NavigationSheetContent(
                scrollController: scrollController,
                destinationName: 'Blue Ridge Parkway',
                distanceMeters: 16093.44,
                estimatedArrivalTime:
                    DateTime.now().add(const Duration(minutes: 42)),
                addingStop: false,
                voiceGuidanceEnabled: true,
                spotify: const SpotifyPlayerState(),
                onToggleSheet: () {},
                onAddStop: () {},
                onCancelAddStop: () {},
                onOverview: () {},
                onRepeatDirection: () {},
                onVoiceGuidanceChanged: (_) {},
                onStopNavigation: () {},
                onPreviousSpotify: () {},
                onToggleSpotify: () {},
                onNextSpotify: () {},
                onOpenSpotify: () {},
                onConnectSpotify: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(sheetController.size, closeTo(0.24, 0.01));
    await tester.drag(find.text('TIME LEFT'), const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(sheetController.size, closeTo(0.7, 0.02));

    await tester.drag(find.text('TIME LEFT'), const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(sheetController.size, closeTo(0.24, 0.02));
  });

  testWidgets('planned route shows overview before a full-width start action', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var started = false;
    var replanned = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const PlannedRouteOverview(
                  startName: 'Current location',
                  destinationName: 'Blue Ridge Parkway',
                  distanceMeters: 16093.44,
                  durationSeconds: 2520,
                  viaPointCount: 1,
                ),
                const SizedBox(height: 12),
                RideActionControls(
                  onPlan: () => replanned = true,
                  routingBusy: false,
                  planLabel: 'Replan',
                  onDraw: () {},
                  drawMode: false,
                  onLoop: () {},
                  onStartOrStop: () => started = true,
                  navigating: false,
                  onSpeak: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Route overview'), findsOneWidget);
    expect(find.text('START'), findsOneWidget);
    expect(find.text('Current location'), findsOneWidget);
    expect(find.text('DESTINATION'), findsOneWidget);
    expect(find.text('Blue Ridge Parkway'), findsOneWidget);
    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('10 mi'), findsOneWidget);
    expect(find.text('RIDE TIME'), findsOneWidget);
    expect(find.text('42 min'), findsOneWidget);
    expect(find.text('ETA'), findsOneWidget);
    expect(find.text('Via 1 point'), findsOneWidget);
    expect(find.text('Start navigation'), findsOneWidget);
    expect(find.text('Replan'), findsOneWidget);
    expect(find.text('Edit route'), findsOneWidget);
    expect(find.text('Build loop'), findsOneWidget);
    expect(find.text('Preview voice'), findsOneWidget);

    final startRect = tester.getRect(
      find.byKey(const ValueKey('start-navigation-button')),
    );
    final replanRect = tester.getRect(
      find.byKey(const ValueKey('replan-route-button')),
    );
    expect(startRect.width, greaterThan(replanRect.width * 1.9));
    expect(startRect.bottom, lessThan(replanRect.top));

    await tester.tap(find.byKey(const ValueKey('start-navigation-button')));
    await tester.tap(find.byKey(const ValueKey('replan-route-button')));
    expect(started, isTrue);
    expect(replanned, isTrue);
  });
}
