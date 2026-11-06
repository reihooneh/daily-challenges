<?php

declare(strict_types=1);

namespace Grassline;

/**
 * A log of real shots on one green, to calibrate a set of bowls:
 *   green 14.5        the green's speed in seconds, if known
 *   draw 25.0 2.10    a bowl drawn to a jack at 25.0 m needed the aiming line 2.10 m wide at the jack
 *   timed 27.4 14.2   a bowl that came to rest 27.4 m from the mat took 14.2 s
 * Lines may have a # comment. Errors give the line number, never the line.
 */
final class Log
{
    public const MAX_BYTES = 64 * 1024;
    public const MAX_LINE = 200;
    public const MAX_SHOTS = 200;

    /** @var list<array{0: float, 1: float}> */
    public array $draws = [];
    /** @var list<array{0: float, 1: float}> */
    public array $timed = [];
    public ?float $green = null;

    public static function parse(string $bytes): self
    {
        if (strlen($bytes) > self::MAX_BYTES) {
            throw new InputError('the log is larger than 64 KB');
        }
        if (!mb_check_encoding($bytes, 'UTF-8')) {
            throw new InputError('the log is not valid UTF-8 text');
        }
        $text = preg_replace('/\A\x{FEFF}/u', '', $bytes);
        $log = new self();
        $n = 0;
        foreach (explode("\n", $text) as $raw) {
            $n++;
            $line = rtrim($raw, "\r");
            if (mb_strlen($line) > self::MAX_LINE) {
                throw new InputError("line $n: is longer than " . self::MAX_LINE . ' characters');
            }
            if (preg_match('/[\x00-\x08\x0A-\x1F\x7F-\x9F\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{206F}\x{FEFF}]/u', $line)) {
                throw new InputError("line $n: contains a control or invisible formatting character");
            }
            $line = trim(explode('#', $line, 2)[0]);
            if ($line === '') {
                continue;
            }
            $w = preg_split('/\s+/', $line);
            $num = static function (string $s, string $what, float $lo, float $hi) use ($n): float {
                if (!preg_match('/\A[0-9]{1,2}(\.[0-9]{1,3})?\z/', $s)) {
                    throw new InputError("line $n: $what must be a number like 25 or 2.15");
                }
                $v = (float) $s;
                if ($v < $lo || $v > $hi) {
                    throw new InputError("line $n: $what must be from $lo to $hi");
                }
                return $v;
            };
            if ($w[0] === 'green' && count($w) === 2) {
                if ($log->green !== null) {
                    throw new InputError("line $n: the green's speed is given twice");
                }
                $log->green = $num($w[1], "the green's speed (seconds)", 8, 25);
            } elseif ($w[0] === 'draw' && count($w) === 3) {
                $len = $num($w[1], 'the jack length (m)', 15, 40);
                $wid = $num($w[2], 'the width (m)', 0.2, 6);
                if ($wid > 0.35 * $len) {
                    throw new InputError("line $n: a width that large for that length is not a draw shot");
                }
                $log->draws[] = [$len, $wid];
            } elseif ($w[0] === 'timed' && count($w) === 3) {
                $log->timed[] = [$num($w[1], 'the distance (m)', 15, 40), $num($w[2], 'the time (seconds)', 5, 30)];
            } else {
                throw new InputError("line $n: lines are 'green SECONDS', 'draw LENGTH WIDTH' or 'timed DISTANCE SECONDS'");
            }
            if (count($log->draws) + count($log->timed) > self::MAX_SHOTS) {
                throw new InputError('at most ' . self::MAX_SHOTS . ' shots');
            }
        }
        if (!$log->draws) {
            throw new InputError("the log needs at least one 'draw LENGTH WIDTH' line");
        }
        if ($log->green === null && !$log->timed) {
            throw new InputError("the log needs the green's speed: a 'green SECONDS' or 'timed DISTANCE SECONDS' line");
        }
        return $log;
    }

    /**
     * Fits the bowls to the log. The model says width = (c/2) × length for every draw, so c is the
     * least-squares slope through the origin; timed bowls then give the deceleration, a = L √(4 + c²) / T².
     */
    public function fit(): array
    {
        $sxy = 0.0;
        $sxx = 0.0;
        foreach ($this->draws as [$len, $wid]) {
            $sxy += $len * $wid;
            $sxx += $len * $len;
        }
        $slope = $sxy / $sxx;
        $c = 2 * $slope;
        $resid = 0.0;
        foreach ($this->draws as [$len, $wid]) {
            $resid = max($resid, abs($wid - $slope * $len));
        }
        if ($this->timed) {
            $as = array_map(static fn ($t) => $t[0] * sqrt(4 + $c * $c) / ($t[1] * $t[1]), $this->timed);
            $a = array_sum($as) / count($as);
            // The green speed these bowls imply: the time to a 30-yard jack.
            $seconds = Physics::duration(Physics::GREEN_LENGTH, $a, $c);
        } else {
            $seconds = $this->green;
            $a = Physics::GREEN_LENGTH * sqrt(4 + $c * $c) / ($seconds * $seconds);
        }
        return [
            'bowls' => new Bowls($c * $a, 'your bowls (from ' . count($this->draws) . ' draw' . (count($this->draws) === 1 ? '' : 's') . ')'),
            'seconds' => $seconds,
            'angle' => rad2deg(atan($c / 2)),
            'worst' => $resid,
        ];
    }
}
