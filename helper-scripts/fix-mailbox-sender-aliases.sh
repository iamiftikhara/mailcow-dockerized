#!/bin/bash
#
# Fix Mailbox Sender Aliases
# 
# This script ensures all mailboxes have corresponding aliases with sender_allowed=1
# which is required for those mailboxes to send emails in mailcow.
#
# The issue: When mailboxes are created, they may not automatically get an alias
# entry with sender_allowed=1, causing Postfix to reject emails from those addresses
# with error: "Sender address rejected: not owned by user"
#
# Usage: ./fix-mailbox-sender-aliases.sh [domain]
#        - If no domain specified, fixes all domains
#

set -e

cd "$(dirname "$0")/../"

# Get database credentials from mailcow.conf
DB_USER=$(grep "^DBUSER=" mailcow.conf | cut -d'=' -f2)
DB_PASS=$(grep "^DBPASS=" mailcow.conf | cut -d'=' -f2)
DB_NAME=$(grep "^DBNAME=" mailcow.conf | cut -d'=' -f2)

MYSQL_CMD="docker exec -i mailcowdockerized-mysql-mailcow-1 mysql -u $DB_USER -p$DB_PASS $DB_NAME"

echo "🔧 Fixing mailbox sender aliases..."
echo ""

# Get the domain to process
if [ -n "$1" ]; then
    DOMAIN_FILTER="AND domain='$1'"
    echo "Processing domain: $1"
else
    DOMAIN_FILTER=""
    echo "Processing all domains..."
fi

# Find all mailboxes that don't have an alias entry with sender_allowed=1
$MYSQL_CMD <<EOF | while read LINE; do
    if [ -z "$LINE" ] || [ "$LINE" = "username" ]; then
        continue
    fi
    
    USERNAME=\$(echo "$LINE" | awk '{print \$1}')
    DOMAIN=\$(echo "$LINE" | awk '{print \$2}')
    
    if [ -z "\$USERNAME" ] || [ -z "\$DOMAIN" ]; then
        continue
    fi
    
    EMAIL="\${USERNAME}@\${DOMAIN}"
    
    # Check if alias already exists
    ALIAS_EXISTS=\$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM alias WHERE address='$EMAIL' AND sender_allowed='1';" 2>/dev/null)
    
    if [ "\$ALIAS_EXISTS" -eq 0 ]; then
        echo "  ✓ Creating sendable alias for: \$EMAIL"
        $MYSQL_CMD <<SQLEOF 2>/dev/null
INSERT INTO alias (address, goto, domain, active, sender_allowed, sogo_visible) 
VALUES ('\$EMAIL', '\$EMAIL', '\$DOMAIN', 1, 1, 1)
ON DUPLICATE KEY UPDATE sender_allowed=1;
SQLEOF
    else
        echo "  ✓ Already configured: \$EMAIL"
    fi
done

SELECT username, domain FROM mailbox 
WHERE NOT EXISTS (
    SELECT 1 FROM alias WHERE address=CONCAT(mailbox.username,'@',mailbox.domain) AND sender_allowed='1'
) $DOMAIN_FILTER
ORDER BY username;
EOF

echo ""
echo "✅ Reloading Postfix configuration..."
docker exec mailcowdockerized-postfix-mailcow-1 postfix reload > /dev/null 2>&1

echo "✅ All done! Mailboxes can now send emails."
echo ""
