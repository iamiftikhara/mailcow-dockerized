# Mailbox Email Sending Issue - Fix Documentation

## Problem Summary

When mailboxes try to send emails via SOGo or other mail clients, they may receive the error:

```
Sender address rejected: not owned by user [mailbox@domain.com] - [recipient@external.com]
```

**Status Code:** 405 Method Not Allowed / SMTP 550/553

**Root Cause:** Mailboxes were missing the `sender_allowed=1` flag in the `alias` table, which is required by Postfix's sender address validation (`smtpd_sender_restrictions` with `reject_authenticated_sender_login_mismatch`).

## How It Works

Mailcow uses Postfix's sender validation system, which queries the database to determine if a user is allowed to send from a specific email address. The query checks:

1. **Alias table** - If the address is an alias with `sender_allowed='1'`
2. **Sender ACL table** - If there's an explicit sender_acl entry allowing it
3. **Mailbox address** - If it's the user's own mailbox address (via alias)

**The Bug:** When creating a new mailbox, an alias entry was created pointing to itself for forwarding purposes, but it was missing:
- `sender_allowed = 1` - Required to allow sending from this address
- `sogo_visible = 1` - Required to show in SOGo's address list

## Solution Applied

### 1. Fixed Existing Mailboxes ✅

All existing mailboxes in your `risewithcode.com` domain now have sendable aliases:

| Email Address | Status |
|---|---|
| admin@risewithcode.com | ✓ Configured with sender_allowed=1 |
| ceo@risewithcode.com | ✓ Configured with sender_allowed=1 |
| contact@risewithcode.com | ✓ Configured with sender_allowed=1 |
| info@risewithcode.com | ✓ Configured with sender_allowed=1 |
| noreply@risewithcode.com | ✓ Configured with sender_allowed=1 |
| support@risewithcode.com | ✓ Configured with sender_allowed=1 |

### 2. Fixed the Mailbox Creation Code ✅

Modified [data/web/inc/functions.mailbox.inc.php](data/web/inc/functions.mailbox.inc.php#L1287-L1294) to automatically create aliases with `sender_allowed=1`:

**Before:**
```php
$stmt = $pdo->prepare("INSERT INTO `alias` (`address`, `goto`, `domain`, `active`)
  VALUES (:username1, :username2, :domain, :active)");
```

**After:**
```php
$stmt = $pdo->prepare("INSERT INTO `alias` (`address`, `goto`, `domain`, `active`, `sender_allowed`, `sogo_visible`)
  VALUES (:username1, :username2, :domain, :active, 1, 1)");
```

**Effect:** All new mailboxes created after this fix will be able to send emails immediately.

### 3. Created Helper Script ✅

A utility script was created to automatically fix any mailboxes that may have been created before this fix.

**Location:** [helper-scripts/fix-mailbox-sender-aliases.sh](helper-scripts/fix-mailbox-sender-aliases.sh)

**Usage:**
```bash
# Fix all mailboxes in all domains
./helper-scripts/fix-mailbox-sender-aliases.sh

# Fix mailboxes in specific domain only
./helper-scripts/fix-mailbox-sender-aliases.sh risewithcode.com
```

## Technical Details

### Database Queries

The Postfix sender validation is controlled by `smtpd_sender_login_maps` in [data/conf/postfix/sql/mysql_virtual_sender_acl.cf](data/conf/postfix/sql/mysql_virtual_sender_acl.cf).

This query returns allowed sender addresses for a given authenticated user. Without the `sender_allowed=1` flag, the query doesn't return the mailbox address as an allowed sender.

### Affected Components

- **Postfix:** Uses `smtpd_sender_login_maps` to validate sender addresses
- **SOGo:** Needs `sogo_visible=1` to display addresses in the compose window
- **Dovecot:** Provides SMTP authentication
- **Mailcow Web UI:** Manages mailbox and alias creation

## Testing

To verify the fix is working:

1. **Login to SOGo** with a mailbox account (e.g., support@risewithcode.com)
2. **Create a new draft** email
3. **Check the "From:" dropdown** - you should see your mailbox address listed
4. **Send the email** - it should succeed without 405/SMTP rejection errors

### Database Check

```bash
# Verify the alias was created with sender_allowed=1
docker exec -i mailcowdockerized-mysql-mailcow-1 mysql -u mailcow -p$(grep DBPASS=/root/projects/mailcow-dockerized/mailcow.conf | cut -d= -f2) mailcow <<EOF
SELECT address, goto, sender_allowed, sogo_visible FROM alias WHERE address='support@risewithcode.com';
EOF
```

Expected output:
```
address                    | goto                      | sender_allowed | sogo_visible
support@risewithcode.com   | support@risewithcode.com  | 1              | 1
```

## Future Improvements

For complete automation, consider:

1. **Add database migration** to automatically add missing flags to all alias tables
2. **Add UI validation** to warn about aliases without sender_allowed=1
3. **Add monitoring** to alert if mailboxes lose their sendable aliases

## References

- [Mailcow Email Alias Documentation](https://github.com/mailcow/mailcow-dockerized)
- [Postfix SASL Authentication](http://www.postfix.org/SASL_README.html)
- [Postfix Sender Restrictions](http://www.postfix.org/postconf.5.html#smtpd_sender_restrictions)
- [SOGo Mail Configuration](https://sogo.nu/files/communications/SOGo-2.3.13-mail_configuration.pdf)

## Support

If mailboxes still can't send emails after applying this fix:

1. Verify Postfix is reloaded: `docker exec mailcowdockerized-postfix-mailcow-1 postfix reload`
2. Check mail logs: `docker logs mailcowdockerized-postfix-mailcow-1`
3. Run the helper script: `./helper-scripts/fix-mailbox-sender-aliases.sh`
4. Verify database entries match the query above
