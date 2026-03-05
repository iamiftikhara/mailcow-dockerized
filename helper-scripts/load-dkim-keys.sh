#!/bin/bash
#
# Load DKIM keys from filesystem into Redis
# This fixes the Rspamd error: "cannot make request to load DKIM selector"
#

set -e

REDIS_PASS=$(grep "^REDISPASS=" /root/projects/mailcow-dockerized/mailcow.conf | cut -d'=' -f2)
REDIS_CONTAINER="mailcowdockerized-redis-mailcow-1"
RSPAMD_CONTAINER="mailcowdockerized-rspamd-mailcow-1"

echo "🔧 Loading DKIM keys into Redis..."

# Get all domains that have DKIM keys
DOMAINS=$(docker exec $RSPAMD_CONTAINER find /var/lib/rspamd/dkim -name "*.dkim.key" -type f 2>/dev/null | sed 's|.*/||g' | sed 's/\.dkim\.key//g')

if [ -z "$DOMAINS" ]; then
    echo "❌ No DKIM keys found in /var/lib/rspamd/dkim/"
    exit 1
fi

for DOMAIN in $DOMAINS; do
    echo "Processing domain: $DOMAIN"
    
    # Read private key
    PRIV_KEY=$(docker exec $RSPAMD_CONTAINER cat "/var/lib/rspamd/dkim/${DOMAIN}.dkim.key")
    
    # Read public key (extract just the p= value)
    PUB_KEY=$(docker exec $RSPAMD_CONTAINER cat "/var/lib/rspamd/dkim/${DOMAIN}.dkim.pub" | tr '\n' ' ')
    
    # Get selector (usually 'dkim')
    SELECTOR="dkim"
    
    # Load into Redis
    docker exec $REDIS_CONTAINER redis-cli -a $REDIS_PASS \
        --no-auth-warning \
        SET "DKIM_PRIV_KEYS(${DOMAIN},${SELECTOR})" "$PRIV_KEY" > /dev/null 2>&1
    
    docker exec $REDIS_CONTAINER redis-cli -a $REDIS_PASS \
        --no-auth-warning \
        SET "DKIM_SELECTORS(${DOMAIN})" "${SELECTOR}" > /dev/null 2>&1
    
    echo "  ✓ Loaded DKIM key for $DOMAIN (selector: $SELECTOR)"
done

echo ""
echo "✅ DKIM keys loaded into Redis successfully!"
echo ""
echo "Testing DKIM signing..."

# Restart Rspamd to reload configuration
docker exec $RSPAMD_CONTAINER pkill -HUP rspamd 2>/dev/null || true
sleep 2

echo "✅ Rspamd restarted"
