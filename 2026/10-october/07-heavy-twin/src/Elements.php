<?php

declare(strict_types=1);

namespace HeavyTwin;

/**
 * Isotope data for the elements that turn up in everyday chemistry.
 *
 * Each isotope is [mass number, exact mass in daltons, natural abundance].
 * Values are the NIST "Atomic Weights and Isotopic Compositions" figures.
 * A test checks that every element's abundances add up to 1 and that its
 * weighted average matches the standard atomic weight on the periodic table.
 */
final class Elements
{
    public const ELECTRON_MASS = 0.000548579909;

    /** @var array<string, list<array{int, float, float}>> */
    public const ISOTOPES = [
        'H'  => [[1, 1.00782503223, 0.999885], [2, 2.01410177812, 0.000115]],
        'Li' => [[6, 6.0151228874, 0.0759], [7, 7.0160034366, 0.9241]],
        'B'  => [[10, 10.01293695, 0.199], [11, 11.00930536, 0.801]],
        'C'  => [[12, 12.0, 0.9893], [13, 13.00335483507, 0.0107]],
        'N'  => [[14, 14.00307400443, 0.99636], [15, 15.00010889888, 0.00364]],
        'O'  => [[16, 15.99491461957, 0.99757], [17, 16.99913175650, 0.00038], [18, 17.99915961286, 0.00205]],
        'F'  => [[19, 18.99840316273, 1.0]],
        'Na' => [[23, 22.9897692820, 1.0]],
        'Mg' => [[24, 23.985041697, 0.7899], [25, 24.985836976, 0.1000], [26, 25.982592968, 0.1101]],
        'Al' => [[27, 26.98153853, 1.0]],
        'Si' => [[28, 27.97692653465, 0.92223], [29, 28.97649466490, 0.04685], [30, 29.973770136, 0.03092]],
        'P'  => [[31, 30.97376199842, 1.0]],
        'S'  => [[32, 31.9720711744, 0.9499], [33, 32.9714589098, 0.0075], [34, 33.967867004, 0.0425], [36, 35.96708071, 0.0001]],
        'Cl' => [[35, 34.968852682, 0.7576], [37, 36.965902602, 0.2424]],
        'K'  => [[39, 38.9637064864, 0.932581], [40, 39.963998166, 0.000117], [41, 40.9618252579, 0.067302]],
        'Ca' => [[40, 39.962590863, 0.96941], [42, 41.95861783, 0.00647], [43, 42.95876644, 0.00135], [44, 43.95548156, 0.02086], [46, 45.9536890, 0.00004], [48, 47.95252276, 0.00187]],
        'Fe' => [[54, 53.93960899, 0.05845], [56, 55.93493633, 0.91754], [57, 56.93539284, 0.02119], [58, 57.93327443, 0.00282]],
        'Cu' => [[63, 62.92959772, 0.6915], [65, 64.92778970, 0.3085]],
        'Zn' => [[64, 63.92914201, 0.4917], [66, 65.92603381, 0.2773], [67, 66.92712775, 0.0404], [68, 67.92484455, 0.1845], [70, 69.9253192, 0.0061]],
        'Se' => [[74, 73.922475934, 0.0089], [76, 75.919213704, 0.0937], [77, 76.919914154, 0.0763], [78, 77.91730928, 0.2377], [80, 79.9165218, 0.4961], [82, 81.9166995, 0.0873]],
        'Br' => [[79, 78.9183376, 0.5069], [81, 80.9162897, 0.4931]],
        'I'  => [[127, 126.9044719, 1.0]],
    ];

    /** Standard atomic weights, used only to cross-check the table above. */
    public const STANDARD_WEIGHTS = [
        'H' => 1.008, 'Li' => 6.94, 'B' => 10.81, 'C' => 12.011, 'N' => 14.007, 'O' => 15.999, 'F' => 18.998,
        'Na' => 22.990, 'Mg' => 24.305, 'Al' => 26.982, 'Si' => 28.085, 'P' => 30.974, 'S' => 32.06,
        'Cl' => 35.45, 'K' => 39.098, 'Ca' => 40.078, 'Fe' => 55.845, 'Cu' => 63.546, 'Zn' => 65.38,
        'Se' => 78.971, 'Br' => 79.904, 'I' => 126.904,
    ];

    public static function known(string $symbol): bool
    {
        return isset(self::ISOTOPES[$symbol]);
    }

    /** Mass of the most common isotope: what a mass spectrometer calls "M". */
    public static function monoisotopicMass(string $symbol): float
    {
        return self::mostAbundant($symbol)[1];
    }

    /** @return array{int, float, float} */
    public static function mostAbundant(string $symbol): array
    {
        $best = self::ISOTOPES[$symbol][0];
        foreach (self::ISOTOPES[$symbol] as $isotope) {
            if ($isotope[2] > $best[2]) {
                $best = $isotope;
            }
        }
        return $best;
    }

    /** Abundance-weighted mean: the number printed on the periodic table. */
    public static function averageMass(string $symbol): float
    {
        $sum = 0.0;
        foreach (self::ISOTOPES[$symbol] as [, $mass, $abundance]) {
            $sum += $mass * $abundance;
        }
        return $sum;
    }
}
