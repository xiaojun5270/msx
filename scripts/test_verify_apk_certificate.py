import unittest
from pathlib import Path

from verify_apk_certificate import verify_report


class CertificateVerificationTests(unittest.TestCase):
    expected = '2cb4707f6c8a31f042c05177c10d5c6de717fed00c61b542a15de175e3cc56de'
    other = 'a' * 64

    def test_actual_failed_github_build_report(self):
        # Downloaded from the apk-signing-diagnostics artifact of:
        # https://github.com/xiaojun5270/msx/actions/runs/37627587520
        report = (Path(__file__).parent / 'fixtures/apksigner-run-37627587520.txt').read_text()
        self.assertEqual(verify_report(report, self.expected), self.expected)

    def test_scheme_prefixed_signers(self):
        for label in ['V1 Signer:', 'V2 Signer:', 'V3 Signer:', 'V3.1 Signer:',
                      'V3.2 Signer:', 'V4 Signer:', 'V2 Signer #1:',
                      'V3.1 Signer (minSdkVersion=33, maxSdkVersion=99):']:
            with self.subTest(label=label):
                self.assertEqual(verify_report(
                    f'{label} certificate SHA-256 digest: {self.expected}',
                    self.expected,
                ), self.expected)

    def test_additional_scheme_certificate_must_also_match(self):
        with self.assertRaisesRegex(ValueError, 'Release certificate mismatch'):
            verify_report('\n'.join([
                f'V2 Signer: certificate SHA-256 digest: {self.expected}',
                f'V3 Signer: certificate SHA-256 digest: {self.other}',
            ]), self.expected)

    def test_scheme_public_key_is_not_a_certificate(self):
        with self.assertRaisesRegex(ValueError, 'No APK signer'):
            verify_report(f'V2 Signer: public key SHA-256 digest: {self.expected}', self.expected)

    def test_numbered_signer(self):
        self.assertEqual(verify_report(
            f'Verifies\nSigner #1 certificate SHA-256 digest: {self.expected}\n',
            self.expected + '\n',
        ), self.expected)

    def test_v31_sdk_range_labels_can_repeat_the_same_certificate(self):
        report = '\n'.join([
            f'Signer (minSdkVersion=33, maxSdkVersion=2147483647) certificate SHA-256 digest: {self.expected}',
            f'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: {self.expected}',
        ])
        self.assertEqual(verify_report(report, self.expected), self.expected)

    def test_dev_release_range_and_colon_separated_uppercase(self):
        formatted = ':'.join(self.expected[i:i+2].upper() for i in range(0, 64, 2))
        self.assertEqual(verify_report(
            f'Signer (minSdkVersion=33 (dev release=true), maxSdkVersion=99) certificate SHA-256 digest: {formatted}\r\n',
            self.expected,
        ), self.expected)

    def test_ignores_public_key_and_source_stamp_hashes(self):
        report = '\n'.join([
            f'Signer #1 certificate SHA-256 digest: {self.expected}',
            f'Signer #1 public key SHA-256 digest: {self.other}',
            f'Source Stamp Signer certificate SHA-256 digest: {self.other}',
        ])
        self.assertEqual(verify_report(report, self.expected), self.expected)

    def test_missing_signer_is_a_distinct_error(self):
        with self.assertRaisesRegex(ValueError, 'No APK signer'):
            verify_report(f'Signer #1 public key SHA-256 digest: {self.expected}', self.expected)

    def test_wrong_certificate_remains_blocked(self):
        with self.assertRaisesRegex(ValueError, 'Release certificate mismatch'):
            verify_report(f'Signer #1 certificate SHA-256 digest: {self.other}', self.expected)

    def test_additional_unexpected_signer_remains_blocked(self):
        with self.assertRaisesRegex(ValueError, 'Release certificate mismatch'):
            verify_report('\n'.join([
                f'Signer #1 certificate SHA-256 digest: {self.expected}',
                f'Signer #2 certificate SHA-256 digest: {self.other}',
            ]), self.expected)

    def test_rotated_certificate_remains_blocked(self):
        with self.assertRaisesRegex(ValueError, 'Release certificate mismatch'):
            verify_report('\n'.join([
                f'Signer (minSdkVersion=33, maxSdkVersion=99) certificate SHA-256 digest: {self.expected}',
                f'Signer (minSdkVersion=24, maxSdkVersion=32) certificate SHA-256 digest: {self.other}',
            ]), self.expected)

    def test_invalid_pin_is_blocked(self):
        for pin in ['', 'not-a-fingerprint', 'a' * 63]:
            with self.subTest(pin=pin), self.assertRaisesRegex(ValueError, 'Invalid SHA-256'):
                verify_report(f'Signer #1 certificate SHA-256 digest: {self.expected}', pin)


if __name__ == '__main__':
    unittest.main()
