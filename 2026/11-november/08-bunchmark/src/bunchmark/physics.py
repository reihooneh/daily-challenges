"""How fast a rider goes on a slope: the steady-state power balance of a bicycle.

    efficiency * P = v * m g (sin(theta) + Crr cos(theta)) + 1/2 rho CdA v^3

The right side is the power to lift the rider and bike, to roll the tyres and to push the air
aside. Riders hold their steady power on the flat and uphill, ease off downhill, and descents
are capped at a speed a group can corner at.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

G = 9.81
RHO = 1.2  # air density, kg/m^3
CRR = 0.005  # rolling resistance, good road tyres
EFFICIENCY = 0.97  # drivetrain
CDA_SOLO = 0.32  # m^2, hands on the hoods
DRAFT = 0.7  # in a bunch on anything but a real climb, the air drag drops by about 30%
CLIMB = 4.0  # % gradient from which drafting stops helping much
DESCENT_POWER = 0.4  # fraction of steady power ridden downhill
V_MAX = 55 / 3.6  # m/s: the fastest a mixed group should descend


@dataclass(frozen=True)
class Rider:
    name: str
    mass: float  # rider and bike, kg
    power: float  # what they can hold for a few hours, watts


def speed(rider: Rider, grade: float) -> float:
    """Steady speed in m/s on a gradient given in percent."""
    theta = math.atan(grade / 100)
    gravity = rider.mass * G * (math.sin(theta) + CRR * math.cos(theta))
    cda = CDA_SOLO if grade >= CLIMB else CDA_SOLO * DRAFT
    power = EFFICIENCY * rider.power * (DESCENT_POWER if grade < -2 else 1.0)
    # f(v) = power - v*gravity - 0.5*rho*cda*v^3 is concave with f(0) > 0, so it crosses zero
    # exactly once for v > 0: bisection finds it.
    lo, hi = 0.0, 40.0
    for _ in range(80):
        mid = (lo + hi) / 2
        if power - mid * gravity - 0.5 * RHO * cda * mid**3 > 0:
            lo = mid
        else:
            hi = mid
    return min(lo, V_MAX)


def seconds(rider: Rider, km: float, grade: float) -> float:
    return km * 1000 / speed(rider, grade)
