---
date: 2024-02-10T14:27:00-08:00
tags: pi-hole,cloudflared,mullvad,dns
title: Too much about DNS (including pi-hole, mullvad and blocking)
---

These days, with the amount of shit that connects to our wifi networks, we can't be sure that everything is going to follow the instructions we've given it, especially given how many of these devices might want to phone home, load ads, track where they are etc.

The best way to prevent this is to not buy these devices. Nah, we're not digital Luddites, but we can take some protections here to prevent the most egregious of these activities. At home I've got the following set up:
* [pi-hole](https://pi-hole.net)
* [cloudflared](https://github.com/cloudflare/cloudflared) to route DNS over HTTPS to [mullvad](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls)
* re-routing all DNS queries to the pi-hole
* blocking DNS over HTTP and TLS for all clients except the pi-hole

This prevents things from having hard-coded DNS services that they talk to by forwarding all DNS requests over port 53 to my pi-hole, blocks DNS over TLS (port 853) to a specific set of hosts and blocks port 443 access to a specific set of hosts.

## cloudflared to mullvad

The first thing I set up was the cloudflared tool to proxy local DNS requests over HTTPS to the Mullvad DNS server. I'm using Mullvad because they've proven to be a pretty champion of user privacy. You should follow the instructions on the cloudflared page to install it. I'm running this on Debian, so I just downloaded the `.dev` package and did a standard `dpkg -i cloudflared*.deb`.

The instructions tell you to pass the arguments `--port 5053 --upstream https://dns.mullvad.net/dns-query` to `cloudflared`, but like, how is it going to resolve `dns.mullvad.net` if `dns.mullvad.net` is the only DNS server its allowed to speak with. We can't use the IP address of the Mullvad server either since the TLS certificate is keyed to the domain name, so that'll throw an error.

The answer to this problem is `/etc/hosts` -- add the [IP address](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls#specifications) for `dns.mullvad.net` to your file: 

```bash
echo "194.242.2.2 dns.mullvad.net" | sudo tee -a /etc/hosts
```

If you're running this on an LXC container on Proxmox you'll also need to do a quick `touch /etc/.pve-ignore.resolv.conf` so that Proxmox doesn't overwrite this file if you restart it.

Now that we've got that squared away we can create a new user for the cloudflared daemon (as it _certainly_ does not need to run as root):

```bash
useradd -s /usr/sbin/nologin -r -M cloudflared
```

This sets the shell to `nologin` so you can't, well, login, marks the account as system account with `-r` and doesn't make a home directory with `-M`.

Then we can create a systemd file for this:

```
[Unit]
Description=cloudflared DNS over HTTPS proxy
After=syslog.target network-online.target

[Service]
Type=simple
User=cloudflared
ExecStart=/usr/local/bin/cloudflared proxy-dns --port 5053 --upstream https://dns.mullvad.net/dns-query
Restart=on-failure
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
```

With a quick `systemctl enable cloudflared && systemctl start cloudflared` we can get this service stared.  We can confirm this is working via `dig`:

```bash
# dig @127.0.0.1 -p 5053 mullvad.net

; <<>> DiG 9.18.18-0ubuntu0.23.04.1-Ubuntu <<>> @127.0.0.1 -p 5053 mullvad.net
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 57822
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
; COOKIE: 06afebf0e4d19267 (echoed)
;; QUESTION SECTION:
;mullvad.net.                   IN      A

;; ANSWER SECTION:
mullvad.net.            60      IN      A       45.83.223.209

;; Query time: 88 msec
;; SERVER: 127.0.0.1#5053(127.0.0.1) (UDP)
;; WHEN: Sat Feb 10 23:46:40 UTC 2024
;; MSG SIZE  rcvd: 79
```

Now that that is setup, we can install pi-hole by following the instructions on the pi-hole site, and during configuration we can tell pi-hole that `127.0.0.1#5053` is our upstream DNS provider.

Now, because I didn't want any thing to use any other hard-coded DNS, I set up my router (which uses [pfSense](https://www.pfsense.org)) so that all requests to port 53 are routed to the pi-hole (but the pi-hole is exempt from this), and then set it to block any requests over ports 853 (DNS over TLS) and 443 to any host that exists on the [public dns nameserver list](http://public-dns.info/nameservers-all.txt), again, exempting the pihole from this requirement.

