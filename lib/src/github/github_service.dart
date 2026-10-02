import 'dart:convert';
import 'dart:math';

import 'package:flutter_system_integration/src/config.dart';
import 'package:flutter_system_integration/src/log.dart';
import 'package:flutter_system_integration/src/version/version_repository.dart';
import 'package:http/http.dart' as http;

final _log = createLogger("GitHubService");

class GitHubRateLimitMaxRetriesExceeded implements Exception {
  @override
  String toString() => "GitHub: rate limit max retries exceeded";
}

class GitHubUnexpectedStatusCode implements Exception {
  final int status;

  GitHubUnexpectedStatusCode(this.status);

  @override
  String toString() => "GitHub: unexpected status code: $status";
}

class GitHubService {
  static const _maxRetries = 5;

  final http.Client _http;

  final Uri _apiBaseUri;
  final Uri _webBaseUri;

  final SystemIntegrationConfig _config;

  GitHubService({
    required this._config,
    http.Client? httpClient,
    String apiBaseUri = "https://api.github.com",
    String webBaseUri = "https://github.com",
  }) : _http = httpClient ?? http.Client(),
       _apiBaseUri = Uri.parse(apiBaseUri),
       _webBaseUri = Uri.parse(webBaseUri);

  Future<String> get userAgent async =>
      "${_config.appName} v${await VersionRepository.getCurrentVersion()}";

  /// Returns the tag names of the repository.
  ///
  /// Returns null if GitHub answers with `304 Not Modified`.
  Future<List<String>?> getRepositoryTagNames({
    required String owner,
    required String repo,
    int? pageSize,
    int? page,
  }) async {
    final json = await _requestJson(
      "GET",
      "/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}/tags",
      queryParameters: {
        if (pageSize != null) "per_page": pageSize.toString(),
        if (page != null) "page": page.toString(),
      },
    );
    if (json == null) return null;
    return (json as List<dynamic>)
        .map((t) => (t as Map<String, dynamic>)["name"] as String)
        .toList();
  }

  Uri generateReleaseDownloadLink({
    required String owner,
    required String repo,
    required String tag,
    required String fileName,
  }) {
    return _webBaseUri.resolveUri(
      Uri(pathSegments: [owner, repo, "releases", "download", tag, fileName]),
    );
  }

  Future<dynamic> _requestJson(
    String method,
    String path, {
    Map<String, String> queryParameters = const {},
  }) async {
    final url = _apiBaseUri.resolveUri(
      Uri(path: path, queryParameters: queryParameters),
    );
    final userAgent = await this.userAgent;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      _log.finest("GitHub request: $method $url");
      final request = http.Request(method, url)
        ..headers.addAll({
          "Accept": "application/vnd.github+json",
          // https://docs.github.com/en/rest/about-the-rest-api/api-versions?apiVersion=2022-11-28#supported-api-versions
          "X-GitHub-Api-Version": "2022-11-28",
          "User-Agent": userAgent,
        });
      final response = await http.Response.fromStream(
        await _http.send(request),
      );
      if (response.statusCode == 429 ||
          (response.statusCode == 403 &&
              response.headers["x-ratelimit-remaining"] == "0")) {
        _log.fine("GitHub rate limit exceeded");
        if (attempt == _maxRetries) break;
        final delay = _retryDelay(response.headers["x-ratelimit-reset"]);
        _log.fine("Retrying GitHub request in ${delay.inSeconds} seconds");
        await Future.delayed(delay);
        continue;
      }
      if (response.statusCode == 304) {
        return null;
      }
      if (response.statusCode >= 300) {
        throw GitHubUnexpectedStatusCode(response.statusCode);
      }
      return jsonDecode(response.body);
    }
    throw GitHubRateLimitMaxRetriesExceeded();
  }

  Duration _retryDelay(String? rateLimitResetHeader) {
    final reset = int.tryParse(rateLimitResetHeader ?? "");
    if (reset == null) {
      _log.warning(
        "GitHub invalid x-ratelimit-reset header: $rateLimitResetHeader",
      );
      return const Duration(seconds: 60);
    }
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Duration(seconds: max(0, reset - nowSeconds) + 1);
  }
}
