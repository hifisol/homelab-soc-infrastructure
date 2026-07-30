# Lab Notes — Defender for Endpoint P2

Working log for validating MDE P2 tooling in the lab before it moves into the client-facing `hifisol/defender-endpoint-p2` repo. Add an entry per test session; keep it dated.

## Open items

- [ ] Get a lab/dev MDE P2 tenant licensed (or confirm which tenant to test against)
- [ ] Run `onboard-linux.yml` against a lab endpoint end-to-end, confirm `mdatp health` reports healthy
- [ ] Confirm sensor shows Active in the Defender portal within 15 minutes of onboarding
- [ ] Test ASR rules in audit mode against normal lab endpoint usage, check for false positives
- [ ] Register a lab Azure AD app, pull an advanced hunting query via Graph API (see client repo's `graph-api/README.md` for the query shape)
- [ ] Wire the advanced hunting pull into this lab's Wazuh manager as a custom log source
- [ ] Once steps above are clean, port the validated playbook/var changes back into `hifisol/defender-endpoint-p2`

## Session log

<!-- 2026-XX-XX: what was tested, what broke, what got fixed -->
