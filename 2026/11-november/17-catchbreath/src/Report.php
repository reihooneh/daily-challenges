<?php

declare(strict_types=1);

namespace Catchbreath;

/** Prints the lyrics with breath marks, then each phrase against the singer's breath. */
final class Report
{
    public const MARK = "\u{2019}";  // the singer's breath mark, a raised comma

    public static function render(Song $song, array $plan): string
    {
        $notes = $song->notes;
        $breathAfter = array_fill_keys($plan['breaths'], true);
        $out = [];
        $out[] = sprintf('Catchbreath: %s  (%g beats a minute, %g s on one breath)', $song->title, $song->tempo, $song->breath);
        $out[] = '';
        // The lyrics, line by line, with a mark wherever to breathe.
        $line = '';
        $catches = 0;
        $rests = 0;
        $n = count($notes);
        foreach ($notes as $i => $note) {
            if (!$note['rest']) {
                $text = Text::clean($note['text'], 40);
                $line .= $note['joins'] ? rtrim($text, '-') : $text . ' ';
            }
            if (isset($breathAfter[$i]) && $i < $n - 1) {
                $atRest = $note['rest'] || $notes[$i + 1]['rest'];
                $atRest ? ++$rests : ++$catches;
                $line = rtrim($line) . ' ' . self::MARK . ' ';
            }
            if ($note['lineEnd']) {
                $out[] = '  ' . rtrim($line);
                $line = '';
            }
        }
        $out[] = '';
        $over = array_filter($plan['phrases'], fn ($p) => $p['seconds'] > $song->breath + 1e-9);
        $longest = max(array_column($plan['phrases'], 'seconds'));
        $out[] = sprintf(
            '%d breaths: %d in rests, %d quick catch breaths. Longest phrase %.1f s (%d%% of your breath).',
            $rests + $catches,
            $rests,
            $catches,
            $longest,
            (int) round(100 * $longest / $song->breath),
        );
        $out[] = '';
        $out[] = sprintf('  %-3s %-34s %7s  %s', '#', 'phrase', 'seconds', 'of one breath');
        foreach ($plan['phrases'] as $k => $p) {
            $ratio = $p['seconds'] / $song->breath;
            $bar = str_repeat('#', (int) round(20 * min($ratio, 1.5)));
            $flag = $ratio > 1 + 1e-9 ? '  too long!' : '';
            $out[] = sprintf('  %-3d %-34s %7.1f  %3d%% %s%s', $k + 1, self::opening($notes, $p['from'], $p['to']), $p['seconds'], (int) round(100 * $ratio), $bar, $flag);
        }
        if ($over !== []) {
            $out[] = '';
            $out[] = 'Some stretches are longer than one breath and have nowhere to breathe (no gap between words):';
            foreach ($over as $p) {
                $out[] = sprintf('  "%s" lasts %.1f s. Take a bigger breath before it, shorten the held note, sing it faster, or in a choir stagger the breathing.', self::opening($notes, $p['from'], $p['to'], 60), $p['seconds']);
            }
        }
        return implode("\n", $out) . "\n";
    }

    /** The first few words of a phrase, for the table. */
    public static function opening(array $notes, int $from, int $to, int $max = 32): string
    {
        $s = '';
        for ($i = $from; $i <= $to; ++$i) {
            if ($notes[$i]['rest']) {
                continue;
            }
            $t = $notes[$i]['text'];
            $s .= $notes[$i]['joins'] ? rtrim($t, '-') : $t . ' ';
        }
        return Text::clean(rtrim($s), $max);
    }
}
