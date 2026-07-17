import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/planner/place_history.dart';
import 'features/planner/place_search_service.dart';
import 'features/planner/planner_models.dart';
import 'features/planner/routing_service.dart';
import 'features/planner/service_connection_mode.dart';
import 'features/navigation/navigation_motion_smoother.dart';
import 'features/navigation/road_speed_limit_service.dart';
import 'integrations/spotify_service.dart';

void main() {
  runApp(const TwistawayApp());
}

class TwistawayApp extends StatefulWidget {
  const TwistawayApp({this.placeSearch, super.key});

  final PlaceSearchService? placeSearch;

  @override
  State<TwistawayApp> createState() => _TwistawayAppState();
}

class _TwistawayAppState extends State<TwistawayApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    const fallbackSeed = Color(0xff3976b8);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff739bcb),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xffa9c7ff),
      onPrimary: const Color(0xff0a305e),
      primaryContainer: const Color(0xff244a73),
      onPrimaryContainer: const Color(0xffd7e3ff),
      secondary: const Color(0xff8fd5cb),
      onSecondary: const Color(0xff003731),
      secondaryContainer: const Color(0xff174c47),
      onSecondaryContainer: const Color(0xffaef2e8),
      tertiary: const Color(0xffefc47a),
      onTertiary: const Color(0xff422c00),
      tertiaryContainer: const Color(0xff5c4212),
      onTertiaryContainer: const Color(0xffffdea1),
      surface: const Color(0xff0b1018),
      onSurface: const Color(0xffe6edf7),
      surfaceContainerLowest: const Color(0xff070b11),
      surfaceContainerLow: const Color(0xff101722),
      surfaceContainer: const Color(0xff151e2a),
      surfaceContainerHigh: const Color(0xff1c2735),
      surfaceContainerHighest: const Color(0xff253244),
      outline: const Color(0xff8390a3),
      outlineVariant: const Color(0xff3b485a),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Twistaway',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: fallbackSeed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surfaceContainerLowest,
        dividerColor: darkScheme.outlineVariant,
        shadowColor: Colors.black.withValues(alpha: 0.55),
      ),
      home: PlannerHome(
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        placeSearch: widget.placeSearch,
      ),
    );
  }
}

enum SearchTarget { origin, destination }

enum RouteBuildMode { normal, draw }

enum _NoticeTone { info, warning, error }

enum _RiderAvatar {
  circle('Circle', Icons.circle),
  triangle('Triangle', Icons.navigation),
  car('Car', Icons.directions_car),
  truck('Truck', Icons.local_shipping),
  bike('Bike', Icons.two_wheeler);

  const _RiderAvatar(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _defaultRiderColor = Color(0xff2475d0);
const _riderColorPresets = <Color>[
  Color(0xff2475d0),
  Color(0xff00a884),
  Color(0xffd44848),
  Color(0xffff8a24),
  Color(0xff8b5cf6),
  Color(0xffe83e8c),
  Color(0xff6c7a89),
  Color(0xff20242a),
];

class _VoiceOption {
  const _VoiceOption({required this.name, required this.locale});

  final String name;
  final String locale;
  String get id => '$name|$locale';
  String get label => locale.isEmpty ? name : '$name · $locale';
}

enum MapStyle {
  bright('Light', Icons.light_mode_outlined),
  fiord('Dark', Icons.dark_mode_outlined),
  threeD('3D', Icons.view_in_ar_outlined);

  const MapStyle(this.label, this.icon);

  final String label;
  final IconData icon;
}

class PlannerHome extends StatefulWidget {
  const PlannerHome({
    required this.themeMode,
    required this.onThemeModeChanged,
    this.placeSearch,
    this.initialPosition,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final PlaceSearchService? placeSearch;
  final Position? initialPosition;

  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<PlannerHome> {
  static const _defaultCenter = LatLng(39.8283, -98.5795);
  static const _sheetAnimationDuration = Duration(milliseconds: 120);
  static const _hideDrawHelpKey = 'planner.hideDrawHelp';
  static const _savedRoutesKey = 'planner.savedRoutes.v1';
  static const _placeHistoryKey = 'planner.placeHistory.v1';
  static const _mapStyleKey = 'settings.mapStyle';
  static const _themeModeKey = 'settings.themeMode';
  static const _avatarKey = 'settings.riderAvatar';
  static const _avatarColorKey = 'settings.riderColor';
  static const _voiceEnabledKey = 'settings.voiceEnabled';
  static const _voiceVolumeKey = 'settings.voiceVolume';
  static const _voiceKey = 'settings.voice';
  static const _serviceConnectionModeKey = 'settings.serviceConnectionMode';
  static const _speedometerEnabledKey = 'settings.speedometerEnabled';
  static const _speedAlertThresholdKey = 'settings.speedAlertThresholdMph';

  final _mapController = _PlannerMapController(
    center: _defaultCenter,
    zoom: 4,
  );
  final _tts = FlutterTts();
  final _storage = const FlutterSecureStorage();
  late final PlaceSearchService _placeSearch;
  PlaceHistory _placeHistory = PlaceHistory();
  final _routing = RoutingService();
  final _roadSpeedLimit = RoadSpeedLimitService();
  final _navigationMotion = NavigationMotionSmoother();
  final _spotify = SpotifyService();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _originFocusNode = FocusNode();
  final _destinationFocusNode = FocusNode();
  final _plannerSheetController = DraggableScrollableController();
  final _navigationSheetController = DraggableScrollableController();
  final _plannerSheetHandleMeasureKey = GlobalKey();
  final _destinationFieldMeasureKey = GlobalKey();
  final _plannerSheetContentMeasureKey = GlobalKey();
  final _plannedRouteOverviewKey = GlobalKey();
  final _preferences = [...defaultPreferences];
  final _distance = const Distance();
  Timer? _autocompleteTimer;
  Timer? _navigationMotionTimer;
  final Map<int, Timer> _noticeTimers = {};
  StreamSubscription<Position>? _positionSubscription;
  int _searchSequence = 0;
  int _originEditSequence = 0;
  int? _currentLocationOriginSequence;
  int? _appliedCurrentLocationOriginSequence;
  int _noticeSequence = 0;
  int _navStepIndex = 0;
  int? _lastSpokenStepIndex;
  bool _programmaticTextEdit = false;
  bool _locationBusy = false;
  bool _navigating = false;
  bool _followNavigation = false;
  bool _headingUp = true;
  bool _offRouteAlerted = false;
  bool _hideDrawHelp = false;
  bool _voiceGuidanceEnabled = true;
  bool _mapStyleUserSelected = false;
  bool _speedometerEnabled = true;
  bool _addingNavigationStop = false;
  double _voiceVolume = 0.8;
  double _speedAlertThresholdMph = 10;
  double _loopTargetMiles = 35;
  RouteBuildMode _routeBuildMode = RouteBuildMode.normal;
  ServiceConnectionMode _serviceConnectionMode = kDebugMode
      ? ServiceConnectionMode.directProviders
      : ServiceConnectionMode.automatic;

  SearchTarget _searchTarget = SearchTarget.destination;
  MapStyle _mapStyle = MapStyle.bright;
  _RiderAvatar _riderAvatar = _RiderAvatar.bike;
  Color _riderColor = _defaultRiderColor;
  String? _selectedVoiceId;
  List<_VoiceOption> _availableVoices = const [];
  PlaceResult? _origin;
  PlaceResult? _destination;
  final List<PlaceResult> _shapingPoints = [];
  PlannedRoute? _route;
  Position? _currentPosition;
  LatLng? _displayedPosition;
  double? _distanceToNextStepMeters;
  double? _distanceToDestinationMeters;
  DateTime? _estimatedArrivalTime;
  double? _roadSpeedLimitMph;
  DateTime? _lastRoadSpeedLookupAt;
  LatLng? _lastRoadSpeedLookupPosition;
  int _roadSpeedLookupSequence = 0;
  String? _navigationAlert;
  List<PlaceResult> _searchResults = const [];
  final List<_PlannerNotice> _notices = [];
  final List<_SavedRoute> _savedRoutes = [];
  bool _searching = false;
  bool _routingBusy = false;
  bool _sheetMeasurementScheduled = false;
  double _collapsedSheetHeight = 106;
  double _expandedSheetHeight = 720;
  int? _plannerSheetPointer;
  double? _plannerSheetPointerStartY;
  final _plannerSheetRaised = ValueNotifier<bool>(false);
  final _displayedPositionNotifier = ValueNotifier<LatLng?>(null);
  int? _navigationSheetPointer;
  double? _navigationSheetPointerStartY;

  SpotifyPlayerState get _spotifyState => _spotify.state;

  double get _currentSpeedMph {
    final metersPerSecond = _currentPosition?.speed ?? 0;
    return metersPerSecond.isFinite && metersPerSecond > 0
        ? metersPerSecond * 2.236936
        : 0;
  }

  @override
  void initState() {
    super.initState();
    _placeSearch = widget.placeSearch ?? PlaceSearchService();
    final initialPosition = widget.initialPosition;
    if (initialPosition != null) {
      final place = _placeFromCurrentPosition(initialPosition);
      _currentPosition = initialPosition;
      _displayedPosition = place.latLng;
      _displayedPositionNotifier.value = place.latLng;
      _origin = place;
      _originController.text = place.name;
      _searchTarget = SearchTarget.destination;
    }
    _originController.addListener(() => _onQueryChanged(SearchTarget.origin));
    _destinationController.addListener(
      () => _onQueryChanged(SearchTarget.destination),
    );
    unawaited(_loadDrawHelpPreference());
    unawaited(_loadSavedRoutes());
    unawaited(_loadPlaceHistory());
    unawaited(_loadAppSettings());
    if (initialPosition == null) {
      unawaited(_centerOnCurrentLocation(setAsOrigin: true, quiet: true));
    }
    _spotify.onError = (message) {
      _showNotice(message, tone: _NoticeTone.error);
    };
    _spotify.addListener(_onSpotifyChanged);
    unawaited(_spotify.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mapStyleUserSelected) _updateMapStyle();
  }

  void _updateMapStyle() {
    final mode = widget.themeMode;
    if (mode == ThemeMode.light) {
      _mapStyle = MapStyle.bright;
    } else if (mode == ThemeMode.dark) {
      _mapStyle = MapStyle.fiord;
    } else {
      final brightness = MediaQuery.platformBrightnessOf(context);
      _mapStyle =
          brightness == Brightness.dark ? MapStyle.fiord : MapStyle.bright;
    }
  }

  Future<void> _loadAppSettings() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _mapStyleKey),
        _storage.read(key: _themeModeKey),
        _storage.read(key: _avatarKey),
        _storage.read(key: _avatarColorKey),
        _storage.read(key: _voiceEnabledKey),
        _storage.read(key: _voiceVolumeKey),
        _storage.read(key: _voiceKey),
        _storage.read(key: _serviceConnectionModeKey),
        _storage.read(key: _speedometerEnabledKey),
        _storage.read(key: _speedAlertThresholdKey),
      ]);
      if (!mounted) return;

      final savedStyle = MapStyle.values.where(
        (style) => style.name == values[0],
      );
      final savedTheme = ThemeMode.values.where(
        (mode) => mode.name == values[1],
      );
      final savedAvatar = _RiderAvatar.values.where(
        (avatar) => avatar.name == values[2],
      );
      final savedRiderColor = int.tryParse(values[3] ?? '');
      final volume = double.tryParse(values[5] ?? '');
      final savedConnectionModes = ServiceConnectionMode.values.where(
        (mode) => mode.name == values[7],
      );
      final speedAlertThreshold = double.tryParse(values[9] ?? '');
      final connectionMode = savedConnectionModes.isEmpty
          ? _serviceConnectionMode
          : savedConnectionModes.first;

      _placeSearch.connectionMode = connectionMode;
      _routing.connectionMode = connectionMode;

      setState(() {
        if (savedStyle.isNotEmpty) {
          _mapStyle = savedStyle.first;
          _mapStyleUserSelected = true;
        }
        if (savedAvatar.isNotEmpty) {
          _riderAvatar = savedAvatar.first;
        } else if (values[2] == 'blueBike' || values[2] == 'redBike') {
          _riderAvatar = _RiderAvatar.bike;
        }
        _riderColor = savedRiderColor == null
            ? values[2] == 'redBike'
                ? const Color(0xffd44848)
                : _defaultRiderColor
            : Color(savedRiderColor);
        _voiceGuidanceEnabled = values[4] != 'false';
        _voiceVolume = (volume ?? 0.8).clamp(0, 1).toDouble();
        _selectedVoiceId = values[6];
        _serviceConnectionMode = connectionMode;
        _speedometerEnabled = values[8] != 'false';
        _speedAlertThresholdMph =
            (speedAlertThreshold ?? 10).clamp(0, 50).toDouble();
      });
      if (savedTheme.isNotEmpty && savedTheme.first != widget.themeMode) {
        widget.onThemeModeChanged(savedTheme.first);
      }
      await _refreshVoices();
      await _applyVoiceSettings();
    } catch (_) {
      // Defaults remain usable if local settings cannot be read.
    }
  }

  @override
  void didUpdateWidget(covariant PlannerHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      if (!_mapStyleUserSelected) _updateMapStyle();
    }
  }

  @override
  void dispose() {
    _autocompleteTimer?.cancel();
    _navigationMotionTimer?.cancel();
    for (final timer in _noticeTimers.values) {
      timer.cancel();
    }
    unawaited(_positionSubscription?.cancel());
    _plannerSheetController.dispose();
    _navigationSheetController.dispose();
    _plannerSheetRaised.dispose();
    _displayedPositionNotifier.dispose();
    _placeSearch.close();
    _routing.close();
    _roadSpeedLimit.close();
    _spotify.removeListener(_onSpotifyChanged);
    _spotify.onError = null;
    _spotify.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  void _onSpotifyChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _connectSpotify() async {
    try {
      final connected = await _spotify.connect();
      if (connected) {
        _showNotice('Spotify connected.', tone: _NoticeTone.info);
      } else {
        _showNotice('Spotify connection canceled.', tone: _NoticeTone.info);
      }
    } catch (error) {
      _showNotice(
        _spotifyErrorMessage(error),
        tone: _NoticeTone.error,
      );
    }
  }

  Future<void> _runSpotifyAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _showNotice(
        _spotifyErrorMessage(error),
        tone: _NoticeTone.error,
      );
    }
  }

  Future<void> _disconnectSpotify() async {
    await _runSpotifyAction(_spotify.disconnect);
    if (!_spotify.state.connected) {
      _showNotice('Spotify disconnected.', tone: _NoticeTone.info);
    }
  }

  Future<void> _openSpotifyPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: _spotify,
            builder: (context, _) => _SpotifyPanel(
              state: _spotify.state,
              onConnect: _connectSpotify,
              onPrevious: () => _runSpotifyAction(_spotify.previous),
              onTogglePlayback: () =>
                  _runSpotifyAction(_spotify.togglePlayback),
              onNext: () => _runSpotifyAction(_spotify.next),
              onOpenSpotify: _openSpotify,
              onDisconnect: _disconnectSpotify,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSpotify() async {
    try {
      final itemUri = _spotifyState.spotifyUri;
      final opened = await launchUrl(
        Uri.parse(itemUri == null || itemUri.isEmpty ? 'spotify:' : itemUri),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        final itemUrl = _spotifyState.spotifyUrl;
        final openedWeb = await launchUrl(
          Uri.parse(
            itemUrl == null || itemUrl.isEmpty
                ? 'https://open.spotify.com/'
                : itemUrl,
          ),
          mode: LaunchMode.externalApplication,
        );
        if (!openedWeb) {
          throw const SpotifyException('Spotify could not be opened.');
        }
      }
    } catch (error) {
      _showNotice(_spotifyErrorMessage(error), tone: _NoticeTone.error);
    }
  }

  String _spotifyErrorMessage(Object error) {
    if (error is SpotifyException) return error.message;
    final message = error.toString();
    if (message.startsWith('Bad state: ')) {
      return message.substring('Bad state: '.length);
    }
    if (message.startsWith('Unsupported operation: ')) {
      return message.substring('Unsupported operation: '.length);
    }
    return 'Spotify could not complete that action.';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final minSheetExtent =
        ((_collapsedSheetHeight + media.padding.bottom) / media.size.height)
            .clamp(0.09, 0.42)
            .toDouble();
    final maxSheetExtent = _expandedPlannerSheetExtent(media);
    const navigationCollapsedHeight = 194.0;
    final navigationMinExtent =
        ((navigationCollapsedHeight + media.padding.bottom) / media.size.height)
            .clamp(0.13, 0.34)
            .toDouble();
    final navigationMaxExtent = math.max(
      navigationMinExtent,
      math.min(0.68, 560 / media.size.height),
    );
    final mapControlsBottom = _navigating
        ? media.size.height * navigationMinExtent + 16
        : media.size.height * minSheetExtent + 16;
    final noticesTop = media.padding.top + (_navigating ? 126 : 68);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _displayedPositionNotifier,
                  builder: (context, displayedPosition, _) => _PlannerMap(
                    key: const ValueKey('planner-map'),
                    controller: _mapController,
                    origin: _origin,
                    destination: _destination,
                    shapingPoints: _shapingPoints,
                    route: _route,
                    mapStyle: _mapStyle,
                    currentPosition: _currentPosition,
                    displayedPosition: displayedPosition ?? _displayedPosition,
                    loopCenter: _destination?.type == 'loop return'
                        ? _origin?.latLng
                        : null,
                    loopRadiusMeters: _destination?.type == 'loop return'
                        ? _loopRadiusMeters()
                        : null,
                    navigating: _navigating,
                    following: _followNavigation,
                    headingUp: _headingUp,
                    riderAvatar: _riderAvatar,
                    riderColor: _riderColor,
                    onTap: _dropPin,
                    onMapMoved: _stopFollowingFromMapGesture,
                    onRemoveShapingPoint: _removeShapingPoint,
                    onRemoveDestination: _removeDestination,
                  ),
                ),
                _buildFloatingMapHeader(),
                if (_navigating)
                  Positioned(
                    key: const ValueKey('navigation-turn-banner'),
                    top: media.padding.top + 8,
                    left: 12,
                    right: 12,
                    child: PointerInterceptor(
                      child: _NavigationTurnBanner(
                        instruction: _currentInstruction,
                        distanceMeters: _distanceToNextStepMeters,
                        alert: _addingNavigationStop
                            ? 'Tap the map where you want to add a stop'
                            : _navigationAlert,
                        onSpeak: _speakNextDirection,
                        onStop: _stopNavigation,
                      ),
                    ),
                  ),
                if (_notices.isNotEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: noticesTop,
                    child: PointerInterceptor(
                      child: _NoticeStack(
                        notices: _notices,
                        onDismissed: _dismissNotice,
                      ),
                    ),
                  ),
                ValueListenableBuilder<bool>(
                  valueListenable: _plannerSheetRaised,
                  builder: (context, raised, child) {
                    final sheetRaised = raised;
                    return AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      right: 12,
                      bottom: mapControlsBottom,
                      child: PointerInterceptor(
                        child: IgnorePointer(
                          ignoring: sheetRaised,
                          child: AnimatedOpacity(
                            key: const ValueKey('map-controls-visibility'),
                            opacity: sheetRaised ? 0 : 1,
                            duration: const Duration(milliseconds: 160),
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_navigating) ...[
                        _MapControlButton(
                          heroTag: 'follow',
                          tooltip: _followNavigation
                              ? 'Following location'
                              : 'Follow location',
                          selected:
                              _currentPosition != null && _followNavigation,
                          onPressed:
                              _locationBusy ? null : _toggleLocationFollow,
                          icon: Icon(
                            _followNavigation
                                ? Icons.explore
                                : Icons.explore_outlined,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _MapControlButton(
                        heroTag: 'heading',
                        tooltip: _headingUp ? 'Heading up' : 'North up',
                        selected: _followNavigation && _headingUp,
                        onPressed: _currentPosition != null
                            ? () {
                                setState(() => _headingUp = !_headingUp);
                                if (!_headingUp) {
                                  _mapController.rotate(0);
                                } else if (_currentPosition != null) {
                                  _moveToPosition(_currentPosition!);
                                }
                              }
                            : null,
                        icon: Icon(
                          _headingUp ? Icons.navigation : Icons.north,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _MapControlButton(
                        heroTag: 'zoomIn',
                        tooltip: 'Zoom in',
                        onPressed: () => _mapController.zoomBy(1),
                        icon: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 10),
                      _MapControlButton(
                        heroTag: 'zoomOut',
                        tooltip: 'Zoom out',
                        onPressed: () => _mapController.zoomBy(-1),
                        icon: const Icon(Icons.remove),
                      ),
                    ],
                  ),
                ),
                if (!_navigating)
                  Positioned.fill(
                    child:
                        NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        final raised =
                            notification.extent > notification.minExtent + 0.06;
                        if (raised != _plannerSheetRaised.value) {
                          _plannerSheetRaised.value = raised;
                        }
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        key: const ValueKey('planner-sheet'),
                        controller: _plannerSheetController,
                        initialChildSize: minSheetExtent,
                        minChildSize: minSheetExtent,
                        maxChildSize: maxSheetExtent,
                        snap: true,
                        snapSizes: [minSheetExtent, maxSheetExtent],
                        snapAnimationDuration: _sheetAnimationDuration,
                        builder: (context, scrollController) {
                          final scheme = Theme.of(context).colorScheme;
                          _schedulePlannerSheetMeasurement(media);
                          return PointerInterceptor(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (event) {
                                _plannerSheetPointer = event.pointer;
                                _plannerSheetPointerStartY = event.position.dy;
                              },
                              onPointerUp: (event) =>
                                  _finishPlannerSheetPointer(
                                event,
                                minSheetExtent,
                                maxSheetExtent,
                              ),
                              onPointerCancel: (_) {
                                _plannerSheetPointer = null;
                                _plannerSheetPointerStartY = null;
                              },
                              child: SizedBox.expand(
                                key: const ValueKey('planner-sheet-drag-area'),
                                child: Material(
                                  key: const ValueKey('planner-sheet-surface'),
                                  elevation: 16,
                                  color: scheme.surface,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(26),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: SingleChildScrollView(
                                    key: const ValueKey('planner-sheet-scroll'),
                                    controller: scrollController,
                                    physics: const ClampingScrollPhysics(),
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      10 +
                                          media.padding.bottom +
                                          media.viewInsets.bottom,
                                    ),
                                    child: KeyedSubtree(
                                      key: _plannerSheetContentMeasureKey,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          KeyedSubtree(
                                            key: _plannerSheetHandleMeasureKey,
                                            child: GestureDetector(
                                              key: const ValueKey(
                                                'planner-sheet-handle',
                                              ),
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => _togglePlannerSheet(
                                                minSheetExtent,
                                                maxSheetExtent,
                                              ),
                                              child: SizedBox(
                                                height: 38,
                                                child: Center(
                                                  child: Container(
                                                    width: 42,
                                                    height: 5,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          scheme.outlineVariant,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              99),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          _SearchCard(
                                            originController: _originController,
                                            destinationController:
                                                _destinationController,
                                            originFocusNode: _originFocusNode,
                                            destinationFocusNode:
                                                _destinationFocusNode,
                                            showOrigin: true,
                                            showDestination: _routeBuildMode !=
                                                RouteBuildMode.draw,
                                            showActions: true,
                                            embedded: true,
                                            stacked: true,
                                            stackedSpacing:
                                                24 + media.padding.bottom,
                                            destinationMeasureKey:
                                                _destinationFieldMeasureKey,
                                            searching: _searching,
                                            results: _searchResults,
                                            searchTarget: _searchTarget,
                                            onSearch: (target) => _search(
                                                target,
                                                selectFirst: true),
                                            onQueryChanged: _selectSearchTarget,
                                            onTargetChanged: _focusSearchTarget,
                                            onResultSelected: _selectPlace,
                                            onSwap: _swapRouteEnds,
                                            onClear: _clearRoute,
                                          ),
                                          const Divider(height: 28),
                                          _RouteSheet(
                                            embedded: true,
                                            plannedRouteOverviewKey:
                                                _plannedRouteOverviewKey,
                                            origin: _origin,
                                            destination: _destination,
                                            shapingPoints: _shapingPoints,
                                            route: _route,
                                            routingBusy: _routingBusy,
                                            navigating: _navigating,
                                            currentStepIndex: _navStepIndex,
                                            distanceToNextStepMeters:
                                                _distanceToNextStepMeters,
                                            distanceToDestinationMeters:
                                                _distanceToDestinationMeters,
                                            navigationAlert: _navigationAlert,
                                            drawMode: _routeBuildMode ==
                                                RouteBuildMode.draw,
                                            loopTargetMiles: _loopTargetMiles,
                                            onPlanRide: _planRoute,
                                            onToggleDrawMode: _toggleDrawMode,
                                            onBuildLoopRide: _origin == null
                                                ? null
                                                : _buildLoopRide,
                                            onLoopTargetChanged:
                                                _updateLoopTarget,
                                            onUndoRoutePoint:
                                                _destination == null
                                                    ? null
                                                    : _undoRoutePoint,
                                            onClearRoutePoints:
                                                _destination == null &&
                                                        _shapingPoints.isEmpty
                                                    ? null
                                                    : _clearRoutePoints,
                                            onSaveRoute: _origin != null &&
                                                    _destination != null
                                                ? _saveCurrentRoute
                                                : null,
                                            onOpenSavedRoutes: _openSavedRoutes,
                                            savedRouteCount:
                                                _savedRoutes.length,
                                            onStartNavigation: _startNavigation,
                                            onStopNavigation: _stopNavigation,
                                            onSpeak: _speakNextDirection,
                                          ),
                                          const Divider(height: 28),
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'planner-settings-button',
                                            ),
                                            onPressed: _openSettings,
                                            icon: const Icon(
                                              Icons.settings_outlined,
                                            ),
                                            label: const Text('Settings'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                if (_navigating && _speedometerEnabled)
                  Positioned(
                    key: const ValueKey('navigation-speedometer-overlay'),
                    left: 12,
                    bottom: mapControlsBottom,
                    child: PointerInterceptor(
                      child: NavigationSpeedometer(
                        speedMph: _currentSpeedMph,
                        roadSpeedLimitMph: _roadSpeedLimitMph,
                        alertThresholdMph: _speedAlertThresholdMph,
                      ),
                    ),
                  ),
                if (shouldShowNavigationRecenter(
                  navigating: _navigating,
                  following: _followNavigation,
                ))
                  Positioned(
                    key: const ValueKey('navigation-recenter-overlay'),
                    left: 0,
                    right: 0,
                    bottom: mapControlsBottom,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _plannerSheetRaised,
                      builder: (context, raised, child) => IgnorePointer(
                        ignoring: raised,
                        child: AnimatedOpacity(
                          opacity: raised ? 0 : 1,
                          duration: const Duration(milliseconds: 160),
                          child: child,
                        ),
                      ),
                      child: Center(
                        child: PointerInterceptor(
                          child: FloatingActionButton.extended(
                            heroTag: 'navigation-recenter',
                            onPressed: _recenterNavigation,
                            icon: const Icon(Icons.my_location),
                            label: const Text('Recenter'),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_navigating)
                  Positioned.fill(
                    child:
                        NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        final raised =
                            notification.extent > notification.minExtent + 0.06;
                        if (raised != _plannerSheetRaised.value) {
                          _plannerSheetRaised.value = raised;
                        }
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        key: const ValueKey('navigation-sheet'),
                        controller: _navigationSheetController,
                        initialChildSize: navigationMinExtent,
                        minChildSize: navigationMinExtent,
                        maxChildSize: navigationMaxExtent,
                        snap: true,
                        snapSizes: [
                          navigationMinExtent,
                          navigationMaxExtent,
                        ],
                        snapAnimationDuration: _sheetAnimationDuration,
                        builder: (context, scrollController) {
                          return PointerInterceptor(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (event) {
                                _navigationSheetPointer = event.pointer;
                                _navigationSheetPointerStartY =
                                    event.position.dy;
                              },
                              onPointerUp: (event) =>
                                  _finishNavigationSheetPointer(
                                event,
                                navigationMinExtent,
                                navigationMaxExtent,
                              ),
                              onPointerCancel: (_) {
                                _navigationSheetPointer = null;
                                _navigationSheetPointerStartY = null;
                              },
                              child: SizedBox.expand(
                                key: const ValueKey(
                                  'navigation-sheet-drag-area',
                                ),
                                child: Material(
                                  key: const ValueKey(
                                    'navigation-sheet-surface',
                                  ),
                                  elevation: 16,
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(26),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: NavigationSheetContent(
                                    scrollController: scrollController,
                                    destinationName:
                                        _destination?.name ?? 'Destination',
                                    distanceMeters:
                                        _distanceToDestinationMeters,
                                    estimatedArrivalTime: _estimatedArrivalTime,
                                    addingStop: _addingNavigationStop,
                                    voiceGuidanceEnabled: _voiceGuidanceEnabled,
                                    spotify: _spotifyState,
                                    onToggleSheet: () => _toggleNavigationSheet(
                                      navigationMinExtent,
                                      navigationMaxExtent,
                                    ),
                                    onAddStop: () => _beginAddingNavigationStop(
                                      navigationMinExtent,
                                    ),
                                    onCancelAddStop:
                                        _cancelAddingNavigationStop,
                                    onOverview: _showNavigationOverview,
                                    onRepeatDirection: _speakNextDirection,
                                    onVoiceGuidanceChanged:
                                        _setVoiceGuidanceEnabled,
                                    onStopNavigation: _stopNavigation,
                                    onPreviousSpotify: () =>
                                        _runSpotifyAction(_spotify.previous),
                                    onToggleSpotify: () => _runSpotifyAction(
                                      _spotify.togglePlayback,
                                    ),
                                    onNextSpotify: () =>
                                        _runSpotifyAction(_spotify.next),
                                    onOpenSpotify: _openSpotify,
                                    onConnectSpotify: _connectSpotify,
                                    onOpenSettings: _openSettings,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingMapHeader() {
    if (_navigating) return const SizedBox.shrink();

    Widget popupSurface({required String tooltip, required Widget child}) {
      final scheme = Theme.of(context).colorScheme;
      return Material(
        elevation: 3,
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Tooltip(message: tooltip, child: child),
      );
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Spacer(),
              PointerInterceptor(
                child: popupSurface(
                  tooltip: _spotifyState.connected
                      ? 'Spotify player'
                      : 'Connect Spotify',
                  child: InkWell(
                    key: const ValueKey('spotify-header-button'),
                    onTap: _openSpotifyPanel,
                    child: const SizedBox.square(
                      dimension: 40,
                      child: Center(child: _SpotifyBrandIcon(size: 24)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _schedulePlannerSheetMeasurement(MediaQueryData media) {
    if (_sheetMeasurementScheduled || _navigating) return;
    _sheetMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetMeasurementScheduled = false;
      if (!mounted) return;

      final handleBox = _plannerSheetHandleMeasureKey.currentContext
          ?.findRenderObject() as RenderBox?;
      final destinationBox = _destinationFieldMeasureKey.currentContext
          ?.findRenderObject() as RenderBox?;
      final contentBox = _plannerSheetContentMeasureKey.currentContext
          ?.findRenderObject() as RenderBox?;
      if (handleBox == null ||
          destinationBox == null ||
          contentBox == null ||
          !handleBox.hasSize ||
          !destinationBox.hasSize ||
          !contentBox.hasSize) {
        return;
      }

      var collapsedHeight = _collapsedSheetHeight;
      if (!_plannerSheetRaised.value) {
        final handleTop = handleBox.localToGlobal(Offset.zero).dy;
        final destinationBottom = destinationBox
            .localToGlobal(Offset(0, destinationBox.size.height))
            .dy;
        collapsedHeight =
            (destinationBottom - handleTop + 12).clamp(88.0, 200.0).toDouble();
      }
      final expandedHeight =
          (contentBox.size.height + 10 + media.padding.bottom)
              .clamp(280.0, media.size.height)
              .toDouble();
      final collapsedChanged =
          (_collapsedSheetHeight - collapsedHeight).abs() > 0.5;
      final expandedChanged =
          (_expandedSheetHeight - expandedHeight).abs() > 0.5;
      if (!collapsedChanged && !expandedChanged) return;

      final oldMaxExtent = _expandedPlannerSheetExtent(media);
      final followContentHeight = _plannerSheetRaised.value &&
          _plannerSheetController.isAttached &&
          (_plannerSheetController.size - oldMaxExtent).abs() < 0.02;
      setState(() {
        _collapsedSheetHeight = collapsedHeight;
        _expandedSheetHeight = expandedHeight;
      });
      if (expandedChanged && followContentHeight) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_plannerSheetController.isAttached) return;
          unawaited(
            _plannerSheetController.animateTo(
              _expandedPlannerSheetExtent(MediaQuery.of(context)),
              duration: _sheetAnimationDuration,
              curve: Curves.easeOutCubic,
            ),
          );
        });
      }
    });
  }

  void _finishPlannerSheetPointer(
    PointerUpEvent event,
    double minExtent,
    double maxExtent,
  ) {
    if (_plannerSheetPointer != event.pointer) return;
    final startY = _plannerSheetPointerStartY;
    _plannerSheetPointer = null;
    _plannerSheetPointerStartY = null;
    if (startY == null) return;
    final dragDelta = event.position.dy - startY;

    scheduleMicrotask(() {
      if (!mounted || !_plannerSheetController.isAttached) return;
      final current = _plannerSheetController.size;
      if (current <= minExtent + 0.004 || current >= maxExtent - 0.004) {
        return;
      }
      final target = dragDelta < -12
          ? maxExtent
          : dragDelta > 12
              ? minExtent
              : current >= (minExtent + maxExtent) / 2
                  ? maxExtent
                  : minExtent;
      if (target == minExtent) _preparePlannerSheetCollapse();
      unawaited(
        _plannerSheetController.animateTo(
          target,
          duration: _sheetAnimationDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _togglePlannerSheet(double minExtent, double maxExtent) {
    if (!_plannerSheetController.isAttached) {
      return;
    }
    final expand = _plannerSheetController.size < minExtent + 0.08;
    if (!expand) {
      _preparePlannerSheetCollapse();
    }
    unawaited(
      _plannerSheetController.animateTo(
        expand ? maxExtent : minExtent,
        duration: _sheetAnimationDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _toggleNavigationSheet(double minExtent, double maxExtent) {
    if (!_navigationSheetController.isAttached) return;
    final expand = _navigationSheetController.size < minExtent + 0.08;
    unawaited(
      _navigationSheetController.animateTo(
        expand ? maxExtent : minExtent,
        duration: _sheetAnimationDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _finishNavigationSheetPointer(
    PointerUpEvent event,
    double minExtent,
    double maxExtent,
  ) {
    if (_navigationSheetPointer != event.pointer) return;
    final startY = _navigationSheetPointerStartY;
    _navigationSheetPointer = null;
    _navigationSheetPointerStartY = null;
    if (startY == null) return;
    final dragDelta = event.position.dy - startY;

    scheduleMicrotask(() {
      if (!mounted || !_navigationSheetController.isAttached) return;
      final current = _navigationSheetController.size;
      if (current <= minExtent + 0.004 || current >= maxExtent - 0.004) {
        return;
      }
      final target = dragDelta < -12
          ? maxExtent
          : dragDelta > 12
              ? minExtent
              : current >= (minExtent + maxExtent) / 2
                  ? maxExtent
                  : minExtent;
      unawaited(
        _navigationSheetController.animateTo(
          target,
          duration: _sheetAnimationDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _selectSearchTarget(SearchTarget target) {
    if (_searchTarget == target) {
      return;
    }
    setState(() => _searchTarget = target);
  }

  void _focusSearchTarget(SearchTarget target) {
    _selectSearchTarget(target);
    _expandPlannerSheet();
    final focusNode = target == SearchTarget.origin
        ? _originFocusNode
        : _destinationFocusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  void _preparePlannerSheetCollapse() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchResults.isNotEmpty) {
      setState(() => _searchResults = const []);
    }
  }

  double _expandedPlannerSheetExtent(MediaQueryData media) {
    final availableHeight = media.size.height - media.padding.top - 72;
    return (math.min(_expandedSheetHeight, availableHeight) / media.size.height)
        .clamp(0.32, 0.92)
        .toDouble();
  }

  void _expandPlannerSheet() {
    if (!_plannerSheetController.isAttached) {
      return;
    }
    final extent = _expandedPlannerSheetExtent(MediaQuery.of(context));
    unawaited(
      _plannerSheetController.animateTo(
        extent,
        duration: _sheetAnimationDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _showPlannedRouteLiveView() {
    if (_navigating || _route == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted ||
          _navigating ||
          _route == null ||
          !_plannerSheetController.isAttached) {
        return;
      }
      final media = MediaQuery.of(context);
      final maxExtent = _expandedPlannerSheetExtent(media);
      final previewExtent = plannedRouteLiveViewExtent(
        viewportHeight: media.size.height,
        bottomPadding: media.padding.bottom,
        collapsedSheetHeight: _collapsedSheetHeight,
        maxExtent: maxExtent,
      );
      await _plannerSheetController.animateTo(
        previewExtent,
        duration: _sheetAnimationDuration,
        curve: Curves.easeOutCubic,
      );
      if (!mounted) return;
      final overviewContext = _plannedRouteOverviewKey.currentContext;
      if (overviewContext != null && overviewContext.mounted) {
        await Scrollable.ensureVisible(
          overviewContext,
          alignment: 0.04,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    }());
  }

  Future<void> _openSettings() async {
    unawaited(_refreshVoices());
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _SettingsScreen(
          themeMode: widget.themeMode,
          mapStyle: _mapStyle,
          riderAvatar: _riderAvatar,
          riderColor: _riderColor,
          voiceGuidanceEnabled: _voiceGuidanceEnabled,
          voiceVolume: _voiceVolume,
          availableVoices: _availableVoices,
          selectedVoiceId: _selectedVoiceId,
          preferences: List.of(_preferences),
          rideFocus: _rideFocus,
          savedRouteCount: _savedRoutes.length,
          spotifyConnected: _spotify.state.connected,
          serviceConnectionMode: _serviceConnectionMode,
          speedometerEnabled: _speedometerEnabled,
          speedAlertThresholdMph: _speedAlertThresholdMph,
          onThemeModeChanged: _setThemeMode,
          onMapStyleChanged: _setMapStyle,
          onRiderAvatarChanged: _setRiderAvatar,
          onRiderColorChanged: _setRiderColor,
          onVoiceGuidanceChanged: _setVoiceGuidanceEnabled,
          onVoiceVolumeChanged: _setVoiceVolume,
          onVoiceChanged: _setVoice,
          onServiceConnectionModeChanged: _setServiceConnectionMode,
          onSpeedometerEnabledChanged: _setSpeedometerEnabled,
          onSpeedAlertThresholdChanged: _setSpeedAlertThreshold,
          onTestVoice: () => _speak(
            'Voice guidance is ready. Have a safe ride.',
            force: true,
          ),
          onPreferenceChanged: _updatePreference,
          onRideFocusChanged: _updateRideFocus,
          onReplan: _origin != null && _destination != null ? _planRoute : null,
          onClearSavedRoutes: _clearSavedRoutes,
          onConnectSpotify: () async {
            await _connectSpotify();
            return _spotify.state.connected;
          },
          onDisconnectSpotify: _spotify.disconnect,
          onOpenSpotify: _openSpotify,
          onShowMapCredits: _showMapCredits,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final motion = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            key: const ValueKey('settings-route-fade'),
            opacity: motion,
            child: SlideTransition(
              key: const ValueKey('settings-route-slide'),
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(motion),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _setThemeMode(ThemeMode mode) {
    widget.onThemeModeChanged(mode);
    unawaited(_storage.write(key: _themeModeKey, value: mode.name));
  }

  void _setMapStyle(MapStyle style) {
    setState(() {
      _mapStyle = style;
      _mapStyleUserSelected = true;
    });
    unawaited(_storage.write(key: _mapStyleKey, value: style.name));
  }

  void _setRiderAvatar(_RiderAvatar avatar) {
    setState(() => _riderAvatar = avatar);
    unawaited(_storage.write(key: _avatarKey, value: avatar.name));
  }

  void _setRiderColor(Color color) {
    setState(() => _riderColor = color);
    unawaited(
      _storage.write(
        key: _avatarColorKey,
        value: color.toARGB32().toString(),
      ),
    );
  }

  void _setServiceConnectionMode(ServiceConnectionMode mode) {
    setState(() => _serviceConnectionMode = mode);
    _placeSearch.connectionMode = mode;
    _routing.connectionMode = mode;
    unawaited(
      _storage.write(key: _serviceConnectionModeKey, value: mode.name),
    );
  }

  void _setSpeedometerEnabled(bool enabled) {
    setState(() {
      _speedometerEnabled = enabled;
      if (!enabled) _roadSpeedLimitMph = null;
    });
    unawaited(
      _storage.write(key: _speedometerEnabledKey, value: '$enabled'),
    );
  }

  void _setSpeedAlertThreshold(double milesPerHour) {
    final value = milesPerHour.clamp(0, 50).toDouble();
    setState(() => _speedAlertThresholdMph = value);
    unawaited(
      _storage.write(key: _speedAlertThresholdKey, value: '$value'),
    );
  }

  Future<void> _refreshVoices() async {
    try {
      final rawVoices = await _tts.getVoices;
      final voices = <_VoiceOption>[];
      if (rawVoices is List) {
        for (final raw in rawVoices) {
          if (raw is! Map) continue;
          final name = raw['name']?.toString() ?? '';
          final locale = raw['locale']?.toString() ?? '';
          if (name.isNotEmpty) {
            voices.add(_VoiceOption(name: name, locale: locale));
          }
        }
      }
      voices.sort((a, b) => a.label.compareTo(b.label));
      if (mounted) setState(() => _availableVoices = voices);
    } catch (_) {
      // Voice selection remains optional on platforms that do not list voices.
    }
  }

  Future<void> _applyVoiceSettings() async {
    await _tts.setVolume(_voiceVolume);
    final voice = _availableVoices.where(
      (candidate) => candidate.id == _selectedVoiceId,
    );
    if (voice.isNotEmpty) {
      await _tts.setVoice({
        'name': voice.first.name,
        'locale': voice.first.locale,
      });
    }
  }

  void _setVoiceGuidanceEnabled(bool enabled) {
    setState(() => _voiceGuidanceEnabled = enabled);
    unawaited(
      _storage.write(key: _voiceEnabledKey, value: enabled.toString()),
    );
  }

  void _setVoiceVolume(double volume) {
    final value = volume.clamp(0, 1).toDouble();
    setState(() => _voiceVolume = value);
    unawaited(_tts.setVolume(value));
    unawaited(_storage.write(key: _voiceVolumeKey, value: '$value'));
  }

  void _setVoice(String? voiceId) {
    setState(() => _selectedVoiceId = voiceId);
    unawaited(_storage.write(key: _voiceKey, value: voiceId));
    unawaited(_applyVoiceSettings());
  }

  Future<void> _speak(String message, {bool force = false}) async {
    if (!_voiceGuidanceEnabled && !force) return;
    await _tts.setVolume(_voiceVolume);
    await _tts.speak(message);
  }

  Future<void> _clearSavedRoutes() async {
    setState(_savedRoutes.clear);
    await _storage.delete(key: _savedRoutesKey);
  }

  Future<void> _showMapCredits() async {
    await showDialog<void>(
      context: context,
      builder: (context) => PointerInterceptor(
        child: AlertDialog(
          icon: const Icon(Icons.info_outline),
          title: const Text('Map credits'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Twistaway uses these open map projects. Tap a provider to learn more.',
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(Uri.parse('https://openfreemap.org/')),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('© OpenFreeMap'),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright')),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('© OpenStreetMap contributors'),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(Uri.parse('https://openmaptiles.org/')),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('© OpenMapTiles'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDrawHelpPreference() async {
    try {
      final value = await _storage.read(key: _hideDrawHelpKey);
      if (mounted) {
        setState(() => _hideDrawHelp = value == 'true');
      }
    } catch (_) {
      // Keep the tutorial available if local preference storage is unavailable.
    }
  }

  Future<void> _loadSavedRoutes() async {
    try {
      final encoded = await _storage.read(key: _savedRoutesKey);
      if (encoded == null || encoded.isEmpty || !mounted) {
        return;
      }
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final routes = decoded
          .whereType<Map<String, dynamic>>()
          .map(_SavedRoute.fromJson)
          .toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      setState(() {
        _savedRoutes
          ..clear()
          ..addAll(routes);
      });
    } catch (_) {
      // A malformed or unavailable local store should not block planning.
    }
  }

  Future<void> _loadPlaceHistory() async {
    try {
      final encoded = await _storage.read(key: _placeHistoryKey);
      if (!mounted) return;
      _placeHistory = PlaceHistory.decode(encoded);
    } catch (_) {
      // Search remains available when encrypted local storage is unavailable.
    }
  }

  Future<void> _rememberPlace(PlaceResult place) async {
    const generatedTypes = {
      'coordinates',
      'device location',
      'loop return',
      'loop shaping',
      'map tap',
    };
    if (generatedTypes.contains(place.type)) return;

    _placeHistory.record(place);
    try {
      await _storage.write(
          key: _placeHistoryKey, value: _placeHistory.encode());
    } catch (_) {
      // Keep the in-memory suggestion even if persistence is unavailable.
    }
  }

  Future<void> _persistSavedRoutes() async {
    try {
      await _storage.write(
        key: _savedRoutesKey,
        value: jsonEncode(
          _savedRoutes.map((route) => route.toJson()).toList(growable: false),
        ),
      );
    } catch (_) {
      _showNotice(
        'Could not update saved routes on this device.',
        tone: _NoticeTone.error,
      );
    }
  }

  Future<void> _saveCurrentRoute() async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) {
      return;
    }

    final controller = TextEditingController(
      text: _defaultRouteName(origin, destination),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => PointerInterceptor(
        child: AlertDialog(
          icon: const Icon(Icons.bookmark_add_outlined),
          title: const Text('Save route'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Route name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) {
      return;
    }

    final saved = _SavedRoute(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      savedAt: DateTime.now(),
      origin: origin,
      destination: destination,
      shapingPoints: List.of(_shapingPoints),
      loopTargetMiles: _loopTargetMiles,
      drawMode: _routeBuildMode == RouteBuildMode.draw,
    );
    setState(() {
      _savedRoutes.insert(0, saved);
      if (_savedRoutes.length > 30) {
        _savedRoutes.removeRange(30, _savedRoutes.length);
      }
    });
    await _persistSavedRoutes();
    _showNotice('Route saved.', tone: _NoticeTone.info);
  }

  Future<void> _openSavedRoutes() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved routes',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_savedRoutes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text('No saved routes yet.'),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _savedRoutes.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final saved = _savedRoutes[index];
                            return ListTile(
                              leading: const Icon(Icons.route_outlined),
                              title: Text(saved.name),
                              subtitle: Text(
                                '${saved.shapingPoints.length} route ${saved.shapingPoints.length == 1 ? 'point' : 'points'} · ${_formatSavedDate(saved.savedAt)}',
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                _restoreSavedRoute(saved);
                              },
                              trailing: IconButton(
                                tooltip: 'Delete saved route',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  setState(() => _savedRoutes.remove(saved));
                                  setModalState(() {});
                                  unawaited(_persistSavedRoutes());
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _restoreSavedRoute(_SavedRoute saved) {
    _markOriginManuallyChanged();
    setState(() {
      _programmaticTextEdit = true;
      _origin = saved.origin;
      _destination = saved.destination;
      _shapingPoints
        ..clear()
        ..addAll(saved.shapingPoints);
      _loopTargetMiles = saved.loopTargetMiles;
      _routeBuildMode =
          saved.drawMode ? RouteBuildMode.draw : RouteBuildMode.normal;
      _originController.text = _shortName(saved.origin.name);
      _destinationController.text = _shortName(saved.destination.name);
      _searchTarget =
          saved.drawMode ? SearchTarget.origin : SearchTarget.destination;
      _searchResults = const [];
      _route = null;
      _programmaticTextEdit = false;
    });
    unawaited(_planRouteIfReady());
  }

  String _defaultRouteName(PlaceResult origin, PlaceResult destination) {
    if (destination.type == 'loop return') {
      return '${_shortName(origin.name)} loop';
    }
    if (origin.type == 'map tap' && destination.type == 'map tap') {
      final now = DateTime.now();
      return 'Drawn ride ${now.month}/${now.day}';
    }
    return '${_shortName(origin.name)} to ${_shortName(destination.name)}';
  }

  void _showNotice(
    String message, {
    required _NoticeTone tone,
    Duration? duration,
  }) {
    if (!mounted) {
      return;
    }

    final id = ++_noticeSequence;
    setState(() {
      final duplicateIndex = _notices.indexWhere(
        (notice) => notice.message == message,
      );
      if (duplicateIndex >= 0) {
        final duplicate = _notices.removeAt(duplicateIndex);
        _noticeTimers.remove(duplicate.id)?.cancel();
      }
      _notices.add(_PlannerNotice(id: id, message: message, tone: tone));
      while (_notices.length > 2) {
        final removed = _notices.removeAt(0);
        _noticeTimers.remove(removed.id)?.cancel();
      }
    });

    final effectiveDuration = duration ??
        switch (tone) {
          _NoticeTone.info => const Duration(seconds: 3),
          _NoticeTone.warning => const Duration(seconds: 5),
          _NoticeTone.error => const Duration(seconds: 7),
        };
    _noticeTimers[id] = Timer(effectiveDuration, () => _dismissNotice(id));
  }

  void _dismissNotice(int id) {
    _noticeTimers.remove(id)?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _notices.removeWhere((notice) => notice.id == id));
  }

  void _clearNotices() {
    for (final timer in _noticeTimers.values) {
      timer.cancel();
    }
    _noticeTimers.clear();
    if (mounted) {
      setState(_notices.clear);
    }
  }

  Future<void> _showDrawHelpIfNeeded() async {
    if (_hideDrawHelp || !mounted) {
      return;
    }

    final neverShowAgain = await showDialog<bool>(
      context: context,
      builder: (context) => PointerInterceptor(
        child: AlertDialog(
          icon: const Icon(Icons.draw_outlined),
          title: const Text('Draw a route'),
          content: const Text(
            'Tap the map to set a start, then keep tapping to draw the route. The newest point is the destination and earlier points shape the ride. Use Loop to draft a round trip, then adjust it until the ride feels right.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Never show again'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );

    if (neverShowAgain == true) {
      setState(() => _hideDrawHelp = true);
      try {
        await _storage.write(key: _hideDrawHelpKey, value: 'true');
      } catch (_) {
        // The in-memory setting still prevents repeat prompts in this session.
      }
    }
  }

  void _onQueryChanged(SearchTarget target) {
    if (_programmaticTextEdit) {
      return;
    }

    if (target == SearchTarget.origin) {
      _markOriginManuallyChanged();
    }

    final query = target == SearchTarget.origin
        ? _originController.text
        : _destinationController.text;
    _searchSequence += 1;
    final recentResults = _recentSearchResults(query, target);
    setState(() {
      _searchTarget = target;
      _route = null;
      if (target == SearchTarget.origin) {
        _origin = null;
      } else {
        _destination = null;
      }
      _searchResults = query.trim().length < 2 ? const [] : recentResults;
    });

    _autocompleteTimer?.cancel();
    if (query.trim().length < 3) {
      return;
    }

    _autocompleteTimer = Timer(
      const Duration(milliseconds: 140),
      () => unawaited(_search(target, previewFirst: true)),
    );
  }

  Future<void> _search(
    SearchTarget target, {
    bool selectFirst = false,
    bool previewFirst = false,
  }) async {
    if (target == SearchTarget.destination &&
        _destination?.type == 'loop return' &&
        _destinationController.text.trim() == 'Loop back to start') {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _searchTarget = SearchTarget.destination;
        _searchResults = const [];
      });
      await _planRouteIfReady();
      return;
    }

    final query = target == SearchTarget.origin
        ? _originController.text
        : _destinationController.text;
    final sequence = ++_searchSequence;
    final recentResults = _recentSearchResults(query, target);
    final coordinate = _parseCoordinateQuery(query);
    if (coordinate != null) {
      final place = PlaceResult(
        name:
            'Coordinates ${coordinate.latitude.toStringAsFixed(5)}, ${coordinate.longitude.toStringAsFixed(5)}',
        latLng: coordinate,
        type: 'coordinates',
      );
      await _selectPlace(place, targetOverride: target);
      return;
    }

    if (selectFirst) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    setState(() {
      _searchTarget = target;
      _searching = true;
      if (recentResults.isNotEmpty) {
        _searchResults = recentResults;
      }
    });

    try {
      final results = await _placeSearch.search(
        query,
        context: _searchContext(target),
      );
      if (!mounted || sequence != _searchSequence) {
        return;
      }
      final combinedResults = _mergeSearchResults(recentResults, results);
      if (selectFirst && combinedResults.isNotEmpty) {
        await _selectPlace(combinedResults.first, targetOverride: target);
        return;
      }
      setState(() {
        _searchResults = combinedResults;
      });
      if (combinedResults.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _expandPlannerSheet();
          }
        });
      }
      if (combinedResults.isEmpty) {
        _showNotice(
          'No places found. Try a city, road, landmark, or full address.',
          tone: _NoticeTone.warning,
        );
      }
      if (previewFirst && combinedResults.isNotEmpty) {
        _mapController.move(
          combinedResults.first.latLng,
          math.max(_mapController.camera.zoom, 11),
        );
      }
    } catch (error) {
      if (mounted && sequence == _searchSequence && recentResults.isEmpty) {
        _showNotice(error.toString(), tone: _NoticeTone.error);
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
    if (target == SearchTarget.origin) {
      _markOriginManuallyChanged();
    }
    setState(() {
      _programmaticTextEdit = true;
      if (target == SearchTarget.origin) {
        _origin = result;
        _originController.text = _shortName(result.name);
        _searchTarget = _routeBuildMode == RouteBuildMode.draw
            ? SearchTarget.origin
            : SearchTarget.destination;
      } else {
        _destination = result;
        _destinationController.text = _shortName(result.name);
      }
      _shapingPoints.clear();
      _programmaticTextEdit = false;
      _searchResults = const [];
    });

    _mapController.move(result.latLng, 13);
    unawaited(_rememberPlace(result));
    await _planRouteIfReady();
  }

  Future<void> _dropPin(LatLng point) async {
    if (!acceptsMapDrop(
      navigating: _navigating,
      addingNavigationStop: _addingNavigationStop,
    )) {
      return;
    }
    if (_navigating) {
      await _addNavigationStop(point);
      return;
    }
    final place = PlaceResult(
      name:
          'Dropped pin ${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}',
      latLng: point,
      type: 'map tap',
    );

    setState(() {
      _programmaticTextEdit = true;
      if (_origin == null ||
          (_routeBuildMode != RouteBuildMode.draw &&
              _searchTarget == SearchTarget.origin)) {
        _markOriginManuallyChanged();
        _origin = place;
        _originController.text = 'Dropped start';
        _searchTarget = _routeBuildMode == RouteBuildMode.draw
            ? SearchTarget.origin
            : SearchTarget.destination;
        _shapingPoints.clear();
      } else if (_destination == null &&
          _routeBuildMode != RouteBuildMode.draw) {
        _destination = place;
        _destinationController.text = 'Dropped destination';
      } else {
        if (_routeBuildMode == RouteBuildMode.draw) {
          final previousDestination = _destination;
          if (previousDestination != null &&
              previousDestination.type != 'loop return') {
            _shapingPoints.add(
              PlaceResult(
                name: 'Drawn route point ${_shapingPoints.length + 1}',
                latLng: previousDestination.latLng,
                type: 'route shaping',
              ),
            );
          }
          _destination = place;
          _destinationController.text = 'Drawn destination';
        } else {
          _shapingPoints.add(
            PlaceResult(
              name: 'Scenic shaping point ${_shapingPoints.length + 1}',
              latLng: point,
              type: 'route shaping',
            ),
          );
        }
      }
      _programmaticTextEdit = false;
    });

    await _planRouteIfReady();
  }

  void _beginAddingNavigationStop(double minExtent) {
    if (!_navigating) return;
    setState(() {
      _addingNavigationStop = true;
      _followNavigation = false;
    });
    if (_navigationSheetController.isAttached) {
      unawaited(
        _navigationSheetController.animateTo(
          minExtent,
          duration: _sheetAnimationDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _cancelAddingNavigationStop() {
    if (!_addingNavigationStop) return;
    setState(() {
      _addingNavigationStop = false;
      _followNavigation = true;
    });
    _recenterNavigation();
  }

  Future<void> _addNavigationStop(LatLng point) async {
    final destination = _destination;
    final currentPosition = _currentPosition;
    if (!_navigating ||
        !_addingNavigationStop ||
        destination == null ||
        currentPosition == null) {
      return;
    }
    final origin = PlaceResult(
      name: 'Current location',
      latLng: LatLng(currentPosition.latitude, currentPosition.longitude),
      type: 'gps',
    );
    final stop = PlaceResult(
      name: 'Added stop',
      latLng: point,
      type: 'navigation stop',
    );
    final currentRoute = _route;
    final riderProgress = currentRoute == null
        ? null
        : _routeProgress(currentRoute, origin.latLng).distanceAlongRouteMeters;
    final remainingShapingPoints = currentRoute == null
        ? <PlaceResult>[]
        : _shapingPoints.where((shapingPoint) {
            final shapingProgress =
                _routeProgress(currentRoute, shapingPoint.latLng)
                    .distanceAlongRouteMeters;
            return shapingProgress > riderProgress! + 50;
          }).toList(growable: false);
    final updatedShapingPoints = [stop, ...remainingShapingPoints];
    setState(() {
      _routingBusy = true;
      _addingNavigationStop = false;
    });
    try {
      final route = await _routing.route(
        origin: origin.latLng,
        destination: destination.latLng,
        shapingPoints: updatedShapingPoints
            .map((shapingPoint) => shapingPoint.latLng)
            .toList(growable: false),
        preferences: _preferenceMap(),
      );
      if (!mounted || !_navigating) return;
      setState(() {
        _programmaticTextEdit = true;
        _origin = origin;
        _originController.text = origin.name;
        _shapingPoints
          ..clear()
          ..addAll(updatedShapingPoints);
        _route = route;
        _navStepIndex = 0;
        _distanceToNextStepMeters =
            route.steps.isEmpty ? null : route.steps.first.distanceMeters;
        _distanceToDestinationMeters = route.distanceMeters;
        _estimatedArrivalTime = DateTime.now().add(
          Duration(seconds: route.durationSeconds.round()),
        );
        _navigationAlert = 'Stop added — route updated';
        _followNavigation = true;
        _programmaticTextEdit = false;
      });
      _moveToPosition(currentPosition);
      _showNotice('Stop added and route updated.', tone: _NoticeTone.info);
    } catch (error) {
      if (!mounted) return;
      setState(() => _addingNavigationStop = true);
      _showNotice(
        'Could not add that stop: $error',
        tone: _NoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => _routingBusy = false);
    }
  }

  Future<bool> _setCurrentLocationAsStart() async {
    return _centerOnCurrentLocation(setAsOrigin: true, quiet: false);
  }

  Future<void> _toggleLocationFollow() async {
    if (_followNavigation) {
      setState(() => _followNavigation = false);
      if (!_navigating) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
      }
      return;
    }

    setState(() {
      _followNavigation = true;
      _headingUp = true;
    });
    final located = await _centerOnCurrentLocation(
      setAsOrigin: false,
      quiet: false,
    );
    if (!located) {
      if (mounted) {
        setState(() => _followNavigation = false);
      }
      return;
    }
    await _startLocationUpdates(restart: true);
  }

  Future<void> _startLocationUpdates({bool restart = false}) async {
    if (_positionSubscription != null && !restart) {
      return;
    }
    if (restart) {
      await _positionSubscription?.cancel();
    }
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPositionUpdate,
      onError: (Object error) {
        if (mounted) {
          _showNotice(
            'Location tracking failed: $error',
            tone: _NoticeTone.error,
          );
        }
      },
    );
  }

  void _onPositionUpdate(Position position) {
    if (_navigating) {
      _onNavigationPosition(position);
      return;
    }
    setState(() {
      _currentPosition = position;
      _displayedPosition = LatLng(position.latitude, position.longitude);
    });
    _displayedPositionNotifier.value = _displayedPosition;
    if (_followNavigation) {
      _moveToPosition(position);
    }
  }

  void _stopFollowingFromMapGesture() {
    if (!_followNavigation) {
      return;
    }
    setState(() => _followNavigation = false);
    if (!_navigating) {
      unawaited(_positionSubscription?.cancel());
      _positionSubscription = null;
    }
  }

  Future<bool> _centerOnCurrentLocation({
    required bool setAsOrigin,
    required bool quiet,
  }) async {
    if (setAsOrigin) {
      _currentLocationOriginSequence = _originEditSequence;
    }
    if (_locationBusy) {
      return false;
    }

    final originRequestAtStart = _currentLocationOriginSequence;
    setState(() => _locationBusy = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!quiet) {
          _showNotice(
            'Turn on location services, then try current location again.',
            tone: _NoticeTone.warning,
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
          _showNotice(
            'Location permission is needed to use current location.',
            tone: _NoticeTone.warning,
          );
        }
        return false;
      }

      final lastKnown = await _safeLastKnownPosition();
      if (lastKnown != null && _isFreshAccuratePosition(lastKnown)) {
        await _applyCurrentPosition(lastKnown);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await _applyCurrentPosition(position);
      return true;
    } catch (error) {
      if (!quiet) {
        _showNotice(
          'Current location failed: $error',
          tone: _NoticeTone.error,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _locationBusy = false);
      }
      final pendingOriginRequest = _currentLocationOriginSequence;
      if (pendingOriginRequest != null &&
          _appliedCurrentLocationOriginSequence == pendingOriginRequest) {
        _currentLocationOriginSequence = null;
      } else if (pendingOriginRequest == originRequestAtStart) {
        _currentLocationOriginSequence = null;
      } else if (pendingOriginRequest != null && mounted) {
        scheduleMicrotask(
          () => unawaited(
            _centerOnCurrentLocation(setAsOrigin: true, quiet: true),
          ),
        );
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

  bool _isFreshAccuratePosition(Position position) {
    final age = DateTime.now().difference(position.timestamp).abs();
    return age <= const Duration(minutes: 2) &&
        position.accuracy.isFinite &&
        position.accuracy <= 50;
  }

  PlaceResult _placeFromCurrentPosition(Position position) {
    return PlaceResult(
      name: 'Current location',
      latLng: LatLng(position.latitude, position.longitude),
      type: 'gps',
    );
  }

  Future<void> _applyCurrentPosition(Position position) async {
    _currentPosition = position;
    final place = _placeFromCurrentPosition(position);
    _displayedPosition = place.latLng;
    _displayedPositionNotifier.value = place.latLng;
    final originRequest = _currentLocationOriginSequence;
    final shouldSetAsOrigin =
        originRequest != null && originRequest == _originEditSequence;
    setState(() {
      if (shouldSetAsOrigin) {
        _programmaticTextEdit = true;
        _origin = place;
        _originController.text = place.name;
        _programmaticTextEdit = false;
        _searchTarget = SearchTarget.destination;
        _shapingPoints.clear();
      }
    });
    if (shouldSetAsOrigin) {
      _appliedCurrentLocationOriginSequence = originRequest;
    }
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
      _showNotice(
        'Turn on location services to start navigation.',
        tone: _NoticeTone.warning,
      );
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showNotice(
        'Location permission is needed to start navigation.',
        tone: _NoticeTone.warning,
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
      _roadSpeedLimitMph = null;
      _addingNavigationStop = false;
      _estimatedArrivalTime = DateTime.now().add(
        Duration(seconds: (_route?.durationSeconds ?? 0).round()),
      );
    });
    _plannerSheetRaised.value = false;
    await _speak(_currentInstruction);

    await _startLocationUpdates(restart: true);

    final lastKnown = await _safeLastKnownPosition();
    if (lastKnown != null) {
      _onNavigationPosition(lastKnown);
    }
  }

  Future<void> _stopNavigation() async {
    if (!_followNavigation) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
    }
    _stopNavigationMotion();
    setState(() {
      _navigating = false;
      _navigationAlert = null;
      _addingNavigationStop = false;
      _estimatedArrivalTime = null;
    });
    _plannerSheetRaised.value = false;
  }

  void _showNavigationOverview() {
    final route = _route;
    if (route == null) return;
    setState(() => _followNavigation = false);
    _fitRoute(route.points);
  }

  void _recenterNavigation() {
    final position = _currentPosition;
    if (position == null) return;
    setState(() => _followNavigation = true);
    _moveToPosition(position, point: _displayedPosition);
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
    final snapThreshold = math.max(
      30.0,
      math.min(70.0, position.accuracy.isFinite ? position.accuracy * 1.5 : 30),
    );
    final displayedPosition =
        offRoute <= snapThreshold ? progress.closestPoint : current;
    final offRouteAlertThreshold = math.max(70.0, snapThreshold);
    final arrived = destinationDistance < 40 ||
        _distance.as(LengthUnit.Meter, current, route.points.last) < 40;

    String? alert;
    if (arrived) {
      alert = 'Arrived at destination';
    } else if (offRoute > offRouteAlertThreshold) {
      alert = 'Off route by ${_formatDistance(offRoute)}';
    } else if (nextDistance < 120 && stepIndex < route.steps.length) {
      alert = route.steps[stepIndex].instruction;
    }

    final previousDisplayedPosition = _displayedPosition ?? displayedPosition;
    setState(() {
      _currentPosition = position;
      _navStepIndex = stepIndex;
      _distanceToNextStepMeters = nextDistance;
      _distanceToDestinationMeters = destinationDistance;
      _estimatedArrivalTime = DateTime.now().add(
        Duration(
          seconds: route.distanceMeters <= 0
              ? 0
              : (route.durationSeconds *
                      destinationDistance /
                      route.distanceMeters)
                  .round(),
        ),
      );
      _navigationAlert = alert;
      if (arrived) {
        _navigating = false;
      }
    });

    if (_navigating) {
      _beginNavigationMotion(
        position,
        from: previousDisplayedPosition,
        target: displayedPosition,
      );
      if (_speedometerEnabled) {
        unawaited(_updateRoadSpeedLimit(current));
      }
    } else {
      _stopNavigationMotion();
    }

    if (arrived) {
      unawaited(_speak('You have arrived.'));
      if (!_followNavigation) {
        unawaited(_positionSubscription?.cancel());
        _positionSubscription = null;
      }
      return;
    }

    if (offRoute > offRouteAlertThreshold && !_offRouteAlerted) {
      _offRouteAlerted = true;
      unawaited(_speak('You are off route. Replan when safe.'));
    } else if (offRoute <= 45) {
      _offRouteAlerted = false;
    }

    if (stepIndex != _lastSpokenStepIndex &&
        nextDistance < 180 &&
        stepIndex < route.steps.length) {
      _lastSpokenStepIndex = stepIndex;
      unawaited(
        _speak(
          '${route.steps[stepIndex].instruction}. ${_formatDistance(nextDistance)}.',
        ),
      );
    }
  }

  void _beginNavigationMotion(
    Position position, {
    required LatLng from,
    required LatLng target,
  }) {
    _navigationMotion.reset(
      from: from,
      target: target,
      at: DateTime.now(),
      speedMetersPerSecond: position.speed,
      headingDegrees: position.heading,
    );
    _navigationMotionTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _tickNavigationMotion(),
    );
    _tickNavigationMotion();
  }

  void _tickNavigationMotion() {
    if (!mounted || !_navigating) {
      _stopNavigationMotion();
      return;
    }
    var position = _navigationMotion.positionAt(DateTime.now());
    if (position == null) return;
    final route = _route;
    if (route != null && route.points.length >= 2) {
      final progress = _routeProgress(route, position);
      if (progress.distanceFromRouteMeters <= 50) {
        position = progress.closestPoint;
      }
    }
    _displayedPosition = position;
    _displayedPositionNotifier.value = position;
    final currentPosition = _currentPosition;
    if (_followNavigation && currentPosition != null) {
      _moveToPosition(currentPosition, point: position, animate: false);
    }
  }

  void _stopNavigationMotion() {
    _navigationMotionTimer?.cancel();
    _navigationMotionTimer = null;
    _navigationMotion.clear();
  }

  Future<void> _updateRoadSpeedLimit(LatLng position) async {
    final now = DateTime.now();
    final lastPosition = _lastRoadSpeedLookupPosition;
    final lastLookup = _lastRoadSpeedLookupAt;
    if (lastPosition != null &&
        lastLookup != null &&
        (now.difference(lastLookup) < const Duration(seconds: 10) ||
            _distance.as(LengthUnit.Meter, lastPosition, position) < 100)) {
      return;
    }
    _lastRoadSpeedLookupAt = now;
    _lastRoadSpeedLookupPosition = position;
    final sequence = ++_roadSpeedLookupSequence;
    try {
      final speedLimit = await _roadSpeedLimit.speedLimitMph(position);
      if (!mounted || sequence != _roadSpeedLookupSequence || !_navigating) {
        return;
      }
      setState(() => _roadSpeedLimitMph = speedLimit);
    } catch (_) {
      // Missing road data or a provider outage must not interrupt navigation.
    }
  }

  void _moveToPosition(
    Position position, {
    LatLng? point,
    bool animate = true,
  }) {
    point ??= LatLng(position.latitude, position.longitude);
    final validHeading = position.heading.isFinite && position.heading >= 0;
    final cameraTarget = _navigating && validHeading
        ? _destinationPoint(point, 210, position.heading)
        : point;
    _mapController.move(
      cameraTarget,
      math.max(_mapController.camera.zoom, _navigating ? 17 : 14),
      animate: animate,
      bearing: _followNavigation && _headingUp && validHeading
          ? position.heading
          : null,
    );
  }

  Future<void> _planRouteIfReady({bool fitCamera = true}) async {
    if (_origin != null && _destination != null) {
      await _planRoute(fitCamera: fitCamera);
    }
  }

  Future<void> _planRoute({bool fitCamera = true}) async {
    final origin = _origin;
    final destination = _destination;
    if (origin == null && destination != null) {
      _showNotice(
        'Requesting location permission for your start point...',
        tone: _NoticeTone.info,
      );
      final located = await _setCurrentLocationAsStart();
      if (!located) {
        return;
      }
      await _planRouteIfReady(fitCamera: fitCamera);
      return;
    }
    if (origin == null || destination == null) {
      _showNotice(
        'Set a start and destination first.',
        tone: _NoticeTone.warning,
      );
      return;
    }

    setState(() {
      _routingBusy = true;
    });

    try {
      final route = await _routing.route(
        origin: origin.latLng,
        destination: destination.latLng,
        shapingPoints:
            _shapingPoints.map((point) => point.latLng).toList(growable: false),
        preferences: _preferenceMap(),
      );
      setState(() {
        _route = route;
        _navStepIndex = 0;
        _distanceToNextStepMeters =
            route.steps.isEmpty ? null : route.steps.first.distanceMeters;
        _distanceToDestinationMeters = route.distanceMeters;
        _navigationAlert = null;
      });
      _showPlannedRouteLiveView();
      if (fitCamera) {
        _fitRoute(route.points);
      }
    } catch (error) {
      _showNotice(error.toString(), tone: _NoticeTone.error);
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
        final media = MediaQuery.of(context);
        final bottomPadding = _route != null && !_navigating
            ? math.min(520.0, media.size.height * 0.68) + 32
            : 180.0 + media.padding.bottom;
        _mapController.fitBounds(
          points,
          padding: EdgeInsets.fromLTRB(
            48,
            88,
            48,
            bottomPadding,
          ),
        );
      }),
    );
  }

  void _swapRouteEnds() {
    _markOriginManuallyChanged();
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
      _destinationController.text =
          _destination == null ? '' : _shortName(_destination!.name);
      _programmaticTextEdit = false;
    });
    unawaited(_planRouteIfReady());
  }

  void _clearRoute() {
    unawaited(_stopNavigation());
    _resetRouteToCurrentLocation(resetBuildMode: true);
    _clearNotices();
  }

  void _undoRoutePoint() {
    if (_destination == null) {
      return;
    }
    setState(() {
      _programmaticTextEdit = true;
      if (_destination?.type == 'loop return' && _shapingPoints.isNotEmpty) {
        _shapingPoints.removeLast();
      } else if (_shapingPoints.isNotEmpty) {
        _destination = _destinationFromPoint(_shapingPoints.removeLast());
        _destinationController.text = 'Drawn destination';
      } else {
        _destination = null;
        _destinationController.clear();
      }
      _route = null;
      _programmaticTextEdit = false;
    });
    unawaited(_planRouteIfReady());
  }

  void _clearRoutePoints() {
    _resetRouteToCurrentLocation(resetBuildMode: false);
  }

  void _markOriginManuallyChanged() {
    _originEditSequence += 1;
    _currentLocationOriginSequence = null;
  }

  void _resetRouteToCurrentLocation({required bool resetBuildMode}) {
    _markOriginManuallyChanged();
    _autocompleteTimer?.cancel();
    _searchSequence += 1;
    final currentPosition = _currentPosition;
    final currentLocation = currentPosition == null
        ? null
        : _placeFromCurrentPosition(currentPosition);
    setState(() {
      _programmaticTextEdit = true;
      _origin = currentLocation;
      _destination = null;
      _shapingPoints.clear();
      if (resetBuildMode) {
        _routeBuildMode = RouteBuildMode.normal;
      }
      _searchTarget = _routeBuildMode == RouteBuildMode.draw
          ? SearchTarget.origin
          : SearchTarget.destination;
      _searchResults = const [];
      _searching = false;
      if (currentLocation == null) {
        _originController.text = 'Current location';
      } else {
        _originController.text = currentLocation.name;
      }
      _destinationController.clear();
      _route = null;
      _programmaticTextEdit = false;
    });

    if (currentPosition == null) {
      unawaited(_centerOnCurrentLocation(setAsOrigin: true, quiet: true));
    }
  }

  void _removeDestination() {
    if (_destination == null) {
      return;
    }
    setState(() {
      _programmaticTextEdit = true;
      if (_routeBuildMode == RouteBuildMode.draw &&
          _destination?.type != 'loop return' &&
          _shapingPoints.isNotEmpty) {
        _destination = _destinationFromPoint(_shapingPoints.removeLast());
        _destinationController.text = 'Drawn destination';
      } else {
        _destination = null;
        _destinationController.clear();
      }
      _route = null;
      _programmaticTextEdit = false;
    });
    unawaited(_planRouteIfReady());
  }

  PlaceResult _destinationFromPoint(PlaceResult point) {
    return PlaceResult(
      name:
          'Dropped pin ${point.latLng.latitude.toStringAsFixed(4)}, ${point.latLng.longitude.toStringAsFixed(4)}',
      latLng: point.latLng,
      type: 'map tap',
    );
  }

  void _removeShapingPoint(int index) {
    if (index < 0 || index >= _shapingPoints.length) {
      return;
    }
    setState(() {
      _shapingPoints.removeAt(index);
    });
    unawaited(_planRouteIfReady());
  }

  void _toggleDrawMode() {
    final enabling = _routeBuildMode != RouteBuildMode.draw;
    setState(() {
      _routeBuildMode = enabling ? RouteBuildMode.draw : RouteBuildMode.normal;
      if (enabling) {
        _searchTarget = SearchTarget.origin;
        _searchResults = const [];
      }
    });
    if (enabling) {
      unawaited(_showDrawHelpIfNeeded());
    }
  }

  void _buildLoopRide({bool fitCamera = true, bool announce = true}) {
    final origin = _origin;
    if (origin == null) {
      _showNotice(
        'Set a start point first.',
        tone: _NoticeTone.warning,
      );
      return;
    }

    final radiusMeters = _loopRadiusMeters();
    final loopPoints = _loopPoints(origin.latLng, radiusMeters);
    setState(() {
      _programmaticTextEdit = true;
      _destination = PlaceResult(
        name: '${origin.name} loop return',
        latLng: origin.latLng,
        type: 'loop return',
      );
      _destinationController.text = 'Loop back to start';
      _shapingPoints
        ..clear()
        ..addAll([
          for (var index = 0; index < loopPoints.length; index += 1)
            PlaceResult(
              name: 'Loop point ${index + 1}',
              latLng: loopPoints[index],
              type: 'loop shaping',
            ),
        ]);
      _routeBuildMode = RouteBuildMode.draw;
      _searchTarget = SearchTarget.origin;
      _searchResults = const [];
      _programmaticTextEdit = false;
    });
    if (announce) {
      unawaited(_showDrawHelpIfNeeded());
    }
    unawaited(_planRouteIfReady(fitCamera: fitCamera));
  }

  void _updateLoopTarget(double miles) {
    setState(() => _loopTargetMiles = miles);
    if (_destination?.type == 'loop return' && _origin != null) {
      _buildLoopRide(fitCamera: false, announce: false);
    }
  }

  double _loopRadiusMeters() {
    final circumferenceMeters = _loopTargetMiles * 1609.344;
    return (circumferenceMeters / (2 * math.pi)).clamp(2400.0, 22000.0);
  }

  List<LatLng> _loopPoints(LatLng center, double radiusMeters) {
    final eastWestLandBridge = center.longitude < -72.55 &&
        center.longitude > -73.98 &&
        center.latitude > 40.52 &&
        center.latitude < 41.05;
    if (eastWestLandBridge) {
      final eastWestMeters = radiusMeters * 1.25;
      final northSouthMeters = radiusMeters * 0.54;
      const offsets = [
        (-0.92, -0.22),
        (-0.34, 0.86),
        (0.46, 0.78),
        (0.98, 0.08),
        (0.38, -0.66),
        (-0.46, -0.62),
      ];
      return offsets
          .map(
            (offset) => _offsetPoint(
              center,
              eastMeters: offset.$1 * eastWestMeters,
              northMeters: offset.$2 * northSouthMeters,
            ),
          )
          .toList(growable: false);
    }

    const bearings = [315.0, 25.0, 92.0, 158.0, 224.0, 286.0];
    return bearings
        .map((bearing) =>
            _destinationPoint(center, radiusMeters * 0.88, bearing))
        .toList(growable: false);
  }

  LatLng _offsetPoint(
    LatLng center, {
    required double eastMeters,
    required double northMeters,
  }) {
    final northSouth = _destinationPoint(
      center,
      northMeters.abs(),
      northMeters >= 0 ? 0 : 180,
    );
    return _destinationPoint(
      northSouth,
      eastMeters.abs(),
      eastMeters >= 0 ? 90 : 270,
    );
  }

  LatLng _destinationPoint(
      LatLng start, double distanceMeters, double bearingDegrees) {
    const earthRadiusMeters = 6371000.0;
    final angularDistance = distanceMeters / earthRadiusMeters;
    final bearing = degreesToRadians(bearingDegrees);
    final lat1 = degreesToRadians(start.latitude);
    final lon1 = degreesToRadians(start.longitude);
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(radiansToDegrees(lat2), radiansToDegrees(lon2));
  }

  Future<void> _speakNextDirection() async {
    final route = _route;
    if (route == null || route.steps.isEmpty) {
      await _speak('Set a start and destination, then plan a ride.');
      return;
    }
    final step = route.steps[math.min(_navStepIndex, route.steps.length - 1)];
    final distance = _distanceToNextStepMeters ?? step.distanceMeters;
    await _speak('${step.instruction}. ${_formatDistance(distance)}.');
  }

  String get _currentInstruction {
    final route = _route;
    if (route == null || route.steps.isEmpty) {
      return 'Navigation started.';
    }
    return route
        .steps[math.min(_navStepIndex, route.steps.length - 1)].instruction;
  }

  String get _rideFocus {
    final values = _preferenceMap();
    if ((values['pureBackroads'] ?? 0) >= 0.5 ||
        (values['avoidMainRoads'] ?? 0) >= 0.5) {
      return 'backroads';
    }
    if ((values['autoScenicDetour'] ?? 0) >= 0.5 ||
        (values['scenic'] ?? 0) >= 0.85) {
      return 'scenic';
    }
    return 'balanced';
  }

  List<RoutePreference> _updateRideFocus(String focus) {
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

      switch (focus) {
        case 'scenic':
          setPreference('scenic', 0.95);
          setPreference('twisty', 0.7);
          setPreference('avoidHighways', 1);
          setPreference('avoidMainRoads', 0);
          setPreference('pureBackroads', 0);
          setPreference('autoScenicDetour', 1);
          setPreference('targetHighways', 0);
          setPreference('targetStraightRoads', 0);
          break;
        case 'backroads':
          setPreference('scenic', 0.65);
          setPreference('twisty', 0.8);
          setPreference('avoidHighways', 1);
          setPreference('avoidMainRoads', 1);
          setPreference('pureBackroads', 1);
          setPreference('autoScenicDetour', 0);
          setPreference('targetHighways', 0);
          setPreference('targetStraightRoads', 0);
          break;
        default:
          setPreference('scenic', 0.6);
          setPreference('twisty', 0.6);
          setPreference('avoidMainRoads', 0);
          setPreference('pureBackroads', 0);
          setPreference('autoScenicDetour', 0);
          setPreference('targetHighways', 0);
          setPreference('targetStraightRoads', 0);
          break;
      }
    });
    return List.of(_preferences);
  }

  List<RoutePreference> _updatePreference(String key, double value) {
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
      if (key == 'autoScenicDetour' && value >= 0.5) {
        setPreference('pureBackroads', 0);
        setPreference('targetHighways', 0);
        setPreference('targetStraightRoads', 0);
      }
      if (key == 'avoidHighways' && value >= 0.5) {
        setPreference('targetHighways', 0);
      }
      if (key == 'avoidMainRoads' && value >= 0.5) {
        setPreference('targetHighways', 0);
        setPreference('targetStraightRoads', 0);
        setPreference('autoScenicDetour', 0);
      }
      if (key == 'pureBackroads' && value >= 0.5) {
        setPreference('avoidHighways', 1);
        setPreference('avoidMainRoads', 1);
        setPreference('autoScenicDetour', 0);
        setPreference('targetHighways', 0);
        setPreference('targetStraightRoads', 0);
      }
      if (key == 'targetHighways' && value >= 0.5) {
        setPreference('avoidHighways', 0);
        setPreference('avoidMainRoads', 0);
        setPreference('pureBackroads', 0);
        setPreference('autoScenicDetour', 0);
        setPreference('targetStraightRoads', 0);
      }
      if (key == 'targetStraightRoads' && value >= 0.5) {
        setPreference('avoidMainRoads', 0);
        setPreference('pureBackroads', 0);
        setPreference('autoScenicDetour', 0);
        setPreference('targetHighways', 0);
      }
    });
    return List.of(_preferences);
  }

  Map<String, double> _preferenceMap() => {
        for (final preference in _preferences) preference.key: preference.value,
      };

  LatLng? _parseCoordinateQuery(String query) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(query);
    if (match == null) {
      return null;
    }
    final first = double.tryParse(match.group(1)!);
    final second = double.tryParse(match.group(2)!);
    if (first == null || second == null) {
      return null;
    }

    final latLng =
        first.abs() <= 90 && second.abs() <= 180 ? LatLng(first, second) : null;
    final lngLat =
        second.abs() <= 90 && first.abs() <= 180 ? LatLng(second, first) : null;
    return latLng ?? lngLat;
  }

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

  List<PlaceResult> _recentSearchResults(String query, SearchTarget target) {
    return _placeHistory.suggestions(
      query,
      center: _searchContext(target).center,
    );
  }

  List<PlaceResult> _mergeSearchResults(
    List<PlaceResult> recent,
    List<PlaceResult> nearby,
  ) {
    final merged = <PlaceResult>[];
    final coordinates = <String>{};
    for (final result in [...recent, ...nearby]) {
      final key = '${result.latLng.latitude.toStringAsFixed(4)}|'
          '${result.latLng.longitude.toStringAsFixed(4)}';
      if (coordinates.add(key)) merged.add(result);
      if (merged.length == 6) break;
    }
    return List.unmodifiable(merged);
  }

  String _shortName(String value) {
    final parts = value.split(',');
    return parts.take(math.min(2, parts.length)).join(',').trim();
  }

  _RouteProgress _routeProgress(PlannedRoute route, LatLng current) {
    var bestDistance = double.infinity;
    var distanceBeforeBest = 0.0;
    var distanceAlong = 0.0;
    var closestPoint = route.points.first;

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
        closestPoint = projection.point;
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
      closestPoint: closestPoint,
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
    required this.closestPoint,
  });

  final double distanceAlongRouteMeters;
  final double distanceFromRouteMeters;
  final LatLng closestPoint;
}

class _SegmentProjection {
  const _SegmentProjection({required this.point, required this.t});

  final LatLng point;
  final double t;
}

class _PlannerNotice {
  const _PlannerNotice({
    required this.id,
    required this.message,
    required this.tone,
  });

  final int id;
  final String message;
  final _NoticeTone tone;
}

class _SavedRoute {
  const _SavedRoute({
    required this.id,
    required this.name,
    required this.savedAt,
    required this.origin,
    required this.destination,
    required this.shapingPoints,
    required this.loopTargetMiles,
    required this.drawMode,
  });

  final String id;
  final String name;
  final DateTime savedAt;
  final PlaceResult origin;
  final PlaceResult destination;
  final List<PlaceResult> shapingPoints;
  final double loopTargetMiles;
  final bool drawMode;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'origin': _placeToJson(origin),
        'destination': _placeToJson(destination),
        'shapingPoints':
            shapingPoints.map(_placeToJson).toList(growable: false),
        'loopTargetMiles': loopTargetMiles,
        'drawMode': drawMode,
      };

  factory _SavedRoute.fromJson(Map<String, dynamic> json) {
    return _SavedRoute(
      id: json['id'] as String,
      name: json['name'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      origin: _placeFromJson(json['origin'] as Map<String, dynamic>),
      destination: _placeFromJson(json['destination'] as Map<String, dynamic>),
      shapingPoints: (json['shapingPoints'] as List<dynamic>)
          .map((value) => _placeFromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      loopTargetMiles: (json['loopTargetMiles'] as num).toDouble(),
      drawMode: json['drawMode'] as bool? ?? false,
    );
  }
}

Map<String, Object?> _placeToJson(PlaceResult place) => {
      'name': place.name,
      'latitude': place.latLng.latitude,
      'longitude': place.latLng.longitude,
      'type': place.type,
    };

PlaceResult _placeFromJson(Map<String, dynamic> json) => PlaceResult(
      name: json['name'] as String,
      latLng: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      type: json['type'] as String?,
    );

ml.LatLng _toMapLibre(LatLng point) {
  return ml.LatLng(point.latitude, point.longitude);
}

LatLng _fromMapLibre(ml.LatLng point) {
  return LatLng(point.latitude, point.longitude);
}

String _hex(Color color) {
  final value = color.toARGB32();
  final red = (value >> 16) & 0xff;
  final green = (value >> 8) & 0xff;
  final blue = value & 0xff;
  return '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

List<ml.LatLng> _circlePoints(LatLng center, double radiusMeters) {
  return [
    for (var index = 0; index <= 72; index += 1)
      _toMapLibre(
        _destinationFrom(center, radiusMeters, index * 5 * math.pi / 180),
      ),
  ];
}

LatLng _destinationFrom(
  LatLng center,
  double distanceMeters,
  double bearingRadians,
) {
  const earthRadiusMeters = 6371000.0;
  final angularDistance = distanceMeters / earthRadiusMeters;
  final latitude1 = center.latitude * math.pi / 180;
  final longitude1 = center.longitude * math.pi / 180;
  final latitude2 = math.asin(
    math.sin(latitude1) * math.cos(angularDistance) +
        math.cos(latitude1) *
            math.sin(angularDistance) *
            math.cos(bearingRadians),
  );
  final longitude2 = longitude1 +
      math.atan2(
        math.sin(bearingRadians) *
            math.sin(angularDistance) *
            math.cos(latitude1),
        math.cos(angularDistance) - math.sin(latitude1) * math.sin(latitude2),
      );
  return LatLng(latitude2 * 180 / math.pi, longitude2 * 180 / math.pi);
}

class _PlannerCamera {
  const _PlannerCamera({
    required this.center,
    required this.zoom,
    this.bearing = 0,
  });

  final LatLng center;
  final double zoom;
  final double bearing;

  _PlannerVisibleBounds get visibleBounds {
    final span = (180 / math.pow(2, zoom - 2)).clamp(0.01, 120.0).toDouble();
    final latitudeSpan = span;
    final longitudeSpan =
        (span / math.cos(degreesToRadians(center.latitude)).abs())
            .clamp(0.01, 180.0)
            .toDouble();
    return _PlannerVisibleBounds(
      north: (center.latitude + latitudeSpan / 2).clamp(-90.0, 90.0),
      south: (center.latitude - latitudeSpan / 2).clamp(-90.0, 90.0),
      east: (center.longitude + longitudeSpan / 2).clamp(-180.0, 180.0),
      west: (center.longitude - longitudeSpan / 2).clamp(-180.0, 180.0),
    );
  }
}

class _PlannerVisibleBounds {
  const _PlannerVisibleBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;
}

class _PlannerMapController {
  _PlannerMapController({required LatLng center, required double zoom})
      : camera = _PlannerCamera(center: center, zoom: zoom);

  _PlannerCamera camera;
  ml.MapLibreMapController? _mapController;

  void attach(ml.MapLibreMapController controller) {
    _mapController = controller;
    _applyCamera();
  }

  void detach(ml.MapLibreMapController controller) {
    if (_mapController == controller) {
      _mapController = null;
    }
  }

  void syncFromMap(ml.CameraPosition? position) {
    if (position == null) {
      return;
    }
    camera = _PlannerCamera(
      center: _fromMapLibre(position.target),
      zoom: position.zoom,
      bearing: position.bearing,
    );
  }

  void move(
    LatLng center,
    double zoom, {
    bool animate = true,
    double? bearing,
  }) {
    camera = _PlannerCamera(
      center: center,
      zoom: zoom.clamp(3, 18).toDouble(),
      bearing: bearing ?? camera.bearing,
    );
    _applyCamera(animate: animate);
  }

  void zoomBy(double delta) {
    move(camera.center, camera.zoom + delta);
  }

  void rotate(double bearing, {bool animate = true}) {
    camera = _PlannerCamera(
      center: camera.center,
      zoom: camera.zoom,
      bearing: bearing,
    );
    _applyCamera(animate: animate);
  }

  void fitBounds(List<LatLng> points, {required EdgeInsets padding}) {
    if (points.isEmpty) {
      return;
    }
    final bounds = _boundsFor(points);
    camera = _PlannerCamera(center: _centerFor(bounds), zoom: camera.zoom);
    unawaited(
      _mapController?.animateCamera(
        ml.CameraUpdate.newLatLngBounds(
          bounds,
          left: padding.left,
          top: padding.top,
          right: padding.right,
          bottom: padding.bottom,
        ),
        duration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _applyCamera({bool animate = true}) {
    final controller = _mapController;
    if (controller == null) {
      return;
    }
    final update = ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: _toMapLibre(camera.center),
        zoom: camera.zoom,
        bearing: camera.bearing,
      ),
    );
    if (animate) {
      unawaited(
        controller.animateCamera(
          update,
          duration: const Duration(milliseconds: 220),
        ),
      );
    } else {
      unawaited(controller.moveCamera(update));
    }
  }

  static ml.LatLngBounds _boundsFor(List<LatLng> points) {
    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;
    for (final point in points.skip(1)) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    return ml.LatLngBounds(
      southwest: ml.LatLng(south, west),
      northeast: ml.LatLng(north, east),
    );
  }

  static LatLng _centerFor(ml.LatLngBounds bounds) {
    return LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }
}

class _PlannerMap extends StatefulWidget {
  const _PlannerMap({
    super.key,
    required this.controller,
    required this.origin,
    required this.destination,
    required this.shapingPoints,
    required this.route,
    required this.mapStyle,
    required this.currentPosition,
    required this.displayedPosition,
    required this.loopCenter,
    required this.loopRadiusMeters,
    required this.navigating,
    required this.following,
    required this.headingUp,
    required this.riderAvatar,
    required this.riderColor,
    required this.onTap,
    required this.onMapMoved,
    required this.onRemoveShapingPoint,
    required this.onRemoveDestination,
  });

  final _PlannerMapController controller;
  final PlaceResult? origin;
  final PlaceResult? destination;
  final List<PlaceResult> shapingPoints;
  final PlannedRoute? route;
  final MapStyle mapStyle;
  final Position? currentPosition;
  final LatLng? displayedPosition;
  final LatLng? loopCenter;
  final double? loopRadiusMeters;
  final bool navigating;
  final bool following;
  final bool headingUp;
  final _RiderAvatar riderAvatar;
  final Color riderColor;
  final ValueChanged<LatLng> onTap;
  final VoidCallback onMapMoved;
  final ValueChanged<int> onRemoveShapingPoint;
  final VoidCallback onRemoveDestination;

  @override
  State<_PlannerMap> createState() => _PlannerMapState();
}

class _PlannerMapState extends State<_PlannerMap> {
  ml.MapLibreMapController? _controller;
  late MapStyle _activeMapStyle;
  MapStyle? _loadedStyle;
  Object? _lastAnnotationKey;
  Uint8List? _styleTransitionSnapshot;
  int _styleTransitionGeneration = 0;
  bool _annotationRebuildRunning = false;
  bool _annotationRebuildQueued = false;
  bool _ignoreNextMapClick = false;
  String? _loadedRiderMarkerImage;
  int _riderMarkerImageRevision = 0;
  ml.Symbol? _riderSymbol;
  Offset? _pointerDownAt;

  @override
  void initState() {
    super.initState();
    _activeMapStyle = widget.mapStyle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshAnnotationsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _PlannerMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mapStyle != widget.mapStyle) {
      unawaited(_transitionToStyle(widget.mapStyle));
    } else if (_annotationKeyFor(oldWidget) != _annotationKeyFor(widget)) {
      _refreshAnnotationsIfNeeded();
    } else {
      unawaited(_updateRiderMarker());
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.onSymbolTapped.remove(_handleSymbolTap);
      controller.onCircleTapped.remove(_handleCircleTap);
      widget.controller.detach(controller);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerDown: (event) => _pointerDownAt = event.position,
          onPointerMove: (event) {
            final start = _pointerDownAt;
            if (start != null && (event.position - start).distance > 8) {
              _pointerDownAt = null;
              widget.onMapMoved();
            }
          },
          onPointerUp: (_) => _pointerDownAt = null,
          onPointerCancel: (_) => _pointerDownAt = null,
          child: ml.MapLibreMap(
            initialCameraPosition: ml.CameraPosition(
              target: _toMapLibre(widget.controller.camera.center),
              zoom: widget.controller.camera.zoom,
              bearing: _initialBearing,
              tilt: _initialTilt,
            ),
            minMaxZoomPreference: const ml.MinMaxZoomPreference(3, 18),
            styleString: _styleAsset,
            trackCameraPosition: true,
            compassEnabled: false,
            attributionButtonPosition: ml.AttributionButtonPosition.bottomRight,
            attributionButtonMargins:
                kIsWeb ? null : const math.Point<double>(8, 8),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _handleMapClick,
            onCameraIdle: () => widget.controller.syncFromMap(
              _controller?.cameraPosition,
            ),
          ),
        ),
        if (_styleTransitionSnapshot case final snapshot?)
          IgnorePointer(
            child: Image.memory(
              snapshot,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
          ),
      ],
    );
  }

  Future<void> _transitionToStyle(MapStyle style) async {
    final generation = ++_styleTransitionGeneration;
    Uint8List? snapshot;
    try {
      snapshot = await _controller?.takeSnapshot();
    } catch (_) {
      // A failed transition snapshot should not prevent changing map styles.
    }
    if (!mounted || generation != _styleTransitionGeneration) {
      return;
    }
    setState(() {
      _styleTransitionSnapshot = snapshot;
      _activeMapStyle = style;
      _loadedStyle = null;
      _lastAnnotationKey = null;
      _loadedRiderMarkerImage = null;
      _activeRiderMarkerImageName = null;
    });
  }

  void _finishStyleTransition() {
    if (_styleTransitionSnapshot == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _styleTransitionSnapshot != null) {
        setState(() => _styleTransitionSnapshot = null);
      }
    });
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _controller = controller;
    widget.controller.attach(controller);
    controller.onSymbolTapped.add(_handleSymbolTap);
    controller.onCircleTapped.add(_handleCircleTap);
  }

  void _onStyleLoaded() {
    _loadedStyle = _effectiveMapStyle;
    _lastAnnotationKey = null;
    _loadedRiderMarkerImage = null;
    _activeRiderMarkerImageName = null;
    _finishStyleTransition();

    final controller = _controller;
    final position = controller?.cameraPosition;
    if (controller != null && position != null) {
      final targetTilt = _effectiveMapStyle == MapStyle.threeD ? 55.0 : 0.0;
      if ((position.tilt - targetTilt).abs() > 0.1) {
        unawaited(
          controller.animateCamera(
            ml.CameraUpdate.newCameraPosition(
              ml.CameraPosition(
                target: position.target,
                zoom: position.zoom,
                bearing: _effectiveMapStyle == MapStyle.threeD
                    ? 35
                    : position.bearing,
                tilt: targetTilt,
              ),
            ),
            duration: const Duration(milliseconds: 220),
          ),
        );
      }
    }

    final symbolIds = controller?.symbolManager?.layerIds;
    if (symbolIds != null) {
      for (final layerId in symbolIds) {
        _controller?.setLayerProperties(layerId,
            const ml.SymbolLayerProperties(textFont: ['Noto Sans Bold']));
      }
    }

    _refreshAnnotationsIfNeeded();
  }

  void _handleSymbolTap(ml.Symbol symbol) {
    _ignoreFollowingMapClick();
    if (symbol.data?['destination'] == true) {
      widget.onRemoveDestination();
      return;
    }
    final index = symbol.data?['shapingIndex'];
    if (index is num) {
      widget.onRemoveShapingPoint(index.toInt());
    }
  }

  void _handleCircleTap(ml.Circle circle) {
    _ignoreFollowingMapClick();
    if (circle.data?['destination'] == true) {
      widget.onRemoveDestination();
      return;
    }
    final index = circle.data?['shapingIndex'];
    if (index is num) {
      widget.onRemoveShapingPoint(index.toInt());
    }
  }

  void _handleMapClick(math.Point<double> _, ml.LatLng coordinates) {
    if (_ignoreNextMapClick) {
      _ignoreNextMapClick = false;
      return;
    }
    widget.onTap(_fromMapLibre(coordinates));
  }

  void _ignoreFollowingMapClick() {
    _ignoreNextMapClick = true;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      _ignoreNextMapClick = false;
    });
  }

  void _refreshAnnotationsIfNeeded() {
    if (_controller == null || _loadedStyle != _effectiveMapStyle) {
      return;
    }
    final key = _annotationKeyFor(widget);
    if (_lastAnnotationKey == key) {
      return;
    }
    _lastAnnotationKey = key;
    _queueAnnotationRebuild();
  }

  Object _annotationKeyFor(_PlannerMap value) {
    return Object.hashAll([
      _effectiveMapStyle,
      value.origin?.latLng,
      value.destination?.latLng,
      ...value.shapingPoints.map((point) => point.latLng),
      value.route,
      value.loopCenter,
      value.loopRadiusMeters,
      value.navigating,
      value.currentPosition != null,
      value.riderAvatar,
      value.riderColor,
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.secondary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.surface,
    ]);
  }

  void _queueAnnotationRebuild() {
    if (_annotationRebuildRunning) {
      _annotationRebuildQueued = true;
      return;
    }
    unawaited(_drainAnnotationRebuilds());
  }

  Future<void> _drainAnnotationRebuilds() async {
    _annotationRebuildRunning = true;
    try {
      do {
        _annotationRebuildQueued = false;
        await _rebuildAnnotations();
      } while (_annotationRebuildQueued && mounted);
    } finally {
      _annotationRebuildRunning = false;
    }
  }

  Future<void> _rebuildAnnotations() async {
    final controller = _controller;
    if (controller == null || _loadedStyle != _effectiveMapStyle) {
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    _riderSymbol = null;
    await controller.clearSymbols();
    await controller.clearCircles();
    await controller.clearLines();

    if (widget.loopCenter != null && widget.loopRadiusMeters != null) {
      await controller.addLine(
        ml.LineOptions(
          geometry: _circlePoints(widget.loopCenter!, widget.loopRadiusMeters!),
          lineColor: _hex(scheme.primary),
          lineOpacity: 0.64,
          lineWidth: 2,
          lineGapWidth: 0,
          lineOffset: 0,
          lineBlur: 0,
        ),
      );
    }

    final route = widget.route;
    if (route != null) {
      final geometry = route.points.map(_toMapLibre).toList(growable: false);
      await controller.addLine(
        ml.LineOptions(
          geometry: geometry,
          lineColor: _hex(scheme.surface),
          lineWidth: 9,
          lineJoin: 'round',
          lineOpacity: 1,
          lineGapWidth: 0,
          lineOffset: 0,
          lineBlur: 0,
        ),
      );
      await controller.addLine(
        ml.LineOptions(
          geometry: geometry,
          lineColor: _hex(scheme.primary),
          lineWidth: 6,
          lineJoin: 'round',
          lineOpacity: 1,
          lineGapWidth: 0,
          lineOffset: 0,
          lineBlur: 0,
        ),
      );
    }

    final originIsLiveLocation =
        widget.origin?.type == 'gps' && widget.currentPosition != null;
    if (widget.origin != null && !originIsLiveLocation) {
      await _addLabeledPin('A', widget.origin!.latLng, scheme.primary);
    }
    if (widget.destination != null) {
      await _addLabeledPin(
        'B',
        widget.destination!.latLng,
        scheme.tertiary,
        data: {'destination': true},
      );
    }
    for (final indexed in widget.shapingPoints.indexed) {
      await _addLabeledPin(
        '${indexed.$1 + 1}',
        indexed.$2.latLng,
        scheme.secondary,
        data: {'shapingIndex': indexed.$1},
      );
    }
    if (widget.currentPosition != null) {
      final position = widget.currentPosition!;
      final validHeading = position.heading.isFinite && position.heading >= 0;
      final heading = validHeading && !(widget.following && widget.headingUp)
          ? position.heading
          : 0.0;
      await _addRiderMarker(
        widget.displayedPosition ??
            LatLng(position.latitude, position.longitude),
        rotate: heading,
      );
    }
  }

  Future<void> _addRiderMarker(
    LatLng point, {
    required double rotate,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final marker = widget.riderAvatar;
    final markerKey =
        '${_loadedStyle?.name}-${marker.name}-${widget.riderColor.toARGB32()}';
    if (_loadedRiderMarkerImage != markerKey) {
      final imageName =
          'twistaway-rider-${marker.name}-${_riderMarkerImageRevision++}';
      await controller.addImage(
        imageName,
        await _renderRiderMarker(marker, widget.riderColor),
      );
      _loadedRiderMarkerImage = markerKey;
      _activeRiderMarkerImageName = imageName;
    }
    final imageName = _activeRiderMarkerImageName;
    if (imageName == null) return;
    await controller.setSymbolIconAllowOverlap(true);
    _riderSymbol = await controller.addSymbol(
      ml.SymbolOptions(
        geometry: _toMapLibre(point),
        iconImage: imageName,
        iconSize: 1,
        iconRotate: rotate,
        iconAnchor: 'center',
        iconOpacity: 1,
        zIndex: 20,
      ),
      {'currentPosition': true, 'zIndex': 20},
    );
  }

  Future<void> _updateRiderMarker() async {
    final controller = _controller;
    final symbol = _riderSymbol;
    final position = widget.currentPosition;
    if (controller == null || symbol == null || position == null) return;
    final validHeading = position.heading.isFinite && position.heading >= 0;
    final heading = validHeading && !(widget.following && widget.headingUp)
        ? position.heading
        : 0.0;
    final point = widget.displayedPosition ??
        LatLng(position.latitude, position.longitude);
    try {
      await controller.updateSymbol(
        symbol,
        ml.SymbolOptions(
          geometry: _toMapLibre(point),
          iconRotate: heading,
        ),
      );
    } catch (_) {
      // A style reload can invalidate the old symbol; the queued rebuild wins.
    }
  }

  String? _activeRiderMarkerImageName;

  Future<Uint8List> _renderRiderMarker(
    _RiderAvatar marker,
    Color riderColor,
  ) async {
    const size = 128.0;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.34);
    final white = Paint()..color = Colors.white;
    final color = Paint()..color = riderColor;

    if (marker == _RiderAvatar.circle) {
      canvas.drawCircle(center + const Offset(0, 4), 38, shadow);
      canvas.drawCircle(center, 39, white);
      canvas.drawCircle(center, 32, color);
    } else if (marker == _RiderAvatar.triangle) {
      final shadowPath = ui.Path()
        ..moveTo(64, 8)
        ..lineTo(103, 108)
        ..lineTo(64, 91)
        ..lineTo(25, 108)
        ..close();
      canvas.save();
      canvas.translate(0, 4);
      canvas.drawPath(shadowPath, shadow);
      canvas.restore();
      canvas.drawPath(shadowPath, white);
      final innerPath = ui.Path()
        ..moveTo(64, 20)
        ..lineTo(92, 94)
        ..lineTo(64, 81)
        ..lineTo(36, 94)
        ..close();
      canvas.drawPath(innerPath, color);
    } else {
      final pointer = ui.Path()
        ..moveTo(64, 3)
        ..lineTo(47, 34)
        ..lineTo(81, 34)
        ..close();
      canvas.drawPath(pointer.shift(const Offset(0, 4)), shadow);
      canvas.drawCircle(center + const Offset(0, 4), 45, shadow);
      canvas.drawPath(pointer, white);
      canvas.drawCircle(center, 46, white);
      final innerPointer = ui.Path()
        ..moveTo(64, 10)
        ..lineTo(53, 34)
        ..lineTo(75, 34)
        ..close();
      canvas.drawPath(innerPointer, color);
      canvas.drawCircle(center, 39, color);

      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(marker.icon.codePoint),
          style: TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontFamily: marker.icon.fontFamily,
            package: marker.icon.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<void> _addLabeledPin(
    String label,
    LatLng point,
    Color color, {
    Map<String, dynamic>? data,
    double size = 13,
    double rotate = 0,
  }) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.addCircle(
      ml.CircleOptions(
        geometry: _toMapLibre(point),
        circleRadius: 15,
        circleColor: _hex(color),
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
        circleBlur: 0,
        circleOpacity: 1,
        circleStrokeOpacity: 1,
      ),
      data,
    );
    await controller.addSymbol(
      ml.SymbolOptions(
        geometry: _toMapLibre(point),
        textField: label,
        fontNames: const ['Noto Sans Bold'],
        textSize: size,
        textColor: '#ffffff',
        textHaloColor: _hex(color),
        textHaloWidth: 1,
        textRotate: rotate,
        zIndex: 10,
        iconSize: 1,
        iconRotate: 0,
        iconOpacity: 1,
        iconHaloWidth: 0,
        iconHaloBlur: 0,
        textOpacity: 1,
        textHaloBlur: 0,
        textMaxWidth: 10,
        textLetterSpacing: 0,
      ),
      {...?data, 'zIndex': 10},
    );
  }

  MapStyle get _effectiveMapStyle {
    return _activeMapStyle;
  }

  String get _styleAsset {
    return switch (_effectiveMapStyle) {
      MapStyle.bright => 'assets/map_styles/bright.json',
      MapStyle.fiord => 'assets/map_styles/fiord.json',
      MapStyle.threeD => 'assets/map_styles/liberty.json',
    };
  }

  double get _initialBearing => _effectiveMapStyle == MapStyle.threeD ? 35 : 0;

  double get _initialTilt => _effectiveMapStyle == MapStyle.threeD ? 55 : 0;
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.originController,
    required this.destinationController,
    required this.originFocusNode,
    required this.destinationFocusNode,
    required this.showOrigin,
    required this.showDestination,
    required this.showActions,
    this.embedded = false,
    this.stacked = false,
    this.stackedSpacing = 24,
    this.destinationMeasureKey,
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
  final FocusNode originFocusNode;
  final FocusNode destinationFocusNode;
  final bool showOrigin;
  final bool showDestination;
  final bool showActions;
  final bool embedded;
  final bool stacked;
  final double stackedSpacing;
  final Key? destinationMeasureKey;
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
    final wide = !stacked && MediaQuery.sizeOf(context).width >= 760;

    return Material(
      elevation: embedded ? 0 : 8,
      borderRadius: BorderRadius.circular(16),
      color:
          embedded ? Colors.transparent : Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: embedded ? EdgeInsets.zero : const EdgeInsets.all(12),
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
              const Divider(height: 12),
              ListView.separated(
                key: const ValueKey('place-search-results'),
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
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
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _searchControls(BuildContext context, {required bool wide}) {
    final originField = _SearchField(
      key: const ValueKey('search-control-origin'),
      controller: originController,
      focusNode: originFocusNode,
      label: 'Start',
      icon: Icons.trip_origin,
      selected: searchTarget == SearchTarget.origin,
      onSelected: () => onTargetChanged(SearchTarget.origin),
      onChanged: () => onQueryChanged(SearchTarget.origin),
      onSubmitted: () => onSearch(SearchTarget.origin),
    );
    final destinationControl = _SearchField(
      key: const ValueKey('search-control-destination'),
      controller: destinationController,
      focusNode: destinationFocusNode,
      label: 'Go to location',
      icon: Icons.place_outlined,
      selected: searchTarget == SearchTarget.destination,
      onSelected: () => onTargetChanged(SearchTarget.destination),
      onChanged: () => onQueryChanged(SearchTarget.destination),
      onSubmitted: () => onSearch(SearchTarget.destination),
    );
    final destinationField = destinationMeasureKey == null
        ? destinationControl
        : KeyedSubtree(
            key: destinationMeasureKey,
            child: destinationControl,
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
        if (showDestination) Expanded(child: destinationField),
        if (showDestination && showOrigin) ...[
          const SizedBox(width: 12),
          swap,
          const SizedBox(width: 12),
        ],
        if (showOrigin) Expanded(child: originField),
        if (showActions) ...[
          const SizedBox(width: 12),
          search,
          const SizedBox(width: 12),
          clear,
        ],
      ];
    }

    return [
      if (showDestination) destinationField,
      if (showDestination && showOrigin) SizedBox(height: stackedSpacing),
      if (showOrigin) originField,
      if (showActions) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            if (showOrigin && showDestination) ...[
              swap,
              const SizedBox(width: 12),
            ],
            Expanded(child: search),
            const SizedBox(width: 12),
            clear,
          ],
        ),
      ],
    ];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
      key: ValueKey('search-field-$label'),
      controller: controller,
      focusNode: focusNode,
      onTap: onSelected,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        filled: true,
        fillColor:
            selected ? scheme.primaryContainer.withValues(alpha: 0.38) : null,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _RiderColorButton extends StatelessWidget {
  const _RiderColorButton({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('rider-color-${_hex(color)}'),
      label: 'Marker color ${_hex(color)}',
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onPressed,
        radius: 28,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

class _CustomRiderColorButton extends StatelessWidget {
  const _CustomRiderColorButton({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('custom-rider-color'),
      onPressed: onPressed,
      icon: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
      ),
      label: const Text('Custom'),
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 1,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
                elevation: 0,
                pressedElevation: 0,
              ),
            ),
            child: Slider(
              value: value.clamp(0, max).toDouble(),
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({
    required this.themeMode,
    required this.mapStyle,
    required this.riderAvatar,
    required this.riderColor,
    required this.voiceGuidanceEnabled,
    required this.voiceVolume,
    required this.availableVoices,
    required this.selectedVoiceId,
    required this.preferences,
    required this.rideFocus,
    required this.savedRouteCount,
    required this.spotifyConnected,
    required this.serviceConnectionMode,
    required this.speedometerEnabled,
    required this.speedAlertThresholdMph,
    required this.onThemeModeChanged,
    required this.onMapStyleChanged,
    required this.onRiderAvatarChanged,
    required this.onRiderColorChanged,
    required this.onVoiceGuidanceChanged,
    required this.onVoiceVolumeChanged,
    required this.onVoiceChanged,
    required this.onServiceConnectionModeChanged,
    required this.onSpeedometerEnabledChanged,
    required this.onSpeedAlertThresholdChanged,
    required this.onTestVoice,
    required this.onPreferenceChanged,
    required this.onRideFocusChanged,
    required this.onReplan,
    required this.onClearSavedRoutes,
    required this.onConnectSpotify,
    required this.onDisconnectSpotify,
    required this.onOpenSpotify,
    required this.onShowMapCredits,
  });

  final ThemeMode themeMode;
  final MapStyle mapStyle;
  final _RiderAvatar riderAvatar;
  final Color riderColor;
  final bool voiceGuidanceEnabled;
  final double voiceVolume;
  final List<_VoiceOption> availableVoices;
  final String? selectedVoiceId;
  final List<RoutePreference> preferences;
  final String rideFocus;
  final int savedRouteCount;
  final bool spotifyConnected;
  final ServiceConnectionMode serviceConnectionMode;
  final bool speedometerEnabled;
  final double speedAlertThresholdMph;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<MapStyle> onMapStyleChanged;
  final ValueChanged<_RiderAvatar> onRiderAvatarChanged;
  final ValueChanged<Color> onRiderColorChanged;
  final ValueChanged<bool> onVoiceGuidanceChanged;
  final ValueChanged<double> onVoiceVolumeChanged;
  final ValueChanged<String?> onVoiceChanged;
  final ValueChanged<ServiceConnectionMode> onServiceConnectionModeChanged;
  final ValueChanged<bool> onSpeedometerEnabledChanged;
  final ValueChanged<double> onSpeedAlertThresholdChanged;
  final VoidCallback onTestVoice;
  final List<RoutePreference> Function(String key, double value)
      onPreferenceChanged;
  final List<RoutePreference> Function(String focus) onRideFocusChanged;
  final VoidCallback? onReplan;
  final Future<void> Function() onClearSavedRoutes;
  final Future<bool> Function() onConnectSpotify;
  final Future<void> Function() onDisconnectSpotify;
  final VoidCallback onOpenSpotify;
  final VoidCallback onShowMapCredits;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _entranceMotion;
  late final Animation<Offset> _entranceOffset;
  late ThemeMode _themeMode;
  late MapStyle _mapStyle;
  late _RiderAvatar _riderAvatar;
  late Color _riderColor;
  late bool _voiceEnabled;
  late double _voiceVolume;
  late String? _selectedVoiceId;
  late List<RoutePreference> _preferences;
  late String _rideFocus;
  late int _savedRouteCount;
  late bool _spotifyConnected;
  late ServiceConnectionMode _serviceConnectionMode;
  late bool _speedometerEnabled;
  late double _speedAlertThresholdMph;
  bool _spotifyBusy = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _entranceMotion = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _entranceOffset = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(_entranceMotion);
    _themeMode = widget.themeMode;
    _mapStyle = widget.mapStyle;
    _riderAvatar = widget.riderAvatar;
    _riderColor = widget.riderColor;
    _voiceEnabled = widget.voiceGuidanceEnabled;
    _voiceVolume = widget.voiceVolume;
    _selectedVoiceId = widget.availableVoices.any(
      (voice) => voice.id == widget.selectedVoiceId,
    )
        ? widget.selectedVoiceId
        : null;
    _preferences = List.of(widget.preferences);
    _rideFocus = widget.rideFocus;
    _savedRouteCount = widget.savedRouteCount;
    _spotifyConnected = widget.spotifyConnected;
    _serviceConnectionMode = widget.serviceConnectionMode;
    _speedometerEnabled = widget.speedometerEnabled;
    _speedAlertThresholdMph = widget.speedAlertThresholdMph;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_entranceController.forward());
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      key: const ValueKey('settings-entrance-fade'),
      opacity: _entranceMotion,
      child: SlideTransition(
        key: const ValueKey('settings-entrance-slide'),
        position: _entranceOffset,
        child: PointerInterceptor(
          child: Scaffold(
            key: const ValueKey('settings-screen'),
            appBar: AppBar(
              backgroundColor: scheme.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                tooltip: 'Close settings',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
              title: const Text('Twistaway settings'),
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 760;
                  final profile = _profileCard(context);
                  final appearance = _appearanceCard(context);
                  final speedometer = _speedometerCard(context);
                  final voice = _voiceCard(context);
                  final routing = _routingCard(context);
                  final integrations = _integrationsCard(context);
                  final privacy = _privacyStorageCard(context);
                  final legal = _legalCard(context);

                  return ColoredBox(
                    color: scheme.surfaceContainerLowest,
                    child: ListView(
                      key: const ValueKey('settings-scroll'),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 14,
                        18,
                        wide ? 28 : 14,
                        32,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _settingsHero(context),
                                const SizedBox(height: 16),
                                if (wide)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            profile,
                                            const SizedBox(height: 14),
                                            appearance,
                                            const SizedBox(height: 14),
                                            speedometer,
                                            const SizedBox(height: 14),
                                            voice,
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            routing,
                                            const SizedBox(height: 14),
                                            integrations,
                                            const SizedBox(height: 14),
                                            privacy,
                                            const SizedBox(height: 14),
                                            legal,
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  profile,
                                  const SizedBox(height: 14),
                                  appearance,
                                  const SizedBox(height: 14),
                                  speedometer,
                                  const SizedBox(height: 14),
                                  voice,
                                  const SizedBox(height: 14),
                                  routing,
                                  const SizedBox(height: 14),
                                  integrations,
                                  const SizedBox(height: 14),
                                  privacy,
                                  const SizedBox(height: 14),
                                  legal,
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsHero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: _riderColor,
            child: Icon(_riderAvatar.icon, size: 30, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make every ride yours',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text('Map, navigation, privacy, and ride preferences.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Navigation marker',
      icon: Icons.navigation_outlined,
      children: [
        const Text(
          'Choose the live marker shown on the map. Changes save automatically.',
        ),
        const SizedBox(height: 12),
        Text('Icon', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final avatar in _RiderAvatar.values)
              ChoiceChip(
                avatar: Icon(avatar.icon, size: 18),
                label: Text(avatar.label),
                selected: _riderAvatar == avatar,
                onSelected: (_) {
                  setState(() => _riderAvatar = avatar);
                  widget.onRiderAvatarChanged(avatar);
                },
              ),
          ],
        ),
        const Divider(height: 28),
        Text('Color', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _riderColorPresets)
              _RiderColorButton(
                color: color,
                selected: _riderColor.toARGB32() == color.toARGB32(),
                onPressed: () => _selectRiderColor(color),
              ),
            _CustomRiderColorButton(
              color: _riderColor,
              selected: !_riderColorPresets.any(
                (color) => color.toARGB32() == _riderColor.toARGB32(),
              ),
              onPressed: _showCustomRiderColorPicker,
            ),
          ],
        ),
      ],
    );
  }

  void _selectRiderColor(Color color) {
    setState(() => _riderColor = color);
    widget.onRiderColorChanged(color);
  }

  Future<void> _showCustomRiderColorPicker() async {
    var hsv = HSVColor.fromColor(_riderColor);
    final selected = await showAdaptiveDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final color = hsv.toColor();
          return AlertDialog.adaptive(
            title: const Text('Custom marker color'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ColorSlider(
                    label: 'Hue',
                    value: hsv.hue,
                    max: 360,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  _ColorSlider(
                    label: 'Saturation',
                    value: hsv.saturation,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withSaturation(value)),
                  ),
                  _ColorSlider(
                    label: 'Brightness',
                    value: hsv.value,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withValue(value)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(color),
                child: const Text('Use color'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null && mounted) _selectRiderColor(selected);
  }

  Widget _appearanceCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Map & appearance',
      icon: Icons.map_outlined,
      children: [
        Text('App theme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ThemeMode.values)
              ChoiceChip(
                avatar: Icon(
                  switch (mode) {
                    ThemeMode.system => Icons.brightness_auto_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                  },
                  size: 18,
                ),
                label: Text(
                  switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  },
                ),
                selected: _themeMode == mode,
                onSelected: (_) {
                  setState(() => _themeMode = mode);
                  widget.onThemeModeChanged(mode);
                },
              ),
          ],
        ),
        const Divider(height: 28),
        Text('Map colors', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final style in MapStyle.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(style.icon),
            title: Text(style.label),
            subtitle: Text(
              switch (style) {
                MapStyle.bright => 'Clear daylight colors',
                MapStyle.fiord => 'Low-glare dark road colors',
                MapStyle.threeD => 'Dimensional terrain and buildings',
              },
            ),
            selected: _mapStyle == style,
            trailing: _mapStyle == style
                ? const Icon(Icons.check_circle)
                : const Icon(Icons.circle_outlined),
            onTap: () {
              setState(() => _mapStyle = style);
              widget.onMapStyleChanged(style);
            },
          ),
      ],
    );
  }

  Widget _speedometerCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Speedometer',
      icon: Icons.speed_outlined,
      children: [
        SwitchListTile(
          key: const ValueKey('speedometer-enabled-setting'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show during navigation'),
          subtitle: const Text(
            'Display your GPS speed above the mapped road speed limit.',
          ),
          value: _speedometerEnabled,
          onChanged: (value) {
            setState(() => _speedometerEnabled = value);
            widget.onSpeedometerEnabledChanged(value);
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const ValueKey('speed-alert-threshold-setting'),
          initialValue: _speedAlertThresholdMph.round().toString(),
          enabled: _speedometerEnabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            TextInputFormatter.withFunction((oldValue, newValue) {
              final value = int.tryParse(newValue.text);
              return newValue.text.isEmpty || (value != null && value <= 50)
                  ? newValue
                  : oldValue;
            }),
          ],
          decoration: const InputDecoration(
            labelText: 'Over-limit warning threshold',
            helperText: 'Turns red this many mph above the mapped limit.',
            suffixText: 'mph',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.warning_amber_outlined),
          ),
          onChanged: (text) {
            final value = double.tryParse(text);
            if (value == null) return;
            setState(() => _speedAlertThresholdMph = value);
            widget.onSpeedAlertThresholdChanged(value);
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Road limits depend on OpenStreetMap data. Always obey posted signs.',
        ),
      ],
    );
  }

  Widget _voiceCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Navigation voice',
      icon: Icons.record_voice_over_outlined,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Spoken directions'),
          subtitle: const Text('Announce turns, arrival, and off-route alerts'),
          value: _voiceEnabled,
          onChanged: (value) {
            setState(() => _voiceEnabled = value);
            widget.onVoiceGuidanceChanged(value);
          },
        ),
        Row(
          children: [
            const Icon(Icons.volume_down_outlined),
            Expanded(
              child: Slider.adaptive(
                value: _voiceVolume,
                divisions: 10,
                label: '${(_voiceVolume * 100).round()}%',
                onChanged: (value) {
                  setState(() => _voiceVolume = value);
                  widget.onVoiceVolumeChanged(value);
                },
              ),
            ),
            const Icon(Icons.volume_up_outlined),
          ],
        ),
        if (widget.availableVoices.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language),
            title: Text('System default voice'),
            subtitle: Text('No alternate voices were reported by this device.'),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedVoiceId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Voice',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.language),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('System default'),
              ),
              for (final voice in widget.availableVoices)
                DropdownMenuItem(value: voice.id, child: Text(voice.label)),
            ],
            onChanged: (value) {
              setState(() => _selectedVoiceId = value);
              widget.onVoiceChanged(value);
            },
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onTestVoice,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Test voice'),
        ),
      ],
    );
  }

  Widget _routingCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Ride preferences',
      icon: Icons.route_outlined,
      children: [
        Text('Route processing',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<ServiceConnectionMode>(
          key: const ValueKey('service-connection-mode'),
          initialValue: _serviceConnectionMode,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.cloud_sync_outlined),
          ),
          items: [
            for (final mode in ServiceConnectionMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (mode) {
            if (mode == null) return;
            setState(() => _serviceConnectionMode = mode);
            widget.onServiceConnectionModeChanged(mode);
          },
        ),
        const SizedBox(height: 8),
        Text(_serviceConnectionMode.description),
        const SizedBox(height: 6),
        Text(
          'Direct providers still need internet access. Fully offline routing requires downloaded road data and is not available yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 28),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _RideFocusChip(
              label: 'Balanced',
              icon: Icons.tune,
              selected: _rideFocus == 'balanced',
              onSelected: () => _selectRideFocus('balanced'),
            ),
            _RideFocusChip(
              label: 'Scenic',
              icon: Icons.landscape_outlined,
              selected: _rideFocus == 'scenic',
              onSelected: () => _selectRideFocus('scenic'),
            ),
            _RideFocusChip(
              label: 'Backroads',
              icon: Icons.forest_outlined,
              selected: _rideFocus == 'backroads',
              onSelected: () => _selectRideFocus('backroads'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final preference in _preferences) ...[
          if (preference.isToggle)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(preference.label),
              subtitle: Text(preference.description),
              value: preference.value >= 0.5,
              onChanged: (value) =>
                  _changePreference(preference.key, value ? 1 : 0),
            )
          else ...[
            Text(
              preference.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(preference.description),
            Slider(
              value: preference.value,
              onChanged: (value) => _changePreference(preference.key, value),
            ),
          ],
          const Divider(height: 16),
        ],
        FilledButton.icon(
          onPressed: widget.onReplan,
          icon: const Icon(Icons.refresh),
          label: const Text('Apply and replan'),
        ),
      ],
    );
  }

  void _selectRideFocus(String focus) {
    final preferences = widget.onRideFocusChanged(focus);
    setState(() {
      _rideFocus = focus;
      _preferences = preferences;
    });
  }

  void _changePreference(String key, double value) {
    final preferences = widget.onPreferenceChanged(key, value);
    setState(() => _preferences = preferences);
  }

  Widget _integrationsCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Music integrations',
      icon: Icons.music_note_outlined,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const SizedBox.square(
            dimension: 40,
            child: Center(child: _SpotifyBrandIcon(size: 24)),
          ),
          title: const Text('Spotify'),
          subtitle: Text(
            _spotifyConnected
                ? 'Connected for playback controls during navigation'
                : 'Connect to show tracks and playback controls while riding',
          ),
          trailing: _spotifyConnected
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        if (_spotifyConnected)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _spotifyBusy ? null : widget.onOpenSpotify,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('OPEN SPOTIFY'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _spotifyBusy ? null : _disconnectSpotify,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _spotifyBusy ? null : _connectSpotifyFromSettings,
            icon: _spotifyBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: const Text('Connect Spotify'),
          ),
        const SizedBox(height: 10),
        const Text(
          'Twistaway requests only the Spotify permissions needed to read the current track and control playback. Authorization tokens are stored in secure device storage.',
        ),
      ],
    );
  }

  Future<void> _connectSpotifyFromSettings() async {
    setState(() => _spotifyBusy = true);
    try {
      final connected = await widget.onConnectSpotify();
      if (mounted) setState(() => _spotifyConnected = connected);
    } finally {
      if (mounted) setState(() => _spotifyBusy = false);
    }
  }

  Future<void> _disconnectSpotify() async {
    setState(() => _spotifyBusy = true);
    try {
      await widget.onDisconnectSpotify();
      if (mounted) setState(() => _spotifyConnected = false);
    } finally {
      if (mounted) setState(() => _spotifyBusy = false);
    }
  }

  Widget _privacyStorageCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Privacy & storage',
      icon: Icons.shield_outlined,
      children: [
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('Local encrypted settings'),
          subtitle: Text(
            'Preferences and saved routes stay in this device\'s secure storage.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('Saved routes'),
          subtitle: Text('$_savedRouteCount stored on this device'),
        ),
        OutlinedButton.icon(
          onPressed: _savedRouteCount == 0 ? null : _confirmClearSavedRoutes,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear saved routes'),
        ),
      ],
    );
  }

  Future<void> _confirmClearSavedRoutes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear saved routes?'),
        content: const Text('This removes every route stored on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onClearSavedRoutes();
    if (mounted) setState(() => _savedRouteCount = 0);
  }

  Widget _legalCard(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Legal & about',
      icon: Icons.gavel_outlined,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDocument(
            'Privacy',
            'Twistaway requests location only for map positioning and navigation. Route preferences and saved routes are stored locally. Map tiles, place searches, and routing requests may be sent to their configured providers when you use those features.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms of service'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDocument(
            'Terms of service',
            'Twistaway provides route-planning assistance only. Road conditions, closures, laws, and hazards can change. Always follow posted signs, local laws, and your own judgment while riding.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.map_outlined),
          title: const Text('Map credits'),
          subtitle: const Text('OpenFreeMap, OpenStreetMap, and OpenMapTiles'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onShowMapCredits,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const SizedBox.square(
            dimension: 24,
            child: _SpotifyBrandIcon(size: 24),
          ),
          title: const Text('Spotify attribution'),
          subtitle: const Text('Brand, content, and service notice'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showDocument(
            'Spotify attribution',
            'Spotify is a third-party service. Spotify and its marks belong to Spotify AB. Twistaway is not endorsed by, sponsored by, or affiliated with Spotify. Spotify content and playback remain subject to Spotify terms. Track metadata and artwork shown by Twistaway link back to Spotify.',
          ),
        ),
        const Divider(),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.two_wheeler),
          title: Text('Twistaway'),
          subtitle: Text('Version 0.1.0 · Privacy-first ride planning'),
        ),
      ],
    );
  }

  Future<void> _showDocument(String title, String body) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(child: Text(body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _RideFocusChip extends StatelessWidget {
  const _RideFocusChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.heroTag,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.selected = false,
  });

  final String heroTag;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final background = !enabled
        ? scheme.surfaceContainer
        : selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh;
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
            ? scheme.onSecondaryContainer
            : scheme.primary;

    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: tooltip,
      onPressed: onPressed,
      elevation: enabled ? 3 : 1,
      disabledElevation: 1,
      backgroundColor: background.withValues(alpha: 0.96),
      foregroundColor: foreground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: enabled
              ? scheme.outlineVariant
              : scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: icon,
    );
  }
}

class _RouteManagementControls extends StatelessWidget {
  const _RouteManagementControls({
    required this.onUndo,
    required this.onClear,
    required this.onSave,
    required this.onOpenSaved,
    required this.savedCount,
  });

  final VoidCallback? onUndo;
  final VoidCallback? onClear;
  final VoidCallback? onSave;
  final VoidCallback onOpenSaved;
  final int savedCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Row(
            children: [
              Expanded(
                child: IconButton.outlined(
                  tooltip: 'Undo last point',
                  onPressed: onUndo,
                  icon: const Icon(Icons.undo),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.outlined(
                  tooltip: 'Clear route points',
                  onPressed: onClear,
                  icon: const Icon(Icons.layers_clear_outlined),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.filledTonal(
                  tooltip: 'Save route',
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.filledTonal(
                  tooltip: 'Saved routes',
                  onPressed: onOpenSaved,
                  icon: Badge(
                    isLabelVisible: savedCount > 0,
                    label: Text('$savedCount'),
                    child: const Icon(Icons.bookmarks_outlined),
                  ),
                ),
              ),
            ],
          );
        }

        final outlinedStyle = OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        );
        final tonalStyle = FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        );

        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: outlinedStyle,
                onPressed: onUndo,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: outlinedStyle,
                onPressed: onClear,
                icon: const Icon(Icons.layers_clear_outlined, size: 18),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: tonalStyle,
                onPressed: onSave,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Save'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: tonalStyle,
                onPressed: onOpenSaved,
                icon: const Icon(Icons.bookmarks_outlined, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    savedCount == 0 ? 'Saved' : 'Saved ($savedCount)',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class RideActionControls extends StatelessWidget {
  const RideActionControls({
    super.key,
    required this.onPlan,
    required this.routingBusy,
    required this.planLabel,
    required this.onDraw,
    required this.drawMode,
    required this.onLoop,
    required this.onStartOrStop,
    required this.navigating,
    required this.onSpeak,
  });

  final VoidCallback? onPlan;
  final bool routingBusy;
  final String planLabel;
  final VoidCallback? onDraw;
  final bool drawMode;
  final VoidCallback? onLoop;
  final VoidCallback? onStartOrStop;
  final bool navigating;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    if (navigating && onStartOrStop != null) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          key: const ValueKey('stop-navigation-button'),
          onPressed: onStartOrStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop navigation'),
        ),
      );
    }

    if (onStartOrStop != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('start-navigation-button'),
              onPressed: onStartOrStop,
              icon: const Icon(Icons.navigation),
              label: const Text('Start navigation'),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 520 ? 2 : 4;
              const spacing = 10.0;
              final buttonWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;

              Widget action({
                required Key key,
                required IconData icon,
                required String label,
                required VoidCallback? onPressed,
                Widget? busyIcon,
              }) {
                return SizedBox(
                  width: buttonWidth,
                  height: 46,
                  child: FilledButton.tonalIcon(
                    key: key,
                    onPressed: onPressed,
                    icon: busyIcon ?? Icon(icon, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                );
              }

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  action(
                    key: const ValueKey('replan-route-button'),
                    icon: Icons.refresh,
                    label: 'Replan',
                    onPressed: routingBusy ? null : onPlan,
                    busyIcon: routingBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                  action(
                    key: const ValueKey('edit-route-button'),
                    icon: drawMode ? Icons.gesture : Icons.draw_outlined,
                    label: drawMode ? 'Drawing' : 'Edit route',
                    onPressed: onDraw,
                  ),
                  action(
                    key: const ValueKey('build-loop-button'),
                    icon: Icons.loop,
                    label: 'Build loop',
                    onPressed: onLoop,
                  ),
                  action(
                    key: const ValueKey('preview-voice-button'),
                    icon: Icons.volume_up_outlined,
                    label: 'Preview voice',
                    onPressed: onSpeak,
                  ),
                ],
              );
            },
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Row(
            children: [
              Expanded(
                child: IconButton.filled(
                  tooltip: planLabel,
                  onPressed: onPlan,
                  icon: routingBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.navigation_outlined),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.filledTonal(
                  tooltip: drawMode ? 'Drawing mode' : 'Draw route',
                  onPressed: onDraw,
                  icon: Icon(drawMode ? Icons.gesture : Icons.draw_outlined),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IconButton.filledTonal(
                  tooltip: 'Build loop',
                  onPressed: onLoop,
                  icon: const Icon(Icons.loop),
                ),
              ),
            ],
          );
        }

        final primaryStyle = FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        );
        final tonalStyle = FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
        );
        Widget label(String text) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1),
            );

        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: primaryStyle,
                onPressed: onPlan,
                icon: routingBusy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.navigation_outlined, size: 18),
                label: label(planLabel),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: tonalStyle,
                onPressed: onDraw,
                icon: Icon(
                  drawMode ? Icons.gesture : Icons.draw_outlined,
                  size: 18,
                ),
                label: label(drawMode ? 'Drawing' : 'Draw'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: tonalStyle,
                onPressed: onLoop,
                icon: const Icon(Icons.loop, size: 18),
                label: label('Loop'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RouteSheet extends StatelessWidget {
  const _RouteSheet({
    this.embedded = false,
    this.plannedRouteOverviewKey,
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
    required this.drawMode,
    required this.loopTargetMiles,
    required this.onPlanRide,
    required this.onToggleDrawMode,
    required this.onBuildLoopRide,
    required this.onLoopTargetChanged,
    required this.onUndoRoutePoint,
    required this.onClearRoutePoints,
    required this.onSaveRoute,
    required this.onOpenSavedRoutes,
    required this.savedRouteCount,
    required this.onStartNavigation,
    required this.onStopNavigation,
    required this.onSpeak,
  });

  final bool embedded;
  final Key? plannedRouteOverviewKey;
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
  final bool drawMode;
  final double loopTargetMiles;
  final VoidCallback onPlanRide;
  final VoidCallback onToggleDrawMode;
  final VoidCallback? onBuildLoopRide;
  final ValueChanged<double> onLoopTargetChanged;
  final VoidCallback? onUndoRoutePoint;
  final VoidCallback? onClearRoutePoints;
  final VoidCallback? onSaveRoute;
  final VoidCallback onOpenSavedRoutes;
  final int savedRouteCount;
  final VoidCallback onStartNavigation;
  final VoidCallback onStopNavigation;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canRoute = origin != null && destination != null;

    return Material(
      elevation: embedded ? 0 : 8,
      borderRadius: BorderRadius.circular(18),
      color: embedded ? Colors.transparent : scheme.surface,
      child: Padding(
        padding: embedded ? EdgeInsets.zero : const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (route != null && !navigating)
                  PlannedRouteOverview(
                    key: plannedRouteOverviewKey,
                    startName: origin?.name ?? 'Choose start',
                    destinationName: destination?.name ?? 'Choose destination',
                    distanceMeters: route!.distanceMeters,
                    durationSeconds: route!.durationSeconds,
                    viaPointCount: shapingPoints.length,
                  )
                else ...[
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
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: RideActionControls(
                    onPlan: !canRoute || routingBusy || navigating
                        ? null
                        : onPlanRide,
                    routingBusy: routingBusy,
                    planLabel: route == null ? 'Plan ride' : 'Replan',
                    onDraw: navigating ? null : onToggleDrawMode,
                    drawMode: drawMode,
                    onLoop: navigating ? null : onBuildLoopRide,
                    onStartOrStop: route == null
                        ? null
                        : navigating
                            ? onStopNavigation
                            : onStartNavigation,
                    navigating: navigating,
                    onSpeak: route == null ? null : onSpeak,
                  ),
                ),
              ],
            ),
            if (!navigating) ...[
              const SizedBox(height: 12),
              _LoopDistanceControl(
                value: loopTargetMiles,
                enabled: onBuildLoopRide != null,
                onChanged: onLoopTargetChanged,
              ),
              const SizedBox(height: 12),
              _RouteManagementControls(
                onUndo: onUndoRoutePoint,
                onClear: onClearRoutePoints,
                onSave: onSaveRoute,
                onOpenSaved: onOpenSavedRoutes,
                savedCount: savedRouteCount,
              ),
            ],
            if (navigating && route != null && route!.steps.isNotEmpty) ...[
              const Divider(height: 24),
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
                const SizedBox(height: 12),
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

class PlannedRouteOverview extends StatelessWidget {
  const PlannedRouteOverview({
    super.key,
    required this.startName,
    required this.destinationName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.viaPointCount,
  });

  final String startName;
  final String destinationName;
  final double distanceMeters;
  final double durationSeconds;
  final int viaPointCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final arrival = DateTime.now().add(
      Duration(seconds: math.max(0, durationSeconds).round()),
    );

    return DecoratedBox(
      key: const ValueKey('planned-route-overview'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Route overview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (viaPointCount > 0)
                  Text(
                    'Via $viaPointCount ${viaPointCount == 1 ? 'point' : 'points'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _RouteEndpoint(
              label: 'START',
              name: startName,
              icon: Icons.trip_origin,
              valueKey: const ValueKey('planned-route-start'),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 2,
                  height: 14,
                  color: scheme.outlineVariant,
                ),
              ),
            ),
            _RouteEndpoint(
              label: 'DESTINATION',
              name: destinationName,
              icon: Icons.flag_outlined,
              valueKey: const ValueKey('planned-route-destination'),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _RouteOverviewMetric(
                    label: 'DISTANCE',
                    value: _formatDistance(distanceMeters),
                  ),
                ),
                const VerticalDivider(width: 18),
                Expanded(
                  child: _RouteOverviewMetric(
                    label: 'RIDE TIME',
                    value: _formatDuration(durationSeconds),
                  ),
                ),
                const VerticalDivider(width: 18),
                Expanded(
                  child: _RouteOverviewMetric(
                    label: 'ETA',
                    value: _formatEta(arrival),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteEndpoint extends StatelessWidget {
  const _RouteEndpoint({
    required this.label,
    required this.name,
    required this.icon,
    required this.valueKey,
  });

  final String label;
  final String name;
  final IconData icon;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: scheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                key: valueKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteOverviewMetric extends StatelessWidget {
  const _RouteOverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ],
    );
  }
}

class _LoopDistanceControl extends StatelessWidget {
  const _LoopDistanceControl({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.radio_button_unchecked,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Loop target',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text('${value.round()} mi'),
              ],
            ),
            Slider(
              value: value,
              min: 12,
              max: 90,
              divisions: 26,
              label: '${value.round()} mi',
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
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

class _NavigationTurnBanner extends StatelessWidget {
  const _NavigationTurnBanner({
    required this.instruction,
    required this.distanceMeters,
    required this.alert,
    required this.onSpeak,
    required this.onStop,
  });

  final String instruction;
  final double? distanceMeters;
  final String? alert;
  final VoidCallback onSpeak;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Material(
          elevation: 10,
          color: scheme.primaryContainer.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    _maneuverIcon,
                    size: 34,
                    color: scheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (distanceMeters != null)
                        Text(
                          _formatDistance(distanceMeters!),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                      Text(
                        alert ?? instruction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Repeat direction',
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_outlined),
                ),
                IconButton(
                  tooltip: 'Stop navigation',
                  onPressed: onStop,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _maneuverIcon {
    final text = (alert ?? instruction).toLowerCase();
    if (text.contains('u-turn') || text.contains('uturn')) {
      return Icons.u_turn_left;
    }
    if (text.contains('roundabout')) return Icons.roundabout_left;
    if (text.contains('left')) return Icons.turn_left;
    if (text.contains('right')) return Icons.turn_right;
    if (text.contains('arriv')) return Icons.flag;
    return Icons.straight;
  }
}

class _SpotifyPanel extends StatelessWidget {
  const _SpotifyPanel({
    required this.state,
    required this.onConnect,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onOpenSpotify,
    required this.onDisconnect,
  });

  final SpotifyPlayerState state;
  final VoidCallback onConnect;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;
  final VoidCallback onOpenSpotify;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controlsRestricted = !state.canTogglePlayback ||
        !state.canSkipPrevious ||
        !state.canSkipNext;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          key: const ValueKey('spotify-panel-content'),
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _SpotifyFullLogo(width: 112),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      state.connected ? 'Connected' : 'Not connected',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!state.connected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Connect Spotify to see the current song and control playback without leaving the map.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('spotify-connect-button'),
                  onPressed: state.busy ? null : onConnect,
                  icon: state.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('Connect Spotify'),
                ),
              ] else ...[
                Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpenSpotify,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          _SpotifyArtwork(url: state.albumArtUrl, size: 76),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  state.trackName ?? 'No song playing',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.artistName ??
                                      (state.hasActiveDevice
                                          ? 'Spotify connected'
                                          : 'Open Spotify to start listening'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.open_in_new, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      tooltip: state.canSkipPrevious
                          ? 'Previous track'
                          : 'Previous track unavailable',
                      onPressed: state.busy || !state.canSkipPrevious
                          ? null
                          : onPrevious,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    const SizedBox(width: 18),
                    SizedBox.square(
                      dimension: 56,
                      child: IconButton.filled(
                        tooltip: state.canTogglePlayback
                            ? (state.isPlaying ? 'Pause' : 'Play')
                            : 'Playback control unavailable',
                        onPressed: state.busy || !state.canTogglePlayback
                            ? null
                            : onTogglePlayback,
                        iconSize: 30,
                        icon: state.busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                state.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    IconButton.filledTonal(
                      tooltip: state.canSkipNext
                          ? 'Next track'
                          : 'Next track unavailable',
                      onPressed:
                          state.busy || !state.canSkipNext ? null : onNext,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
                if (controlsRestricted) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Unavailable controls are restricted by Spotify for this playback.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onOpenSpotify,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('OPEN SPOTIFY'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      tooltip: 'Disconnect Spotify',
                      onPressed: state.busy ? null : onDisconnect,
                      icon: const Icon(Icons.link_off),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotifyArtwork extends StatelessWidget {
  const _SpotifyArtwork({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: url == null
              ? Center(child: _SpotifyBrandIcon(size: size * 0.42))
              : Image.network(
                  url!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: _SpotifyBrandIcon(size: size * 0.42),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SpotifyBrandIcon extends StatelessWidget {
  const _SpotifyBrandIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      'assets/brand/Spotify_Primary_Logo_RGB_${dark ? 'White' : 'Black'}.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Spotify',
    );
  }
}

class _SpotifyFullLogo extends StatelessWidget {
  const _SpotifyFullLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      'assets/brand/Spotify_Full_Logo_RGB_${dark ? 'White' : 'Black'}.png',
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Spotify',
    );
  }
}

class NavigationSpeedometer extends StatelessWidget {
  const NavigationSpeedometer({
    super.key,
    required this.speedMph,
    required this.roadSpeedLimitMph,
    required this.alertThresholdMph,
  });

  final double speedMph;
  final double? roadSpeedLimitMph;
  final double alertThresholdMph;

  @override
  Widget build(BuildContext context) {
    final limit = roadSpeedLimitMph;
    final overLimit = isSpeedWarning(
      speedMph: speedMph,
      speedLimitMph: limit,
      thresholdMph: alertThresholdMph,
    );
    final speedColor = overLimit ? const Color(0xffff4d4d) : Colors.white;
    final roundedSpeed = speedMph.round();
    final roundedLimit = limit?.round();
    return Semantics(
      key: const ValueKey('navigation-speedometer'),
      label: roundedLimit == null
          ? 'Current speed $roundedSpeed miles per hour. Road speed limit unknown.'
          : 'Current speed $roundedSpeed miles per hour. Road speed limit $roundedLimit miles per hour.',
      child: Container(
        width: 100,
        height: 132,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xff11151b),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: overLimit ? speedColor : const Color(0xff59616d),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'YOUR SPEED',
                    style: TextStyle(
                      color: speedColor.withValues(alpha: 0.82),
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$roundedSpeed',
                    key: const ValueKey('current-speed-mph'),
                    style: TextStyle(
                      color: speedColor,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xff46505c),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'SPEED LIMIT',
                    style: TextStyle(
                      color: Color(0xffd3d8df),
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    roundedLimit?.toString() ?? '--',
                    key: const ValueKey('road-speed-limit-mph'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
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

class NavigationSheetContent extends StatelessWidget {
  const NavigationSheetContent({
    super.key,
    required this.scrollController,
    required this.destinationName,
    required this.distanceMeters,
    required this.estimatedArrivalTime,
    required this.addingStop,
    required this.voiceGuidanceEnabled,
    required this.spotify,
    required this.onToggleSheet,
    required this.onAddStop,
    required this.onCancelAddStop,
    required this.onOverview,
    required this.onRepeatDirection,
    required this.onVoiceGuidanceChanged,
    required this.onStopNavigation,
    required this.onPreviousSpotify,
    required this.onToggleSpotify,
    required this.onNextSpotify,
    required this.onOpenSpotify,
    required this.onConnectSpotify,
    required this.onOpenSettings,
  });

  final ScrollController scrollController;
  final String destinationName;
  final double? distanceMeters;
  final DateTime? estimatedArrivalTime;
  final bool addingStop;
  final bool voiceGuidanceEnabled;
  final SpotifyPlayerState spotify;
  final VoidCallback onToggleSheet;
  final VoidCallback onAddStop;
  final VoidCallback onCancelAddStop;
  final VoidCallback onOverview;
  final VoidCallback onRepeatDirection;
  final ValueChanged<bool> onVoiceGuidanceChanged;
  final VoidCallback onStopNavigation;
  final VoidCallback onPreviousSpotify;
  final VoidCallback onToggleSpotify;
  final VoidCallback onNextSpotify;
  final VoidCallback onOpenSpotify;
  final VoidCallback onConnectSpotify;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      key: const ValueKey('navigation-sheet-scroll'),
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                key: const ValueKey('navigation-sheet-handle'),
                behavior: HitTestBehavior.opaque,
                onTap: onToggleSheet,
                child: SizedBox(
                  height: 32,
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        destinationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
              _tripSummary(context),
              const Divider(height: 12),
              _spotifyShortcut(context),
              const Divider(height: 24),
              if (addingStop) ...[
                Container(
                  key: const ValueKey('add-stop-map-prompt'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_location_alt,
                          color: scheme.onTertiaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tap the map to place the stop. Route updates after you choose it.',
                          style: TextStyle(color: scheme.onTertiaryContainer),
                        ),
                      ),
                      TextButton(
                        onPressed: onCancelAddStop,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _navigationActions(context),
              const Divider(height: 28),
              OutlinedButton.icon(
                key: const ValueKey('navigation-settings-button'),
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Settings'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('navigation-stop-button'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                ),
                onPressed: onStopNavigation,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop navigation'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripSummary(BuildContext context) {
    final eta = estimatedArrivalTime;
    final timeLeft = eta?.difference(DateTime.now());
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          Expanded(
            child: _NavigationMetric(
              label: 'TIME LEFT',
              value: timeLeft == null ? '--' : _formatTimeRemaining(timeLeft),
            ),
          ),
          const VerticalDivider(width: 20, indent: 6, endIndent: 6),
          Expanded(
            child: _NavigationMetric(
              label: 'ETA',
              value: eta == null ? '--' : _formatEta(eta),
            ),
          ),
          const VerticalDivider(width: 20, indent: 6, endIndent: 6),
          Expanded(
            child: _NavigationMetric(
              label: 'MILES LEFT',
              value: distanceMeters == null
                  ? '--'
                  : _formatMilesRemaining(distanceMeters!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spotifyShortcut(BuildContext context) {
    if (!spotify.connected) {
      return SizedBox(
        height: 52,
        child: Row(
          children: [
            const _SpotifyBrandIcon(size: 36),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spotify',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('Connect for ride controls'),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: spotify.busy ? null : onConnectSpotify,
              child: const Text('Connect'),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          InkWell(
            onTap: onOpenSpotify,
            borderRadius: BorderRadius.circular(4),
            child: _SpotifyArtwork(url: spotify.albumArtUrl, size: 48),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spotify.trackName ?? 'Open Spotify to play',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  spotify.artistName ??
                      (spotify.hasActiveDevice
                          ? 'Spotify connected'
                          : 'No active player'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onOpenSpotify,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: _SpotifyBrandIcon(size: 24),
            ),
          ),
          const SizedBox(width: 6),
          if (spotify.canSkipPrevious)
            IconButton(
              tooltip: 'Previous track',
              onPressed: spotify.busy ? null : onPreviousSpotify,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.skip_previous),
            ),
          IconButton.filled(
            tooltip: spotify.isPlaying ? 'Pause' : 'Play',
            onPressed: spotify.busy || !spotify.canTogglePlayback
                ? null
                : onToggleSpotify,
            visualDensity: VisualDensity.compact,
            icon: spotify.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(spotify.isPlaying ? Icons.pause : Icons.play_arrow),
          ),
          if (spotify.canSkipNext)
            IconButton(
              tooltip: 'Next track',
              onPressed: spotify.busy ? null : onNextSpotify,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.skip_next),
            ),
        ],
      ),
    );
  }

  Widget _navigationActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 10) / 2;
        Widget action({
          Key? key,
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          bool emphasized = false,
        }) {
          final button = emphasized
              ? FilledButton.tonalIcon(
                  key: key,
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                )
              : OutlinedButton.icon(
                  key: key,
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                        label == 'Voice on' ? scheme.primaryContainer : null,
                  ),
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                );
          return SizedBox(width: buttonWidth, height: 50, child: button);
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            action(
              key: const ValueKey('navigation-add-stop'),
              icon: addingStop ? Icons.close : Icons.add_location_alt_outlined,
              label: addingStop ? 'Cancel stop' : 'Add stop',
              onPressed: addingStop ? onCancelAddStop : onAddStop,
              emphasized: true,
            ),
            action(
              icon: Icons.route_outlined,
              label: 'Route overview',
              onPressed: onOverview,
            ),
            action(
              icon: Icons.volume_up_outlined,
              label: 'Repeat direction',
              onPressed: onRepeatDirection,
            ),
            action(
              icon: voiceGuidanceEnabled
                  ? Icons.record_voice_over
                  : Icons.voice_over_off_outlined,
              label: voiceGuidanceEnabled ? 'Voice on' : 'Voice off',
              onPressed: () => onVoiceGuidanceChanged(!voiceGuidanceEnabled),
            ),
          ],
        );
      },
    );
  }
}

class _NavigationMetric extends StatelessWidget {
  const _NavigationMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _NoticeStack extends StatelessWidget {
  const _NoticeStack({required this.notices, required this.onDismissed});

  final List<_PlannerNotice> notices;
  final ValueChanged<int> onDismissed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final notice in notices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _NoticeCard(
                    key: ValueKey(notice.id),
                    notice: notice,
                    onDismissed: () => onDismissed(notice.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.onDismissed,
    super.key,
  });

  final _PlannerNotice notice;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, accent) = switch (notice.tone) {
      _NoticeTone.info => (
          Icons.info_outline,
          scheme.primary,
        ),
      _NoticeTone.warning => (
          Icons.warning_amber_rounded,
          scheme.tertiary,
        ),
      _NoticeTone.error => (
          Icons.error_outline,
          scheme.error,
        ),
    };

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(12 * (1 - progress), 0),
          child: child,
        ),
      ),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.97),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: accent.withValues(alpha: 0.42)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 5, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                ),
                child: SizedBox.square(
                  dimension: 28,
                  child: Icon(icon, color: accent, size: 17),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  notice.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismissed,
                color: scheme.onSurfaceVariant,
                iconSize: 17,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
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

String _formatMilesRemaining(double meters) {
  final miles = math.max(0, meters) / 1609.344;
  return '${miles.toStringAsFixed(miles >= 10 ? 0 : 1)} mi';
}

String _formatEta(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _formatTimeRemaining(Duration duration) {
  final minutes = math.max(0, (duration.inSeconds / 60).ceil());
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
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

String _formatSavedDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$month/$day/${local.year}';
}

double degreesToRadians(double value) => value * math.pi / 180;

double radiansToDegrees(double value) => value * 180 / math.pi;

bool acceptsMapDrop({
  required bool navigating,
  required bool addingNavigationStop,
}) {
  return !navigating || addingNavigationStop;
}

bool shouldShowNavigationRecenter({
  required bool navigating,
  required bool following,
}) {
  return navigating && !following;
}

double plannedRouteLiveViewExtent({
  required double viewportHeight,
  required double bottomPadding,
  required double collapsedSheetHeight,
  required double maxExtent,
}) {
  final safeHeight = math.max(1.0, viewportHeight);
  final minExtent = ((collapsedSheetHeight + bottomPadding) / safeHeight)
      .clamp(0.09, 0.42)
      .toDouble();
  return math.min(
    maxExtent,
    math.max(minExtent, math.min(0.68, 520 / safeHeight)),
  );
}
