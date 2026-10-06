<?php

declare(strict_types=1);

namespace HeavyTwin;

/** The command line. run() returns the exit code and never throws for bad input. */
final class Cli
{
    private const USAGE = <<<'TEXT'
        Usage:
          heavytwin FORMULA [--charge N]     masses and isotope pattern, e.g. heavytwin C6H5Br
          heavytwin --read M1 M2             read a pattern backwards: M+1 and M+2 as % of M
          heavytwin --elements               list the supported elements

        Formulas may use brackets and hydrates: Ca(OH)2, K4[Fe(CN)6], CuSO4.5H2O
        Exit codes: 0 success, 2 the input could not be understood.

        TEXT;

    /**
     * @param list<string> $args
     * @param resource $out
     * @param resource $err
     */
    public static function run(array $args, $out, $err): int
    {
        try {
            if ($args === [] || $args === ['-h'] || $args === ['--help']) {
                fwrite($args === [] ? $err : $out, self::USAGE);
                return $args === [] ? 2 : 0;
            }
            if ($args === ['--elements']) {
                fwrite($out, implode(' ', array_keys(Elements::ISOTOPES)) . "\n");
                return 0;
            }
            if ($args[0] === '--read') {
                if (count($args) !== 3) {
                    throw new FormulaException('--read needs two numbers: the M+1 and M+2 heights as percentages of M');
                }
                foreach (Reader::read(self::number($args[1]), self::number($args[2])) as $clue) {
                    fwrite($out, "- $clue\n");
                }
                fwrite($out, "These are rules of thumb. They suggest; they do not prove.\n");
                return 0;
            }

            $charge = 0;
            if (count($args) === 3 && $args[1] === '--charge') {
                if (preg_match('/^[+-]?[1-9]$/', $args[2]) !== 1) {
                    throw new FormulaException('--charge must be a whole number from -9 to 9, not zero');
                }
                $charge = (int) $args[2];
            } elseif (count($args) !== 1) {
                throw new FormulaException('expected one formula (see --help)');
            }
            fwrite($out, self::report(Formula::parse($args[0]), $charge));
            return 0;
        } catch (FormulaException $problem) {
            fwrite($err, 'heavytwin: ' . $problem->getMessage() . "\n");
            return 2;
        }
    }

    private static function number(string $text): float
    {
        if (preg_match('/^\d{1,4}(\.\d{1,3})?$/', $text) !== 1) {
            throw new FormulaException('peak heights must be plain numbers such as 8.8 or 32');
        }
        return (float) $text;
    }

    /** @param array<string, int> $atoms */
    private static function report(array $atoms, int $charge): string
    {
        $parts = [];
        foreach ($atoms as $symbol => $count) {
            $parts[] = $symbol . ($count > 1 ? (string) $count : '');
        }
        $mono = Pattern::monoisotopicMass($atoms);
        $lines = [
            'Formula:            ' . implode(' ', $parts) . '   (' . array_sum($atoms) . ' atoms)',
            sprintf('Average mass:       %.3f   (what you weigh out on a balance)', Pattern::averageMass($atoms)),
            sprintf('Monoisotopic mass:  %.5f   (the M peak: every atom its most common isotope)', $mono),
        ];
        // A positive ion has lost electrons; a negative ion has gained them.
        $toMz = static fn (float $mass): float => $charge === 0 ? $mass : ($mass - $charge * Elements::ELECTRON_MASS) / abs($charge);
        if ($charge !== 0) {
            $lines[] = sprintf('m/z at charge %+d:   %.5f', $charge, $toMz($mono));
        }
        $lines[] = '';
        $lines[] = 'Isotope pattern (tallest peak = 100):';
        foreach (Pattern::relative($atoms) as $shift => [$percent, $mass]) {
            $label = $shift === 0 ? 'M  ' : sprintf('M%+d', $shift);
            $lines[] = rtrim(sprintf('  %-4s %10.4f  %6.1f  %s', $label, $toMz($mass), $percent, str_repeat('#', (int) round($percent * 0.4))));
        }
        $lines[] = '';
        $lines[] = 'Why it looks like this:';
        foreach (Pattern::explain($atoms) as $note) {
            $lines[] = "  - $note";
        }
        return implode("\n", $lines) . "\n";
    }
}
