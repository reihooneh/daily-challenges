<?php

declare(strict_types=1);

namespace Spoilheap;

/**
 * Turns dating clues into a date window for every deposit, using the sequence:
 * a deposit is no earlier than anything found in or under it (terminus post quem),
 * and no later than any "before" date on it or on anything above it (terminus ante quem).
 *
 * When the clues can't all be true, it finds the fewest clues to question so that the rest
 * agree (a minimum vertex cover, found exactly with König's theorem).
 */
final class Dating
{
    /** @var array<string, array{from: ?int, fromClue: ?int, to: ?int, toClue: ?int}> */
    public array $window = [];
    /** @var list<array{low: int, high: int}> pairs of clue ids that can't both be right */
    public array $conflicts = [];
    /** @var list<array{clue: int, side: string}> the fewest clue bounds to question */
    public array $question = [];
    /** @var array<string, array{from: ?int, fromClue: ?int, to: ?int, toClue: ?int}> windows once those are set aside */
    public array $repaired = [];

    /** @var array<string, array<string, true>> group => groups at or below it */
    private array $under = [];

    public function __construct(private readonly Matrix $matrix)
    {
        $edges = $matrix->keptEdges();
        $below = array_fill_keys(array_keys($matrix->members), []);
        foreach ($edges as $e) {
            $below[$e['later']][] = $e['earlier'];
        }
        foreach ($matrix->topological($edges) as $g) {
            $set = [$g => true];
            foreach ($below[$g] as $b) {
                $set += $this->under[$b];
            }
            $this->under[$g] = $set;
        }
        $this->window = $this->windows([]);
        $this->findConflicts();
        $this->question = $this->cover();
        $skip = [];
        foreach ($this->question as $q) {
            $skip[$q['side'] . $q['clue']] = true;
        }
        $this->repaired = $this->question ? $this->windows($skip) : $this->window;
    }

    /**
     * For each deposit: the latest "no earlier than" from itself and everything under it, and the
     * earliest "no later than" from itself and everything above it. Skipped bounds are ignored.
     */
    private function windows(array $skip): array
    {
        $out = [];
        foreach (array_keys($this->matrix->members) as $g) {
            $out[$g] = ['from' => null, 'fromClue' => null, 'to' => null, 'toClue' => null];
        }
        foreach ($this->matrix->record->clues as $c) {
            $home = $this->matrix->group[$c['context']];
            foreach ($out as $g => &$w) {
                if ($c['from'] !== null && !isset($skip['low' . $c['id']]) && isset($this->under[$g][$home])
                    && ($w['from'] === null || $c['from'] > $w['from'])) {
                    $w['from'] = $c['from'];
                    $w['fromClue'] = $c['id'];
                }
                if ($c['to'] !== null && !isset($skip['high' . $c['id']]) && isset($this->under[$home][$g])
                    && ($w['to'] === null || $c['to'] < $w['to'])) {
                    $w['to'] = $c['to'];
                    $w['toClue'] = $c['id'];
                }
            }
            unset($w);
        }
        return $out;
    }

    /** A "no earlier than" at or below a "no later than" with a bigger year: both can't be right. */
    private function findConflicts(): void
    {
        $clues = $this->matrix->record->clues;
        foreach ($clues as $a) {
            if ($a['from'] === null) {
                continue;
            }
            foreach ($clues as $b) {
                if ($b['to'] === null || $a['from'] <= $b['to']) {
                    continue;
                }
                $low = $this->matrix->group[$a['context']];
                $high = $this->matrix->group[$b['context']];
                if (isset($this->under[$high][$low])) {
                    $this->conflicts[] = ['low' => $a['id'], 'high' => $b['id']];
                }
            }
        }
    }

    /**
     * Each conflict is an edge between a lower bound and an upper bound, so the conflict graph is
     * bipartite. The smallest set of bounds touching every conflict is a minimum vertex cover; by
     * König's theorem its size equals a maximum matching, and it can be read off the matching.
     *
     * @return list<array{clue: int, side: string}>
     */
    private function cover(): array
    {
        if (!$this->conflicts) {
            return [];
        }
        $adj = [];
        foreach ($this->conflicts as $c) {
            $adj[$c['low']][] = $c['high'];
        }
        $matchR = []; // upper bound => lower bound it's matched with
        $matchL = [];
        foreach (array_keys($adj) as $l) {
            $seen = [];
            $this->augment($l, $adj, $matchL, $matchR, $seen);
        }
        // Walk alternating paths from unmatched lower bounds.
        $visL = [];
        $visR = [];
        $queue = array_values(array_filter(array_keys($adj), static fn ($l) => !isset($matchL[$l])));
        foreach ($queue as $l) {
            $visL[$l] = true;
        }
        while ($queue) {
            $l = array_shift($queue);
            foreach ($adj[$l] as $r) {
                if (isset($visR[$r])) {
                    continue;
                }
                $visR[$r] = true;
                if (isset($matchR[$r]) && !isset($visL[$matchR[$r]])) {
                    $visL[$matchR[$r]] = true;
                    $queue[] = $matchR[$r];
                }
            }
        }
        $out = [];
        foreach (array_keys($adj) as $l) {
            if (!isset($visL[$l])) {
                $out[] = ['clue' => $l, 'side' => 'low'];
            }
        }
        foreach (array_keys($visR) as $r) {
            $out[] = ['clue' => $r, 'side' => 'high'];
        }
        usort($out, static fn ($a, $b) => [$a['clue'], $a['side']] <=> [$b['clue'], $b['side']]);
        return $out;
    }

    private function augment(int $l, array $adj, array &$matchL, array &$matchR, array &$seen): bool
    {
        foreach ($adj[$l] as $r) {
            if (isset($seen[$r])) {
                continue;
            }
            $seen[$r] = true;
            if (!isset($matchR[$r]) || $this->augment($matchR[$r], $adj, $matchL, $matchR, $seen)) {
                $matchR[$r] = $l;
                $matchL[$l] = $r;
                return true;
            }
        }
        return false;
    }
}
