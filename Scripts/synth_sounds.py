"""Synthesise the CatPuzzle UI sound set.

All cues share one tonal world (C major / pentatonic flavour), one format
(44.1 kHz, 16-bit stereo), instant attacks with no lead-in noise, and no
energy below ~110 Hz (phone speakers cannot reproduce it).
"""
import numpy as np, wave, os
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.dirname(os.path.abspath(__file__)) + "/out"
os.makedirs(OUT, exist_ok=True)

N = {  # note -> Hz
    "C4": 261.63, "D#4": 311.13, "E4": 329.63, "F4": 349.23, "G4": 392.00, "A4": 440.00,
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99, "A5": 880.00, "B5": 987.77,
    "C6": 1046.50, "E6": 1318.51, "G6": 1567.98, "C7": 2093.00,
}

def buf(dur):
    return np.zeros(int(SR * dur))

def add(dst, src, at):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n]

def env_exp(n, decay, attack=0.002):
    """Percussive envelope: near-instant attack, exponential decay."""
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = int(attack * SR)
    if a > 1:
        e[:a] *= np.linspace(0, 1, a) ** 0.5
    return e

def tone(freq, dur, partials, decay, attack=0.002, vib=0.0, vib_hz=5.0, glide_to=None):
    """Additive voice. `partials` = [(ratio, amp, decay_scale), ...]."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = np.full(n, float(freq))
    if glide_to is not None:                       # portamento over the first 40%
        k = max(1, int(n * 0.4))
        f[:k] = np.geomspace(freq, glide_to, k)
        f[k:] = glide_to
    if vib:
        f = f * (2 ** (vib / 1200.0 * np.sin(2 * np.pi * vib_hz * t)))
    out = np.zeros(n)
    for ratio, amp, dscale in partials:
        ph = np.cumsum(2 * np.pi * f * ratio / SR)
        out += amp * np.sin(ph) * env_exp(n, decay * dscale, attack)
    return out

def mallet(dur, cutoff=(2000, 9000), decay=0.004):
    """Very short filtered-noise transient - the 'click' of a mallet hit."""
    n = int(dur * SR)
    rng = np.random.default_rng(7)
    x = rng.normal(0, 1, n)
    sos = butter(2, [cutoff[0] / (SR / 2), cutoff[1] / (SR / 2)], btype="band", output="sos")
    return sosfilt(sos, x) * env_exp(n, decay, attack=0.0005)

def sweep(f0, f1, dur, decay, partials=((1, 1, 1),)):
    n = int(dur * SR)
    f = np.geomspace(f0, f1, n)
    out = np.zeros(n)
    for ratio, amp, dscale in partials:
        out += amp * np.sin(np.cumsum(2 * np.pi * f * ratio / SR)) * env_exp(n, decay * dscale)
    return out

# voice colours -------------------------------------------------------------
BELL   = [(1, 1.0, 1.0), (2.01, 0.45, 0.7), (3.02, 0.22, 0.5), (4.21, 0.11, 0.35)]
GLASS  = [(1, 1.0, 1.0), (2.0, 0.30, 0.6), (4.0, 0.14, 0.4), (6.1, 0.05, 0.25)]
WOOD   = [(1, 1.0, 1.0), (3.9, 0.32, 0.35), (9.2, 0.10, 0.18)]   # marimba-like
SOFT   = [(1, 1.0, 1.0), (2.0, 0.22, 0.8), (3.0, 0.08, 0.6)]
REEDY  = [(1, 1.0, 1.0), (2.0, 0.18, 0.9), (3.0, 0.35, 0.8), (5.0, 0.14, 0.6)]

def finish(x, peak_dbfs, hp=110, fade_out=0.012):
    """High-pass, fade, normalise to a target peak, soft-limit, to stereo int16."""
    sos = butter(2, hp / (SR / 2), btype="high", output="sos")
    x = sosfilt(sos, x)
    f = int(fade_out * SR)
    if f < len(x):
        x[-f:] *= np.linspace(1, 0, f) ** 2
    x[:32] *= np.linspace(0, 1, 32)                 # guarantee a click-free start
    x = np.tanh(x / max(np.abs(x).max(), 1e-9) * 0.9) / np.tanh(0.9)
    x = x / max(np.abs(x).max(), 1e-9) * (10 ** (peak_dbfs / 20))
    return np.repeat((x * 32767).astype(np.int16)[:, None], 2, axis=1)

def save(name, x, peak_dbfs):
    data = finish(x, peak_dbfs)
    with wave.open(f"{OUT}/{name}.wav", "w") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name+'.wav':26s} {len(data)/SR*1000:6.0f}ms  peak {peak_dbfs:+.1f}dBFS")

# 1. sfx_start - rising C major arpeggio landing on a bright chord ----------
x = buf(1.0)
for i, note in enumerate(["C5", "E5", "G5", "C6"]):
    add(x, tone(N[note], 0.55, BELL, decay=0.20) * 0.8, 0.095 * i)
for note, amp in [("C6", 1.0), ("E6", 0.7), ("G6", 0.55), ("C7", 0.3)]:
    add(x, tone(N[note], 0.62, GLASS, decay=0.26) * amp, 0.40)
add(x, mallet(0.05, (4000, 12000), 0.010) * 0.25, 0.40)      # sparkle on the landing
save("sfx_start", x, -9.0)

# 2. sfx_excluded_mark - short wooden "decided" tick, stacks rhythmically ---
x = buf(0.095)
add(x, tone(N["G5"], 0.095, WOOD, decay=0.030, attack=0.0008), 0.0)
add(x, mallet(0.012, (2500, 8000), 0.0035) * 0.30, 0.0)
save("sfx_excluded_mark", x, -10.5)

# 3. sfx_excluded_unmark - shorter, darker, falling: "undone" ---------------
x = buf(0.058)
add(x, tone(N["G5"], 0.058, SOFT, decay=0.018, attack=0.0008, glide_to=N["D5"]), 0.0)
save("sfx_excluded_unmark", x, -13.0)

# 4. sfx_cat_mark - the headline cue: bell pair + rising vocal glide --------
x = buf(0.46)
add(x, tone(N["C6"], 0.40, BELL, decay=0.125) * 1.0, 0.0)
add(x, tone(N["G6"], 0.38, BELL, decay=0.110) * 0.68, 0.045)
add(x, tone(N["E5"], 0.42, SOFT, decay=0.210, vib=14, vib_hz=6.5,
            glide_to=N["A5"]) * 1.00, 0.025)                  # the feline lilt, left ringing
add(x, mallet(0.02, (3000, 10000), 0.005) * 0.22, 0.0)
save("sfx_cat_mark", x, -9.0)

# 5. sfx_cat_unmark - mirror of the above, falling and brief ---------------
x = buf(0.20)
add(x, tone(N["G6"], 0.18, BELL, decay=0.055), 0.0)
add(x, tone(N["C6"], 0.16, BELL, decay=0.050) * 0.8, 0.055)
save("sfx_cat_unmark", x, -12.0)

# 6. sfx_cat_failed - mild setback: detuned falling second -----------------
x = buf(0.30)
for note, at, amp in [("A4", 0.0, 1.0), ("F4", 0.115, 0.9)]:
    add(x, tone(N[note], 0.22, REEDY, decay=0.075) * amp, at)
    add(x, tone(N[note] * 2 ** (20 / 1200), 0.22, REEDY, decay=0.075) * amp * 0.6, at)  # beating
save("sfx_cat_failed", x, -10.0)

# 7. sfx_heart_broken - game over: descending fall into a minor chord ------
x = buf(0.85)
for note, at, amp in [("C5", 0.0, 1.0), ("G4", 0.13, 0.9), ("D#4", 0.26, 0.85)]:
    add(x, tone(N[note], 0.40, REEDY, decay=0.13) * amp, at)
for note, amp in [("C4", 1.0), ("D#4", 0.75), ("G4", 0.6)]:
    add(x, tone(N[note], 0.48, SOFT, decay=0.22) * amp, 0.40)
add(x, sweep(620, 210, 0.40, 0.16) * 0.22, 0.40)             # the sigh
save("sfx_heart_broken", x, -9.0)
