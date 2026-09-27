/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

import '../../i18n/i18n.dart';

class LocaleInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final locale = activeLocale.value;

    if (locale != null && !options.headers.containsKey('Accept-Language')) {
      options.headers['Accept-Language'] = locale.toLanguageTag();
    }

    handler.next(options);
  }
}
