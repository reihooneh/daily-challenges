<?php

declare(strict_types=1);

namespace Catchbreath;

/**
 * A song as the singer sees it: syllables (or rests) with how long each lasts, in beats.
 *
 * File format, one lyric line per text line:
 *
 *     title: Amazing Grace
 *     tempo: 76          beats per minute
 *     breath: 8          seconds you can comfortably sing on one breath
 *     catch: 0.5         beats a quick breath takes from the note before it
 *
 *     A-:1 ma-:1 zing:2 grace!:3 _:1
 *
 * A syllable ending in "-" carries on into the next one (the same word). "_" is a rest.
 * Punctuation stays on the word it follows. Lines starting with # are comments.
 */
final class Song
{
    public const MAX_BYTES = 65536;
    public const MAX_NOTES = 5000;
    public const MAX_BEATS = 32.0;

    /** @var list<array{text:string, beats:float, rest:bool, joins:bool, lineEnd:bool, line:int}> */
    public array $notes = [];
    public string $title = 'Untitled';
    public float $tempo = 80.0;
    public float $breath = 8.0;
    public float $catch = 0.5;

    private const SETTINGS = [
        'tempo' => [20.0, 300.0],
        'breath' => [2.0, 60.0],
        'catch' => [0.125, 2.0],
    ];

    public static function parse(string $text): self
    {
        if (strlen($text) > self::MAX_BYTES) {
            throw new SongError('the song is larger than 64 KB');
        }
        if (str_contains($text, "\0")) {
            throw new SongError('the song contains a NUL byte');
        }
        if (!mb_check_encoding($text, 'UTF-8')) {
            throw new SongError('the song is not valid UTF-8 text');
        }
        $song = new self();
        $lines = preg_split('/\r\n|\r|\n/', $text) ?: [];
        foreach ($lines as $i => $raw) {
            $n = $i + 1;
            $line = trim($raw);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            if (preg_match('/^(title|tempo|breath|catch)\s*:\s*(.*)$/i', $line, $m) === 1 && !str_contains($m[2], ':')) {
                $song->applySetting(strtolower($m[1]), trim($m[2]), $n);
                continue;
            }
            $tokens = preg_split('/\s+/', $line) ?: [];
            $first = count($song->notes);
            foreach ($tokens as $token) {
                $song->note($token, $n);
            }
            if (count($song->notes) > $first) {
                $song->notes[count($song->notes) - 1]['lineEnd'] = true;
            }
        }
        if ($song->notes === []) {
            throw new SongError('no notes found: write syllables like "grace:2"');
        }
        $last = $song->notes[count($song->notes) - 1];
        if ($last['joins']) {
            throw new SongError(sprintf('line %d: the song ends in the middle of a word', $last['line']));
        }
        return $song;
    }

    /** Sets title, tempo, breath or catch, checking the value; $line is 0 for the command line. */
    public function applySetting(string $key, string $value, int $line = 0): void
    {
        $at = $line > 0 ? sprintf('line %d: ', $line) : '';
        if ($key === 'title') {
            $this->title = Text::clean($value, 60);
            return;
        }
        if (!isset(self::SETTINGS[$key])) {
            throw new SongError($at . sprintf('unknown setting "%s"', Text::clean($key, 20)));
        }
        [$lo, $hi] = self::SETTINGS[$key];
        if (preg_match('/^\d{1,4}(\.\d{1,3})?$/', $value) !== 1) {
            throw new SongError($at . sprintf('%s must be a number', $key));
        }
        $v = (float) $value;
        if ($v < $lo || $v > $hi) {
            throw new SongError($at . sprintf('%s must be between %g and %g', $key, $lo, $hi));
        }
        $this->{$key} = $v;
    }

    private function note(string $token, int $line): void
    {
        if (count($this->notes) >= self::MAX_NOTES) {
            throw new SongError(sprintf('the song has more than %d notes', self::MAX_NOTES));
        }
        if (preg_match('/^(.+):(\d{1,2}(?:\.\d{1,3})?)$/u', $token, $m) !== 1) {
            throw new SongError(sprintf('line %d: can\'t read "%s": write a syllable and its beats, like "grace:2"', $line, Text::clean($token, 30)));
        }
        $beats = (float) $m[2];
        if ($beats <= 0 || $beats > self::MAX_BEATS) {
            throw new SongError(sprintf('line %d: "%s" must last more than 0 and at most 32 beats', $line, Text::clean($token, 30)));
        }
        $text = $m[1];
        $rest = $text === '_';
        $previous = $this->notes === [] ? null : $this->notes[count($this->notes) - 1];
        if ($rest && $previous !== null && $previous['joins']) {
            throw new SongError(sprintf('line %d: a rest in the middle of a word', $line));
        }
        $this->notes[] = [
            'text' => $text,
            'beats' => $beats,
            'rest' => $rest,
            'joins' => !$rest && str_ends_with($text, '-'),
            'lineEnd' => false,
            'line' => $line,
        ];
    }

    public function seconds(float $beats): float
    {
        return $beats * 60.0 / $this->tempo;
    }
}

final class SongError extends \RuntimeException
{
}

final class Text
{
    /** Strips control characters and cuts long text, so nothing from a file can upset a terminal. */
    public static function clean(string $s, int $max): string
    {
        $s = preg_replace('/[\x00-\x1F\x7F]|\xC2[\x80-\x9F]/u', '?', $s) ?? '?';
        return mb_strlen($s) > $max ? mb_substr($s, 0, $max - 3) . '...' : $s;
    }
}
