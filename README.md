# untitledIRC Automation

Automated installer for UnrealIRCd 6.x and Anope 2.0.x (including WebCP) on Ubuntu 22.04 and newer. All configuration is driven by the `.env` file with safe defaults.

## Quickstart

```bash
git clone https://example.com/untitledIRC.git /root/untitledIRC
cd /root/untitledIRC
bash scripts/install.sh
```

## TLS via Let's Encrypt (DNS-01)

Run the DNS helper to issue a certificate once DNS is ready:

```bash
bash scripts/le-dns-manual.sh
```

The script prints the required `_acme-challenge` TXT record. After publishing it, you can use the built-in check:

```bash
dig -t TXT _acme-challenge.irc.untitledbot.xyz
```

Once validation succeeds, the certificate is deployed automatically and UnrealIRCd is reloaded.

## Troubleshooting

- UnrealIRCd logs: `/root/untitledIRC/unrealircd/logs/unrealircd.log`
- Anope logs: `/root/untitledIRC/anope/logs/services.log`
- WebCP access: `http://<server-hostname>:8080/` (use the credentials from `.env`)

Re-run `bash scripts/verify.sh` to validate service health and connectivity after any change.
