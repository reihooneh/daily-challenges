<?php

declare(strict_types=1);

namespace HeavyTwin;

/**
 * Works backwards: from the heights of the M+1 and M+2 peaks to what is
 * probably in the molecule. These are the rules of thumb taught in organic
 * chemistry, with the numbers taken from the isotope table.
 */
final class Reader
{
    /**
     * @param float $m1 height of M+1 as a percentage of M
     * @param float $m2 height of M+2 as a percentage of M
     * @return list<string>
     */
    public static function read(float $m1, float $m2): array
    {
        foreach ([$m1, $m2] as $value) {
            if (!is_finite($value) || $value < 0 || $value > 1000) {
                throw new FormulaException('peak heights must be percentages between 0 and 1000');
            }
        }
        $clues = [];

        // Halogens first: they dominate M+2 and their ratios are distinctive.
        $cl = 100 * 0.2424 / 0.7576;   // 32.0
        $br = 100 * 0.4931 / 0.5069;   // 97.3
        $remaining = $m2;
        if (abs($m2 - $br) <= 8) {
            $clues[] = sprintf('M+2 is almost as tall as M (%.0f%%): one bromine atom (expected %.0f%%).', $m2, $br);
            $remaining = 0.0;
        } elseif (abs($m2 - $cl) <= 5) {
            $clues[] = sprintf('M+2 is about a third of M (%.0f%%): one chlorine atom (expected %.0f%%).', $m2, $cl);
            $remaining = 0.0;
        } elseif (abs($m2 - 2 * $cl) <= 7) {
            $clues[] = sprintf('M+2 is about two thirds of M (%.0f%%): two chlorine atoms (expected %.0f%%; look for M+4 near 10%%).', $m2, 2 * $cl);
            $remaining = 0.0;
        } elseif (abs($m2 - 2 * $br) <= 15) {
            $clues[] = sprintf('M+2 is about twice M (%.0f%%): two bromine atoms (expected %.0f%%; M+4 should be about as tall as M).', $m2, 2 * $br);
            $remaining = 0.0;
        } elseif (abs($m2 - ($cl + $br)) <= 10) {
            $clues[] = sprintf('M+2 is taller than M (%.0f%%): one chlorine and one bromine (expected %.0f%%).', $m2, $cl + $br);
            $remaining = 0.0;
        }

        $carbons = (int) round($m1 / 1.0816);
        if ($carbons >= 1) {
            $clues[] = sprintf('M+1 is %.1f%% of M: about %d carbon atom%s (each adds 1.1%%).', $m1, $carbons, $carbons === 1 ? '' : 's');
            // Two carbon-13 atoms in one molecule also land on M+2.
            $remaining -= 0.0058 * $carbons * $carbons;
        } else {
            $clues[] = 'M+1 is tiny: few or no carbon atoms.';
        }

        if ($remaining >= 3.0) {
            $sulfurs = max(1, (int) round($remaining / 4.47));
            $clues[] = sprintf('The rest of M+2 (%.1f%%) fits %d sulfur atom%s (4.5%% each), or silicon (3.4%% each).', $remaining, $sulfurs, $sulfurs === 1 ? '' : 's');
        } elseif ($remaining >= 0.3) {
            $oxygens = max(1, (int) round($remaining / 0.2055));
            $clues[] = sprintf('The rest of M+2 (%.1f%%) fits roughly %d oxygen atom%s (0.2%% each).', $remaining, $oxygens, $oxygens === 1 ? '' : 's');
        } elseif ($m2 < 1.0 && $carbons >= 1) {
            $clues[] = 'M+2 is very small: no chlorine, bromine or sulfur.';
        }
        return $clues;
    }
}
