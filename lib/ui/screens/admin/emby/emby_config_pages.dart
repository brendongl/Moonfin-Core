import 'package:flutter/material.dart';

import '../admin_search_index.dart';
import 'admin_config_form.dart';
import 'admin_emby_transcoding_screen.dart';

const _toggle = AdminConfigKind.toggle;
const _number = AdminConfigKind.number;
const _path = AdminConfigKind.path;
const _list = AdminConfigKind.list;

final databasePage = AdminConfigPage(
  id: 'database',
  title: (l) => l.adminDrawerDatabase,
  icon: Icons.storage_outlined,
  warning: (l) => l.adminDatabaseWarning,
  sections: [
    AdminConfigSection((l) => l.adminDrawerDatabase, Icons.storage_outlined, [
      AdminConfigField(
        'DatabaseCacheSizeMB',
        _number,
        (l) => l.adminDatabaseCacheSize,
        help: (l) => l.adminDatabaseCacheSizeHelp,
        min: 64,
      ),
      AdminConfigField(
        'OptimizeDatabaseOnShutdown',
        _toggle,
        (l) => l.adminDatabaseOptimize,
        help: (l) => l.adminDatabaseOptimizeHelp,
      ),
      AdminConfigField(
        'DatabaseAnalysisLimit',
        _number,
        (l) => l.adminDatabaseAnalysisLimit,
        help: (l) => l.adminDatabaseAnalysisLimitHelp,
        min: 400,
      ),
      AdminConfigField(
        'VacuumDatabaseOnStartup',
        _toggle,
        (l) => l.adminDatabaseVacuum,
        help: (l) => l.adminDatabaseVacuumHelp,
      ),
    ]),
  ],
);

final cinemaIntrosPage = AdminConfigPage(
  id: 'cinema-intros',
  namedKey: 'cinemamode',
  title: (l) => l.adminDrawerCinemaIntros,
  icon: Icons.theaters_outlined,
  premiere: true,
  sections: [
    AdminConfigSection(
      (l) => l.adminCinemaIntrosPlayBefore,
      Icons.play_circle_outline,
      [
        AdminConfigField('EnableIntrosForMovies', _toggle, (l) => l.movies),
        AdminConfigField('EnableIntrosForEpisodes', _toggle, (l) => l.episodes),
        AdminConfigField(
          'EnableIntrosForWatchedContent',
          _toggle,
          (l) => l.adminCinemaIntrosUnwatchedOnly,
          inverted: true,
        ),
      ],
    ),
    AdminConfigSection((l) => l.trailers, Icons.movie_outlined, [
      AdminConfigField(
        'EnableIntrosFromUpcomingTrailers',
        _toggle,
        (l) => l.adminCinemaIntrosUpcoming,
      ),
      AdminConfigField(
        'EnableIntrosFromSimilarMovies',
        _toggle,
        (l) => l.adminCinemaIntrosOlder,
      ),
      AdminConfigField(
        'EnableIntrosFromMoviesInLibrary',
        _toggle,
        (l) => l.adminCinemaIntrosLibrary,
        help: (l) => l.adminCinemaIntrosLibraryHelp,
      ),
      AdminConfigField(
        'MaximizeRandomization',
        _toggle,
        (l) => l.adminCinemaIntrosSimilarOnly,
        help: (l) => l.adminCinemaIntrosSimilarOnlyHelp,
        inverted: true,
      ),
      AdminConfigField(
        'EnableIntrosParentalControl',
        _toggle,
        (l) => l.adminCinemaIntrosParental,
        help: (l) => l.adminCinemaIntrosParentalHelp,
      ),
      AdminConfigField(
        'TrailerLimit',
        _number,
        (l) => l.adminCinemaIntrosCount,
      ),
    ]),
    AdminConfigSection(
      (l) => l.adminCinemaIntrosCustom,
      Icons.folder_outlined,
      [
        AdminConfigField(
          'CustomIntroPath',
          _path,
          (l) => l.adminCinemaIntrosCustomPath,
          help: (l) => l.adminCinemaIntrosCustomPathHelp,
        ),
        AdminConfigField(
          'MediaInfoIntroPath',
          _path,
          (l) => l.adminCinemaIntrosCodecPath,
          help: (l) => l.adminCinemaIntrosCodecPathHelp,
        ),
      ],
    ),
  ],
);

final dlnaPage = AdminConfigPage(
  id: 'dlna',
  namedKey: 'dlna',
  title: (l) => l.adminDrawerDlna,
  icon: Icons.cast_outlined,
  sections: [
    AdminConfigSection((l) => l.adminDrawerDlna, Icons.cast_outlined, [
      AdminConfigField(
        'EnablePlayTo',
        _toggle,
        (l) => l.adminDlnaPlayTo,
        help: (l) => l.adminDlnaPlayToHelp,
      ),
      AdminConfigField(
        'EnableServer',
        _toggle,
        (l) => l.adminDlnaServer,
        help: (l) => l.adminDlnaServerHelp,
      ),
      AdminConfigField(
        'DefaultUserId',
        AdminConfigKind.user,
        (l) => l.adminDlnaDefaultUser,
        help: (l) => l.adminDlnaDefaultUserHelp,
      ),
      AdminConfigField(
        'EnableDebugLog',
        _toggle,
        (l) => l.adminDlnaDebugLog,
        help: (l) => l.adminDlnaDebugLogHelp,
      ),
    ]),
  ],
);

final cameraUploadPage = AdminConfigPage(
  id: 'camera-upload',
  namedKey: 'devices',
  title: (l) => l.adminDrawerCameraUpload,
  icon: Icons.photo_camera_outlined,
  premiere: true,
  sections: [
    AdminConfigSection(
      (l) => l.adminDrawerCameraUpload,
      Icons.photo_camera_outlined,
      [
        AdminConfigField(
          'CameraUploadPath',
          _path,
          (l) => l.adminCameraUploadPath,
          help: (l) => l.adminCameraUploadPathHelp,
        ),
        AdminConfigField(
          'EnableCameraUploadSubfolders',
          _toggle,
          (l) => l.adminCameraUploadSubfolders,
        ),
      ],
    ),
  ],
);

final conversionsPage = AdminConfigPage(
  id: 'conversions',
  namedKey: 'sync',
  title: (l) => l.adminDrawerConversions,
  icon: Icons.sync_outlined,
  premiere: true,
  sections: [
    AdminConfigSection((l) => l.adminDrawerConversions, Icons.sync_outlined, [
      AdminConfigField(
        'TemporaryPath',
        _path,
        (l) => l.adminConversionsTempPath,
        help: (l) => l.adminConversionsTempPathHelp,
      ),
      AdminConfigField(
        'EnableFullSpeedTranscoding',
        _toggle,
        (l) => l.adminConversionsFullSpeed,
        help: (l) => l.adminConversionsFullSpeedHelp,
      ),
    ]),
  ],
);

/// Emby keeps these in the base configuration under its own names.
final embyNetworkingPage = AdminConfigPage(
  id: 'networking',
  title: (l) => l.adminNetworkingTitle,
  icon: Icons.lan_outlined,
  warning: (l) => l.adminNetworkingRestartWarning,
  sections: [
    AdminConfigSection(
      (l) => l.adminNetworkingSectionServerAddress,
      Icons.dns_outlined,
      [
        AdminConfigField(
          'LocalNetworkSubnets',
          _list,
          (l) => l.adminNetworkingLocalSubnets,
          help: (l) => l.adminNetworkingLanNetworksHelp,
        ),
        AdminConfigField(
          'LocalNetworkAddresses',
          _list,
          (l) => l.adminNetworkingLocalAddress,
          help: (l) => l.adminNetworkingLocalAddressHelp,
        ),
        AdminConfigField(
          'HttpServerPortNumber',
          _number,
          (l) => l.adminNetworkingLocalHttpPort,
          help: (l) => l.adminNetworkingLocalHttpPortHelp,
          min: 1,
          max: 65535,
        ),
        AdminConfigField(
          'HttpsPortNumber',
          _number,
          (l) => l.adminNetworkingLocalHttpsPort,
          help: (l) => l.adminNetworkingLocalHttpsPortHelp,
          min: 1,
          max: 65535,
        ),
      ],
    ),
    AdminConfigSection(
      (l) => l.adminNetworkingSectionHttps,
      Icons.lock_outline,
      [
        AdminConfigField(
          'EnableHttps',
          _toggle,
          (l) => l.adminNetworkingEnableHttps,
          help: (l) => l.adminNetworkingEnableHttpsHelp,
        ),
        AdminConfigField(
          'RequireHttps',
          _toggle,
          (l) => l.adminNetworkingRequireHttps,
          help: (l) => l.adminNetworkingRequireHttpsHint,
        ),
        AdminConfigField(
          'IsBehindProxy',
          _toggle,
          (l) => l.adminNetworkingBehindProxy,
        ),
        AdminConfigField(
          'CertificatePath',
          AdminConfigKind.file,
          (l) => l.adminNetworkingCustomCertPath,
          help: (l) => l.adminNetworkingCertPathHelp,
        ),
        AdminConfigField(
          'CertificatePassword',
          AdminConfigKind.password,
          (l) => l.adminNetworkingCertPassword,
          help: (l) => l.adminNetworkingCertPasswordHelp,
        ),
      ],
    ),
    AdminConfigSection(
      (l) => l.adminNetworkingSectionRemoteAccess,
      Icons.public,
      [
        AdminConfigField(
          'EnableRemoteAccess',
          _toggle,
          (l) => l.adminNetworkingAllowRemote,
          help: (l) => l.adminNetworkingAllowRemoteHelp,
        ),
        AdminConfigField(
          'RemoteIPFilter',
          _list,
          (l) => l.adminNetworkingRemoteIpFilterLabel,
          help: (l) => l.adminNetworkingRemoteIpFilterHelp,
        ),
        AdminConfigField(
          'IsRemoteIPFilterBlacklist',
          AdminConfigKind.choice,
          (l) => l.adminNetworkingRemoteIpFilterMode,
          choices: [
            (false, (l) => l.adminNetworkingWhitelist),
            (true, (l) => l.adminNetworkingBlacklist),
          ],
        ),
        AdminConfigField(
          'PublicPort',
          _number,
          (l) => l.adminNetworkingPublicHttpPort,
          help: (l) => l.adminNetworkingPublicHttpPortHelp,
          min: 1,
          max: 65535,
        ),
        AdminConfigField(
          'PublicHttpsPort',
          _number,
          (l) => l.adminNetworkingPublicHttpsPort,
          help: (l) => l.adminNetworkingPublicHttpsPortHelp,
          min: 1,
          max: 65535,
        ),
        AdminConfigField(
          'WanDdns',
          AdminConfigKind.text,
          (l) => l.adminNetworkingExternalDomain,
          help: (l) => l.adminNetworkingExternalDomainHelp,
        ),
        AdminConfigField(
          'EnableUPnP',
          _toggle,
          (l) => l.adminNetworkingUpnp,
          help: (l) => l.adminNetworkingUpnpHelp,
        ),
      ],
    ),
    AdminConfigSection((l) => l.adminNetworkingSectionFirewall, Icons.link, [
      AdminConfigField(
        'ProxyHeaderMode',
        AdminConfigKind.choice,
        (l) => l.adminNetworkingProxyHeaders,
        help: (l) => l.adminNetworkingProxyHeadersHelp,
        choices: [
          ('None', (l) => l.no),
          ('RemoteAddressesOnly', (l) => l.adminNetworkingProxyHeadersRemote),
          ('AllAddresses', (l) => l.yes),
        ],
      ),
      AdminConfigField(
        'DisableOutgoingIPv6',
        _toggle,
        (l) => l.adminNetworkingIpv4Only,
        help: (l) => l.adminNetworkingIpv4OnlyHelp,
      ),
    ]),
  ],
);

final embyConfigPages = [
  databasePage,
  cinemaIntrosPage,
  dlnaPage,
  cameraUploadPage,
  conversionsPage,
  embyNetworkingPage,
];

/// Pages both servers have that Emby builds its own way, so the Jellyfin
/// search rows don't apply there.
const embyOwnPages = {'transcoding', 'networking'};

/// The search rows only Emby has.
final List<AdminSearchEntry> embySearchEntries = [
  for (final page in embyConfigPages) ...page.searchEntries,
  ...embyTranscodingSearchEntries,
  adminSettingRow(
    'streaming',
    'SimultaneousStreamLimit',
    (l) => l.adminStreamingStreamLimit,
    (l) => l.general,
  ),
];
