<?php

declare(strict_types=1);

namespace HeavyTwin;

/**
 * Predicts the isotope pattern of a molecule: how much of it is one, two,
 * three... mass units heavier than the lightest version, and why.
 *
 * A distribution is a map from "extra mass units" to probability. One carbon
 * atom is {0: 0.9893, 1: 0.0107}. Putting two atoms together means every
 * combination of their possibilities: offsets add, probabilities multiply.
 * That operation is a convolution, the same one used to multiply polynomials.
 */
final class Pattern
{
    /**
     * Peaks more than ten billion times smaller than the tallest are dropped
     * after every step. No instrument could see them, and without pruning the
     * work would grow with every atom added.
     */
    private const RELATIVE_FLOOR = 1e-10;

    /**
     * Each peak is [probability, probability x mass]. Carrying the second
     * number through the convolution gives every peak's true average mass
     * for free: divide it by the first.
     *
     * @param array<string, int> $atoms
     * @return array<int, array{float, float}> offset from the lightest isotopologue => peak
     */
    public static function distribution(array $atoms): array
    {
        $result = [0 => [1.0, 0.0]];
        foreach ($atoms as $symbol => $count) {
            $result = self::convolve($result, self::power(self::single($symbol), $count));
        }
        ksort($result);
        return $result;
    }

    /**
     * One atom of an element, measured from its LIGHTEST isotope.
     * @return array<int, array{float, float}>
     */
    public static function single(string $symbol): array
    {
        $isotopes = Elements::ISOTOPES[$symbol];
        $lightest = $isotopes[0][0];
        $out = [];
        foreach ($isotopes as [$massNumber, $mass, $abundance]) {
            $out[$massNumber - $lightest] = [$abundance, $abundance * $mass];
        }
        return $out;
    }

    /**
     * n atoms of the same element. Instead of convolving n times, square
     * repeatedly (x, x^2, x^4, x^8...) and combine the pieces n is made of.
     * 1,000 atoms then take about 10 steps instead of 1,000.
     *
     * @param array<int, array{float, float}> $base
     * @return array<int, array{float, float}>
     */
    public static function power(array $base, int $n): array
    {
        $result = [0 => [1.0, 0.0]];
        while ($n > 0) {
            if ($n & 1) {
                $result = self::convolve($result, $base);
            }
            $n >>= 1;
            if ($n > 0) {
                $base = self::convolve($base, $base);
            }
        }
        return $result;
    }

    /**
     * @param array<int, array{float, float}> $a
     * @param array<int, array{float, float}> $b
     * @return array<int, array{float, float}>
     */
    public static function convolve(array $a, array $b): array
    {
        $out = [];
        foreach ($a as $offsetA => [$pa, $ma]) {
            foreach ($b as $offsetB => [$pb, $mb]) {
                $offset = $offsetA + $offsetB;
                $out[$offset] ??= [0.0, 0.0];
                $out[$offset][0] += $pa * $pb;
                // Masses add, so the weighted mass of a pair is ma*pb + pa*mb.
                $out[$offset][1] += $ma * $pb + $pa * $mb;
            }
        }
        $floor = max(array_column($out, 0)) * self::RELATIVE_FLOOR;
        return array_filter($out, static fn (array $peak): bool => $peak[0] >= $floor);
    }

    /**
     * Heights relative to the tallest peak (= 100), numbered from the
     * monoisotopic peak M (every atom its most common isotope).
     *
     * @param array<string, int> $atoms
     * @return array<int, array{float, float}> shift from M (negative for e.g. iron) => [percent, mass]
     */
    public static function relative(array $atoms, float $threshold = 0.05): array
    {
        $distribution = self::distribution($atoms);
        $monoOffset = 0;
        foreach ($atoms as $symbol => $count) {
            $monoOffset += (Elements::mostAbundant($symbol)[0] - Elements::ISOTOPES[$symbol][0][0]) * $count;
        }
        $tallest = max(array_column($distribution, 0));
        $out = [];
        foreach ($distribution as $offset => [$p, $weightedMass]) {
            $percent = 100.0 * $p / $tallest;
            if ($percent >= $threshold) {
                $out[$offset - $monoOffset] = [$percent, $weightedMass / $p];
            }
        }
        return $out;
    }

    /**
     * @param array<string, int> $atoms
     */
    public static function monoisotopicMass(array $atoms): float
    {
        $mass = 0.0;
        foreach ($atoms as $symbol => $count) {
            $mass += Elements::monoisotopicMass($symbol) * $count;
        }
        return $mass;
    }

    /**
     * @param array<string, int> $atoms
     */
    public static function averageMass(array $atoms): float
    {
        $mass = 0.0;
        foreach ($atoms as $symbol => $count) {
            $mass += Elements::averageMass($symbol) * $count;
        }
        return $mass;
    }

    /**
     * Plain-language reasons for the M+1 and M+2 peaks.
     *
     * @param array<string, int> $atoms
     * @return list<string>
     */
    public static function explain(array $atoms): array
    {
        $notes = [];
        $c = $atoms['C'] ?? 0;
        if ($c > 0) {
            $notes[] = sprintf('M+1 is mostly carbon-13: %d carbon%s x 1.1%% = about %.1f%%.', $c, $c === 1 ? '' : 's', $c * 1.0816);
        }
        foreach (['Cl' => ['chlorine-37', 'about a third the height of M'], 'Br' => ['bromine-81', 'almost as tall as M']] as $symbol => [$isotope, $look]) {
            $n = $atoms[$symbol] ?? 0;
            if ($n === 1) {
                $notes[] = "M+2 is $look: the signature of one $isotope atom.";
            } elseif ($n > 1) {
                $notes[] = sprintf('%d %s atoms give a ladder of peaks two units apart (M, M+2, M+4...).', $n, $symbol === 'Cl' ? 'chlorine' : 'bromine');
            }
        }
        if (($atoms['S'] ?? 0) > 0) {
            $notes[] = sprintf('Sulfur-34 adds about %.1f%% to M+2.', 4.47 * $atoms['S']);
        }
        if (($atoms['Si'] ?? 0) > 0) {
            $notes[] = 'Silicon adds to both M+1 (silicon-29) and M+2 (silicon-30).';
        }
        foreach (['Fe', 'Se', 'Zn', 'Cu', 'Ca', 'Mg', 'B', 'Li', 'K'] as $metal) {
            if (($atoms[$metal] ?? 0) > 0 && count(Elements::ISOTOPES[$metal]) > 1) {
                $notes[] = "$metal has several common isotopes, which spreads the pattern out.";
            }
        }
        if ($notes === []) {
            $notes[] = 'Every element here has one dominant isotope, so M stands almost alone.';
        }
        return $notes;
    }
}
