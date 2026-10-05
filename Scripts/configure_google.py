#!/usr/bin/python3
"""Configure the public iOS OAuth client ID and its redirect URL scheme."""
import argparse
import plistlib
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('client_id', help='Google OAuth client ID of type iOS (not web or Android)')
parser.add_argument('--plist', type=Path, default=Path(__file__).resolve().parents[1] / 'SenseVoiceApp/Info.plist')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_-]+\.apps\.googleusercontent\.com', args.client_id):
    parser.error('Expected an iOS client ID ending in .apps.googleusercontent.com')
with args.plist.open('rb') as source:
    info = plistlib.load(source)
info['GIDClientID'] = args.client_id
scheme = '.'.join(reversed(args.client_id.split('.')))
types = [item for item in info.get('CFBundleURLTypes', []) if item.get('CFBundleURLName') != 'GoogleSignIn']
types.append({'CFBundleURLName': 'GoogleSignIn', 'CFBundleURLSchemes': [scheme]})
info['CFBundleURLTypes'] = types
with args.plist.open('wb') as target:
    plistlib.dump(info, target, sort_keys=False)
print('Configured Google iOS Client ID and callback scheme. Rebuild the app in Xcode.')
