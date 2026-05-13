import 'dart:async';
import 'dart:math' as math;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'features/planner/place_search_service.dart';
import 'features/planner/planner_models.dart';
import 'features/planner/routing_service.dart';

void main() {
  runApp(const MotoPlannerApp());
}

class MotoPlannerApp extends StatefulWidget {
  const MotoPlannerApp({super.key});

  @override
  State<MotoPlannerApp> createState() => _MotoPlannerAppState();
}

class _MotoPlannerAppState extends State<MotoPlannerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    const fallbackSeed = Color(0xff1565c0);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme =
            lightDynamic ?? ColorScheme.fromSeed(seedColor: fallbackSeed);
        final darkScheme =
            darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: fallbackSeed,
              brightness: Brightness.dark,
            );

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'MotoPlanner',
          themeMode: _themeMode,
          theme: ThemeData(useMaterial3: true, colorScheme: lightScheme),
          darkTheme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
          home: PlannerHome(
            themeMode: _themeMode,
            onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
          ),
        );
      },
    );
  }
}

enum SearchTarget { origin, destination }

enum MapStyle {
  roads('Roads', Icons.map_outlined),
  satellite('Satellite', Icons.satellite_alt_outlined),
  traffic('Traffic', Icons.traffic_outlined);

  const MapStyle(this.label, this.icon);

  final String label;
  final IconData icon;
}

class PlannerHome extends StatefulWidget {
  const PlannerHome({
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<PlannerHome> {
  static const _defaultCenter = LatLng(39.8283, -98.5795);

  final _mapController = MapController();
  final _tts = FlutterTts();
  final _placeSearch = PlaceSearchService();
  final _routing = RoutingService();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _preferences = [...defaultPreferences];
  final _distance = const Distance();
  Timer? _autocompleteTimer;
  StreamSubscription<Position>? _positionSubscription;
  int _searchSequence = 0;
  int _navStepIndex = 0;
  int? _lastSpokenStepIndex;
  bool _programmaticTextEdit = false;
  bool _locationBusy = false;
  bool _navigating = false;
  bool _followNavigation = true;
  bool _headingUp = true;
  bool _offRouteAlerted = false;

  SearchTarget _searchTarget = SearchTarget.destination;
  MapStyle _mapStyle = MapStyle.roads;
  PlaceResult? _origin;
  PlaceResult? _destination;
  final List<PlaceResult> _shapingPoints = [];
  PlannedRoute? _route;
  Position? _currentPosition;
  double? _distanceToNextStepMeters;
  double? _distanceToDestinationMeters;
  String? _navigationAlert;
  List<PlaceResult> _searchResults = const [];
  bool _searching = false;
  bool _routingBusy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _originController.addListener(() => _onQueryChanged(SearchTarget.origin));
    _destinationController.addListener(
      () => _onQueryChanged(SearchTarget.destination),
    );
    unawaited(_centerOnCurrentLocation(setAsOrigin: true, quiet: true));
  }

  @override
  void dispose() {
    _autocompleteTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MotoPlanner'),
        actions: [
          IconButton(
            tooltip: 'Use current location',
            icon: _locationBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined),
            onPressed: _locationBusy ? null : _setCurrentLocationAsStart,
          ),
          PopupMenuButton<MapStyle>(
            tooltip: 'Map type',
            icon: Icon(_mapStyle.icon),
            initialValue: _mapStyle,
            onSelected: (style) => setState(() => _mapStyle = style),
            itemBuilder: (context) => [
              for (final style in MapStyle.values)
                PopupMenuItem(
                  value: style,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(style.icon),
                    title: Text(style.label),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Speak next direction',
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: _speakNextDirection,
          ),
          PopupMenuButton<ThemeMode>(
            tooltip: 'Theme',
            icon: const Icon(Icons.contrast_outlined),
            initialValue: widget.themeMode,
            onSelected: widget.onThemeModeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: ThemeMode.system, child: Text('System')),
              PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
              PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _buildPreferences())),
      body: Row(
        children: [
          if (wide) SizedBox(width: 390, child: _buildPreferences()),
          Expanded(
            child: Stack(
              children: [
                _PlannerMap(
                  controller: _mapController,
                  origin: _origin,
                  destination: _destination,
                  shapingPoints: _shapingPoints,
                  route: _route,
                  mapStyle: _mapStyle,
                  currentPosition: _currentPosition,
                  navigating: _navigating,
                  headingUp: _headingUp,
                  onTap: _dropPin,
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: _SearchCard(
                    originController: _originController,
                    destinationController: _destinationController,
                    searching: _searching,
                    results: _searchResults,
                    searchTarget: _searchTarget,
                    onSearch: (target) => _search(target, selectFirst: true),
                    onQueryChanged: (target) =>
                        setState(() => _searchTarget = target),
                    onTargetChanged: (target) =>
                        setState(() => _searchTarget = target),
                    onResultSelected: _selectPlace,
                    onSwap: _swapRouteEnds,
                    onClear: _clearRoute,
                  ),
                ),
                if (_message != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: wide ? 156 : 172,
                    child: _StatusBanner(
                      message: _message!,
                      onDismissed: () => setState(() => _message = null),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: _route == null ? 120 : 214,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'follow',
                        tooltip: _followNavigation
                            ? 'Following location'
                            : 'Follow location',
                        onPressed: _currentPosition == null
                            ? null
                            : () {
                                setState(
                                  () => _followNavigation = !_followNavigation,
                                );
                                if (_followNavigation) {
                                  _moveToPosition(_currentPosition!);
                                }
                              },
                        child: Icon(
                          _followNavigation
                              ? Icons.explore
                              : Icons.explore_outlined,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'heading',
                        tooltip: _headingUp ? 'Heading up' : 'North up',
                        onPressed: _navigating
                            ? () {
                                setState(() => _headingUp = !_headingUp);
                                if (!_headingUp) {
                                  _mapController.rotate(0);
                                } else if (_currentPosition != null) {
                                  _moveToPosition(_currentPosition!);
                                }
                              }
                            : null,
                        child: Icon(
                          _headingUp ? Icons.navigation : Icons.north,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoomIn',
                        tooltip: 'Zoom in',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom + 1,
                        ),
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoomOut',
                        tooltip: 'Zoom out',
                        onPressed: () => _mapController.move(
                          _mapController.camera.center,
                          _mapController.camera.zoom - 1,
                        ),
                        child: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _RouteSheet(
                    origin: _origin,
                    destination: _destination,
                    shapingPoints: _shapingPoints,
                    route: _route,
                    routingBusy: _routingBusy,
                    navigating: _navigating,
                    currentStepIndex: _navStepIndex,
                    distanceToNextStepMeters: _distanceToNextStepMeters,
                    distanceToDestinationMeters: _distanceToDestinationMeters,
                    navigationAlert: _navigationAlert,
                    onPlanRide: _planRoute,
                    onUndoShapingPoint: _shapingPoints.isEmpty
                        ? null
                        : _undoLastShapingPoint,
                    onClearShapingPoints: _shapingPoints.isEmpty
                        ? null
                        : _clearShapingPoints,
                    onStartNavigation: _startNavigation,
                    onStopNavigation: _stopNavigation,
                    onSpeak: _speakNextDirection,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferences() {
    return _PreferencePanel(
      preferences: _preferences,
      onChanged: _updatePreference,
      onReplan: _origin != null && _destination != null ? _planRoute : null,
    );
  }

  void _onQueryChanged(SearchTarget target) {
    if (_programmaticTextEdit) {
      return;
    }

    final query = target == SearchTarget.origin
        ? _originController.text
        : _destinationController.text;
    setState(() {
      _searchTarget = target;
      _message = null;
      _route = null;
      if (target == SearchTarget.origin) {
        _origin = null;
      } else {
        _destination = null;
      }
      if (query.trim().length < 3) {
        _searchResults = const [];
      }
    });

    _autocompleteTimer?.cancel();
    if (query.trim().length < 3) {
      return;
    }

    _autocompleteTimer = Timer(
      const Duration(milliseconds: 220),
      () => unawaited(_search(target, previewFirst: true)),
    );
  }

  Future<void> _search(
    SearchTarget target, {
    bool selectFirst = false,
    bool previewFirst = false,
  }) async {
    final query = target == SearchTarget.origin
        ? _originController.text
        : _destinationController.text;
    final sequence = ++_searchSequence;
    if (selectFirst) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    setState(() {
      _searchTarget = target;
      _searching = true;
      _message = null;
    });

    try {
      final results = await _placeSearch.search(
        query,
        context: _searchContext(target),
      );
      if (!mounted || sequence != _searchSequence) {
        return;
      }
      if (selectFirst && results.isNotEmpty) {
        await _selectPlace(results.first, targetOverride: target);
        return;
      }
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _message =
              'No places found. Try a city, road, landmark, or full address.';
        }
      });
      if (previewFirst && results.isNotEmpty) {
        _mapController.move(
          results.first.latLng,
          math.max(_mapController.camera.zoom, 11),
        );
      }
    } catch (error) {
      if (mounted && sequence == _searchSequence) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted && sequence == _searchSequence) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _selectPlace(
    PlaceResult result, {
    SearchTarget? targetOverride,
  }) async {
    final target = targetOverride ?? _searchTarget;
    setState(() {
      _programmaticTextEdit = true;
      if (target == SearchTarget.origin) {
        _origin = result;
        _originController.text = _shortName(result.name);
        _searchTarget = SearchTarget.destination;
      } else {
        _destination = result;
        _destinationController.text = _shortName(result.name);
      }
      _shapingPoints.clear();
      _programmaticTextEdit = false;
      _searchResults = const [];
      _message = null;
    });

    _mapController.move(result.latLng, 13);
    await _planRouteIfReady();
  }

  Future<void> _dropPin(LatLng point) async {
    final place = PlaceResult(
      name:
          'Dropped pin ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
      latLng: point,
      type: 'map tap',
    );

    setState(() {
      if (_origin == null || _searchTarget == SearchTarget.origin) {
        _origin = place;
        _originController.text = 'Dropped start';
        _searchTarget = SearchTarget.destination;
        _shapingPoints.clear();
      } else if (_destination == null) {
        _destination = place;
        _destinationController.text = 'Dropped destination';
      } else {
        _shapingPoints.add(
          PlaceResult(
            name: 'Scenic shaping point ${_shapingPoints.length + 1}',
            latLng: point,
            type: 'route shaping',
          ),
        );
      }
      _message = null;
    });

    await _planRouteIfReady();
  }

  Future<bool> _setCurrentLocationAsStart() async {
    return _centerOnCurrentLocation(setAsOrigin: true, quiet: false);
  }

  Future<bool> _centerOnCurrentLocation({
    required bool setAsOrigin,
    required bool quiet,
  }) async {
    if (_locationBusy) {
      return false;
    }

    setState(() => _locationBusy = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!quiet) {
          setState(
            () => _message =
                'Turn on location services, then try current location again.',
          );
        }
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!quiet) {
          setState(
            () => _message =
                'Location permission is needed to use current location.',
          );
        }
        return false;
      }

      final lastKnown = await _safeLastKnownPosition();
      if (lastKnown != null) {
        await _applyCurrentPosition(lastKnown, setAsOrigin: setAsOrigin);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 4),
        ),
      );
      await _applyCurrentPosition(position, setAsOrigin: setAsOrigin);
      return true;
    } catch (error) {
      if (!quiet) {
        setState(() => _message = 'Current location failed: $error');
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _locationBusy = false);
      }
    }
  }

  Future<Position?> _safeLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } on UnsupportedError {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyCurrentPosition(
    Position position, {
    required bool setAsOrigin,
  }) async {
    _currentPosition = position;
    final place = PlaceResult(
      name: 'Current location',
      latLng: LatLng(position.latitude, position.longitude),
      type: 'gps',
    );
    setState(() {
      if (setAsOrigin) {
        _programmaticTextEdit = true;
        _origin = place;
        _originController.text = place.name;
        _programmaticTextEdit = false;
        _searchTarget = SearchTarget.destination;
        _shapingPoints.clear();
      }
      _message = null;
    });
    _mapController.move(place.latLng, 14);
    await _planRouteIfReady();
  }

  Future<void> _startNavigation() async {
    if (_route == null) {
      await _planRoute();
      if (_route == null) {
        return;
      }
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(
        () => _message = 'Turn on location services to start navigation.',
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(
        () => _message = 'Location permission is needed to start navigation.',
      );
      return;
    }

    await _positionSubscription?.cancel();
    setState(() {
      _navigating = true;
      _followNavigation = true;
      _headingUp = true;
      _navStepIndex = 0;
      _lastSpokenStepIndex = null;
      _offRouteAlerted = false;
      _navigationAlert = 'Navigation started';
      _message = null;
    });
    await _tts.speak(_currentInstruction);

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          _onNavigationPosition,
          onError: (Object error) {
            if (mounted) {
              setState(() => _message = 'Navigation location failed: $error');
            }
          },
        );

    final lastKnown = await _safeLastKnownPosition();
    if (lastKnown != null) {
      _onNavigationPosition(lastKnown);
    }
  }

  Future<void> _stopNavigation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    setState(() {
      _navigating = false;
      _navigationAlert = null;
      _mapController.rotate(0);
    });
  }

  void _onNavigationPosition(Position position) {
    final route = _route;
    if (route == null || route.points.length < 2) {
      return;
    }

    final current = LatLng(position.latitude, position.longitude);
    final progress = _routeProgress(route, current);
    final stepIndex = _stepIndexForDistance(
      route,
      progress.distanceAlongRouteMeters,
    );
    final nextDistance = _distanceToStepEnd(
      route,
      stepIndex,
      progress.distanceAlongRouteMeters,
    );
    final destinationDistance = math
        .max(0, route.distanceMeters - progress.distanceAlongRouteMeters)
        .toDouble();
    final offRoute = progress.distanceFromRouteMeters;
    final arrived =
        destinationDistance < 40 ||
        _distance.as(LengthUnit.Meter, current, route.points.last) < 40;

    String? alert;
    if (arrived) {
      alert = 'Arrived at destination';
    } else if (offRoute > 70) {
      alert = 'Off route by ${_formatDistance(offRoute)}';
    } else if (nextDistance < 120 && stepIndex < route.steps.length) {
      alert =
          '${_formatDistance(nextDistance)}: ${route.steps[stepIndex].instruction}';
    }

    setState(() {
      _currentPosition = position;
      _navStepIndex = stepIndex;
      _distanceToNextStepMeters = nextDistance;
      _distanceToDestinationMeters = destinationDistance;
      _navigationAlert = alert;
      if (arrived) {
        _navigating = false;
      }
    });

    if (_followNavigation) {
      _moveToPosition(position);
    }

    if (arrived) {
      unawaited(_tts.speak('You have arrived.'));
      unawaited(_positionSubscription?.cancel());
      return;
    }

    if (offRoute > 70 && !_offRouteAlerted) {
      _offRouteAlerted = true;
      unawaited(_tts.speak('You are off route. Replan when safe.'));
    } else if (offRoute <= 45) {
      _offRouteAlerted = false;
    }

    if (stepIndex != _lastSpokenStepIndex &&
        nextDistance < 180 &&
        stepIndex < route.steps.length) {
      _lastSpokenStepIndex = stepIndex;
      unawaited(
        _tts.speak(
          '${route.steps[stepIndex].instruction}. ${_formatDistance(nextDistance)}.',
        ),
      );
    }
  }

  void _moveToPosition(Position position) {
    final point = LatLng(position.latitude, position.longitude);
    _mapController.move(
      point,
      math.max(_mapController.camera.zoom, _navigating ? 17 : 14),
    );
    if (_navigating &&
        _headingUp &&
        position.heading.isFinite &&
        position.heading >= 0) {
      _mapController.rotate(position.heading);
    }
  }

  Future<void> _planRouteIfReady() async {
    if (_origin != null && _destination != null) {
      await _planRoute();
    }
  }

  Future<void> _planRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null && destination != null) {
      setState(
        () =>
            _message = 'Requesting location permission for your start point...',
      );
      final located = await _setCurrentLocationAsStart();
      if (!located) {
        return;
      }
      await _planRouteIfReady();
      return;
    }
    if (origin == null || destination == null) {
      setState(() => _message = 'Set a start and destination first.');
      return;
    }

    setState(() {
      _routingBusy = true;
      _message = null;
    });

    try {
      final route = await _routing.route(
        origin: origin.latLng,
        destination: destination.latLng,
        shapingPoints: _shapingPoints
            .map((point) => point.latLng)
            .toList(growable: false),
        preferences: _preferenceMap(),
      );
      setState(() {
        _route = route;
        _navStepIndex = 0;
        _distanceToNextStepMeters = route.steps.isEmpty
            ? null
            : route.steps.first.distanceMeters;
        _distanceToDestinationMeters = route.distanceMeters;
        _navigationAlert = null;
      });
      _fitRoute(route.points);
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) {
        setState(() => _routingBusy = false);
      }
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.length < 2) {
      return;
    }
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) {
          return;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.fromLTRB(48, 170, 48, 230),
          ),
        );
      }),
    );
  }

  void _swapRouteEnds() {
    setState(() {
      final oldOrigin = _origin;
      _origin = _destination;
      _destination = oldOrigin;
      final reversedShapingPoints = _shapingPoints.reversed.toList(
        growable: false,
      );
      _shapingPoints
        ..clear()
        ..addAll(reversedShapingPoints);
      _programmaticTextEdit = true;
      _originController.text = _origin == null ? '' : _shortName(_origin!.name);
      _destinationController.text = _destination == null
          ? ''
          : _shortName(_destination!.name);
      _programmaticTextEdit = false;
    });
    unawaited(_planRouteIfReady());
  }

  void _clearRoute() {
    unawaited(_stopNavigation());
    setState(() {
      _origin = null;
      _destination = null;
      _shapingPoints.clear();
      _route = null;
      _searchResults = const [];
      _programmaticTextEdit = true;
      _originController.clear();
      _destinationController.clear();
      _programmaticTextEdit = false;
      _message = null;
    });
  }

  void _undoLastShapingPoint() {
    if (_shapingPoints.isEmpty) {
      return;
    }
    setState(() {
      _shapingPoints.removeLast();
      _message = null;
    });
    unawaited(_planRouteIfReady());
  }

  void _clearShapingPoints() {
    if (_shapingPoints.isEmpty) {
      return;
    }
    setState(() {
      _shapingPoints.clear();
      _message = null;
    });
    unawaited(_planRouteIfReady());
  }

  Future<void> _speakNextDirection() async {
    final route = _route;
    if (route == null || route.steps.isEmpty) {
      await _tts.speak('Set a start and destination, then plan a ride.');
      return;
    }
    final step = route.steps[math.min(_navStepIndex, route.steps.length - 1)];
    final distance = _distanceToNextStepMeters ?? step.distanceMeters;
    await _tts.speak('${step.instruction}. ${_formatDistance(distance)}.');
  }

  String get _currentInstruction {
    final route = _route;
    if (route == null || route.steps.isEmpty) {
      return 'Navigation started.';
    }
    return route
        .steps[math.min(_navStepIndex, route.steps.length - 1)]
        .instruction;
  }

  void _updatePreference(String key, double value) {
    setState(() {
      void setPreference(String targetKey, double targetValue) {
        final index = _preferences.indexWhere(
          (preference) => preference.key == targetKey,
        );
        if (index >= 0) {
          _preferences[index] = _preferences[index].copyWith(
            value: targetValue,
          );
        }
      }

      setPreference(key, value);
      if (key == 'avoidHighways' && value >= 0.5) {
        setPreference('targetHighways', 0);
      }
      if (key == 'avoidMainRoads' && value >= 0.5) {
        setPreference('targetHighways', 0);
      }
      if (key == 'targetHighways' && value >= 0.5) {
        setPreference('avoidHighways', 0);
        setPreference('avoidMainRoads', 0);
      }
    });
  }

  Map<String, double> _preferenceMap() => {
    for (final preference in _preferences) preference.key: preference.value,
  };

  SearchContext _searchContext(SearchTarget target) {
    final bounds = _mapController.camera.visibleBounds;
    final anchor = target == SearchTarget.destination
        ? _origin?.latLng ?? _mapController.camera.center
        : _destination?.latLng ?? _mapController.camera.center;

    return SearchContext(
      center: anchor,
      north: bounds.north,
      south: bounds.south,
      east: bounds.east,
      west: bounds.west,
    );
  }

  String _shortName(String value) {
    final parts = value.split(',');
    return parts.take(math.min(2, parts.length)).join(',').trim();
  }

  _RouteProgress _routeProgress(PlannedRoute route, LatLng current) {
    var bestDistance = double.infinity;
    var distanceBeforeBest = 0.0;
    var distanceAlong = 0.0;

    for (var index = 0; index < route.points.length - 1; index += 1) {
      final start = route.points[index];
      final end = route.points[index + 1];
      final segmentLength = _distance.as(LengthUnit.Meter, start, end);
      final projection = _projectToSegment(current, start, end);
      final offRoute = _distance.as(
        LengthUnit.Meter,
        current,
        projection.point,
      );
      if (offRoute < bestDistance) {
        bestDistance = offRoute;
        distanceBeforeBest = distanceAlong + segmentLength * projection.t;
      }
      distanceAlong += segmentLength;
    }

    return _RouteProgress(
      distanceAlongRouteMeters: math.min(
        distanceBeforeBest,
        route.distanceMeters,
      ),
      distanceFromRouteMeters: bestDistance,
    );
  }

  _SegmentProjection _projectToSegment(LatLng point, LatLng start, LatLng end) {
    final latScale = math.cos(
      degreesToRadians((start.latitude + end.latitude) / 2),
    );
    final px = point.longitude * latScale;
    final py = point.latitude;
    final sx = start.longitude * latScale;
    final sy = start.latitude;
    final ex = end.longitude * latScale;
    final ey = end.latitude;
    final dx = ex - sx;
    final dy = ey - sy;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0
        ? 0.0
        : (((px - sx) * dx + (py - sy) * dy) / lengthSquared).clamp(0.0, 1.0);

    return _SegmentProjection(
      point: LatLng(
        start.latitude + (end.latitude - start.latitude) * t,
        start.longitude + (end.longitude - start.longitude) * t,
      ),
      t: t,
    );
  }

  int _stepIndexForDistance(
    PlannedRoute route,
    double distanceAlongRouteMeters,
  ) {
    var cumulative = 0.0;
    for (var index = 0; index < route.steps.length; index += 1) {
      cumulative += route.steps[index].distanceMeters;
      if (distanceAlongRouteMeters <= cumulative) {
        return index;
      }
    }
    return math.max(0, route.steps.length - 1);
  }

  double _distanceToStepEnd(
    PlannedRoute route,
    int stepIndex,
    double distanceAlongRouteMeters,
  ) {
    final stepEnd = route.steps
        .take(stepIndex + 1)
        .fold<double>(0, (sum, step) => sum + step.distanceMeters);
    return math.max(0, stepEnd - distanceAlongRouteMeters);
  }
}

class _RouteProgress {
  const _RouteProgress({
    required this.distanceAlongRouteMeters,
    required this.distanceFromRouteMeters,
  });

  final double distanceAlongRouteMeters;
  final double distanceFromRouteMeters;
}

class _SegmentProjection {
  const _SegmentProjection({required this.point, required this.t});

  final LatLng point;
  final double t;
}

class _PlannerMap extends StatelessWidget {
  const _PlannerMap({
    required this.controller,
    required this.origin,
    required this.destination,
    required this.shapingPoints,
    required this.route,
    required this.mapStyle,
    required this.currentPosition,
    required this.navigating,
    required this.headingUp,
    required this.onTap,
  });

  static const _trafficTileTemplate = String.fromEnvironment(
    'MOTOPLANNER_TRAFFIC_TILE_TEMPLATE',
  );

  final MapController controller;
  final PlaceResult? origin;
  final PlaceResult? destination;
  final List<PlaceResult> shapingPoints;
  final PlannedRoute? route;
  final MapStyle mapStyle;
  final Position? currentPosition;
  final bool navigating;
  final bool headingUp;
  final ValueChanged<LatLng> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final darkMap = Theme.of(context).brightness == Brightness.dark;
    final trafficConfigured = _trafficTileTemplate.isNotEmpty;

    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: _PlannerHomeState._defaultCenter,
        initialZoom: 4,
        minZoom: 3,
        maxZoom: 18,
        onTap: (_, point) => onTap(point),
      ),
      children: [
        TileLayer(
          urlTemplate: _baseTileTemplate,
          userAgentPackageName: 'com.motoplanner.mobile',
          tileBuilder: darkMap && mapStyle != MapStyle.satellite
              ? darkModeTileBuilder
              : null,
        ),
        if (mapStyle == MapStyle.traffic && trafficConfigured)
          TileLayer(
            urlTemplate: _trafficTileTemplate,
            userAgentPackageName: 'com.motoplanner.mobile',
            tileBuilder: darkMap ? darkModeTileBuilder : null,
          ),
        if (mapStyle == MapStyle.traffic && !trafficConfigured)
          Positioned(
            left: 12,
            top: 92,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 10,
                    offset: Offset(0, 3),
                    color: Color(0x22000000),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.traffic_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('Traffic provider not configured'),
                  ],
                ),
              ),
            ),
          ),
        if (route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route!.points,
                strokeWidth: 6,
                color: scheme.primary,
                borderStrokeWidth: 3,
                borderColor: scheme.surface,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (origin != null)
              Marker(
                point: origin!.latLng,
                width: 46,
                height: 46,
                child: _MapPin(label: 'A', color: scheme.primary),
              ),
            if (destination != null)
              Marker(
                point: destination!.latLng,
                width: 46,
                height: 46,
                child: _MapPin(label: 'B', color: scheme.tertiary),
              ),
            for (final indexed in shapingPoints.indexed)
              Marker(
                point: indexed.$2.latLng,
                width: 38,
                height: 38,
                child: _MapPin(
                  label: '${indexed.$1 + 1}',
                  color: scheme.secondary,
                ),
              ),
            if (currentPosition != null)
              Marker(
                point: LatLng(
                  currentPosition!.latitude,
                  currentPosition!.longitude,
                ),
                width: 52,
                height: 52,
                child: _CurrentLocationMarker(
                  heading: currentPosition!.heading,
                  navigating: navigating,
                  headingUp: headingUp,
                ),
              ),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(_attribution, style: const TextStyle(fontSize: 11)),
            ),
          ),
        ),
      ],
    );
  }

  String get _baseTileTemplate {
    return switch (mapStyle) {
      MapStyle.satellite =>
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      MapStyle.roads ||
      MapStyle.traffic => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    };
  }

  String get _attribution {
    return switch (mapStyle) {
      MapStyle.satellite => 'Tiles © Esri',
      MapStyle.roads => '© OpenStreetMap contributors',
      MapStyle.traffic =>
        _trafficTileTemplate.isEmpty
            ? '© OpenStreetMap contributors'
            : '© OpenStreetMap contributors · traffic provider',
    };
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.originController,
    required this.destinationController,
    required this.searching,
    required this.results,
    required this.searchTarget,
    required this.onSearch,
    required this.onQueryChanged,
    required this.onTargetChanged,
    required this.onResultSelected,
    required this.onSwap,
    required this.onClear,
  });

  final TextEditingController originController;
  final TextEditingController destinationController;
  final bool searching;
  final List<PlaceResult> results;
  final SearchTarget searchTarget;
  final ValueChanged<SearchTarget> onSearch;
  final ValueChanged<SearchTarget> onQueryChanged;
  final ValueChanged<SearchTarget> onTargetChanged;
  final ValueChanged<PlaceResult> onResultSelected;
  final VoidCallback onSwap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _searchControls(context, wide: true),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _searchControls(context, wide: false),
              ),
            if (results.isNotEmpty) ...[
              const Divider(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 230),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(
                        result.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        result.distanceMeters == null
                            ? '${result.latLng.latitude.toStringAsFixed(4)}, ${result.latLng.longitude.toStringAsFixed(4)}'
                            : '${_formatDistance(result.distanceMeters!)} away',
                      ),
                      onTap: () => onResultSelected(result),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _searchControls(BuildContext context, {required bool wide}) {
    final originField = _SearchField(
      controller: originController,
      label: 'Start',
      icon: Icons.trip_origin,
      selected: searchTarget == SearchTarget.origin,
      onSelected: () => onTargetChanged(SearchTarget.origin),
      onChanged: () => onQueryChanged(SearchTarget.origin),
      onSubmitted: () => onSearch(SearchTarget.origin),
    );
    final destinationField = _SearchField(
      controller: destinationController,
      label: 'Destination',
      icon: Icons.place_outlined,
      selected: searchTarget == SearchTarget.destination,
      onSelected: () => onTargetChanged(SearchTarget.destination),
      onChanged: () => onQueryChanged(SearchTarget.destination),
      onSubmitted: () => onSearch(SearchTarget.destination),
    );
    final swap = IconButton.filledTonal(
      tooltip: 'Swap start and destination',
      onPressed: onSwap,
      icon: const Icon(Icons.swap_vert),
    );
    final search = FilledButton.icon(
      onPressed: searching ? null : () => onSearch(searchTarget),
      icon: searching
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Text('Search'),
    );
    final clear = IconButton(
      tooltip: 'Clear route',
      onPressed: onClear,
      icon: const Icon(Icons.close),
    );

    if (wide) {
      return [
        Expanded(child: originField),
        const SizedBox(width: 8),
        swap,
        const SizedBox(width: 8),
        Expanded(child: destinationField),
        const SizedBox(width: 8),
        search,
        const SizedBox(width: 8),
        clear,
      ];
    }

    return [
      originField,
      const SizedBox(height: 8),
      destinationField,
      const SizedBox(height: 8),
      Row(
        children: [
          swap,
          const SizedBox(width: 8),
          Expanded(child: search),
          const SizedBox(width: 8),
          clear,
        ],
      ),
    ];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onTap: onSelected,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        filled: true,
        fillColor: selected
            ? scheme.primaryContainer.withValues(alpha: 0.38)
            : null,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _PreferencePanel extends StatelessWidget {
  const _PreferencePanel({
    required this.preferences,
    required this.onChanged,
    required this.onReplan,
  });

  final List<RoutePreference> preferences;
  final void Function(String key, double value) onChanged;
  final VoidCallback? onReplan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ride profile', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text(
          'Tune the ride, then replan. Provider-specific routing weights will get deeper as the routing engine is swapped in.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onReplan,
          icon: const Icon(Icons.route_outlined),
          label: const Text('Apply and replan'),
        ),
        const SizedBox(height: 14),
        for (final preference in preferences)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preference.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (preference.isToggle)
                        Switch(
                          value: preference.value >= 0.5,
                          onChanged: (value) =>
                              onChanged(preference.key, value ? 1 : 0),
                        ),
                    ],
                  ),
                  Text(preference.description),
                  if (!preference.isToggle)
                    Slider(
                      value: preference.value,
                      onChanged: (value) => onChanged(preference.key, value),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RouteSheet extends StatelessWidget {
  const _RouteSheet({
    required this.origin,
    required this.destination,
    required this.shapingPoints,
    required this.route,
    required this.routingBusy,
    required this.navigating,
    required this.currentStepIndex,
    required this.distanceToNextStepMeters,
    required this.distanceToDestinationMeters,
    required this.navigationAlert,
    required this.onPlanRide,
    required this.onUndoShapingPoint,
    required this.onClearShapingPoints,
    required this.onStartNavigation,
    required this.onStopNavigation,
    required this.onSpeak,
  });

  final PlaceResult? origin;
  final PlaceResult? destination;
  final List<PlaceResult> shapingPoints;
  final PlannedRoute? route;
  final bool routingBusy;
  final bool navigating;
  final int currentStepIndex;
  final double? distanceToNextStepMeters;
  final double? distanceToDestinationMeters;
  final String? navigationAlert;
  final VoidCallback onPlanRide;
  final VoidCallback? onUndoShapingPoint;
  final VoidCallback? onClearShapingPoints;
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canRoute = origin != null && destination != null;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 520,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(origin, destination, shapingPoints),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: !canRoute || routingBusy || navigating
                          ? null
                          : onPlanRide,
                      icon: routingBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.navigation_outlined),
                      label: Text(route == null ? 'Plan ride' : 'Replan'),
                    ),
                    FilledButton.icon(
                      onPressed: route == null
                          ? null
                          : navigating
                          ? onStopNavigation
                          : onStartNavigation,
                      icon: Icon(navigating ? Icons.stop : Icons.play_arrow),
                      label: Text(navigating ? 'Stop' : 'Start'),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Speak next direction',
                      onPressed: route == null ? null : onSpeak,
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
              ],
            ),
            if (route != null && route!.steps.isNotEmpty) ...[
              const Divider(height: 22),
              if (shapingPoints.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.edit_road_outlined, size: 18),
                      label: Text(
                        '${shapingPoints.length} shaping ${shapingPoints.length == 1 ? 'point' : 'points'}',
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Undo last shaping point',
                      onPressed: onUndoShapingPoint,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Clear shaping points',
                      onPressed: onClearShapingPoints,
                      icon: const Icon(Icons.layers_clear_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (navigating) ...[
                _NavigationStatus(
                  instruction: route!
                      .steps[math.min(
                        currentStepIndex,
                        route!.steps.length - 1,
                      )]
                      .instruction,
                  distanceToNextStepMeters: distanceToNextStepMeters,
                  distanceToDestinationMeters: distanceToDestinationMeters,
                  alert: navigationAlert,
                ),
                const SizedBox(height: 12),
              ],
              if (route!.plannerNotes.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final note in route!.plannerNotes.take(2))
                      Chip(
                        avatar: const Icon(Icons.tune_outlined, size: 18),
                        label: Text(note),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: math.min(route!.steps.length, 8),
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final step = route!.steps[index];
                    return SizedBox(
                      width: 230,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.instruction,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const Spacer(),
                              Text(_formatDistance(step.distanceMeters)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _title {
    if (route == null) {
      return 'Set your ride';
    }
    if (navigating) {
      final destination = distanceToDestinationMeters ?? route!.distanceMeters;
      return '${_formatDistance(destination)} remaining';
    }
    return '${_formatDistance(route!.distanceMeters)} · ${_formatDuration(route!.durationSeconds)}';
  }

  String _subtitle(
    PlaceResult? origin,
    PlaceResult? destination,
    List<PlaceResult> shapingPoints,
  ) {
    if (origin == null && destination == null) {
      return 'Search for places or tap the map to drop start and destination pins.';
    }
    final start = origin?.name ?? 'Choose start';
    final end = destination?.name ?? 'Choose destination';
    final via = shapingPoints.isEmpty
        ? ''
        : ' via ${shapingPoints.length} shaping ${shapingPoints.length == 1 ? 'point' : 'points'}';
    return '$start → $end$via';
  }
}

class _NavigationStatus extends StatelessWidget {
  const _NavigationStatus({
    required this.instruction,
    required this.distanceToNextStepMeters,
    required this.distanceToDestinationMeters,
    required this.alert,
  });

  final String instruction;
  final double? distanceToNextStepMeters;
  final double? distanceToDestinationMeters;
  final String? alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.navigation, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert ?? instruction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (distanceToNextStepMeters != null)
                        '${_formatDistance(distanceToNextStepMeters!)} to next',
                      if (distanceToDestinationMeters != null)
                        '${_formatDistance(distanceToDestinationMeters!)} left',
                    ].join(' · '),
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Color(0x33000000),
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker({
    required this.heading,
    required this.navigating,
    required this.headingUp,
  });

  final double heading;
  final bool navigating;
  final bool headingUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rotation = heading.isFinite && heading >= 0
        ? degreesToRadians(heading)
        : 0.0;

    return Transform.rotate(
      angle: headingUp ? 0 : rotation,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 3),
          boxShadow: const [
            BoxShadow(
              blurRadius: 14,
              offset: Offset(0, 4),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            navigating ? Icons.navigation : Icons.my_location,
            color: scheme.onPrimary,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismissed,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDistance(double meters) {
  final miles = meters / 1609.344;
  if (miles < 0.2) {
    return '${(meters * 3.28084).round()} ft';
  }
  return '${miles.toStringAsFixed(miles >= 10 ? 0 : 1)} mi';
}

String _formatDuration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
}

double degreesToRadians(double value) => value * math.pi / 180;
