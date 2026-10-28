<?php

declare(strict_types=1);

namespace Ammonite;

/** A problem in the tank file. Messages give a line number and never repeat the input. */
final class TankException extends \RuntimeException
{
}

/** A group of fish that go in together. */
final class FishGroup
{
    public function __construct(
        public readonly string $name,
        public readonly int $count,
        public readonly float $length,   // adult length, cm
        public readonly float $waste,    // mg of ammonia-nitrogen (TAN) per fish per day
        public readonly int $line,
    ) {
    }

    /** Rough ammonia output of one fish from its length: weight ~ 0.012 L³ g, fed 2% of that a day,
     *  45% protein, 16% nitrogen in protein, half excreted as ammonia (TAN). */
    public static function wasteFromLength(float $cm): float
    {
        $grams = 0.012 * $cm ** 3;
        return $grams * 0.02 * 0.45 * 0.16 * 0.5 * 1000;
    }

    public function load(): float
    {
        return $this->count * $this->waste;
    }
}

/** Everything about the tank, as read from the file. */
final class Tank
{
    public const MAX_INPUT = 32768;
    public const MAX_GROUPS = 20;

    public string $name = 'My tank';
    public float $litres = 0;
    public float $celsius = 25;
    public float $ph = 7.2;
    public float $seed = 0;            // mg TAN per litre per day an established filter can already clear
    public float $changeShare = 0;     // fraction of water changed ...
    public int $changeEvery = 0;       // ... every this many days (0 = never)
    public float $limitAmmonia = 0.02; // mg/L free ammonia (NH3-N)
    public float $limitNitrite = 0.5;  // mg/L nitrite-nitrogen
    /** @var list<FishGroup> */
    public array $fish = [];

    /** Fraction of the ammonia in the water that is the toxic, un-ionised form (Emerson et al., 1975). */
    public function freeFraction(): float
    {
        $pKa = 0.09018 + 2729.92 / (273.15 + $this->celsius);
        return 1 / (1 + 10 ** ($pKa - $this->ph));
    }

    private static function fail(int $line, string $msg): never
    {
        throw new TankException($line > 0 ? "line $line: $msg" : $msg);
    }

    /** Reads a plain decimal within a range; nothing else (no exponents, signs or spaces) is accepted. */
    private static function number(string $text, float $min, float $max, int $line, string $what): float
    {
        if (preg_match('/\A\d{1,5}(?:\.\d{1,3})?\z/', $text) !== 1) {
            self::fail($line, "$what must be a plain number like 7.4");
        }
        $v = (float) $text;
        if ($v < $min || $v > $max) {
            self::fail($line, "$what must be between $min and $max");
        }
        return $v;
    }

    public static function parse(string $text): self
    {
        if (strlen($text) > self::MAX_INPUT) {
            self::fail(0, 'the file is larger than 32 KB');
        }
        if (str_starts_with($text, "\u{FEFF}")) {
            $text = substr($text, 3);
        }
        if (preg_match('//u', $text) !== 1) {
            self::fail(0, 'the file is not valid UTF-8');
        }
        $t = new self();
        $seen = [];
        foreach (explode("\n", $text) as $i => $raw) {
            $n = $i + 1;
            if (strlen($raw) > 200) {
                self::fail($n, 'is longer than 200 characters');
            }
            // Control characters (terminal escapes) and invisible direction or zero-width marks.
            if (preg_match('/[\x00-\x08\x0B-\x1F\x7F\x{80}-\x{9F}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{FEFF}]/u', $raw) === 1) {
                self::fail($n, 'contains a control or hidden character');
            }
            $line = trim((string) preg_replace('/#.*/', '', $raw));
            if ($line === '') {
                continue;
            }
            $parts = preg_split('/\s+/', $line) ?: [];
            $key = $parts[0];
            $once = static function () use (&$seen, $key, $n): void {
                if (isset($seen[$key])) {
                    self::fail($n, "'$key' comes once");
                }
                $seen[$key] = true;
            };
            switch ($key) {
                case 'tank':
                    $once();
                    $name = trim(substr($line, 4));
                    if (preg_match('/\A[A-Za-z0-9][A-Za-z0-9 \'.,&()\/-]{0,59}\z/', $name) !== 1) {
                        self::fail($n, "tank names use letters, digits, spaces and ' . , & ( ) / - (up to 60)");
                    }
                    $t->name = $name;
                    break;
                case 'volume':
                    $once();
                    if (count($parts) !== 3 || $parts[2] !== 'L') {
                        self::fail($n, "write the volume like 'volume 60 L'");
                    }
                    $t->litres = self::number($parts[1], 5, 2000, $n, 'volume');
                    break;
                case 'temperature':
                    $once();
                    if (count($parts) !== 3 || $parts[2] !== 'C') {
                        self::fail($n, "write the temperature like 'temperature 26 C'");
                    }
                    $t->celsius = self::number($parts[1], 10, 35, $n, 'temperature');
                    break;
                case 'ph':
                    $once();
                    if (count($parts) !== 2) {
                        self::fail($n, "write the pH like 'ph 7.4'");
                    }
                    $t->ph = self::number($parts[1], 5.5, 9, $n, 'pH');
                    break;
                case 'filter':
                    $once();
                    if (count($parts) === 2 && $parts[1] === 'new') {
                        $t->seed = 0;
                    } elseif (count($parts) === 3 && $parts[1] === 'seeded') {
                        $t->seed = self::number($parts[2], 0.01, 20, $n, 'seeded capacity');
                    } else {
                        self::fail($n, "write 'filter new' or 'filter seeded 1.5' (mg of ammonia per litre per day it already clears)");
                    }
                    break;
                case 'water-change':
                    $once();
                    if (count($parts) !== 5 || !str_ends_with($parts[1], '%') || $parts[2] !== 'every' || $parts[4] !== 'days') {
                        self::fail($n, "write 'water-change 25% every 7 days'");
                    }
                    $t->changeShare = self::number(substr($parts[1], 0, -1), 5, 75, $n, 'the water change') / 100;
                    $t->changeEvery = (int) self::number($parts[3], 1, 60, $n, 'days between changes');
                    break;
                case 'limits':
                    $once();
                    if (count($parts) !== 5 || $parts[1] !== 'free-ammonia' || $parts[3] !== 'nitrite') {
                        self::fail($n, "write 'limits free-ammonia 0.02 nitrite 0.5' (mg/L)");
                    }
                    $t->limitAmmonia = self::number($parts[2], 0.005, 0.5, $n, 'the free ammonia limit');
                    $t->limitNitrite = self::number($parts[4], 0.05, 5, $n, 'the nitrite limit');
                    break;
                case 'fish':
                    // fish <name words> x <count> (length <cm> | waste <mg/day>)
                    if (preg_match('/\Afish\s+(.+?)\s+x\s*(\d{1,3})\s+(length|waste)\s+(\S+)\z/', $line, $m) !== 1) {
                        self::fail($n, "write fish like 'fish Neon tetra x 10 length 3' (adult length in cm) or '... waste 0.4' (mg/day each)");
                    }
                    if (preg_match('/\A[A-Za-z][A-Za-z0-9 \'.-]{0,39}\z/', $m[1]) !== 1) {
                        self::fail($n, "fish names use letters, digits, spaces and ' . - (up to 40)");
                    }
                    $count = (int) $m[2];
                    if ($count < 1 || $count > 200) {
                        self::fail($n, 'a group has 1 to 200 fish');
                    }
                    if (count($t->fish) >= self::MAX_GROUPS) {
                        self::fail($n, 'at most 20 groups of fish');
                    }
                    if ($m[3] === 'length') {
                        $len = self::number($m[4], 1, 60, $n, 'length');
                        $waste = FishGroup::wasteFromLength($len);
                    } else {
                        $waste = self::number($m[4], 0.01, 500, $n, 'waste');
                        $len = 0;
                    }
                    $t->fish[] = new FishGroup($m[1], $count, $len, $waste, $n);
                    break;
                default:
                    self::fail($n, 'lines start with tank, volume, temperature, ph, filter, water-change, limits or fish');
            }
        }
        if ($t->litres === 0.0) {
            self::fail(0, "the file needs a 'volume' line");
        }
        if ($t->fish === []) {
            self::fail(0, "the file needs at least one 'fish' line");
        }
        return $t;
    }
}
