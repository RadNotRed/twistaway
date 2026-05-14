class RoutePreference {
  const RoutePreference({
    required this.key,
    required this.label,
    required this.description,
    required this.value,
    this.isToggle = false,
  });

  final String key;
  final String label;
  final String description;
  final double value;
  final bool isToggle;

  RoutePreference copyWith({double? value}) => RoutePreference(
        key: key,
        label: label,
        description: description,
        value: value ?? this.value,
        isToggle: isToggle,
      );
}

const defaultPreferences = [
  RoutePreference(
    key: 'twisty',
    label: 'Twists and turns',
    description: 'Favor technical roads and interesting curves.',
    value: 0.75,
  ),
  RoutePreference(
    key: 'scenic',
    label: 'Scenic views',
    description: 'Prefer overlooks, water, forests, ridgelines, and parks.',
    value: 0.7,
  ),
  RoutePreference(
    key: 'avoidHighways',
    label: 'Avoid highways',
    description: 'Bias toward secondary roads.',
    value: 1,
    isToggle: true,
  ),
  RoutePreference(
    key: 'avoidMainRoads',
    label: 'Backroads',
    description: 'Strongly prefer local and county roads over major arterials.',
    value: 1,
    isToggle: true,
  ),
  RoutePreference(
    key: 'pureBackroads',
    label: 'Pure backroads',
    description:
        'Aggressively avoid highways, arterials, parkways, and direct main-road corridors.',
    value: 0,
    isToggle: true,
  ),
  RoutePreference(
    key: 'autoScenicDetour',
    label: 'Auto scenic detour',
    description:
        'Allow a less direct route when scenic and backroad scores are high.',
    value: 1,
    isToggle: true,
  ),
  RoutePreference(
    key: 'targetHighways',
    label: 'Target highways',
    description: 'Useful for making time between better riding segments.',
    value: 0,
    isToggle: true,
  ),
  RoutePreference(
    key: 'targetStraightRoads',
    label: 'Target straight roads',
    description: 'Prefer simpler, direct roads when the ride needs to be calm.',
    value: 0,
    isToggle: true,
  ),
  RoutePreference(
    key: 'avoidGravel',
    label: 'Avoid gravel',
    description: 'Keep routes friendlier to street tires.',
    value: 1,
    isToggle: true,
  ),
  RoutePreference(
    key: 'weatherAware',
    label: 'Weather aware',
    description:
        'Penalize rain, strong wind, poor visibility, and storm cells.',
    value: 1,
    isToggle: true,
  ),
  RoutePreference(
    key: 'fuelStops',
    label: 'Fuel stops',
    description: 'Add stops based on tank range.',
    value: 1,
    isToggle: true,
  ),
];
