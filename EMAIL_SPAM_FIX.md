# Email Spam Issue - DKIM Signing Fix

## Problem
Emails sent from mailcow were going directly to recipients' spam folders because they lacked proper DKIM signatures.

**Rspamd Error:**
```
signing failure: cannot make request to load DKIM selector for domain risewithcode.com: nil
```

## Root Cause
The DKIM private keys exist on the filesystem (`/var/lib/rspamd/dkim/`) but Rspamd is configured to load them from Redis. The keys were never loaded into Redis, so outgoing emails couldn't be signed with DKIM.

## Solution Applied

### ✅ Step 1: Loaded DKIM Keys into Redis
Executed the helper script that:
1. Found DKIM keys in `/var/lib/rspamd/dkim/risewithcode.com.dkim.key`
2. Loaded them into Redis with proper keys:
   - `DKIM_PRIV_KEYS(risewithcode.com,dkim)` - Private key
   - `DKIM_SELECTORS(risewithcode.com)` - Selector (dkim)
3. Restarted Rspamd to pick up the new Redis configuration

**Helper Script:** [helper-scripts/load-dkim-keys.sh](helper-scripts/load-dkim-keys.sh)

### ✅ Step 2: Verified Keys are Accessible
```bash
Redis Keys Loaded:
  ✓ DKIM_PRIV_KEYS(risewithcode.com,dkim)
  ✓ DKIM_SELECTORS(risewithcode.com)
```

## What This Fixes

### Email Authentication Headers
Outgoing emails will now include proper DKIM signatures:
```
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=risewithcode.com;
  s=dkim; h=from:sender:reply-to:subject:date:message-id:to:cc:mime-version:
  content-type:content-transfer-encoding;
  bh=....; b=....
```

### Email Deliverability
- **Reduced spam folder placement** - Properly signed emails score better
- **Improved sender reputation** - Yahoo, Gmail, and other ISPs check DKIM signatures
- **Authentication framework** - DKIM proves the email wasn't forged

## Testing the Fix

### 1. Send a Test Email
```bash
# Login to SOGo as support@risewithcode.com
# Send an email to an external Gmail/Outlook account
# Check if it arrives in Inbox (not spam)
```

### 2. Verify DKIM Signature
In Gmail:
1. Open the received email
2. Click the dropdown arrow → "Show original"
3. Look for the `DKIM-Signature` header at the top
4. Should see: `dkim=pass` in the authentication results

### 3. Check Logs
```bash
# Monitor Rspamd for successful DKIM signing
docker logs mailcowdockerized-rspamd-mailcow-1 -f | grep DKIM_SIGNED
```

## Database Content

### Redis Configuration
The DKIM keys are now stored in Redis:

```
DKIM_SELECTORS(risewithcode.com) = "dkim"
DKIM_PRIV_KEYS(risewithcode.com,dkim) = [RSA private key]
```

### Rspamd Configuration
File: [data/conf/rspamd/local.d/dkim_signing.conf](data/conf/rspamd/local.d/dkim_signing.conf)
- `use_redis = true` - Keys stored in Redis
- `sign_authenticated = true` - Sign authenticated user emails
- `sign_local = true` - Sign local emails
- `sign_networks = /etc/rspamd/custom/dovecot_trusted.map` - Sign from Dovecot

## For New Domains

When you add new domains to mailcow:

1. **Automatic DKIM Key Generation** - Mailcow automatically generates DKIM keys
2. **Manual Redis Loading** - Run the helper script:
   ```bash
   ./helper-scripts/load-dkim-keys.sh
   ```
3. **Or via Mailcow Web UI** - Regenerate domain DKIM keys to trigger automatic loading

## Troubleshooting

### Emails Still Going to Spam
1. **Check SPF Record:**
   ```bash
   nslookup -type=TXT risewithcode.com mail
   # Should contain: v=spf1 mx ~all
   ```

2. **Check DMARC Policy:**
   ```bash
   nslookup -type=TXT _dmarc.risewithcode.com
   # Should be set appropriately
   ```

3. **Verify DKIM Selector:**
   ```bash
   nslookup -type=TXT dkim._domainkey.risewithcode.com mail
   # Should return the public key record
   ```

4. **Check Rspamd Logs:**
   ```bash
   docker logs mailcowdockerized-rspamd-mailcow-1 | grep "signing failure"
   ```

### Manual DKIM Key Reload
If DKIM signing still fails:

```bash
# Reload DKIM keys into Redis
./helper-scripts/load-dkim-keys.sh

# Restart Rspamd
docker exec mailcowdockerized-rspamd-mailcow-1 pkill -HUP rspamd
```

## DNS Records Required

For proper email authentication, ensure these DNS records exist:

1. **SPF Record** (TXT record on risewithcode.com):
   ```
   v=spf1 mx ~all
   ```

2. **DKIM Public Key** (TXT record on dkim._domainkey.risewithcode.com):
   ```
   v=DKIM1; k=rsa; p=<public-key-from-mailcow>
   ```

3. **DMARC Policy** (TXT record on _dmarc.risewithcode.com):
   ```
   v=DMARC1; p=quarantine; rua=mailto:postmaster@risewithcode.com
   ```

## Details

### Postfix Configuration
- **Milter:** Rspamd is configured as a Postfix milter on port 9900
- **Protocol:** SMTP milter protocol version 6
- **Action:** Adds DKIM signature headers to outgoing mail

### Rspamd Configuration
- **Mechanism:** DKIM signing via `dkim_signing.lua`
- **Storage:** Redis with key prefixes for private keys and selectors
- **Signing Policy:** All outbound emails are candidate for signing
- **Authentication:** Already authenticated users (via password) are always signed

## Related Files
- [data/conf/postfix/main.cf](data/conf/postfix/main.cf) - line 145-147 (milter config)
- [data/conf/rspamd/local.d/dkim_signing.conf](data/conf/rspamd/local.d/dkim_signing.conf) - DKIM configuration
- [helper-scripts/load-dkim-keys.sh](helper-scripts/load-dkim-keys.sh) - DKIM key loader script
