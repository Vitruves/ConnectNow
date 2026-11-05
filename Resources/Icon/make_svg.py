"""Generates icon.svg: the ConnectNow logo on the macOS icon grid (1024 canvas, 824 body)."""
import math

def squircle(x, y, size, n=5.0, steps=720):
    # Superellipse: "continuous" corners like Apple's icons.
    r = size / 2; cx, cy = x + r, y + r; pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** (2 / n), c), cy + r * math.copysign(abs(s) ** (2 / n), s)))
    return "M" + " L".join(f"{px:.2f},{py:.2f}" for px, py in pts) + " Z"

def arc(cx, cy, r, half_angle=46):
    a = math.radians(half_angle)
    x1, y1 = cx - r * math.sin(a), cy - r * math.cos(a)
    x2, y2 = cx + r * math.sin(a), cy - r * math.cos(a)
    return f"M{x1:.1f},{y1:.1f} A{r},{r} 0 0 1 {x2:.1f},{y2:.1f}"

body = squircle(100, 100, 824)
cx, cy = 512, 604            # wave centre: the door is the dot of the Wi-Fi symbol
door_l, door_r, door_t, door_b = 432, 592, 566, 806
arcs = "".join(f'<path d="{arc(cx, cy, r)}"/>' for r in (146, 246, 346))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="sky" x1="0.15" y1="1" x2="0.85" y2="0">
    <stop offset="0" stop-color="#1E2160"/><stop offset="0.38" stop-color="#4A2A78"/>
    <stop offset="0.66" stop-color="#C2486A"/><stop offset="0.86" stop-color="#F07A55"/><stop offset="1" stop-color="#FFC56E"/>
  </linearGradient>
  <radialGradient id="dawn" cx="512" cy="700" r="520" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#FFD48A" stop-opacity="0.55"/><stop offset="0.45" stop-color="#FF8A5C" stop-opacity="0.18"/><stop offset="1" stop-color="#FF8A5C" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.22"/><stop offset="0.5" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="light" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFBEF"/><stop offset="1" stop-color="#FFD98C"/>
  </linearGradient>
  <linearGradient id="spill" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFD98C" stop-opacity="0.6"/><stop offset="0.7" stop-color="#FFB870" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="leaf" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#7A2E5E"/><stop offset="1" stop-color="#B8476A"/>
  </linearGradient>
  <linearGradient id="wave" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#FFF1DC"/>
  </linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.32"/>
  </filter>
  <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="22"/>
  </filter>
  <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="7"/></filter>
  <clipPath id="clip"><path d="{body}"/></clipPath>
</defs>
<g filter="url(#shadow)"><path d="{body}" fill="url(#sky)"/></g>
<g clip-path="url(#clip)">
  <rect width="1024" height="1024" fill="url(#dawn)"/>
  <rect width="1024" height="520" fill="url(#sheen)"/>
  <!-- light spilling out of the door -->
  <path d="M{door_l},{door_b} L{door_r},{door_b} L720,960 L304,960 Z" fill="url(#spill)" filter="url(#soft)"/>
  <rect x="{door_l-30}" y="{door_t-30}" width="{door_r-door_l+60}" height="{door_b-door_t+30}" rx="60" fill="#FFD27A" opacity="0.55" filter="url(#glow)"/>
</g>
<path d="{body}" fill="none" stroke="#fff" stroke-opacity="0.18" stroke-width="3"/>
<!-- Wi-Fi waves -->
<g fill="none" stroke="url(#wave)" stroke-width="56" stroke-linecap="round">{arcs}</g>
<!-- open door: glowing doorway, leaf swung open to the left -->
<path d="M{door_l},{door_b} L{door_l},{door_t+40} Q{door_l},{door_t} {door_l+40},{door_t} L{door_r-40},{door_t} Q{door_r},{door_t} {door_r},{door_t+40} L{door_r},{door_b} Z" fill="url(#light)"/>
<path d="M{door_l},{door_t+22} L{door_l+62},{door_t+48} L{door_l+62},{door_b-16} L{door_l},{door_b} Z" fill="url(#leaf)"/>
<circle cx="{door_l+46}" cy="{(door_t+door_b)//2+14}" r="8" fill="#FFC56E"/>
</svg>'''
open(__file__.replace("make_svg.py", "icon.svg"), "w").write(svg)
