/// Parses [url] as a base for resolving relative paths. Without a trailing
/// slash the last path segment would be replaced on resolution.
Uri parseBaseUri(String url) {
  final uri = Uri.parse(url);
  return uri.path.endsWith("/") ? uri : uri.replace(path: "${uri.path}/");
}
