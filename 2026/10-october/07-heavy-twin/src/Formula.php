<?php

declare(strict_types=1);

namespace HeavyTwin;

/** A problem with what the user typed. The message never repeats the input. */
final class FormulaException extends \InvalidArgumentException
{
}

/**
 * Parses a chemical formula into atom counts.
 *
 *   C8H10N4O2      caffeine
 *   Ca(OH)2        brackets with a multiplier
 *   K4[Fe(CN)6]    nested brackets
 *   CuSO4.5H2O     a hydrate: "." (or "·") then an optional count
 *
 * This is a recursive descent parser reading one character at a time:
 *
 *   formula := part ( "." [count] part )*
 *   part    := group+
 *   group   := ( Element | "(" part ")" | "[" part "]" ) [count]
 */
final class Formula
{
    public const MAX_LENGTH = 200;
    public const MAX_DEPTH = 10;
    public const MAX_ATOMS = 10000;
    public const MAX_COUNT = 9999;

    private int $position = 0;
    private int $depth = 0;

    private function __construct(private readonly string $text)
    {
    }

    /**
     * @return array<string, int> element symbol => number of atoms, in the order first seen
     */
    public static function parse(string $text): array
    {
        if (strlen($text) > self::MAX_LENGTH) {
            throw new FormulaException('the formula is longer than ' . self::MAX_LENGTH . ' characters');
        }
        // Accept the middle dot people paste from documents, and ignore spaces.
        $text = str_replace(["\u{00B7}", "\u{2022}", ' '], ['.', '.', ''], $text);
        if ($text === '') {
            throw new FormulaException('the formula is empty');
        }
        if (preg_match('/[^A-Za-z0-9()\[\].]/', $text) === 1) {
            throw new FormulaException('a formula may only contain letters, digits, brackets and a dot');
        }

        $parser = new self($text);
        $atoms = $parser->part();
        while ($parser->peek() === '.') {
            $parser->position++;
            $multiplier = $parser->count();
            self::merge($atoms, $parser->part(), $multiplier);
        }
        if ($parser->position < strlen($text)) {
            throw new FormulaException('unexpected character at position ' . ($parser->position + 1));
        }
        if (array_sum($atoms) > self::MAX_ATOMS) {
            throw new FormulaException('the formula has more than ' . self::MAX_ATOMS . ' atoms');
        }
        return $atoms;
    }

    /** @return array<string, int> */
    private function part(): array
    {
        $atoms = [];
        $groups = 0;
        while (true) {
            $c = $this->peek();
            if ($c === '(' || $c === '[') {
                if (++$this->depth > self::MAX_DEPTH) {
                    throw new FormulaException('brackets are nested more than ' . self::MAX_DEPTH . ' deep');
                }
                $open = $this->position++;
                $inner = $this->part();
                if ($this->peek() !== ($c === '(' ? ')' : ']')) {
                    throw new FormulaException('the bracket opened at position ' . ($open + 1) . ' is never closed');
                }
                $this->position++;
                $this->depth--;
                self::merge($atoms, $inner, $this->count());
            } elseif ($c !== null && ctype_upper($c)) {
                $symbol = $c;
                $this->position++;
                $next = $this->peek();
                if ($next !== null && ctype_lower($next)) {
                    $symbol .= $next;
                    $this->position++;
                }
                if (!Elements::known($symbol)) {
                    // $symbol is one or two ASCII letters, so it is safe to show.
                    throw new FormulaException("unknown or unsupported element \"$symbol\" at position " . ($this->position - strlen($symbol) + 1));
                }
                self::merge($atoms, [$symbol => 1], $this->count());
            } else {
                break;
            }
            $groups++;
        }
        if ($groups === 0) {
            throw new FormulaException('expected an element symbol at position ' . ($this->position + 1));
        }
        return $atoms;
    }

    /** An optional whole number; 1 when absent. */
    private function count(): int
    {
        $start = $this->position;
        while (($c = $this->peek()) !== null && ctype_digit($c)) {
            $this->position++;
        }
        if ($this->position === $start) {
            return 1;
        }
        $digits = substr($this->text, $start, $this->position - $start);
        if (strlen($digits) > 4 || (int) $digits < 1) {
            throw new FormulaException('counts must be between 1 and ' . self::MAX_COUNT);
        }
        return (int) $digits;
    }

    private function peek(): ?string
    {
        return $this->position < strlen($this->text) ? $this->text[$this->position] : null;
    }

    /**
     * @param array<string, int> $into
     * @param array<string, int> $from
     */
    private static function merge(array &$into, array $from, int $times): void
    {
        foreach ($from as $symbol => $count) {
            $into[$symbol] = ($into[$symbol] ?? 0) + $count * $times;
            if ($into[$symbol] > self::MAX_ATOMS) {
                throw new FormulaException('the formula has more than ' . self::MAX_ATOMS . ' atoms');
            }
        }
    }
}
