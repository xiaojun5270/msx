"""Provision a reusable PKCS12 signing key and encrypted GitHub Actions secrets.

Requires OpenSSL and PyNaCl. Private material stays outside the checkout; only
the public certificate fingerprint is tracked. Existing keys are never rotated.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import urllib.request


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, check=False, **kwargs)
    if result.returncode:
        # Do not echo subprocess arguments/output that may contain credentials.
        raise RuntimeError(f'{Path(command[0]).name} failed with exit code {result.returncode}')
    return result.stdout


def github_headers():
    raw = run(['git', 'credential', 'fill'],
              input=b'protocol=https\nhost=github.com\n\n')
    credentials = dict(line.split('=', 1) for line in raw.decode().splitlines() if '=' in line)
    return {
        'Authorization': 'Bearer ' + credentials['password'],
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'MusicX-signing-setup',
    }


def request(url, headers, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers,
                                 method='GET' if data is None else 'PUT')
    with urllib.request.urlopen(req, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openssl', default='openssl')
    parser.add_argument('--backup-dir', type=Path, required=True)
    parser.add_argument('--repo', default='xiaojun5270/msx')
    parser.add_argument('--upload', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    backup = args.backup_dir.resolve()
    if backup == root or root in backup.parents:
        raise RuntimeError('Store the signing backup outside the checkout.')
    fingerprint_file = root / 'android/signing-certificate.sha256'
    keystore = backup / 'musix-release.p12'
    credentials_file = backup / 'signing-credentials.json'

    if keystore.exists() != credentials_file.exists():
        raise RuntimeError('Incomplete signing backup: restore the missing file; do not rotate the key.')
    if fingerprint_file.exists() and not keystore.exists():
        raise RuntimeError('A release certificate is already pinned. Restore its backup instead of generating another key.')

    backup.mkdir(parents=True, exist_ok=True)
    if not keystore.exists():
        password = secrets.token_urlsafe(36)
        env = dict(os.environ, MUSIX_SIGNING_PASSWORD=password)
        with tempfile.TemporaryDirectory(prefix='musix-signing-') as temp:
            key = str(Path(temp) / 'encrypted-key.pem')
            cert = str(Path(temp) / 'certificate.pem')
            run([args.openssl, 'req', '-x509', '-newkey', 'rsa:3072',
                 '-sha256', '-days', '10950', '-keyout', key, '-out', cert,
                 '-passout', 'env:MUSIX_SIGNING_PASSWORD',
                 '-subj', '/CN=MusicX Android Release/O=MusicX'], env=env)
            run([args.openssl, 'pkcs12', '-export', '-name', 'musix',
                 '-inkey', key, '-in', cert, '-out', str(keystore),
                 '-passin', 'env:MUSIX_SIGNING_PASSWORD',
                 '-passout', 'env:MUSIX_SIGNING_PASSWORD'], env=env)
        credentials = {'alias': 'musix', 'password': password}
        credentials_file.write_text(json.dumps(credentials), encoding='utf-8')
        keystore.chmod(0o600)
        credentials_file.chmod(0o600)
    else:
        credentials = json.loads(credentials_file.read_text(encoding='utf-8'))

    env = dict(os.environ, MUSIX_SIGNING_PASSWORD=credentials['password'])
    cert_pem = run([args.openssl, 'pkcs12', '-in', str(keystore),
                   '-clcerts', '-nokeys', '-passin', 'env:MUSIX_SIGNING_PASSWORD'], env=env)
    cert_der = run([args.openssl, 'x509', '-outform', 'DER'], input=cert_pem)
    fingerprint = hashlib.sha256(cert_der).hexdigest()
    if fingerprint_file.exists() and fingerprint_file.read_text().strip() != fingerprint:
        raise RuntimeError('The backup does not match the pinned release certificate.')
    fingerprint_file.write_text(fingerprint + '\n', encoding='ascii')
    (backup / 'certificate.sha256').write_text(fingerprint + '\n', encoding='ascii')

    # This generated local file is ignored by Git; passwords are never printed.
    properties = root / 'android/key.properties'
    if not properties.exists():
        properties.write_text(
            f'storeFile={keystore.as_posix()}\n'
            f'storePassword={credentials["password"]}\n'
            f'keyAlias={credentials["alias"]}\n'
            f'keyPassword={credentials["password"]}\n', encoding='ascii')
        properties.chmod(0o600)

    if args.upload:
        from nacl.public import PublicKey, SealedBox
        headers = github_headers()
        api = f'https://api.github.com/repos/{args.repo}/actions/secrets'
        values = {
            'ANDROID_KEYSTORE_BASE64': base64.b64encode(keystore.read_bytes()).decode(),
            'ANDROID_KEYSTORE_PASSWORD': credentials['password'],
            'ANDROID_KEY_ALIAS': credentials['alias'],
            'ANDROID_KEY_PASSWORD': credentials['password'],
        }
        existing = request(api + '?per_page=100', headers)
        conflicts = {secret['name'] for secret in existing['secrets']} & values.keys()
        if conflicts:
            raise RuntimeError('Signing secrets already exist; refusing to overwrite them.')
        public = request(api + '/public-key', headers)
        box = SealedBox(PublicKey(base64.b64decode(public['key'])))
        for name, value in values.items():
            request(api + '/' + name, headers, {
                'key_id': public['key_id'],
                'encrypted_value': base64.b64encode(box.encrypt(value.encode())).decode(),
            })
        uploaded = request(api + '?per_page=100', headers)
        if not values.keys() <= {secret['name'] for secret in uploaded['secrets']}:
            raise RuntimeError('Signing secret verification failed.')
        print('Configured and verified four GitHub Actions signing secrets.')

    print(f'Signing backup: {backup}')
    print(f'Certificate SHA-256: {fingerprint}')


if __name__ == '__main__':
    main()
