import 'package:flutter_system_integration/flutter_system_integration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse', () {
    test('full versions', () {
      expect(
        Version.parse("1.2.3"),
        const Version(major: 1, minor: 2, patch: 3),
      );
      expect(
        Version.parse("v1.2.3"),
        const Version(major: 1, minor: 2, patch: 3),
      );
      expect(Version.parse("1.2"), const Version(major: 1, minor: 2));
      expect(Version.parse("1"), const Version(major: 1));
      expect(
        Version.parse("1.2.3+45"),
        const Version(major: 1, minor: 2, patch: 3),
      );
    });

    test('prereleases', () {
      expect(Version.parse("1.2.3-beta.1").isFullVersion, isFalse);
      expect(Version.parse("1.2-rc").isFullVersion, isFalse);
    });

    test('invalid versions throw', () {
      expect(() => Version.parse("abc"), throwsA(isA<InvalidVersion>()));
      expect(() => Version.parse("1.2.3.4"), throwsA(isA<InvalidVersion>()));
      expect(() => Version.parse(""), throwsA(isA<InvalidVersion>()));
    });
  });

  group('compare', () {
    const v123 = Version(major: 1, minor: 2, patch: 3);
    const v124pre = Version(major: 1, minor: 2, patch: 4, isFullVersion: false);
    const v123pre = Version(major: 1, minor: 2, patch: 3, isFullVersion: false);

    test('basic ordering', () {
      expect(const Version(major: 2) > v123, isTrue);
      expect(v123 < const Version(major: 1, minor: 3), isTrue);
      expect(v123 >= v123, isTrue);
      expect(v123 <= v123, isTrue);
    });

    test('full version is greater than its prerelease', () {
      expect(v123 > v123pre, isTrue);
      expect(v123pre < v123, isTrue);
    });

    test('lower full version is not greater than higher prerelease', () {
      expect(v123 > v124pre, isFalse);
      expect(v123 < v124pre, isTrue);
      expect(v124pre < v123, isFalse);
    });

    test('compareTo sorts', () {
      final list = [v124pre, v123, v123pre]..sort();
      expect(list, [v123pre, v123, v124pre]);
    });
  });

  test('json round trip', () {
    const v = Version(major: 1, minor: 2, patch: 3, isFullVersion: false);
    expect(Version.fromJson(v.toJson()), v);
    expect(Version.fromJson({"major": 4}), const Version(major: 4));
  });
}
