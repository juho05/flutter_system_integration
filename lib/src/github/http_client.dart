import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _connectionTimeout = Duration(seconds: 30);

http.Client createHttpClient() => kIsWeb
    ? http.Client()
    : IOClient(HttpClient()..connectionTimeout = _connectionTimeout);
