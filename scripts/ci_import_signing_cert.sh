#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Imports the App Intents signing identity into a temporary keychain on a CI
# runner. Reads BUILD_CERTIFICATE_BASE64, P12_PASSWORD and KEYCHAIN_PASSWORD.

set -euo pipefail

CERT_PATH="$RUNNER_TEMP/build_certificate.p12"
KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o "$CERT_PATH"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH"
security find-identity -p codesigning -v
