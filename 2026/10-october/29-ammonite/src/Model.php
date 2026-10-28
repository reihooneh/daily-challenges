<?php

declare(strict_types=1);

namespace Ammonite;

/**
 * The nitrogen cycle in a tank, day by day.
 *
 * Fish give off ammonia (TAN: total ammonia nitrogen). Ammonia-oxidising bacteria (AOB) in the
 * filter turn it into nitrite; nitrite-oxidising bacteria (NOB) turn that into nitrate, which is
 * fairly harmless and leaves with water changes. Each kind of bacteria grows on its food with
 * Monod kinetics (fast while food is plentiful, slowing as it runs short), grows faster when warm,
 * slows in acid water, and slowly dies back. NOB are also held back by free ammonia, which is why
 * an over-dosed fishless cycle can stall at the nitrite stage.
 *
 * All concentrations are mg of nitrogen per litre. The parameters are typical textbook values for
 * nitrifiers in aquarium filters, rounded; real tanks vary.
 */
final class Model
{
    public const DT = 0.1;          // days per step
    public const MU_AOB = 0.75;     // max growth per day at 20 °C
    public const MU_NOB = 0.6;
    public const K_AOB = 0.5;       // half-saturation, mg/L
    public const K_NOB = 0.6;
    public const Y_AOB = 0.15;      // biomass made per mg of nitrogen used
    public const Y_NOB = 0.05;
    public const DECAY = 0.04;      // per day
    public const THETA = 1.07;      // growth multiplies by this per °C
    public const SEED = 0.0005;     // a brand-new filter: a trace of bacteria on the media
    public const NOB_FA_INHIBIT = 0.6; // free ammonia (mg/L) at which NOB work at half speed

    /**
     * Runs the tank for $days days.
     *
     * @param array<int, list<int>> $adds  day => indexes of fish groups added that morning
     * @param float $dose                  ammonia dosed per day (mg/L) on days 0 .. $doseDays-1 (fishless cycling)
     * @return array{rows: list<array{day:int,tan:float,free:float,nitrite:float,nitrate:float,fish:int}>,
     *               peakFree: float, peakFreeDay: int, peakNitrite: float, peakNitriteDay: int,
     *               firstFish: int, capacity: float}
     */
    public static function run(Tank $tank, array $adds, int $days, float $dose = 0, int $doseDays = 0): array
    {
        $tempFactor = self::THETA ** ($tank->celsius - 20);
        $phFactor = $tank->ph >= 7 ? 1.0 : max(0.05, ($tank->ph - 5.5) / 1.5);
        $muA = self::MU_AOB * $tempFactor * $phFactor;
        $muN = self::MU_NOB * $tempFactor * $phFactor;
        $free = $tank->freeFraction();

        // A seeded filter starts with enough bacteria to clear $tank->seed mg/L a day of ammonia (and the nitrite it makes).
        $aob = max(self::SEED, $tank->seed * self::Y_AOB / max($muA, 1e-9));
        $nob = max(self::SEED, $tank->seed * self::Y_NOB / max($muN, 1e-9));
        $tan = $nitrite = $nitrate = 0.0;
        $load = 0.0;      // mg/L per day from the fish in the tank
        $fishCount = 0;
        $firstFish = -1;
        $rows = [];
        $peak = ['free' => 0.0, 'freeDay' => -1, 'nitrite' => 0.0, 'nitriteDay' => -1];
        $steps = (int) round(1 / self::DT);

        for ($day = 0; $day < $days; $day++) {
            foreach ($adds[$day] ?? [] as $g) {
                $load += $tank->fish[$g]->load() / $tank->litres;
                $fishCount += $tank->fish[$g]->count;
                if ($firstFish < 0) {
                    $firstFish = $day;
                }
            }
            if ($tank->changeEvery > 0 && $day > 0 && $day % $tank->changeEvery === 0) {
                $keep = 1 - $tank->changeShare;
                $tan *= $keep;
                $nitrite *= $keep;
                $nitrate *= $keep;
            }
            $input = $load + ($day < $doseDays ? $dose : 0);
            for ($s = 0; $s < $steps; $s++) {
                $fa = $tan * $free;
                $rA = $muA / self::Y_AOB * $aob * $tan / (self::K_AOB + $tan);
                $rN = $muN / self::Y_NOB * $nob * $nitrite / (self::K_NOB + $nitrite) / (1 + $fa / self::NOB_FA_INHIBIT);
                $rA = min($rA, $tan / self::DT + $input);         // can't use more than there is
                $rN = min($rN, $nitrite / self::DT + $rA);
                $tan = max(0.0, $tan + ($input - $rA) * self::DT);
                $nitrite = max(0.0, $nitrite + ($rA - $rN) * self::DT);
                $nitrate += $rN * self::DT;
                $aob = max(self::SEED, $aob + (self::Y_AOB * $rA - self::DECAY * $aob) * self::DT);
                $nob = max(self::SEED, $nob + (self::Y_NOB * $rN - self::DECAY * $nob) * self::DT);
                if ($fishCount > 0) {
                    if ($tan * $free > $peak['free']) {
                        $peak['free'] = $tan * $free;
                        $peak['freeDay'] = $day;
                    }
                    if ($nitrite > $peak['nitrite']) {
                        $peak['nitrite'] = $nitrite;
                        $peak['nitriteDay'] = $day;
                    }
                }
            }
            $rows[] = ['day' => $day, 'tan' => $tan, 'free' => $tan * $free, 'nitrite' => $nitrite, 'nitrate' => $nitrate, 'fish' => $fishCount];
        }
        return [
            'rows' => $rows,
            'peakFree' => $peak['free'], 'peakFreeDay' => $peak['freeDay'],
            'peakNitrite' => $peak['nitrite'], 'peakNitriteDay' => $peak['nitriteDay'],
            'firstFish' => $firstFish,
            // Ammonia (mg/L per day) the filter could clear at the end, if fed: a measure of how cycled it is.
            'capacity' => min($muA / self::Y_AOB * $aob, $muN / self::Y_NOB * $nob),
        ];
    }

    /** True if the fish never see more than the limits. */
    public static function safe(Tank $tank, array $result): bool
    {
        return $result['peakFree'] <= $tank->limitAmmonia && $result['peakNitrite'] <= $tank->limitNitrite;
    }
}
