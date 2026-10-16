<?php

declare(strict_types=1);

namespace Spoilheap;

final class Report
{
    public static function year(int $y): string
    {
        return $y < 0 ? (-$y) . ' BCE' : (string) $y;
    }

    public static function window(?int $from, ?int $to): string
    {
        return match (true) {
            $from === null && $to === null => 'undated',
            $to === null => 'after ' . self::year($from),
            $from === null => 'before ' . self::year($to),
            default => self::year($from) . ' to ' . self::year($to),
        };
    }

    public static function hasProblems(Matrix $m, Dating $d): bool
    {
        return $m->cycles || $m->selfContradictions || $d->conflicts;
    }

    public static function render(Matrix $m, Dating $d, string $name): string
    {
        $r = $m->record;
        $out = [];
        $out[] = sprintf('SPOILHEAP  %s  (%s: %d contexts, %d relations, %d dating clues)', $name, $r->site,
            count($r->contexts), count($r->relations), count($r->clues));
        $out[] = '';

        // ---------- the sequence ----------
        if ($m->cycles || $m->selfContradictions) {
            $out[] = 'SEQUENCE PROBLEMS';
            foreach ($m->selfContradictions as $s) {
                $out[] = sprintf('  x line %d says %s is above %s, but they are recorded as the same deposit.', $s['line'], $s['a'], $s['b']);
            }
            foreach ($m->cycles as $c) {
                $names = array_map([$m, 'label'], $c['nodes']);
                $out[] = '  x ' . self::listing($names) . ' form a loop: each is recorded as both above and below another.';
                $out[] = sprintf('    %s (%d):', $c['exact'] ? 'Fewest relations to re-check' : 'Relations to re-check', count($c['drop']));
                foreach ($c['drop'] as $i) {
                    $e = $m->edges[$i];
                    $out[] = sprintf('      line %-4d %s above %s', $e['line'], $m->label($e['later']), $m->label($e['earlier']));
                }
            }
            $out[] = '';
        }

        // ---------- the dating ----------
        if ($d->conflicts) {
            $out[] = 'DATING PROBLEMS';
            $clues = $r->clues;
            foreach ($d->conflicts as $c) {
                $lo = $clues[$c['low']];
                $hi = $clues[$c['high']];
                $where = $m->group[$lo['context']] === $m->group[$hi['context']]
                    ? 'in the same deposit'
                    : sprintf('but %s lies above %s (%s)', $hi['context'], $lo['context'],
                        self::path($m, $m->group[$hi['context']], $m->group[$lo['context']]));
                $out[] = sprintf('  x %s says %s or later, %s says %s or earlier, %s.',
                    self::clueName($lo), self::year($lo['from']), self::clueName($hi), self::year($hi['to']), $where);
            }
            $out[] = sprintf('  Fewest clues to question (%d), then everything else agrees:', count($d->question));
            foreach ($d->question as $q) {
                $c = $clues[$q['clue']];
                $why = $q['side'] === 'low'
                    ? ($c['kind'] === 'find'
                        ? 'the find may be intrusive (a later object that worked its way down) or misdated'
                        : 'its start date may be too late')
                    : 'the deposit may have been disturbed later, or this end date is too early';
                $out[] = sprintf('    line %-4d %s: %s', $c['line'], self::clueName($c), $why);
            }
            $out[] = '';
        }

        // ---------- phases ----------
        $out[] = 'PHASES (latest at the top)';
        $byPhase = [];
        foreach ($m->phase as $g => $p) {
            $byPhase[$p][] = $g;
        }
        krsort($byPhase);
        $width = 8;
        foreach (array_keys($m->members) as $g) {
            $width = max($width, strlen($m->label($g)));
        }
        $windows = $d->repaired;
        foreach ($byPhase as $p => $groups) {
            sort($groups, SORT_NATURAL);
            foreach ($groups as $k => $g) {
                $w = $windows[$g];
                $src = [];
                foreach ([$w['fromClue'], $w['toClue']] as $id) {
                    if ($id !== null && !in_array($r->clues[$id]['note'], $src, true)) {
                        $src[] = $r->clues[$id]['note'];
                    }
                }
                $out[] = rtrim(sprintf('  %-8s %-' . $width . 's  %-20s %s', $k === 0 ? "Phase $p" : '', $m->label($g),
                    self::window($w['from'], $w['to']), $src ? '(' . implode('; ', $src) . ')' : ''));
            }
        }
        if ($d->question) {
            $out[] = '  Dates above leave out the clues in question.';
        }

        // ---------- tidy-ups ----------
        if ($m->redundant) {
            $out[] = '';
            $out[] = 'REDUNDANT RELATIONS (already implied by others; harmless, but a Harris matrix leaves them out)';
            foreach ($m->redundant as $i) {
                $e = $m->edges[$i];
                $out[] = sprintf('  line %-4d %s above %s', $e['line'], $m->label($e['later']), $m->label($e['earlier']));
            }
        }
        $linked = [];
        foreach ($m->edges as $e) {
            $linked[$e['later']] = $linked[$e['earlier']] = true;
        }
        $loose = array_values(array_filter(array_keys($m->members), static fn ($g) => !isset($linked[$g])));
        if ($loose && count($m->members) > 1) {
            $out[] = '';
            $out[] = 'NOT LINKED TO THE SEQUENCE';
            $out[] = '  ' . implode(', ', array_map([$m, 'label'], $loose)) . ': record how these relate to their neighbours.';
        }
        $out[] = '';
        $out[] = self::hasProblems($m, $d) ? 'Result: problems to check in the record.' : 'Result: the sequence and the dates are consistent.';
        return implode("\n", $out) . "\n";
    }

    /** "1001 > 1002 > 1003": a chain of recorded relations from the upper deposit down to the lower one. */
    public static function path(Matrix $m, string $from, string $to): string
    {
        $below = [];
        foreach ($m->keptEdges() as $e) {
            $below[$e['later']][] = $e['earlier'];
        }
        $prev = [$from => null];
        $queue = [$from];
        while ($queue) {
            $v = array_shift($queue);
            if ($v === $to) {
                break;
            }
            foreach ($below[$v] ?? [] as $w) {
                if (!array_key_exists($w, $prev)) {
                    $prev[$w] = $v;
                    $queue[] = $w;
                }
            }
        }
        $chain = [];
        for ($v = $to; $v !== null; $v = $prev[$v]) {
            $chain[] = $m->label($v);
        }
        return implode(' > ', array_reverse($chain));
    }

    public static function clueName(array $c): string
    {
        return match ($c['kind']) {
            'find' => sprintf('the %s in %s', $c['note'], $c['context']),
            'before' => sprintf('"%s" on %s', $c['note'], $c['context']),
            default => sprintf('the %s date for %s', $c['note'], $c['context']),
        };
    }

    /** @param list<string> $items */
    private static function listing(array $items): string
    {
        if (count($items) < 2) {
            return implode('', $items);
        }
        return implode(', ', array_slice($items, 0, -1)) . ' and ' . end($items);
    }

    /** Graphviz DOT for drawing the matrix. Names are already restricted to safe characters. */
    public static function dot(Matrix $m): string
    {
        $drop = [];
        foreach ($m->cycles as $c) {
            foreach ($c['drop'] as $i) {
                $drop[$i] = true;
            }
        }
        $redundant = array_flip($m->redundant);
        $lines = ['digraph spoilheap {', '  rankdir=TB;', '  node [shape=box, fontname="Helvetica"];'];
        foreach (array_keys($m->members) as $g) {
            $lines[] = sprintf('  "%s" [label="%s"];', $g, $m->label($g));
        }
        foreach ($m->edges as $i => $e) {
            if (isset($redundant[$i])) {
                continue;
            }
            $style = isset($drop[$i]) ? ' [color=red, style=dashed, label="check line ' . $e['line'] . '"]' : '';
            $lines[] = sprintf('  "%s" -> "%s"%s;', $e['later'], $e['earlier'], $style);
        }
        $lines[] = '}';
        return implode("\n", $lines) . "\n";
    }
}
