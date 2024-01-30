---
date: 2024-01-30T11:52:00-08:00
tags: proxmox,home-lab,containers
title: Custom container templates in Proxmox
---

After finally purchasing [some hardware](https://www.amazon.com/gp/product/B0BZH534YZ/ref=ppx_yo_dt_b_asin_title_o03_s01?ie=UTF8&psc=1) that is powerful enough to run many things at once (to replace my aging set of raspberries pi and my lenovo thin clients), I figured I'd also switch over from using a mix of running-on-bare-metal and everything else in _very_ long single Docker compose file and install [proxmox](https://www.proxmox.com/en/) because apparently I have no self-worth and like to make things complicated.

While I'm waiting for the rest of the hardware to arrive (namely an SSD to stick in the server), I figured I'd mess around with proxmox and create some lxc containers. After making one or two I noticed that there a few tools that I would like by default installed that aren't in the pre-build images, and don't exist in the other tool images they provide, namely:

* avahi for zeroconf dns
* tailscaled for easier remote management

So I realized I needed to look into creating a new container template. Unfortunately, like most things even moderately difficult, search engines are a complete failure when trying to find this, however I was able to cobble together what is going on here from a variety of proxmox forum and reddit posts, along with the docs for [distrobuilder](https://linuxcontainers.org/distrobuilder), so for future sake, here's what you need to do.

1. Install [distrobuilder](https://linuxcontainers.org/distrobuilder/docs/latest/howto/install/) and it's requirements. I already have go installed and configured via asdf, so I omitted that package from the list.
1. Grab a [template](https://github.com/lxc/distrobuilder/blob/main/doc/examples/ubuntu.yaml) from the distrobuilder repo (or make your own, but I'm pretty lazy)
1. Edit the template to include what you want pre-installed. (I also added `lunar` as a target and told it to use that as my release)
1. Run `sudo ~/go/bin/distrobuilder build-lxc ubuntu.yaml` (or where ever distrobuilder was installed to)
1. For some reason proxmox can only use these templates if they're compressed with `zstd`. I'm sure there's some configuration flag to tell distrobuilder to do this, but we can also just do it with the CLIs: `xz -dc rootfs.tar.xz | zstd -o ubuntu-home-lab.tar.zst`
1. Copy that file to `/var/lib/vz/template/cache/` on your proxmox machine (or use the GUI and upload it that way).

Now you've got your own container template. Which turns out is just the rootfs output from distrobuilder.

