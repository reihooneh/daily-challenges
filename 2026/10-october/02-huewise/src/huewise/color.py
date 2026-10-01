"""Colour parsing and conversion.

Everything here is pure maths on tuples, with no input/output, so it is easy
to test. Colours travel through three spaces:

    "#1f77b4"  ->  sRGB (0..1, what screens store)
               ->  linear RGB (real light intensity; needed for mixing)
               ->  CIE Lab (designed so that distance ~ how different two
                            colours look to a person)
"""

from __future__ import annotations

import re
from typing import NamedTuple

# A hex colour is "#" plus exactly 3 or 6 hex digits. Anchored on both sides,
# so a longer string can never sneak through.
_HEX = re.compile(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")

# D65 white point, the "daylight" white that sRGB is defined against.
_WHITE = (0.95047, 1.0, 1.08883)


class RGB(NamedTuple):
    """A colour with channels from 0.0 to 1.0."""

    r: float
    g: float
    b: float


class ColorError(ValueError):
    """Raised when text is not a valid colour."""


def parse_hex(text: str) -> RGB:
    """Turn "#rgb" or "#rrggbb" into sRGB. Anything else raises ColorError."""
    if not isinstance(text, str) or len(text) > 7 or not _HEX.match(text):
        shown = repr(text)[:40]
        raise ColorError(f"{shown} is not a hex colour like #1f77b4 or #abc")
    digits = text[1:]
    if len(digits) == 3:
        digits = "".join(ch * 2 for ch in digits)
    return RGB(*(int(digits[i : i + 2], 16) / 255 for i in (0, 2, 4)))


def to_hex(rgb: RGB) -> str:
    """Format sRGB as lowercase #rrggbb, clamping anything out of range."""
    return "#" + "".join(f"{round(min(1.0, max(0.0, c)) * 255):02x}" for c in rgb)


def srgb_to_linear(rgb: RGB) -> RGB:
    """Undo the screen's gamma curve to get real light intensity."""
    return RGB(*(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb))


def linear_to_srgb(rgb: RGB) -> RGB:
    """Apply the gamma curve again, clamping to the displayable range."""

    def enc(c: float) -> float:
        c = min(1.0, max(0.0, c))
        return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055

    return RGB(*(enc(c) for c in rgb))


def relative_luminance(rgb: RGB) -> float:
    """How bright a colour is to the eye (0 = black, 1 = white), per WCAG."""
    r, g, b = srgb_to_linear(rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(a: RGB, b: RGB) -> float:
    """WCAG contrast ratio, from 1 (identical) to 21 (black on white)."""
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def to_lab(rgb: RGB) -> tuple[float, float, float]:
    """Convert sRGB to CIE L*a*b* (L = lightness, a = green-red, b = blue-yellow)."""
    r, g, b = srgb_to_linear(rgb)
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    def f(t: float) -> float:
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = (f(v / w) for v, w in zip((x, y, z), _WHITE, strict=True))
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def from_lab(lab: tuple[float, float, float]) -> RGB:
    """Convert CIE L*a*b* back to sRGB (clamped to what a screen can show)."""
    lightness, a, b = lab
    fy = (lightness + 16) / 116
    fx, fz = fy + a / 500, fy - b / 200

    def inv(t: float) -> float:
        return t**3 if t**3 > 0.008856 else (t - 16 / 116) / 7.787

    x, y, z = (inv(v) * w for v, w in zip((fx, fy, fz), _WHITE, strict=True))
    lin = RGB(
        3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
        -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
        0.0556434 * x - 0.2040259 * y + 1.0572252 * z,
    )
    return linear_to_srgb(lin)


def delta_e(a: RGB, b: RGB) -> float:
    """Perceived difference between two colours (CIE76: distance in Lab).

    Roughly: under 2 is invisible, around 10 is "similar", 20+ is clearly different.
    """
    la, lb = to_lab(a), to_lab(b)
    return sum((p - q) ** 2 for p, q in zip(la, lb, strict=True)) ** 0.5
