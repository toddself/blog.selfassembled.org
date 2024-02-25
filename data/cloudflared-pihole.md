---
date: 2024-02-10T14:27:00-08:00
tags: pi-hole,cloudflared,mullvad,dns
title: Too much about DNS (including Pi-Hole, Mullvad and blocking)
---

These days, with the amount of shit that connects to our wifi networks, we can't be sure that everything is going to follow the instructions we've given it, especially given how many of these devices might want to phone home, load ads, track where they are etc.

The best way to prevent this is to not buy these devices. Nah, we're not digital Luddites, but we can take some protections here to prevent the most egregious of these activities. At home I've got the following set up:
* [Pi-Hole](https://pi-hole.net)
* [cloudflared](https://github.com/cloudflare/cloudflared) to route DNS over HTTPS to [Mullvad](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls)
* re-routing all DNS queries to the Pi-Hole
* blocking DNS over HTTP and TLS for all clients except the Pi-Hole

This prevents things from having hard-coded DNS services that they talk to by forwarding all DNS requests over port 53 to my Pi-Hole, blocks DNS over TLS (port 853) to a specific set of hosts and blocks port 443 access to a specific set of hosts.

## Cloudflared to Mullvad

The first thing I set up was the cloudflared tool to proxy local DNS requests over HTTPS to the Mullvad DNS server. I'm using Mullvad because they've proven to be a pretty champion of user privacy. You should follow the instructions on the cloudflared page to install it. I'm running this on Debian, so I just downloaded the `.dev` package and did a standard `dpkg -i cloudflared*.deb`.

The instructions tell you to pass the arguments `--port 5053 --upstream https://dns.mullvad.net/dns-query` to `cloudflared`, but like, how is it going to resolve `dns.mullvad.net` if `dns.mullvad.net` is the only DNS server its allowed to speak with. We can't use the IP address of the Mullvad server either since the TLS certificate is keyed to the domain name, so that'll throw an error.

The answer to this problem is `/etc/hosts` -- add the [IP address](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls#specifications) for `dns.mullvad.net` to your file: 

```bash
echo "194.242.2.2 dns.mullvad.net" | sudo tee -a /etc/hosts
```

If you're running this on an LXC container on Proxmox you'll also need to do a quick `touch /etc/.pve-ignore.resolv.conf` so that Proxmox doesn't overwrite this file if you restart it.

Now that we've got that squared away we can create a new user for the cloudflared daemon (as it _certainly_ does not need to run as root):

```bash
sudo useradd -s /usr/sbin/nologin -r -M cloudflared
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

Now that that is setup, we can install Pi-Hole by following the instructions on the Pi-Hole site, and during configuration we can tell Pi-Hole that `127.0.0.1#5053` is our upstream DNS provider.

## Setting up TLS for Pi-Hole

Technically this has nothing to do with the rest of the DNS setup, but setting up a TLS cert via Lets Encrypt for our Pi-Hole will be nice since it'll stop our browser from yelling at us about entering a password over a non-secure connection. With the DNS challenge type we won't have to expose the server to the internet at large, and we can use the Pi-Hole's own local DNS service to make it accessible via the custom domain name.

I use [Porkbun](https://porkbun.com) for my domain names which is nice since it has an API for making changes, and that API has been implemented in a wide number of ACME providers, including [lego](https://github.com/go-acme/lego), which we'll be using here. Download the binary from the releases page and issue yourself a certificate:

```bash
sudo mkdir -p /etc/{certs,secrets}
sudo PORKBUN_SECRET_API_KEY=xxx PORKBUN_API_KEY=xxx lego --email [your email] --domains="pihole.yourawesomedomainname.com" --dns porkbun --path /etc/certs --pem run
```

If you're not using porkbun, there's a [massive list](https://go-acme.github.io/lego/dns/) of other providers that are supported. We're using the `--pem` argument since LightHTTPd requires a single concatenated cert + key and so rather than having to generate that manually, we'll let the tool do it for us.

We also want to set this up for renewal so we can make a new system account to run the process, put the secrets in the filesystem and then lock down access to that user for those secrets, and the certs so that that user and the `www-data` user for LightHTTPd can read them.

```bash
sudo useradd -s /usr/sbin/nologin -r -M lego
echo "PORKBUN_SECRET_API_KEY=xxx" | sudo tee -a /etc/secrets/porkbun > /dev/null
echo "PORKBUN_API_KEY=xxx" | sudo tee -a /etc/secrets/porkbun > /dev/null
echo "EMAIL=xxx" | sudo tee -a /etc/secrets/porkbun > /dev/null
echo "DOMAIN=xxx" | sudo tee -a /etc/secrets/porkbun > /dev/null
sudo chown lego:lego /etc/secrets/porkbun
sudo chown -R lego:www-data /etc/certs
sudo chmod -R 750 /etc/certs
```

Now we can create a systemd service file in `/etc/systemd/system/lego-acme.service`:

```
[Unit]
Description=Renew tls cert

[Service]
Type=oneshot
User=lego
EnvironmentFile=/etc/secrets/porkbun
ExecStart=/usr/local/bin/lego --email $EMAIL --dns porkbun --pem --path /etc/certs --domains=$DOMAIN renew --renew-hook="/usr/local/bin/cert-renew.sh"
PrivateTmp=true
WorkingDirectory=/etc/certs
```

And a timer in `/etc/systemd/system/lego-acme.timer`:

```
[Unit]
Description=Renew certs

[Timer]
Persistent=true
OnCalendar=* *-*-01 2:56
RandomizeDelaySec=1h

[Install]
WantedBy=timers.target
```

This will check for a renewal once a month. You'll want to enable this timer: `systemctl enable lego-acme.timer`

I also added a renew hook to the script to restart lighttpd after the cert has been renewed:

```bash
#!/bin/sh
systemctl restart lighttpd
```

## Routing DNS requests internally

Now, because I didn't want any thing to use any other hard-coded DNS, I set up my router (which uses [pfSense](https://www.pfsense.org)) so that all requests to port 53 are routed to the Pi-Hole (but the Pi-Hole is exempt from this), and then set it to block any requests over ports 853 (DNS over TLS) and 443 to any host that exists on the [public dns nameserver list](http://public-dns.info/nameservers-all.txt), again, exempting the pihole from this requirement.

We'll start off by going to the Firewall > NAT > Port Forward section in pfSense and create two new rules.

Rule to redirect all DNS requests over port 53 back to the Pi-Hole (which lives at 192.168.1.10 in my local network):
![](dns-redirect1.png)

Rule to allow the Pi-Hole to make requests over port 53:
![](dns-redirect2.png)

The second rule for the Pi-Hole to be allowed to do this needs to be _above_ the one blocking everything.

Now, when anything makes a request to any DNS service, it'll be forwarded to your Pi-Hole instead.

I also wanted to block DNS over TLS and DNS over HTTPS because you know some shitty company is gonna figure out how to force you to see ads by resolving the servers over a TLS connection, so we'll just nip that one in the bud by blocking all of this. My network, my rules. The first thing we need to do is get a list of the public services that provide DNS over HTTP/TLS so we can block requests to them. (And yes, this is a cat and mouse game, but isn't all ad-blocking?).

Go Firewall -> Aliases -> URLs and create a new alias

![](firewall-alias.png)

And then go to Firewall -> Rules -> LAN and create another two rules:

![](dns-over-https.png)

![](dns-over-tls.png)

In these rules we can create an invert match so they say anything that _isn't_ our Pi-Hole is unable to make connections over ports 853 or 443 to the servers on this list. I've been running this rule for 2 1/2 years and, aside from my work VPN, have not run into a problem. (I have additional rules that allow my work laptop, which has a static IP internally, to access ths correct DNS services for my job. This is an exercise left to the reader.)

_This post has been updated to fix the position of the command `renew` and to change `Environment` to `EnvironmentFile` in the service file for the renewal, and to fix the `WantedBy` section in the systemd timer._
