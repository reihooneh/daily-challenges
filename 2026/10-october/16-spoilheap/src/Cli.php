<?php

declare(strict_types=1);

namespace Spoilheap;

final class Cli
{
    private const USAGE = <<<'TXT'
        Usage: spoilheap RECORD.txt [--dot]
               spoilheap - [--dot]        read the record from standard input

        Checks an excavation's stratigraphic record: loops in the sequence, dating clues that
        can't all be true, phases, date windows and redundant relations.
          --dot     print the cleaned-up Harris matrix as Graphviz DOT instead of the report
        Exit codes: 0 consistent, 1 problems found, 2 bad input.

        TXT;

    /** @param list<string> $args @param resource $out @param resource $err */
    public static function run(array $args, $out, $err, $stdin = null): int
    {
        $dot = false;
        $path = null;
        foreach ($args as $a) {
            if ($a === '--help' || $a === '-h') {
                fwrite($out, self::USAGE);
                return 0;
            }
            if ($a === '--dot') {
                $dot = true;
            } elseif ($path === null && ($a === '-' || !str_starts_with($a, '-'))) {
                $path = $a;
            } else {
                fwrite($err, "spoilheap: unexpected argument\n" . self::USAGE);
                return 2;
            }
        }
        if ($path === null) {
            fwrite($err, self::USAGE);
            return 2;
        }
        try {
            [$text, $name] = self::read($path, $stdin ?? STDIN);
            $record = Record::parse($text);
        } catch (RecordException $e) {
            fwrite($err, 'spoilheap: ' . $e->getMessage() . "\n");
            return 2;
        }
        $matrix = new Matrix($record);
        $dating = new Dating($matrix);
        fwrite($out, $dot ? Report::dot($matrix) : Report::render($matrix, $dating, $name));
        return Report::hasProblems($matrix, $dating) ? 1 : 0;
    }

    /** @return array{string, string} the text and a display-safe name */
    private static function read(string $path, $stdin): array
    {
        if ($path === '-') {
            $text = stream_get_contents($stdin, Record::MAX_BYTES + 1);
            return [$text === false ? '' : $text, 'standard input'];
        }
        // Only regular files, read with a size limit, so devices, pipes and huge files are refused.
        if (!is_file($path)) {
            throw new RecordException('no such file (or not a regular file)');
        }
        if (filesize($path) > Record::MAX_BYTES) {
            throw new RecordException('the record is larger than 64 KB');
        }
        $text = @file_get_contents($path, false, null, 0, Record::MAX_BYTES + 1);
        if ($text === false) {
            throw new RecordException('the file could not be read');
        }
        $name = preg_replace('/[^A-Za-z0-9._-]/', '?', basename($path));
        return [$text, substr($name, 0, 60)];
    }
}
