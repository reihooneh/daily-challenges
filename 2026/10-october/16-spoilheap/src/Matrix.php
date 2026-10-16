<?php

declare(strict_types=1);

namespace Spoilheap;

/**
 * The stratigraphic sequence as a graph. Each node is a deposit (contexts recorded as "same"
 * are merged into one node); an edge later -> earlier says "this was laid down after that".
 * A correct record has no cycles: nothing can be both above and below something else.
 */
final class Matrix
{
    /** Largest set of relations tried exhaustively when looking for the fewest to question. */
    private const EXACT_LIMIT = 4;

    /** @var array<string, string> context => the representative of its merged group */
    public array $group = [];
    /** @var array<string, list<string>> representative => contexts in the group */
    public array $members = [];
    /** @var list<array{later: string, earlier: string, line: int, word: string}> edges between groups */
    public array $edges = [];
    /** @var list<array{line: int, a: string, b: string}> relations between two numbers for the same deposit */
    public array $selfContradictions = [];
    /** @var list<array{nodes: list<string>, drop: list<int>, exact: bool}> one entry per tangle of cycles */
    public array $cycles = [];
    /** @var list<int> indexes into $edges that are implied by other relations */
    public array $redundant = [];
    /** @var array<string, int> representative => phase, 1 = earliest */
    public array $phase = [];

    public function __construct(public readonly Record $record)
    {
        // PHP turns numeric string keys such as "1001" into integers, so internal node names get a
        // "g" prefix and context names are always handled as strings.
        $parent = [];
        foreach (array_keys($record->contexts) as $c) {
            $parent[(string) $c] = (string) $c;
        }
        $find = static function (string $x) use (&$parent): string {
            while ($parent[$x] !== $x) {
                $parent[$x] = $parent[$parent[$x]];
                $x = $parent[$x];
            }
            return $x;
        };
        foreach ($record->same as $s) {
            $a = $find($s[0]);
            $b = $find($s[1]);
            if ($a !== $b) {
                // Keep the name that was recorded first as the group's name, for stable output.
                if ($record->contexts[$a] <= $record->contexts[$b]) {
                    $parent[$b] = $a;
                } else {
                    $parent[$a] = $b;
                }
            }
        }
        foreach (array_keys($record->contexts) as $c) {
            $c = (string) $c;
            $g = 'g' . $find($c);
            $this->group[$c] = $g;
            $this->members[$g][] = $c;
        }
        $seen = [];
        foreach ($record->relations as $rel) {
            $a = $this->group[$rel['later']];
            $b = $this->group[$rel['earlier']];
            if ($a === $b) {
                $this->selfContradictions[] = ['line' => $rel['line'], 'a' => $rel['later'], 'b' => $rel['earlier']];
                continue;
            }
            $key = "$a\0$b";
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $this->edges[] = ['later' => $a, 'earlier' => $b, 'line' => $rel['line'], 'word' => $rel['word']];
        }
        $this->findCycles();
        $this->findRedundant();
        $this->findPhases();
    }

    /** Edges that are kept for dating and phasing: everything except the relations questioned in cycles. */
    public function keptEdges(): array
    {
        $drop = [];
        foreach ($this->cycles as $c) {
            foreach ($c['drop'] as $e) {
                $drop[$e] = true;
            }
        }
        return array_values(array_filter($this->edges, static fn ($e, $i) => !isset($drop[$i]), ARRAY_FILTER_USE_BOTH));
    }

    /** @return array<string, list<int>> node => indexes of edges leaving it (towards earlier deposits) */
    private function adjacency(array $skip = []): array
    {
        $adj = [];
        foreach (array_keys($this->members) as $g) {
            $adj[$g] = [];
        }
        foreach ($this->edges as $i => $e) {
            if (!isset($skip[$i])) {
                $adj[$e['later']][] = $i;
            }
        }
        return $adj;
    }

    /** Tarjan's strongly connected components, written without recursion so deep sequences are safe. */
    private function components(): array
    {
        $adj = $this->adjacency();
        $index = [];
        $low = [];
        $onStack = [];
        $stack = [];
        $out = [];
        $counter = 0;
        foreach (array_keys($adj) as $start) {
            if (isset($index[$start])) {
                continue;
            }
            $work = [[$start, 0]];
            $index[$start] = $low[$start] = $counter++;
            $stack[] = $start;
            $onStack[$start] = true;
            while ($work) {
                [$v, $k] = $work[count($work) - 1];
                if ($k < count($adj[$v])) {
                    $work[count($work) - 1][1]++;
                    $w = $this->edges[$adj[$v][$k]]['earlier'];
                    if (!isset($index[$w])) {
                        $index[$w] = $low[$w] = $counter++;
                        $stack[] = $w;
                        $onStack[$w] = true;
                        $work[] = [$w, 0];
                    } elseif (!empty($onStack[$w])) {
                        $low[$v] = min($low[$v], $index[$w]);
                    }
                    continue;
                }
                array_pop($work);
                if ($work) {
                    $parentNode = $work[count($work) - 1][0];
                    $low[$parentNode] = min($low[$parentNode], $low[$v]);
                }
                if ($low[$v] === $index[$v]) {
                    $comp = [];
                    do {
                        $w = array_pop($stack);
                        $onStack[$w] = false;
                        $comp[] = $w;
                    } while ($w !== $v);
                    $out[] = $comp;
                }
            }
        }
        return $out;
    }

    private function findCycles(): void
    {
        foreach ($this->components() as $comp) {
            if (count($comp) < 2) {
                continue;
            }
            $inside = array_flip($comp);
            $local = [];
            foreach ($this->edges as $i => $e) {
                if (isset($inside[$e['later']], $inside[$e['earlier']])) {
                    $local[] = $i;
                }
            }
            [$drop, $exact] = $this->fewestToDrop($comp, $local);
            sort($comp, SORT_NATURAL);
            $this->cycles[] = ['nodes' => $comp, 'drop' => $drop, 'exact' => $exact];
        }
    }

    /**
     * The fewest relations whose removal breaks every cycle in one tangle (a minimum feedback
     * arc set). This is NP-hard in general, so sets of up to EXACT_LIMIT relations are tried
     * exhaustively, smallest first; bigger tangles fall back to a depth-first search that drops
     * every back edge, which always works but may question more relations than needed.
     *
     * @param list<string> $nodes
     * @param list<int> $local
     * @return array{list<int>, bool}
     */
    private function fewestToDrop(array $nodes, array $local): array
    {
        $budget = 200000; // combinations tried at most, so a huge tangle can't stall the tool
        for ($k = 1; $k <= self::EXACT_LIMIT && $k < count($local); $k++) {
            $found = [];
            foreach (self::combinations($local, $k) as $combo) {
                if (--$budget < 0) {
                    break 2;
                }
                if ($this->acyclic($nodes, $local, array_flip($combo))) {
                    $found[] = $combo;
                }
            }
            if ($found) {
                return [$this->mostPlausible($found), true];
            }
        }
        return [$this->backEdges($nodes, $local), false];
    }

    /**
     * Several equally small sets of relations may break a loop. Prefer the one that leaves the
     * dating clues in least disagreement (the finds are independent evidence about the order),
     * then the one recorded latest in the notebook.
     *
     * @param list<list<int>> $options
     * @return list<int>
     */
    private function mostPlausible(array $options): array
    {
        $best = null;
        $bestKey = null;
        foreach ($options as $combo) {
            $key = [$this->datingConflicts(array_flip($combo)), -max(array_map(fn ($i) => $this->edges[$i]['line'], $combo))];
            if ($bestKey === null || $key < $bestKey) {
                [$best, $bestKey] = [$combo, $key];
            }
        }
        return $best;
    }

    /** How many pairs of dating clues disagree if the given relations are left out (cycles elsewhere ignored). */
    private function datingConflicts(array $skip): int
    {
        $adj = $this->adjacency($skip);
        $count = 0;
        foreach ($this->record->clues as $hi) {
            if ($hi['to'] === null) {
                continue;
            }
            // Everything at or below the deposit holding the "no later than" clue.
            $start = $this->group[$hi['context']];
            $seen = [$start => true];
            $queue = [$start];
            while ($queue) {
                $v = array_pop($queue);
                foreach ($adj[$v] as $j) {
                    $w = $this->edges[$j]['earlier'];
                    if (!isset($seen[$w])) {
                        $seen[$w] = true;
                        $queue[] = $w;
                    }
                }
            }
            foreach ($this->record->clues as $lo) {
                if ($lo['from'] !== null && $lo['from'] > $hi['to'] && isset($seen[$this->group[$lo['context']]])) {
                    $count++;
                }
            }
        }
        return $count;
    }

    /** @return \Generator<list<int>> */
    private static function combinations(array $items, int $k, int $from = 0, array $chosen = []): \Generator
    {
        if (count($chosen) === $k) {
            yield $chosen;
            return;
        }
        for ($i = $from; $i <= count($items) - ($k - count($chosen)); $i++) {
            yield from self::combinations($items, $k, $i + 1, [...$chosen, $items[$i]]);
        }
    }

    /** Kahn's algorithm on the tangle without the skipped edges: acyclic if every node can be removed. */
    private function acyclic(array $nodes, array $local, array $skip): bool
    {
        $in = array_fill_keys($nodes, 0);
        $out = array_fill_keys($nodes, []);
        foreach ($local as $i) {
            if (isset($skip[$i])) {
                continue;
            }
            $e = $this->edges[$i];
            $in[$e['earlier']]++;
            $out[$e['later']][] = $e['earlier'];
        }
        $queue = array_keys(array_filter($in, static fn ($d) => $d === 0));
        $done = 0;
        while ($queue) {
            $v = array_pop($queue);
            $done++;
            foreach ($out[$v] as $w) {
                if (--$in[$w] === 0) {
                    $queue[] = $w;
                }
            }
        }
        return $done === count($nodes);
    }

    private function backEdges(array $nodes, array $local): array
    {
        $out = array_fill_keys($nodes, []);
        foreach ($local as $i) {
            $out[$this->edges[$i]['later']][] = $i;
        }
        $state = [];
        $back = [];
        foreach ($nodes as $start) {
            if (isset($state[$start])) {
                continue;
            }
            $state[$start] = 1;
            $work = [[$start, 0]];
            while ($work) {
                [$v, $k] = $work[count($work) - 1];
                if ($k < count($out[$v])) {
                    $work[count($work) - 1][1]++;
                    $i = $out[$v][$k];
                    $w = $this->edges[$i]['earlier'];
                    if (!isset($state[$w])) {
                        $state[$w] = 1;
                        $work[] = [$w, 0];
                    } elseif ($state[$w] === 1) {
                        $back[] = $i;
                    }
                    continue;
                }
                $state[$v] = 2;
                array_pop($work);
            }
        }
        sort($back);
        return $back;
    }

    /** A relation is redundant when the same order already follows from other relations. */
    private function findRedundant(): void
    {
        if ($this->cycles) {
            return; // with contradictions present, "implied by" would be meaningless
        }
        foreach ($this->edges as $i => $e) {
            $adj = $this->adjacency([$i => true]);
            $seen = [$e['later'] => true];
            $queue = [$e['later']];
            while ($queue) {
                $v = array_pop($queue);
                foreach ($adj[$v] as $j) {
                    $w = $this->edges[$j]['earlier'];
                    if ($w === $e['earlier']) {
                        $this->redundant[] = $i;
                        continue 3;
                    }
                    if (!isset($seen[$w])) {
                        $seen[$w] = true;
                        $queue[] = $w;
                    }
                }
            }
        }
    }

    /** Phase = length of the longest chain of deposits underneath, plus one (bottom layers are phase 1). */
    private function findPhases(): void
    {
        $kept = $this->keptEdges();
        $below = array_fill_keys(array_keys($this->members), []);
        foreach ($kept as $e) {
            $below[$e['later']][] = $e['earlier'];
        }
        foreach ($this->topological($kept) as $g) {
            $p = 1;
            foreach ($below[$g] as $b) {
                $p = max($p, $this->phase[$b] + 1);
            }
            $this->phase[$g] = $p;
        }
    }

    /**
     * Earliest deposits first.
     * @param list<array{later: string, earlier: string}> $edges
     * @return list<string>
     */
    public function topological(array $edges): array
    {
        $nodes = array_keys($this->members);
        $pending = array_fill_keys($nodes, 0);
        $up = array_fill_keys($nodes, []);
        foreach ($edges as $e) {
            $pending[$e['later']]++;
            $up[$e['earlier']][] = $e['later'];
        }
        $queue = array_values(array_filter($nodes, static fn ($n) => $pending[$n] === 0));
        $order = [];
        for ($i = 0; $i < count($queue); $i++) {
            $v = $queue[$i];
            $order[] = $v;
            foreach ($up[$v] as $w) {
                if (--$pending[$w] === 0) {
                    $queue[] = $w;
                }
            }
        }
        return $order;
    }

    public function label(string $group): string
    {
        $m = $this->members[$group];
        return count($m) === 1 ? $m[0] : implode('=', $m);
    }
}
