"""Derive the APK/UI version from the stable GitHub workflow run number."""

import argparse
import os
from pathlib import Path
import re


def build_version(pubspec, properties, run_number):
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$', pubspec, re.MULTILINE)
    offset = re.search(r'^versionCodeOffset=(\d+)\s*$', properties, re.MULTILINE)
    if version is None or offset is None:
        raise ValueError('Missing or invalid app version configuration.')
    sequence = run_number - int(offset[1])
    if sequence < 1 or run_number > 2100000000:
        raise ValueError('Build number is outside the Android version range or predates the version baseline.')
    return {
        'APP_BUILD_NAME': version[1],
        'APP_BUILD_SEQUENCE': str(sequence),
        'APP_DISPLAY_VERSION': f'{version[1]}({sequence:03d})',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-number', required=True, type=int)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    values = build_version(
        (root / 'pubspec.yaml').read_text(encoding='utf-8'),
        (root / 'android/version.properties').read_text(encoding='utf-8'),
        args.run_number,
    )
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as output:
            output.write(''.join(f'{key}={value}\n' for key, value in values.items()))
    print(f'App version: {values["APP_DISPLAY_VERSION"]}; Android versionCode: {args.run_number}')


if __name__ == '__main__':
    main()
