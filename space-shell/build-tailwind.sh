#!/bin/bash
# Prebuilds the full Tailwind v4 base (scanning all Construct space sources) +
# the @construct-space/ui stylesheet into the app resources. Spaces then don't
# need to ship Tailwind — the desktop provides it.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bunx @tailwindcss/cli -i "$DIR/tailwind-base.css" -o /tmp/construct-tw.css --minify
cat /tmp/construct-tw.css "$DIR/node_modules/@construct-space/ui/dist/style.css" \
  > "$DIR/../App/Construct/Resources/spaceshell/base.css"
echo "base.css: $(wc -c < "$DIR/../App/Construct/Resources/spaceshell/base.css") bytes"
