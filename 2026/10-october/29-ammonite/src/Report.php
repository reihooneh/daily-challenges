<?php

declare(strict_types=1);

namespace Ammonite;

/** The printed plan. Names come from the file but were checked against a safe character set. */
final class Report
{
    private static function mg(float $v): string
    {
        return $v >= 1 ? sprintf('%.1f', $v) : ($v >= 0.1 ? sprintf('%.2f', $v) : sprintf('%.3f', $v));
    }

    /** A small bar for the weekly table, 0 to the limit fills it; past the limit it shows "!". */
    private static function bar(float $v, float $limit): string
    {
        $n = (int) min(10, round($v / $limit * 10));
        return str_repeat('#', $n) . str_repeat('.', 10 - $n) . ($v > $limit ? '!' : ' ');
    }

    public static function render(Tank $t, array $plan, array $naive): string
    {
        $o = [];
        $o[] = "AMMONITE  {$t->name}";
        $o[] = sprintf('%g L at %g °C and pH %g: %.1f%% of the ammonia is the toxic free form (NH3).', $t->litres, $t->celsius, $t->ph, $t->freeFraction() * 100);
        $o[] = sprintf('Limits: free ammonia %s mg/L, nitrite %s mg/L (as nitrogen). Filter: %s.', self::mg($t->limitAmmonia), self::mg($t->limitNitrite),
            $t->seed > 0 ? sprintf('seeded, already clears %s mg/L of ammonia a day', self::mg($t->seed)) : 'new');
        $total = array_sum(array_map(static fn (FishGroup $g): float => $g->load(), $t->fish));
        $o[] = sprintf('The fish will give off about %s mg/L of ammonia a day when all are in.', self::mg($total / $t->litres));
        $o[] = '';

        if (Model::safe($t, $naive)) {
            $o[] = 'All the fish could go in on day 0 without passing the limits.';
        } else {
            $o[] = 'If every fish went in on day 0:';
            if ($naive['peakFree'] > $t->limitAmmonia) {
                $o[] = sprintf('  free ammonia would reach %s mg/L on day %d (%.0f times the limit),', self::mg($naive['peakFree']), $naive['peakFreeDay'], $naive['peakFree'] / $t->limitAmmonia);
            }
            if ($naive['peakNitrite'] > $t->limitNitrite) {
                $o[] = sprintf('  nitrite would reach %s mg/L on day %d (%.0f times the limit).', self::mg($naive['peakNitrite']), $naive['peakNitriteDay'], $naive['peakNitrite'] / $t->limitNitrite);
            }
        }
        $o[] = '';

        $r = $plan['result'];
        $o[] = $plan['ok'] ? 'Plan:' : 'No safe plan was found within the limits searched; the closest is:';
        if ($plan['cycleDays'] > 0) {
            $o[] = sprintf('  Days 0-%d: cycle the tank without fish, adding %s mg/L of ammonia (as nitrogen) each day.', $plan['cycleDays'] - 1, self::mg($plan['dose']));
        }
        foreach ($plan['days'] as $g => $day) {
            $f = $t->fish[$g];
            $o[] = sprintf('  Day %-3d add %d x %s (%s mg/L of ammonia a day)', $day, $f->count, $f->name, self::mg($f->load() / $t->litres));
        }
        $o[] = sprintf('  With this plan the fish meet at most %s mg/L free ammonia and %s mg/L nitrite.', self::mg($r['peakFree']), self::mg($r['peakNitrite']));
        $o[] = '';

        $o[] = 'Week by week:';
        $o[] = sprintf('  %-5s %5s %-12s %-12s %8s  %s', 'Day', 'Fish', 'Free NH3', 'Nitrite', 'Nitrate', '');
        $last = count($r['rows']) - 1;
        foreach ($r['rows'] as $row) {
            if ($row['day'] % 7 !== 0 && $row['day'] !== $last) {
                continue;
            }
            $o[] = sprintf('  %-5d %5d %s %s %8s', $row['day'], $row['fish'], self::bar($row['free'], $t->limitAmmonia), self::bar($row['nitrite'], $t->limitNitrite), self::mg($row['nitrate']));
        }
        $o[] = '  (bars fill up to the limit; "!" means over it. Fishless days may go over: no fish are there yet.)';
        $o[] = '';
        $end = $r['rows'][$last];
        if ($end['nitrate'] > 10) {
            $o[] = sprintf('Nitrate reaches %s mg/L as nitrogen (%.0f mg/L as nitrate) by day %d: plan regular water changes.', self::mg($end['nitrate']), $end['nitrate'] * 4.43, $end['day']);
        }
        $o[] = 'A model with typical bacteria, not a guarantee: test the water with a kit before each addition.';
        return implode("\n", $o) . "\n";
    }
}
