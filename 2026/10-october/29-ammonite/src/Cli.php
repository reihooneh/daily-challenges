<?php

declare(strict_types=1);

namespace Ammonite;

/** The command line, with its streams passed in so tests can drive it. Exit codes: 0 done, 2 bad usage or input. */
final class Cli
{
    /** @param list<string> $args  @param resource $out  @param resource $err  @param resource|null $in */
    public static function run(array $args, $out, $err, $in = null): int
    {
        if (count($args) !== 1 || in_array($args[0], ['-h', '--help'], true)) {
            fwrite($err, "usage: ammonite <tank.txt>   (or - for standard input)\nPlans when to add fish to a new tank so ammonia and nitrite stay safe.\n");
            return 2;
        }
        $text = self::read($args[0], $in ?? STDIN);
        if ($text === null) {
            fwrite($err, "ammonite: the tank file could not be read (it must be a readable file)\n");
            return 2;
        }
        try {
            $tank = Tank::parse($text);
        } catch (TankException $e) {
            fwrite($err, 'ammonite: ' . $e->getMessage() . "\n");
            return 2;
        }
        fwrite($out, Report::render($tank, Planner::plan($tank), Planner::allAtOnce($tank)));
        return 0;
    }

    /** Reads at most MAX_INPUT + 1 bytes, from a regular file only (or the given stream for "-"). */
    private static function read(string $path, $in): ?string
    {
        if ($path === '-') {
            $data = stream_get_contents($in, Tank::MAX_INPUT + 1);
            return $data === false ? null : $data;
        }
        if (str_contains($path, "\0") || !is_file($path) || !is_readable($path)) {
            return null;
        }
        $fh = @fopen($path, 'rb');
        if ($fh === false) {
            return null;
        }
        $data = stream_get_contents($fh, Tank::MAX_INPUT + 1);
        fclose($fh);
        return $data === false ? null : $data;
    }
}
