<?php

declare(strict_types=1);

namespace Catchbreath;

/**
 * catchbreath SONG.txt [--breath SECONDS] [--tempo BPM]   (- reads standard input)
 * Exit codes: 0 every phrase fits, 3 some stretch is longer than one breath, 1 bad song, 2 usage.
 */
final class Cli
{
    /** @param resource $in @param resource $out @param resource $err */
    public static function run(array $args, $in, $out, $err): int
    {
        $path = null;
        $over = [];
        for ($i = 0; $i < count($args); ++$i) {
            $a = (string) $args[$i];
            if ($a === '--breath' || $a === '--tempo') {
                $v = $args[++$i] ?? '';
                $over[substr($a, 2)] = (string) $v;
            } elseif ($path === null && ($a === '-' || !str_starts_with($a, '-'))) {
                $path = $a;
            } else {
                $path = null;
                break;
            }
        }
        if ($path === null) {
            fwrite($err, "usage: catchbreath SONG.txt [--breath SECONDS] [--tempo BPM]   (- reads standard input)\n");
            return 2;
        }
        try {
            $text = self::read($path, $in);
            $song = Song::parse($text);
            foreach ($over as $key => $value) {
                $song->applySetting($key, $value);
            }
            $plan = (new Planner($song))->plan();
        } catch (SongError $e) {
            fwrite($err, 'catchbreath: ' . $e->getMessage() . "\n");
            return 1;
        }
        fwrite($out, Report::render($song, $plan));
        foreach ($plan['phrases'] as $p) {
            if ($p['seconds'] > $song->breath + 1e-9) {
                return 3;
            }
        }
        return 0;
    }

    /** @param resource $in */
    private static function read(string $path, $in): string
    {
        if ($path === '-') {
            $text = stream_get_contents($in, Song::MAX_BYTES + 1);
            return $text === false ? '' : $text;
        }
        if (!file_exists($path) && !is_link($path)) {
            throw new SongError('the song file was not found');
        }
        if (is_link($path) || !is_file($path)) {
            throw new SongError('the song must be a plain file');
        }
        if (filesize($path) > Song::MAX_BYTES) {
            throw new SongError('the song is larger than 64 KB');
        }
        $text = file_get_contents($path, false, null, 0, Song::MAX_BYTES + 1);
        if ($text === false) {
            throw new SongError('the song can\'t be read');
        }
        return $text;
    }
}
