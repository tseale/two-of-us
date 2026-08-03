"""Synthesize the Two of Us alarm tones.

Three candidates, each built from physically-motivated partial sets
(free-bar ratios for music box / kalimba, church-bell ratios for the bells),
exponential per-partial decay, a soft attack, a detuned second voice for
warmth, and a diffuse convolution reverb tail. 44.1 kHz stereo, peak -1 dBFS,
each ends in silence so the system's alarm loop restarts cleanly.
"""
import numpy as np

SR = 44100
rng = np.random.default_rng(20260801)


def midi(m: float) -> float:
    return 440.0 * 2 ** ((m - 69) / 12)


def strike(freq, seconds, partials, attack=0.002, detune_cents=3.0):
    """One struck/plucked note: additive partials + a detuned ghost voice."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        # Higher partials die faster; tiny per-partial phase keeps it organic.
        out += amp * np.exp(-t / decay) * np.sin(2 * np.pi * f * t)
    ghost = freq * 2 ** (detune_cents / 1200)
    r0, a0, d0 = partials[0]
    out += 0.30 * a0 * np.exp(-t / d0) * np.sin(2 * np.pi * ghost * r0 * t)
    a = max(4, int(attack * SR))
    out[:a] *= np.linspace(0, 1, a) ** 2
    return out


# Partial sets --------------------------------------------------------------
# Free-bar transverse mode ratios (music box comb / celesta): 1, 2.76, 5.40, 8.93
MUSIC_BOX = [(1.0, 1.00, 2.8), (2.76, 0.32, 0.9), (5.40, 0.10, 0.40), (8.93, 0.035, 0.18)]
# Kalimba: dominant fundamental, soft thumb attack, quick upper modes
KALIMBA = [(1.0, 1.00, 1.9), (2.76, 0.16, 0.55), (5.40, 0.05, 0.25)]
# Church-bell-lite: hum, prime, tierce, quint, nominal (minor-third bell)
BELL = [(0.5, 0.28, 4.5), (1.0, 1.00, 3.2), (1.20, 0.42, 2.6),
        (1.50, 0.20, 2.0), (2.00, 0.30, 1.4), (2.67, 0.10, 0.8), (3.01, 0.06, 0.5)]


def render(events, total, partials, attack=0.002):
    """events: (time, midi_note, amplitude). Returns mono at `total` seconds."""
    n = int(SR * total)
    out = np.zeros(n)
    for when, note, amp in events:
        dur = total - when
        v = strike(midi(note), dur, partials, attack=attack)
        i = int(when * SR)
        out[i:i + len(v)] += amp * v
    return out


def reverb_ir(seconds, rt60, seed):
    """Exponentially decaying noise — a smooth, diffuse hall tail."""
    g = np.random.default_rng(seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = g.standard_normal(n) * np.exp(-6.91 * t / rt60)
    ir[:int(0.008 * SR)] *= np.linspace(0, 1, int(0.008 * SR))  # no direct spike
    return ir / np.sqrt(np.sum(ir ** 2))


def fftconv(x, h):
    n = len(x) + len(h) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(h, N), N)[:n]


def stereoize(mono, wet=0.22, rt60=1.6, seed=1):
    """Dry center + decorrelated left/right reverb tails."""
    irL = reverb_ir(1.8, rt60, seed)
    irR = reverb_ir(1.8, rt60, seed + 100)
    L = fftconv(mono, irL)[:len(mono)]
    R = fftconv(mono, irR)[:len(mono)]
    left = mono + wet * L
    right = mono + wet * R
    return np.stack([left, right], axis=1)


def finalize(st, peak=0.89, fade_out=0.6):
    n = len(st)
    f = int(fade_out * SR)
    st[n - f:] *= np.linspace(1, 0, f)[:, None] ** 2
    st *= peak / np.max(np.abs(st))
    return st


def write_wav(path, st):
    import wave
    data = (np.clip(st, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{path}: {len(st)/SR:.1f}s peak {np.max(np.abs(st)):.2f}")


A4, B4, Cs5, D5, E5, Fs5, Gs5, A5, B5, Cs6, D6 = 69, 71, 73, 74, 76, 78, 80, 81, 83, 85, 86

# 1. Nightlight — music box lullaby arpeggio in A major, rises then settles home.
nightlight = [
    (0.00, A4, 0.80), (0.55, Cs5, 0.68), (1.10, E5, 0.74), (1.65, A5, 0.85),
    (2.55, Fs5, 0.62), (3.10, E5, 0.68), (3.65, Cs5, 0.58),
    (4.50, B4, 0.55), (5.05, Cs5, 0.50), (5.60, A4, 0.66),
    (6.60, E5, 0.42), (7.15, A5, 0.46),
]

# 2. Sunrise — kalimba in D major, a brighter rising figure with a little answer.
sunrise = [
    (0.00, D5, 0.80), (0.40, Fs5, 0.70), (0.80, A5, 0.80),
    (1.55, B5, 0.60), (1.95, A5, 0.64), (2.60, D6, 0.85),
    (3.50, A5, 0.52), (3.90, Fs5, 0.50), (4.30, D5, 0.62),
    (5.20, Fs5, 0.40), (5.60, A5, 0.44), (6.00, D6, 0.50),
]

# 3. Bells — a slow, soft ding-dong (E down to C#), twice, quieter the second time.
bells = [
    (0.00, E5, 0.90), (1.70, Cs5, 0.78),
    (3.90, E5, 0.62), (5.60, Cs5, 0.52),
]

# Renders .wav next to this script; convert + install into the app bundle with:
#   afconvert -f caff -d ima4 alarm-<tone>.wav ../TwoOfUs/Resources/Sounds/alarm-<tone>.caf
import os
OUT = os.path.dirname(os.path.abspath(__file__))
write_wav(f"{OUT}/alarm-nightlight.wav",
          finalize(stereoize(render(nightlight, 10.0, MUSIC_BOX), wet=0.24, rt60=1.8, seed=1)))
write_wav(f"{OUT}/alarm-sunrise.wav",
          finalize(stereoize(render(sunrise, 9.0, KALIMBA, attack=0.005), wet=0.18, rt60=1.3, seed=2)))
write_wav(f"{OUT}/alarm-bells.wav",
          finalize(stereoize(render(bells, 11.0, BELL), wet=0.28, rt60=2.2, seed=3)))
