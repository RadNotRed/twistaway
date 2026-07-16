enum ServiceConnectionMode {
  automatic,
  apiOnly,
  directProviders,
}

extension ServiceConnectionModeLabel on ServiceConnectionMode {
  String get label => switch (this) {
        ServiceConnectionMode.automatic => 'Automatic',
        ServiceConnectionMode.apiOnly => 'Twistaway API',
        ServiceConnectionMode.directProviders => 'Direct providers',
      };

  String get description => switch (this) {
        ServiceConnectionMode.automatic =>
          'Use the API first, then connect directly if it is unavailable.',
        ServiceConnectionMode.apiOnly =>
          'Always use the Twistaway API for search and route planning.',
        ServiceConnectionMode.directProviders =>
          'Bypass the API and connect to routing and search providers directly.',
      };
}
