/*
 * Copyright Krafter SAS <developer@krafter.io>
 * MIT License (see LICENSE file).
 */

import 'package:dio/dio.dart';

/// Off the web there is no CORS, so there is no warning to silence.
void silenceCorsWarning(Dio dio) {}
