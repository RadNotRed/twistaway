import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import 'google_dark_layers.dart';

/// Custom map themes for MotoPlanner.
class MapThemes {
  MapThemes._();

  static final _builder = const ProtomapsThemes(
    sprites: 'https://protomaps.github.io/basemaps-assets/sprites/v4/dark',
  );

  /// Google Maps-inspired dark theme using remapped Protomaps v4 colors.
  ///
  /// Dark gray/blue tones instead of the stock black/purple palette.
  static dynamic googleDark() => _builder.build(googleMapsDarkLayers);
}
