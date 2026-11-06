<?php

declare(strict_types=1);

namespace Grassline;

/** The plan for a shot in words, as a picture of the rink, and as SVG. */
final class Report
{
    private static function m(float $v): string
    {
        return number_format($v, 2) . ' m';
    }

    /**
     * $aimSide is the side the player aims to ('right' or 'left'); the bowl curves the other way.
     */
    public static function text(Shot $shot, string $hand, string $aimSide, float $stareAt, float $rink, ?array $fit = null): string
    {
        $other = $aimSide === 'right' ? 'left' : 'right';
        $sh = $shot->shoulder();
        $o = [];
        $o[] = sprintf('GRASSLINE  %s, %s, %.1f-second green, jack at %.1f m', $hand, $shot->bowls->label, $shot->seconds, $shot->length);
        if ($fit) {
            $o[] = sprintf('Fitted from your log: these bowls take %.2f° of grass on a %.1f-second green (worst draw off the fit by %s).', $fit['angle'], $fit['seconds'], self::m($fit['worst']));
        }
        $o[] = '';
        $o[] = sprintf('Aim %.2f° %s of the centre line:', rad2deg($shot->angle), $aimSide);
        $o[] = sprintf('  %s %s of the jack, measured across at the jack', self::m($shot->width()), $aimSide);
        $o[] = sprintf('  a stare spot %.1f m along your line is %d cm %s of the centre line', $stareAt, (int) round(100 * $shot->stare($stareAt)), $aimSide);
        $o[] = sprintf('The bowl leaves the hand at %.2f m/s, travels %s in %.1f s, and is widest (its shoulder) %s %s of centre at %s up the rink, then curves %s onto the jack.',
            $shot->v0, self::m($shot->pathLength()), $shot->duration(), self::m($sh['across']), $aimSide, self::m($sh['along']), $other);
        $half = $rink / 2;
        $o[] = $sh['across'] <= $half
            ? sprintf('It stays within this rink (%.1f m wide) the whole way.', $rink)
            : sprintf('Its shoulder is %s past this rink\'s %s boundary (%.1f m wide): it passes over the next rink.', self::m($sh['across'] - $half), $aimSide, $rink);
        $o[] = '';
        $o[] = 'If it goes wrong:';
        foreach ([0.05, -0.05] as $e) {
            $p = $shot->withWeightError($e);
            $o[] = sprintf('  %d%% too %-5s on the right line: finishes %s %s, still on the centre line', 5, $e > 0 ? 'heavy' : 'light', self::m(abs($p['along'] - $shot->length)), $e > 0 ? 'past the jack' : 'short');
        }
        foreach ([1.0, -1.0] as $d) {
            $p = $shot->withLineError($d);
            $o[] = sprintf('  1° too %-6s with the right weight: finishes %s %s of the jack', $d > 0 ? 'wide' : 'narrow', self::m(abs($p['across'])), $d > 0 ? $aimSide : $other);
        }
        $o[] = '';
        $o[] = 'The same bowls at other jack lengths (the angle of aim does not change):';
        $o[] = sprintf('  %-8s %-14s %-12s %-10s %s', 'Jack', 'Width at jack', 'Shoulder', 'Time', 'Delivery speed');
        foreach ([23.0, 25.0, 27.0, 29.0, 31.0, 33.0, 35.0] as $len) {
            $s = new Shot($shot->bowls, $shot->seconds, $len);
            $o[] = sprintf('  %-8s %-14s %-12s %-10s %.2f m/s', $len . ' m', self::m($s->width()), self::m($s->shoulder()['across']), sprintf('%.1f s', $s->duration()), $s->v0);
        }
        $o[] = '';
        $o[] = sprintf('The same jack on other greens (faster greens, more seconds, need more grass):');
        foreach ([10.0, 12.0, 14.0, 16.0, 18.0] as $sec) {
            $s = new Shot($shot->bowls, $sec, $shot->length);
            $o[] = sprintf('  %4.1f-second green: aim %.2f°, %s wide at the jack', $sec, rad2deg($s->angle), self::m($s->width()));
        }
        $o[] = '';
        $o[] = self::rink($shot, $aimSide, $rink);
        return implode("\n", $o) . "\n";
    }

    /** The rink from above, the far end at the top: the path (o), aiming line (.), jack (J), mat (M). */
    public static function rink(Shot $shot, string $aimSide, float $rink): string
    {
        $half = $rink / 2;
        $step = 0.25;
        $cols = (int) round($rink / $step) + 1;
        $rows = (int) ceil($shot->length) + 2;
        $grid = [];
        for ($r = 0; $r <= $rows; $r++) {
            $grid[$r] = array_fill(0, $cols, ' ');
            $grid[$r][intdiv($cols, 2)] = ':';
        }
        $put = function (float $along, float $across, string $ch) use (&$grid, $rows, $cols, $half, $step, $aimSide): void {
            $x = $aimSide === 'right' ? $across : -$across;
            $col = (int) round(($x + $half) / $step);
            $row = $rows - (int) round($along);
            if ($row >= 0 && $row <= $rows && $col >= 0 && $col < $cols) {
                $grid[$row][$col] = $ch;
            }
        };
        for ($d = 0; $d <= $shot->length; $d += 0.5) {
            $put($d * cos($shot->angle), $d * sin($shot->angle), '.');
        }
        foreach ($shot->path(400) as $p) {
            $put($p['along'], $p['across'], 'o');
        }
        $put($shot->length, 0, 'J');
        $put(0, 0, 'M');
        $lines = [];
        foreach ($grid as $r => $row) {
            $lines[] = sprintf('%5s |%s|', ($rows - $r) % 5 === 0 ? ($rows - $r) . ' m' : '', implode('', $row));
        }
        return implode("\n", $lines);
    }

    private static function esc(string $s): string
    {
        return htmlspecialchars($s, ENT_QUOTES | ENT_XML1, 'UTF-8');
    }

    public static function svg(Shot $shot, string $aimSide, float $rink, string $title): string
    {
        $half = $rink / 2;
        $len = $shot->length + 2;
        $s = 24;   // pixels per metre
        $pad = 30;
        $w = $rink * $s + 2 * $pad;
        $h = $len * $s + 2 * $pad;
        $X = static fn (float $across) => $pad + ($half + ($aimSide === 'right' ? $across : -$across)) * $s;
        $Y = static fn (float $along) => $pad + ($len - $along) * $s;
        $o = [sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f">', $w, $h, $w, $h)];
        $o[] = '<title>' . self::esc($title) . '</title>';
        $o[] = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#4f8a3c"/>', $pad, $pad, $rink * $s, $len * $s);
        $o[] = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e8f0dc" stroke-width="1" stroke-dasharray="4 4"/>', $X(0), $Y($len), $X(0), $Y(0));
        $o[] = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#f2c230" stroke-width="2" stroke-dasharray="6 4"/>', $X(0), $Y(0), $X($shot->length * tan($shot->angle)), $Y($shot->length));
        $pts = array_map(static fn ($p) => sprintf('%.1f,%.1f', $X($p['across']), $Y($p['along'])), $shot->path(300));
        $o[] = '<polyline fill="none" stroke="#1b2a4a" stroke-width="3" stroke-linejoin="round" points="' . implode(' ', $pts) . '"/>';
        $o[] = sprintf('<circle cx="%.1f" cy="%.1f" r="5" fill="#ffffff" stroke="#1b2a4a" stroke-width="1.5"/>', $X(0), $Y($shot->length));
        $o[] = sprintf('<rect x="%.1f" y="%.1f" width="14" height="8" fill="#1b2a4a"/>', $X(0) - 7, $Y(0) - 4);
        $o[] = '</svg>';
        return implode("\n", $o) . "\n";
    }
}
