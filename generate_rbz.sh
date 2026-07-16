#!/bin/bash
set -e
NAME="DetailSimple"
ZIPNAME="${NAME}.zip"
RBZNAME="${NAME}.rbz"
cd "$(dirname "$0")"
rm -f "$ZIPNAME" "$RBZNAME"
zip -r "$ZIPNAME" "${NAME}.rb" "${NAME}"
mv "$ZIPNAME" "$RBZNAME"
echo "Criado: $RBZNAME"
