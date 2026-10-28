<?php

declare(strict_types=1);

namespace Ammonite;

/**
 * Finds a stocking plan: when to add each group of fish so they never meet more free ammonia or
 * nitrite than the limits, by simulating forward. Groups go in the order the file lists them;
 * each goes in on the earliest day that keeps every fish already in the tank, and itself, safe for
 * the following weeks. If even the first group can't go in safely within the search window, the
 * planner tries a fishless cycle first: dosing ammonia to grow the bacteria before any fish arrive.
 */
final class Planner
{
    public const WATCH = 42;      // days simulated after the last addition to check it settles safely
    public const MAX_WAIT = 90;   // latest day a group may be added
    public const MAX_CYCLE = 60;  // longest fishless cycle tried

    /** @return array{days: list<int>, cycleDays: int, dose: float, result: array, ok: bool} */
    public static function plan(Tank $tank): array
    {
        $plan = self::schedule($tank, 0, 0.0, 0);
        if ($plan !== null) {
            return $plan;
        }
        // Fishless cycle: dose about what the whole stock will produce every day until the first fish
        // arrive, so the bacteria grow to match it; the first fish go in on the earliest safe day.
        $dose = min(4.0, max(0.25, array_sum(array_map(static fn (FishGroup $g): float => $g->load(), $tank->fish)) / $tank->litres));
        $plan = self::schedule($tank, 7, $dose, -1);
        if ($plan !== null) {
            return $plan;
        }
        // Nothing worked: report the best effort (everything after the longest cycle) and say so.
        $adds = [self::MAX_CYCLE => array_keys($tank->fish)];
        $result = Model::run($tank, $adds, self::MAX_CYCLE + self::WATCH, $dose, self::MAX_CYCLE);
        return ['days' => array_fill(0, count($tank->fish), self::MAX_CYCLE), 'cycleDays' => self::MAX_CYCLE, 'dose' => $dose, 'result' => $result, 'ok' => false];
    }

    /**
     * Earliest safe day for each group in turn, starting no earlier than $start. With $doseDays = -1,
     * ammonia is dosed every day until the first group goes in. Null if a group can't fit.
     */
    private static function schedule(Tank $tank, int $start, float $dose, int $doseDays): ?array
    {
        $days = [];
        $adds = [];
        $from = $start;
        $limit = $doseDays < 0 ? self::MAX_CYCLE : $start + self::MAX_WAIT;
        foreach (array_keys($tank->fish) as $g) {
            $placed = false;
            for ($d = $from; $d <= max($limit, $from + self::MAX_WAIT); $d++) {
                if ($g === 0 && $d > $limit) {
                    break;
                }
                $dd = $doseDays < 0 ? ($g === 0 ? $d : $days[0]) : $doseDays;
                $trial = $adds;
                $trial[$d][] = $g;
                $result = Model::run($tank, $trial, $d + self::WATCH, $dose, $dd);
                if (Model::safe($tank, $result)) {
                    $adds = $trial;
                    $days[] = $d;
                    $from = $d;
                    $placed = true;
                    break;
                }
            }
            if (!$placed) {
                return null;
            }
        }
        $dd = $doseDays < 0 ? $days[0] : $doseDays;
        $result = Model::run($tank, $adds, max($days) + self::WATCH, $dose, $dd);
        return ['days' => $days, 'cycleDays' => $dose > 0 ? $dd : 0, 'dose' => $dose, 'result' => $result, 'ok' => true];
    }

    /** What happens if every fish goes in on day 0 with no cycling: the usual "new tank syndrome". */
    public static function allAtOnce(Tank $tank): array
    {
        return Model::run($tank, [0 => array_keys($tank->fish)], 70);
    }
}
