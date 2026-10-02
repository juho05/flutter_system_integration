class InvalidVersion implements Exception {
  final String version;

  const InvalidVersion(this.version);

  @override
  String toString() => "InvalidVersion: $version";
}

class Version implements Comparable<Version> {
  final int major;
  final int minor;
  final int patch;

  final bool isFullVersion;

  const Version({
    required this.major,
    this.minor = 0,
    this.patch = 0,
    this.isFullVersion = true,
  });

  factory Version.parse(String version) {
    var v = version.trim();
    if (v.startsWith("v") && v.length > 1) {
      v = v.substring(1);
    }
    v = v.split("+")[0];
    final prereleaseIndex = v.indexOf("-");
    final core = prereleaseIndex == -1 ? v : v.substring(0, prereleaseIndex);
    final parts = core.split(".");
    if (parts.length > 3) {
      throw InvalidVersion(version);
    }
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((n) => n == null || n < 0)) {
      throw InvalidVersion(version);
    }
    return Version(
      major: numbers[0]!,
      minor: numbers.length > 1 ? numbers[1]! : 0,
      patch: numbers.length > 2 ? numbers[2]! : 0,
      isFullVersion: prereleaseIndex == -1,
    );
  }

  bool operator >(Version other) {
    if (major > other.major) return true;
    if (major < other.major) return false;
    if (minor > other.minor) return true;
    if (minor < other.minor) return false;
    if (patch > other.patch) return true;
    if (patch < other.patch) return false;
    return isFullVersion && !other.isFullVersion;
  }

  bool operator <(Version other) => other > this;

  bool operator >=(Version other) => !(this < other);

  bool operator <=(Version other) => !(this > other);

  @override
  bool operator ==(Object other) {
    if (other is! Version) return false;
    return major == other.major &&
        minor == other.minor &&
        patch == other.patch &&
        isFullVersion == other.isFullVersion;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch, isFullVersion);

  @override
  int compareTo(Version other) {
    if (this == other) return 0;
    return this < other ? -1 : 1;
  }

  @override
  String toString() {
    final v = "$major.$minor.$patch";
    if (isFullVersion) return v;
    return "$v-prerelease";
  }

  factory Version.fromJson(Map<String, dynamic> json) => Version(
    major: (json["major"] as num).toInt(),
    minor: (json["minor"] as num?)?.toInt() ?? 0,
    patch: (json["patch"] as num?)?.toInt() ?? 0,
    isFullVersion: json["isFullVersion"] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    "major": major,
    "minor": minor,
    "patch": patch,
    "isFullVersion": isFullVersion,
  };
}
