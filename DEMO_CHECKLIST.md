# ViraNari V1.4.1 demo checklist

## Backend
- [ ] `/health` returns version `1.4.1`
- [ ] Both test accounts can log in
- [ ] Trusted Circle relationship is active

## Live map
- [ ] Map tab renders OpenStreetMap tiles
- [ ] SOS creates an active emergency
- [ ] sender marker/trail appears on Map
- [ ] responder Map/Track view follows the victim
- [ ] stationary victim stays LIVE because heartbeat continues
- [ ] walking changes marker/trail and distance travelled

## SMS
- [ ] physical Android phone, not emulator
- [ ] `Prepare SMS` requests SMS permission
- [ ] diagnostics says SEND_SMS is declared
- [ ] diagnostics says permission granted
- [ ] SIM ready
- [ ] default SMS SIM selected
- [ ] accepted Trusted Circle phone number is cached
- [ ] TEST SMS succeeds before relying on outage fallback

## Safety Presence
- [ ] enable Nearby on Phone A
- [ ] enable Nearby on Phone B
- [ ] both broadcast anonymously
- [ ] each phone sees the other as a dot
- [ ] test also works when both phones use the same account

## Connectivity
- [ ] active SOS online -> LIVE
- [ ] data off -> last-known marker retained
- [ ] GPS points continue queueing locally
- [ ] data on -> queue replays and LIVE returns
