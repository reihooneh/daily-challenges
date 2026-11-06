<?php

declare(strict_types=1);

namespace Grassline;

/**
 * The path of a biased bowl.
 *
 * A bowl rolls on a flat green, slowed by rolling resistance at a constant rate a (m/s²). Its bias
 * (a running surface shaped so it leans) makes it precess like a gyroscope: the gravitational torque
 * is fixed, and the spin is proportional to speed, so the heading turns at a rate proportional to
 * 1/v:   dθ/dt = K / v.
 * With v = v0 − a t, write u = ln(v0 / v); then θ = c u with c = K / a, and the position integrates
 * in closed form:
 *   x(u) = (v0²/a) (2 + e^(−2u) (c sin cu − 2 cos cu)) / (4 + c²)
 *   y(u) = (v0²/a) (c − e^(−2u) (2 sin cu + c cos cu)) / (4 + c²)
 * The bowl comes to rest (u → ∞) at (v0²/a)(2, c)/(4 + c²): at angle atan(c/2) from where it was
 * aimed, whatever its speed. So the aiming angle is the same for every length of jack, and a bowl
 * delivered too heavy or too light finishes on the same line, just long or short.
 *
 * Coordinates: the bowl starts at the origin heading along +x; it curves towards +y.
 */
final class Physics
{
    /** The standard length a green's speed is timed over: 30 yards. */
    public const GREEN_LENGTH = 27.432;

    /** Position, speed, time and distance travelled at parameter u (u = 0 at delivery). */
    public static function at(float $v0, float $a, float $c, float $u): array
    {
        $scale = $v0 * $v0 / $a / (4 + $c * $c);
        $e = exp(-2 * $u);
        $s = sin($c * $u);
        $k = cos($c * $u);
        $v = $v0 * exp(-$u);
        return [
            'x' => $scale * (2 + $e * ($c * $s - 2 * $k)),
            'y' => $scale * ($c - $e * (2 * $s + $c * $k)),
            'v' => $v,
            't' => ($v0 - $v) / $a,
            's' => ($v0 * $v0 - $v * $v) / (2 * $a),
            'heading' => $c * $u,
        ];
    }

    /** Where the bowl comes to rest. */
    public static function rest(float $v0, float $a, float $c): array
    {
        $scale = $v0 * $v0 / $a / (4 + $c * $c);
        return ['x' => 2 * $scale, 'y' => $c * $scale];
    }

    /** The angle (radians) between the aiming line and the line to where the bowl stops. */
    public static function aimAngle(float $c): float
    {
        return atan($c / 2);
    }

    /** Delivery speed that finishes at distance L (m) from the mat. */
    public static function speedFor(float $length, float $a, float $c): float
    {
        return sqrt($length * $a * sqrt(4 + $c * $c));
    }

    /** Seconds from delivery to rest, for a bowl drawn to distance L. */
    public static function duration(float $length, float $a, float $c): float
    {
        return self::speedFor($length, $a, $c) / $a;
    }

    /**
     * Green speed in seconds (the time a bowl takes to come to rest 30 yards from the mat) gives the
     * deceleration, once the bias constant K is known: solved by bisection, as c = K/a depends on a.
     */
    public static function decelerationFor(float $seconds, float $k): float
    {
        $lo = 1e-4;
        $hi = 5.0;
        for ($i = 0; $i < 200; $i++) {
            $mid = ($lo + $hi) / 2;
            // Faster greens (smaller a) take longer: the duration falls as a rises.
            if (self::duration(self::GREEN_LENGTH, $mid, $k / $mid) > $seconds) {
                $lo = $mid;
            } else {
                $hi = $mid;
            }
        }
        return ($lo + $hi) / 2;
    }

    /** The same path by brute force (fourth-order Runge–Kutta in time), to check the closed form. */
    public static function integrate(float $v0, float $a, float $k, float $dt = 0.001): array
    {
        $x = 0.0;
        $y = 0.0;
        $th = 0.0;
        $t = 0.0;
        $stop = $v0 / $a;
        $f = static function (float $tt, float $theta) use ($v0, $a, $k): array {
            $v = max(1e-12, $v0 - $a * $tt);
            return [$v * cos($theta), $v * sin($theta), $k / $v];
        };
        // Stop just short of rest, where dθ/dt grows without bound; the remaining path is tiny.
        while ($t + $dt < $stop - 1e-3) {
            $k1 = $f($t, $th);
            $k2 = $f($t + $dt / 2, $th + $dt / 2 * $k1[2]);
            $k3 = $f($t + $dt / 2, $th + $dt / 2 * $k2[2]);
            $k4 = $f($t + $dt, $th + $dt * $k3[2]);
            $x += $dt / 6 * ($k1[0] + 2 * $k2[0] + 2 * $k3[0] + $k4[0]);
            $y += $dt / 6 * ($k1[1] + 2 * $k2[1] + 2 * $k3[1] + $k4[1]);
            $th += $dt / 6 * ($k1[2] + 2 * $k2[2] + 2 * $k3[2] + $k4[2]);
            $t += $dt;
        }
        return ['x' => $x, 'y' => $y];
    }
}
