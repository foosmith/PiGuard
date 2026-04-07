# PiGuard App Review Notes

## App Behavior

PiGuard is a menu bar utility for macOS. After launch, it appears in the macOS menu bar and does not display a Dock icon.

## Review Access

- Server type: Pi-hole
- Host: dns.sidious.net
- Port: 443
- Protocol: HTTPS
- Username: not required
- Password: N2w3soBStx6nJAga41u9

## Validation Steps

1. Launch PiGuard.
2. Open Preferences from the menu bar.
3. Add a new server with the review credentials above.
4. Use Test Connection.
5. Save the server.
6. Verify the server status appears in the menu bar.
7. Disable blocking.
8. Re-enable blocking.
9. Trigger refresh.
10. Open Query Log.

## Notes

- The review server is a dedicated temporary environment for App Review only.
- Accessing `https://dns.sidious.net` redirects to the Pi-hole admin interface.
- PiGuard's primary UI is the macOS menu bar rather than a standard window at launch.
