import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const _connectionTimeout = Duration(seconds: 30);

http.Client createHttpClient() =>
    IOClient(HttpClient()..connectionTimeout = _connectionTimeout);
