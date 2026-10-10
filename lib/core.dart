/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

/// Everything flutter_fastedgy.dart gives (the client, the api models, the
/// realtime socket, the i18n, the images, the storage), without Material and
/// without Cupertino: an application drawn on the widgets layer alone imports
/// this one, and compiles nothing of Material coming from the package.
///
/// Its `context.fastEdgyLocalizationDelegates` leaves out the localizations
/// of Material and Cupertino, which `material.dart` and `cupertino.dart`
/// give an application that draws them. Import this one or
/// flutter_fastedgy.dart, not both.
library;

export 'src/initializer.dart';

export 'src/app_info/app_info.dart';

export 'src/container/container.dart'
    show container, initializeContainer, getService, hasService;

export 'src/bus/bus.dart';
export 'src/bus/events.dart';

export 'src/logging/logging.dart';

export 'package:logging/logging.dart' show Level, Logger, LogRecord;

export 'src/i18n/i18n.dart';

export 'package:flutter/widgets.dart' show Locale;
export 'package:easy_localization/easy_localization.dart'
    show StringTranslateExtension, BuildContextEasyLocalizationExtension;

export 'src/fetcher/fetcher.dart';

export 'package:dio/dio.dart' show Response, ResponseType;

export 'src/auth/auth.dart';

export 'src/api/api.dart';

export 'src/metadata/metadata.dart';

export 'src/sync/sync_status.dart';

export 'src/offline/offline.dart';

export 'src/realtime/origin.dart';
export 'src/realtime/realtime_events.dart';
export 'src/realtime/realtime_socket.dart';
export 'src/realtime/resource_relay.dart';
export 'src/realtime/resource_watch.dart';

export 'src/image/image.dart';

export 'src/storage/storage.dart';
