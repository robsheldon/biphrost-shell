# Return the host's external IP address

This should be a fairly bulletproof way to tease this out in most environments. Does not require curl, wget, or external resources.
```bash
ip route get to 1.1.1.1 | grep -oP '^1.1.1.1 via.*src \K[0-9.]+(?= uid)'
```