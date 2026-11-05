<h1 align="center">ConnectNow</h1>

<p align="center"><b>When your Mac can't find the Wi-Fi login page.</b></p>

<table align="center"><tr><td align="center">
<h3><a href="https://github.com/Vitruves/ConnectNow/releases/latest/download/ConnectNow.zip">⬇ Download ConnectNow</a></h3>
Universal app (Apple Silicon + Intel) · macOS 14 or later<br>
<sub>Unzip, move it to Applications, then <b>right-click → Open</b> the first time (the app is not notarized).</sub>
</td></tr></table>

ConnectNow finds and opens the sign-in page of a public Wi-Fi (hotel, train, café, airport) when macOS doesn't show it, explains what is blocking it, and fixes the most common cause for you.

<p align="center"><img src="docs/screenshot.png" width="320" alt="ConnectNow showing a detected portal"></p>

## Purpose

You are "connected" to the Wi-Fi, yet no page loads and the login window never appears. macOS only shows it when its own check against `captive.apple.com` is redirected, and many everyday settings get in the way:

- **A manual DNS** (1.1.1.1, 8.8.8.8, NextDNS…) that the network blocks until you sign in.
- **A VPN, iCloud Private Relay or a network extension** (firewall, ad blocker) that carries the traffic away from the Wi-Fi.
- **A web proxy**, or **another connection with priority** (Ethernet, iPhone hotspot).
- **A portal that lets Apple's check through** while blocking everything else.

## How it works

- **Probes** the detection URLs of Apple, Google, Firefox and Microsoft without following redirects: a single hijacked probe reveals the portal.
- **Asks the network**: the portal advertised by DHCP (RFC 8910/8908) and the web pages of the gateway.
- **Bypasses your setup**: requests are bound to the Wi-Fi interface (around a VPN or Ethernet) and fall back to the network's own DNS when yours is blocked.
- **Opens the portal** in its own window, always showing the real address, with nothing kept on disk between networks.
- **Fixes the DNS case**: one click switches a blocked manual DNS to automatic; your servers are backed up first and restored as soon as you are online, when you quit, or at next launch after a crash.
- **Tells you what's wrong**: VPN, proxy, private Wi-Fi address, network extensions, Wi-Fi off or without an address, each with what to do.

It rescans when the network changes, every few seconds while you're not online, and every 30 s once connected, so an expired session is caught and the portal reopens.

## Privacy

No account, no telemetry, no third-party server: only the public connectivity probes above and the portal itself are contacted.

## Build

```sh
make app      # builds ConnectNow.app (Xcode or the Command Line Tools, no need to open Xcode)
make test     # runs the tests
make install  # copies the app to /Applications
```

Pushing a `v*` tag makes the CI publish a release, which the download link above always points to.

## License

[MIT](LICENSE)
