#!/usr/bin/env python3
"""Synthesises the app's Halloween sound effects from scratch (no samples, so no licensing to worry about).

Usage: python3 Tools/make_sounds.py <output-dir>   → writes ghost/organ/bell/shiny .wav files
"""
import array
import math
import os
import random
import sys
import wave

SR = 44100
random.seed(31)


def silence(sec):
    return [0.0] * int(sec * SR)


def reverb(x, mix):
    """Small Schroeder reverb: four parallel combs into two allpasses."""
    wet = [0.0] * len(x)
    for delay, gain in [(1557, 0.84), (1617, 0.83), (1491, 0.82), (1422, 0.81)]:
        buf, idx = [0.0] * delay, 0
        for i, s in enumerate(x):
            y = buf[idx]
            buf[idx] = s + y * gain
            idx = (idx + 1) % delay
            wet[i] += y * 0.25
    for delay, gain in [(225, 0.5), (556, 0.5)]:
        buf, idx = [0.0] * delay, 0
        for i, s in enumerate(wet):
            b = buf[idx]
            buf[idx] = s + b * gain
            wet[i] = b - s
            idx = (idx + 1) % delay
    return [a * (1 - mix) + b * mix for a, b in zip(x, wet)]


def write(path, samples, level):
    peak = max(abs(s) for s in samples) or 1.0
    fade = int(0.05 * SR)
    data = array.array("h")
    for i, s in enumerate(samples):
        g = min(1.0, (len(samples) - i) / fade)
        data.append(int(max(-1.0, min(1.0, s / peak * level * g)) * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def ghost():
    """Theremin-style "woooOOOooo" with a second ghost harmonising a fifth above."""
    dur = 2.6
    pts = [(0, 230), (0.45, 420), (0.9, 380), (1.4, 470), (2.1, 250), (2.6, 200)]

    def contour(t):
        for (t0, f0), (t1, f1) in zip(pts, pts[1:]):
            if t <= t1:
                x = 0.5 - 0.5 * math.cos(math.pi * (t - t0) / (t1 - t0))
                return f0 + (f1 - f0) * x
        return pts[-1][1]

    out = silence(dur)
    for ratio, gain, delay in [(1.0, 1.0, 0.0), (1.498, 0.35, 0.18)]:
        phase = 0.0
        for i in range(len(out)):
            t = i / SR - delay
            if t < 0:
                continue
            f = contour(t) * ratio * (1 + 0.025 * math.sin(2 * math.pi * 5.5 * t))
            phase += 2 * math.pi * f / SR
            s = math.sin(phase) + 0.25 * math.sin(2 * phase) + 0.08 * math.sin(3 * phase)
            a = min(1.0, t / 0.35) * min(1.0, max(0.0, (dur - delay - t) / 0.7))
            a *= 0.85 + 0.15 * math.sin(2 * math.pi * 3.1 * t)
            out[i] += s * a * gain
    return reverb(out + silence(1.0), 0.35)


def organ():
    """Pipe-organ "dun, dun, DUNNN" ending on a creepy minor-major chord."""
    D2, D3, F3, A3, D4, F4, A4, Cs5 = 73.42, 146.83, 174.61, 220.0, 293.66, 349.23, 440.0, 554.37
    hits = [
        (0.00, 0.20, 0.06, [D3, F3, A3, D4]),
        (0.26, 0.20, 0.06, [D3, F3, A3, D4]),
        (0.52, 2.00, 0.90, [D2, D3, A3, D4, F4, A4, Cs5]),
    ]
    drawbars = [(1, 1.0), (2, 0.55), (3, 0.35), (4, 0.4), (6, 0.18), (8, 0.22)]
    out = silence(2.7)
    for start, length, release, notes in hits:
        i0 = int(start * SR)
        for k in range(int(length * SR)):
            t = k / SR
            a = min(1.0, t / 0.012) * min(1.0, (length - t) / release)
            trem = 1 + 0.08 * math.sin(2 * math.pi * 6.2 * t)
            s = 0.0
            for f in notes:
                w = 2 * math.pi * f * t
                for h, g in drawbars:
                    s += g * math.sin(w * h)
            out[i0 + k] += s * a * trem / len(notes)
    return reverb(out + silence(1.2), 0.4)


def bell():
    """Two tolls of a deep church bell at midnight."""
    f0 = 196.0
    partials = [(0.5, 0.45, 4.5), (1.0, 1.0, 3.2), (1.19, 0.55, 2.4), (1.5, 0.35, 2.0), (2.0, 0.6, 1.7),
                (2.52, 0.28, 1.2), (3.0, 0.22, 1.0), (4.17, 0.12, 0.7), (5.43, 0.08, 0.5)]
    total = 3.6
    out = silence(total)
    for strike, vel in [(0.0, 1.0), (1.3, 0.85)]:
        i0 = int(strike * SR)
        for k in range(len(out) - i0):
            t = k / SR
            s = 0.0
            for r, g, d in partials:
                s += g * math.exp(-t / d) * math.sin(2 * math.pi * f0 * r * t + r)
            out[i0 + k] += s * vel * min(1.0, t / 0.003)
        click = int(0.01 * SR)
        for k in range(click):
            out[i0 + k] += (random.random() * 2 - 1) * 0.3 * (1 - k / click)
    return reverb(out + silence(0.8), 0.3)


def chime(notes, spacing, total):
    out = silence(total)
    for j, f in enumerate(notes):
        i0 = int(j * spacing * SR)
        for k in range(len(out) - i0):
            t = k / SR
            s = (math.sin(2 * math.pi * f * t)
                 + 0.35 * math.sin(2 * math.pi * f * 2.76 * t) * math.exp(-t / 0.15)
                 + 0.2 * math.sin(2 * math.pi * f * 2 * t))
            out[i0 + k] += s * math.exp(-t / 0.45) * min(1.0, t / 0.002) * 0.5
    return out


def shiny():
    """Longer two-octave run plus a shimmering chord for Shiny pulls."""
    out = chime([783.99, 1046.5, 1318.5, 1568.0, 2093.0, 2637.0, 3136.0], 0.055, 1.8)
    i0 = int(0.42 * SR)
    for k in range(len(out) - i0):
        t = k / SR
        s = sum(math.sin(2 * math.pi * f * t) for f in (1046.5, 1318.5, 1568.0, 2093.0))
        out[i0 + k] += s * 0.18 * (0.6 + 0.4 * math.sin(2 * math.pi * 11 * t)) * math.exp(-t / 0.6) * min(1.0, t / 0.05)
    return reverb(out + silence(0.6), 0.3)


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)
    for name, fn, level in [("ghost", ghost, 0.80), ("organ", organ, 0.80), ("bell", bell, 0.85),
                            ("shiny", shiny, 0.65)]:
        write(os.path.join(out_dir, name + ".wav"), fn(), level)
        print("wrote", name)
