#!/usr/bin/env bash
# Publish a built site directory to S3 and, optionally, refresh CloudFront.
# The same script is used for the Floci rehearsal and for production.
#
# Usage: scripts/deploy-site.sh <site-dir>
#
# Required env: BUCKET, VERSION
# Optional env: DISTRIBUTION_ID  invalidate this CloudFront distribution and wait
#               SITE_URL         also verify the public URL serves this VERSION
set -euo pipefail

site_dir="${1:?usage: deploy-site.sh <site-dir>}"
: "${BUCKET:?BUCKET is required}" "${VERSION:?VERSION is required}"

[ -f "$site_dir/index.html" ] || { echo "No index.html in $site_dir" >&2; exit 1; }

# Marker file used to verify that the deployed version is the expected one.
echo "$VERSION" > "$site_dir/version.txt"

echo "==> Uploading $site_dir to s3://$BUCKET (version $VERSION)"

# 1. Hashed build assets never change, so they can be cached forever. Old ones
#    are kept on purpose: visitors holding a cached index.html still need them.
if [ -d "$site_dir/assets" ]; then
  aws s3 sync "$site_dir/assets" "s3://$BUCKET/assets" \
    --cache-control "public,max-age=31536000,immutable"
fi

# 2. Other static files keep their names between builds: short cache, and
#    remove whatever no longer exists.
aws s3 sync "$site_dir" "s3://$BUCKET" --delete \
  --exclude "assets/*" --exclude "index.html" --exclude "version.txt" \
  --cache-control "public,max-age=3600"

# 3. Entry points go last, so the site only switches once everything it
#    references is already in place.
for f in index.html version.txt; do
  aws s3 cp "$site_dir/$f" "s3://$BUCKET/$f" --cache-control "no-cache"
done

if [ -n "${DISTRIBUTION_ID:-}" ]; then
  echo "==> Invalidating CloudFront distribution $DISTRIBUTION_ID"
  invalidation_id=$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" --paths "/*" \
    --query 'Invalidation.Id' --output text)
  aws cloudfront wait invalidation-completed \
    --distribution-id "$DISTRIBUTION_ID" --id "$invalidation_id"
fi

echo "==> Verifying"
stored=$(aws s3 cp "s3://$BUCKET/version.txt" - | tr -d '[:space:]')
if [ "$stored" != "$VERSION" ]; then
  echo "Bucket holds version '$stored', expected '$VERSION'" >&2
  exit 1
fi

if [ -n "${SITE_URL:-}" ]; then
  for attempt in $(seq 1 20); do
    live=$(curl -fsS "${SITE_URL%/}/version.txt?v=$VERSION" 2>/dev/null | tr -d '[:space:]' || true)
    if [ "$live" = "$VERSION" ]; then
      echo "$SITE_URL is serving $VERSION"
      exit 0
    fi
    echo "Attempt $attempt: $SITE_URL serves '${live:-nothing}', waiting..."
    sleep 6
  done
  echo "$SITE_URL did not serve $VERSION in time" >&2
  exit 1
fi

echo "Deployed $VERSION to s3://$BUCKET"
