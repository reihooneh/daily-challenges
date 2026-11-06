<?php

declare(strict_types=1);

namespace Grassline;

/** A set of bowls: how strongly their bias turns them (K, in rad·m/s²). */
final class Bowls
{
    /**
     * Typical widths (m) at a 30-yard jack on a 14-second green, for bowls described as narrow,
     * medium or wide. Real sets vary: calibrate from your own shots with a log file.
     */
    public const PRESETS = ['narrow' => 1.9, 'medium' => 2.2, 'wide' => 2.5];

    public function __construct(public readonly float $k, public readonly string $label)
    {
        if (!($k > 0 && $k < 1)) {
            throw new InputError('the bias constant is out of range');
        }
    }

    /** From an observed width W (m) at jack length L (m) on a green of T seconds. */
    public static function fromWidth(float $width, float $length, float $seconds, string $label): self
    {
        $c = 2 * $width / $length;                                 // tan(aim) = c / 2 at every length
        $a = Physics::GREEN_LENGTH * sqrt(4 + $c * $c) / ($seconds * $seconds); // the green's deceleration
        return new self($c * $a, $label);
    }

    public static function preset(string $name): self
    {
        if (!array_key_exists($name, self::PRESETS)) {
            throw new InputError('the bias is narrow, medium or wide');
        }
        return self::fromWidth(self::PRESETS[$name], Physics::GREEN_LENGTH, 14.0, "$name bias");
    }
}

/** One draw shot: where to aim so the bowl finishes on the jack. */
final class Shot
{
    public readonly float $a;
    public readonly float $c;
    public readonly float $angle;   // radians off the centre line, to the outside of the curve
    public readonly float $v0;

    public function __construct(public readonly Bowls $bowls, public readonly float $seconds, public readonly float $length)
    {
        $this->a = Physics::decelerationFor($seconds, $bowls->k);
        $this->c = $bowls->k / $this->a;
        $this->angle = Physics::aimAngle($this->c);
        $this->v0 = Physics::speedFor($length, $this->a, $this->c);
    }

    /** How far right of the centre line the aiming line is, at the jack. */
    public function width(): float
    {
        return $this->length * tan($this->angle);
    }

    /** How far right of the centre line a spot d metres along the aiming line is. */
    public function stare(float $d): float
    {
        return $d * sin($this->angle);
    }

    public function duration(): float
    {
        return $this->v0 / $this->a;
    }

    public function pathLength(): float
    {
        return $this->v0 * $this->v0 / (2 * $this->a);
    }

    /**
     * The path on the rink: 'along' metres from the mat towards the jack, 'across' metres right of
     * the centre line (the bowl is aimed right and curves left onto the jack).
     */
    public function path(int $points = 240): array
    {
        $out = [];
        $cos = cos($this->angle);
        $sin = sin($this->angle);
        // Spread the samples evenly in distance travelled, so the slow hook at the end is not crowded.
        for ($i = 0; $i <= $points; $i++) {
            $frac = $i / $points;
            $v = $this->v0 * sqrt(max(0.0, 1 - $frac));
            $u = $v > 0 ? log($this->v0 / $v) : 12.0;
            $p = Physics::at($this->v0, $this->a, $this->c, min($u, 12.0));
            $out[] = [
                'along' => $p['x'] * $cos + $p['y'] * $sin,
                'across' => $p['x'] * $sin - $p['y'] * $cos,
                't' => $p['t'],
                'v' => $p['v'],
            ];
        }
        return $out;
    }

    /** The widest point of the path from the centre line: the bowl's "shoulder". */
    public function shoulder(): array
    {
        $best = ['across' => 0.0, 'along' => 0.0];
        foreach ($this->path(2000) as $p) {
            if ($p['across'] > $best['across']) {
                $best = $p;
            }
        }
        return $best;
    }

    /** Where a bowl finishes if it is delivered with the speed off by a fraction e (0.05 = 5 % heavy). */
    public function withWeightError(float $e): array
    {
        // Every position scales with v0², along the same line: it stays on line, long or short.
        return ['along' => $this->length * (1 + $e) ** 2, 'across' => 0.0];
    }

    /** Where it finishes if the aim is off by a number of degrees (positive: too wide). */
    public function withLineError(float $degrees): array
    {
        $r = deg2rad($degrees);
        return ['along' => $this->length * cos($r), 'across' => $this->length * sin($r)];
    }
}

final class InputError extends \RuntimeException
{
}
