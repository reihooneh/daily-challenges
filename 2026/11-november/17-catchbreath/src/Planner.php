<?php

declare(strict_types=1);

namespace Catchbreath;

/**
 * Chooses where to breathe: the set of breaths with the lowest total cost such that no phrase
 * runs longer than the singer's breath.
 *
 * A breath can go after any word (never inside one). Each place has a cost:
 *   in a rest                     0  (free, and it doesn't shorten a note)
 *   at a full stop, ! ? ; :       1      at the end of a lyric line   1
 *   at a comma or dash            2      between ordinary words       5
 *   after "the", "a", "of" ...   12  (it cuts a word off from the one it belongs to)
 * plus 1 for every breath, so fewer breaths win a tie, and 8 more if the breath would eat a note
 * shorter than the catch. A phrase over 90% of the limit costs a little extra (comfort), and one over the
 * limit costs a lot, so a song with a note too long for one breath still gets a plan (with that
 * stretch flagged) instead of none.
 *
 * Dynamic programming over the gaps: best[e] is the cheapest way to sing notes 0..e and breathe
 * after note e; best[e] = min over the previous breath p of best[p] + phrase(p+1..e) + gap(e).
 */
final class Planner
{
    public const FUNCTION_WORDS = [
        'a', 'an', 'the', 'of', 'to', 'and', 'in', 'on', 'at', 'by', 'for', 'from', 'with', 'my', 'your', 'his', 'her',
        'our', 'their', 'its', 'thy', 'thine', 'o', 'but', 'or', 'as', 'that', 'than', 'so', 'if', 'i', 'we', 'you',
    ];
    private const OVER_PER_SECOND = 200.0;
    private const COMFORT_FROM = 0.9;  // phrases over 90% of a breath start to cost extra

    public function __construct(private readonly Song $song)
    {
    }

    /** Cost of breathing after note $i, or null if it can't be done there (inside a word). */
    public function gapCost(int $i): ?float
    {
        $notes = $this->song->notes;
        $n = count($notes);
        if ($i === $n - 1) {
            return 0.0;  // the end of the song
        }
        $note = $notes[$i];
        if ($note['rest'] || $notes[$i + 1]['rest']) {
            return 0.0;
        }
        if ($note['joins']) {
            return null;
        }
        $text = $note['text'];
        if (preg_match('/[.!?;:]["\')]*$/u', $text) === 1) {
            $cost = 1.0;
        } elseif ($note['lineEnd']) {
            $cost = 1.0;
        } elseif (preg_match('/[,\x{2014}\x{2013}]["\')]*$/u', $text) === 1) {
            $cost = 2.0;
        } elseif (in_array(self::word($notes, $i), self::FUNCTION_WORDS, true)) {
            $cost = 12.0;
        } else {
            $cost = 5.0;
        }
        if ($note['beats'] <= $this->song->catch) {
            $cost += 8.0;  // the breath would swallow the whole note
        }
        return $cost + 1.0;
    }

    /** The whole word that ends at note $i, lower case, letters only. */
    public static function word(array $notes, int $i): string
    {
        $parts = [$notes[$i]['text']];
        for ($k = $i - 1; $k >= 0 && $notes[$k]['joins']; --$k) {
            array_unshift($parts, $notes[$k]['text']);
        }
        $w = mb_strtolower(implode('', $parts));
        return preg_replace('/[^\p{L}\']+/u', '', $w) ?? '';
    }

    /** Cost of singing one phrase of $len seconds on a single breath. */
    public function phraseCost(float $len): float
    {
        $max = $this->song->breath;
        $ratio = $len / $max;
        $cost = $ratio > self::COMFORT_FROM ? 3.0 * ($ratio - self::COMFORT_FROM) / (1 - self::COMFORT_FROM) : 0.0;
        if ($len > $max) {
            $cost += 100.0 + self::OVER_PER_SECOND * ($len - $max);
        }
        return $cost;
    }

    /**
     * @return array{breaths: list<int>, phrases: list<array{from:int, to:int, seconds:float}>, cost: float}
     */
    public function plan(): array
    {
        $notes = $this->song->notes;
        $n = count($notes);
        $max = $this->song->breath;
        // Prefix sums of beats, and the nearest sung note on each side, so a phrase's sung time
        // (leading and trailing rests don't count: you are breathing then) is O(1).
        $sum = [0.0];
        foreach ($notes as $k => $note) {
            $sum[$k + 1] = $sum[$k] + $note['beats'];
        }
        $nextSung = array_fill(0, $n + 1, $n);
        for ($k = $n - 1; $k >= 0; --$k) {
            $nextSung[$k] = $notes[$k]['rest'] ? $nextSung[$k + 1] : $k;
        }
        $prevSung = [];
        $last = -1;
        foreach ($notes as $k => $note) {
            if (!$note['rest']) {
                $last = $k;
            }
            $prevSung[$k] = $last;
        }
        $seconds = function (int $from, int $to) use ($nextSung, $prevSung, $sum): float {
            $a = $nextSung[$from];
            $b = $prevSung[$to];
            return $a > $b ? 0.0 : $this->song->seconds($sum[$b + 1] - $sum[$a]);
        };

        // best[p + 1]: cheapest plan for notes 0..p with a breath after p; best[0] is the start.
        $best = [0.0];
        $from = [-1];
        for ($e = 0; $e < $n; ++$e) {
            $gap = $this->gapCost($e);
            $best[$e + 1] = INF;
            $from[$e + 1] = -1;
            if ($gap === null) {
                continue;
            }
            $feasible = false;
            for ($p = $e - 1; $p >= -1; --$p) {
                if (!is_finite($best[$p + 1]) || $nextSung[$p + 1] > $e) {
                    continue;  // unreachable, or a "phrase" of nothing but rest
                }
                $len = $seconds($p + 1, $e);
                if ($len > $max + 1.0 && $feasible) {
                    break;  // every longer phrase costs more than one that fits
                }
                if ($len <= $max) {
                    $feasible = true;
                }
                $c = $best[$p + 1] + $this->phraseCost($len) + $gap;
                if ($c < $best[$e + 1] - 1e-9) {
                    $best[$e + 1] = $c;
                    $from[$e + 1] = $p;
                }
            }
        }
        // Read the plan back from the end.
        $breaths = [];
        $phrases = [];
        for ($e = $n - 1; $e >= 0; $e = $p) {
            $p = $from[$e + 1];
            $breaths[] = $e;
            $phrases[] = ['from' => $p + 1, 'to' => $e, 'seconds' => $seconds($p + 1, $e)];
        }
        return ['breaths' => array_reverse($breaths), 'phrases' => array_reverse($phrases), 'cost' => $best[$n]];
    }
}
