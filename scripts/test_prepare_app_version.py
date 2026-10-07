import unittest

from prepare_app_version import build_version


class AppVersionTests(unittest.TestCase):
    def version(self, run):
        return build_version('version: 0.7.8+1\n', 'versionCodeOffset=42\n', run)

    def test_first_new_release_still_upgrades_previous_version_code(self):
        version = self.version(43)
        self.assertEqual(version['APP_DISPLAY_VERSION'], '0.7.8(001)')
        self.assertEqual(int(version['APP_BUILD_SEQUENCE']) + 42, 43)

    def test_next_build_and_retry(self):
        self.assertEqual(self.version(44)['APP_DISPLAY_VERSION'], '0.7.8(002)')
        self.assertEqual(self.version(44), self.version(44))

    def test_padding_and_large_sequences(self):
        self.assertEqual(self.version(52)['APP_DISPLAY_VERSION'], '0.7.8(010)')
        self.assertEqual(self.version(1042)['APP_DISPLAY_VERSION'], '0.7.8(1000)')

    def test_rejects_stale_or_invalid_android_build_numbers(self):
        for run in [0, 42, 2100000001]:
            with self.subTest(run=run), self.assertRaises(ValueError):
                self.version(run)

    def test_reads_major_version_from_pubspec(self):
        self.assertEqual(build_version('version: 0.7.9+1', 'versionCodeOffset=42', 45)
                         ['APP_DISPLAY_VERSION'], '0.7.9(003)')


if __name__ == '__main__':
    unittest.main()
