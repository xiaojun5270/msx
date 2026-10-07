"""Check every APK signer against the pinned certificate after apksigner verify.

Recent build-tools print SDK-range labels for v3.1 signers instead of `Signer #1`.
Never include public-key hashes or a source-stamp certificate in this comparison.
"""

import argparse
from pathlib import Path
import re
import sys


def normalize_fingerprint(value):
    fingerprint = re.sub(r'[:\s]', '', value).lower()
    if not re.fullmatch(r'[0-9a-f]{64}', fingerprint):
        raise ValueError('Invalid SHA-256 certificate fingerprint (expected 64 hex digits).')
    return fingerprint


def verify_report(report, expected):
    expected = normalize_fingerprint(expected)
    signers = re.findall(
        r'^\s*Signer (?:#\d+|\([^\r\n]+\)) certificate SHA-256 digest:\s*([^\r\n]+)',
        report, re.MULTILINE,
    )
    if not signers:
        raise ValueError('No APK signer certificate found in apksigner output. See the certificate report.')
    actual = {normalize_fingerprint(value) for value in signers}
    if actual != {expected}:
        raise ValueError(
            f'Release certificate mismatch. Expected: {expected}; '
            f'APK certificate(s): {", ".join(sorted(actual))}. APK will not be published.'
        )
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('fingerprint', type=Path)
    args = parser.parse_args()
    try:
        fingerprint = verify_report(
            args.report.read_text(encoding='utf-8'),
            args.fingerprint.read_text(encoding='utf-8'),
        )
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f'Verified release certificate SHA-256: {fingerprint}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
