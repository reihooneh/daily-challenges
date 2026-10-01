"""Colour vision deficiency (CVD) simulation.

Our eyes have three kinds of colour sensor (cones). In the most common forms
of colour blindness one kind is missing:

    protanopia    no "red" cones    (~1% of men)
    deuteranopia  no "green" cones  (~1% of men; with milder forms, ~6%)
    tritanopia    no "blue" cones   (rare)

The matrices below are from Machado, Oliveira & Fernandes (2009), "A
Physiologically-based Model for Simulation of Color Vision Deficiency", at
full severity. Each one maps what a typical eye sees to what an affected eye
sees, working on linear (gamma-removed) RGB.
"""

from __future__ import annotations

from .color import RGB, linear_to_srgb, srgb_to_linear

Matrix = tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]

MATRICES: dict[str, Matrix] = {
    "protanopia": (
        (0.152286, 1.052583, -0.204868),
        (0.114503, 0.786281, 0.099216),
        (-0.003882, -0.048116, 1.051998),
    ),
    "deuteranopia": (
        (0.367322, 0.860646, -0.227968),
        (0.280085, 0.672501, 0.047413),
        (-0.011820, 0.042940, 0.968881),
    ),
    "tritanopia": (
        (1.255528, -0.076749, -0.178779),
        (-0.078411, 0.930809, 0.147602),
        (0.004733, 0.691367, 0.303900),
    ),
}

KINDS = tuple(MATRICES)


def simulate(rgb: RGB, kind: str) -> RGB:
    """Return the colour as someone with the given deficiency would see it."""
    if kind not in MATRICES:
        raise ValueError(f"unknown deficiency {kind!r}; choose from {', '.join(KINDS)}")
    lin = srgb_to_linear(rgb)
    out = RGB(*(sum(m * c for m, c in zip(row, lin, strict=True)) for row in MATRICES[kind]))
    return linear_to_srgb(out)
