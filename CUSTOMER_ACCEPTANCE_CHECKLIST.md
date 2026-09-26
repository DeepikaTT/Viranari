# ViraNari V1.6.0 Customer Acceptance Checklist

- [ ] V1.4.4 Home/Circle/Inbox/History experience remains recognizable.
- [ ] Trusted Circle and consent flow still work.
- [ ] New registration collects a valid international-format mobile number.
- [ ] Existing users can add/edit their number from Circle.
- [ ] Trusted contact numbers are visible only after acceptance.
- [ ] Call trusted opens the selected contact in the system dialer.
- [ ] Emergency services opens the configured emergency number in the system dialer.
- [ ] SMS fallback opens the normal Messages app with current emergency information prefilled.
- [ ] No Android SEND_SMS permission is requested.
- [ ] Trusted phone numbers remain available from encrypted cache during an API outage after at least one successful Circle sync.
- [ ] Live-location timeline still shows all server-stored records.
- [ ] Offline GPS journal uses SQLite and does not stop after 120 points.
- [ ] Reconnect replay preserves original timestamps.
- [ ] Verified Help does not block SOS/Trusted Circle when no responder is available.
- [ ] Incident record shows human-readable actions and cryptographic verification.
- [ ] Incident record does not falsely label an opened dialer as a completed call or a prepared SMS as delivered.
