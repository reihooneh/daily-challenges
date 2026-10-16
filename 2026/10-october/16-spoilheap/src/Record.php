<?php

declare(strict_types=1);

namespace Spoilheap;

final class RecordException extends \RuntimeException
{
}

/**
 * A site record: contexts, the stratigraphic relations between them, and the dating clues.
 *
 * File format, one statement per line (# starts a comment):
 *   site Hollow Lane, trench 2
 *   1001 above 1002          also: over, cuts, fills, seals   (left is later than right)
 *   1003 below 1002          also: under                      (left is earlier than right)
 *   1005 same 1006           two numbers for one deposit
 *   find 1002 1850 clay pipe stem      a find made no earlier than 1850 (terminus post quem)
 *   before 1001 1900 school floor      formed no later than 1900 (terminus ante quem)
 *   date 1003 1700 1750 coin hoard     formed between these years
 * Years are whole numbers; BCE years are negative (-50 is 50 BCE).
 */
final class Record
{
    public const MAX_BYTES = 65536;
    public const MAX_LINE = 200;
    public const MAX_CONTEXTS = 500;
    public const MAX_RELATIONS = 2000;
    public const MAX_CLUES = 300;
    public const MIN_YEAR = -10000;
    public const MAX_YEAR = 2100;

    private const LATER = ['above', 'over', 'cuts', 'fills', 'seals'];
    private const EARLIER = ['below', 'under'];
    private const ID = '/\A[A-Za-z0-9][A-Za-z0-9._-]{0,15}\z/';
    private const YEAR = '/\A-?[0-9]{1,5}\z/';
    // Notes may hold letters in any script, digits, spaces and common punctuation; nothing else.
    private const NOTE = '/\A[\p{L}\p{M}\p{N} .,;:\'"()\/&+?!-]{1,80}\z/u';

    public string $site = 'Unnamed site';
    /** @var array<string, int> context id => line where first seen */
    public array $contexts = [];
    /** @var list<array{later: string, earlier: string, line: int, word: string}> */
    public array $relations = [];
    /** @var list<array{0: string, 1: string, line: int}> */
    public array $same = [];
    /** @var list<array{id: int, kind: string, context: string, from: ?int, to: ?int, note: string, line: int}> */
    public array $clues = [];

    public static function parse(string $text): self
    {
        if (strlen($text) > self::MAX_BYTES) {
            throw new RecordException('the record is larger than 64 KB');
        }
        if (!mb_check_encoding($text, 'UTF-8')) {
            throw new RecordException('the record is not valid UTF-8 text');
        }
        $r = new self();
        $lines = preg_split('/\r\n|\n|\r/', $text);
        foreach ($lines as $i => $raw) {
            $n = $i + 1;
            if (mb_strlen($raw) > self::MAX_LINE) {
                throw new RecordException("line $n is longer than " . self::MAX_LINE . ' characters');
            }
            if (preg_match('/[\x00-\x08\x0B-\x1F\x7F\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}]/u', $raw)) {
                throw new RecordException("line $n contains control or hidden direction characters");
            }
            $line = trim(preg_replace('/#.*/u', '', $raw));
            if ($line === '') {
                continue;
            }
            $r->statement($line, $n);
        }
        if (!$r->contexts) {
            throw new RecordException('the record has no contexts');
        }
        return $r;
    }

    private function statement(string $line, int $n): void
    {
        $words = preg_split('/\s+/u', $line);
        $head = strtolower($words[0]);

        if ($head === 'site') {
            $this->site = $this->note(implode(' ', array_slice($words, 1)), $n);
            return;
        }
        if (in_array($head, ['find', 'before', 'date'], true)) {
            $this->clue($head, $words, $n);
            return;
        }
        if (count($words) !== 3) {
            throw new RecordException("line $n: expected 'CONTEXT above CONTEXT' (or below, cuts, fills, seals, same)");
        }
        [$a, $verb, $b] = [$words[0], strtolower($words[1]), $words[2]];
        $this->context($a, $n);
        $this->context($b, $n);
        if ($a === $b) {
            throw new RecordException("line $n: a context can't be related to itself");
        }
        if ($verb === 'same') {
            $this->same[] = [$a, $b, 'line' => $n];
            return;
        }
        if (in_array($verb, self::LATER, true)) {
            $this->relate($a, $b, $n, $verb);
        } elseif (in_array($verb, self::EARLIER, true)) {
            $this->relate($b, $a, $n, $verb);
        } else {
            throw new RecordException("line $n: unknown relation (use above, over, cuts, fills, seals, below, under or same)");
        }
    }

    private function relate(string $later, string $earlier, int $n, string $word): void
    {
        if (count($this->relations) >= self::MAX_RELATIONS) {
            throw new RecordException('more than ' . self::MAX_RELATIONS . ' relations');
        }
        $this->relations[] = ['later' => $later, 'earlier' => $earlier, 'line' => $n, 'word' => $word];
    }

    /** @param list<string> $words */
    private function clue(string $kind, array $words, int $n): void
    {
        $years = $kind === 'date' ? 2 : 1;
        if (count($words) < 3 + $years) {
            $shape = ['find' => 'find CONTEXT YEAR note', 'before' => 'before CONTEXT YEAR note', 'date' => 'date CONTEXT FROM TO note'][$kind];
            throw new RecordException("line $n: expected '$shape'");
        }
        if (count($this->clues) >= self::MAX_CLUES) {
            throw new RecordException('more than ' . self::MAX_CLUES . ' dating clues');
        }
        $context = $words[1];
        $this->context($context, $n);
        $y1 = $this->year($words[2], $n);
        $y2 = $years === 2 ? $this->year($words[3], $n) : null;
        $note = $this->note(implode(' ', array_slice($words, 2 + $years)), $n);
        $from = null;
        $to = null;
        if ($kind === 'find') {
            $from = $y1;
        } elseif ($kind === 'before') {
            $to = $y1;
        } else {
            if ($y2 < $y1) {
                throw new RecordException("line $n: the date range ends before it starts");
            }
            [$from, $to] = [$y1, $y2];
        }
        $this->clues[] = ['id' => count($this->clues), 'kind' => $kind, 'context' => $context, 'from' => $from, 'to' => $to, 'note' => $note, 'line' => $n];
    }

    private function context(string $id, int $n): void
    {
        if (!preg_match(self::ID, $id)) {
            throw new RecordException("line $n: context names are 1-16 letters, digits, dots, dashes or underscores");
        }
        if (!isset($this->contexts[$id])) {
            if (count($this->contexts) >= self::MAX_CONTEXTS) {
                throw new RecordException('more than ' . self::MAX_CONTEXTS . ' contexts');
            }
            $this->contexts[$id] = $n;
        }
    }

    private function year(string $text, int $n): int
    {
        if (!preg_match(self::YEAR, $text)) {
            throw new RecordException("line $n: years are whole numbers (negative for BCE)");
        }
        $y = (int) $text;
        if ($y < self::MIN_YEAR || $y > self::MAX_YEAR) {
            throw new RecordException("line $n: years must be between " . self::MIN_YEAR . ' and ' . self::MAX_YEAR);
        }
        return $y;
    }

    private function note(string $text, int $n): string
    {
        $text = trim($text);
        if (!preg_match(self::NOTE, $text)) {
            throw new RecordException("line $n: notes are 1-80 letters, digits, spaces and simple punctuation");
        }
        return $text;
    }
}
