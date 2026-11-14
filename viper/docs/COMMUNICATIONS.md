# Email, SMS and notifications

VIPER never sends an external message until you set up the channel, and outgoing email/SMS to
anyone other than yourself is always shown to you for approval first.

## Email accounts

*Communications → Mail → Add account*.

**Gmail with an app password (simplest).** Turn on 2-Step Verification, create an app password at
<https://myaccount.google.com/apppasswords>, choose provider *Gmail* and paste it.

**Gmail or Outlook with OAuth (no password stored).** VIPER uses the official desktop OAuth flow
(Authorization Code + PKCE, loopback redirect). You need your own OAuth client ID:

- Google: Cloud Console → APIs & Services → Credentials → *Create OAuth client ID* → type
  *Desktop app*. Add the scope `https://mail.google.com/` to the consent screen and your account as
  a test user.
- Microsoft: Entra admin center → App registrations → *New registration* → platform *Mobile and
  desktop applications* with redirect `http://localhost`, allow public client flows, and add
  delegated permissions `IMAP.AccessAsUser.All`, `SMTP.Send`, `offline_access`.

Enter the client ID in VIPER (*Comms → Mail* account → *Sign in*; the client ID is stored
encrypted), then sign in in your browser. VIPER keeps only the encrypted refresh token.

**Any other provider:** choose *IMAP/SMTP* and enter the server names and an app password.

Then add yourself in *Recipients* and tick *This is me*; email notifications and reports go there.

## SMS

- **Through your phone:** pair VIPER Mobile, enable *Settings → SMS bridge* in the app and grant
  the SMS permission. Each message is shown on the phone for approval. Carrier rates apply.
- **Twilio:** enter Account SID, sending number and auth token (*Comms → Notifications → SMS*).
  Twilio charges per message.

## Push notifications

- **VIPER Mobile:** delivered over the encrypted link while the phone is connected (enable *Stay
  connected* in the app to receive them in the background). Missed notifications are fetched on
  reconnect.
- **ntfy (optional):** for alerts away from home without a VPN, set an ntfy server and secret topic.
  Messages pass through that server.

## Rules

Quiet hours, emergency mute, categories, default channels, rate limit (external messages per
hour), retry attempts and full delivery history live in *Communications → Notifications*. Each
automation can choose its own channels.
