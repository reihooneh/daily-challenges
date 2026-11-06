<?php

declare(strict_types=1);

namespace Grassline;

final class Cli
{
    public const USAGE = <<<'TXT'
usage: grassline [options]
Works out how much grass to take: where to aim a biased lawn bowl so it draws to the jack.
  --jack M        jack length in metres, 20 to 40 (default 25)
  --green S       green speed in seconds, 8 to 25 (default 14)
  --bias B        narrow, medium or wide (default medium)
  --log FILE      calibrate your own bowls from shots you played (- for standard input)
  --hand H        forehand or backhand (default forehand)
  --left          for a left-handed bowler
  --stare M       distance of the stare spot along your line, 1 to 5 (default 2)
  --rink M        rink width, 4.3 to 5.8 (default 5.5)
  --svg           print a drawing (SVG) instead of the plan

TXT;

    private static function num(?string $v, string $what, float $lo, float $hi): float
    {
        if ($v === null || !preg_match('/\A[0-9]{1,2}(\.[0-9]{1,3})?\z/', $v)) {
            throw new InputError("$what must be a number like 25 or 14.5");
        }
        $f = (float) $v;
        if ($f < $lo || $f > $hi) {
            throw new InputError("$what must be from $lo to $hi");
        }
        return $f;
    }

    /** Reads a log from a regular file (never through a link) or standard input, at most 64 KB + 1. */
    private static function read(string $path, $stdin): string
    {
        if ($path === '-') {
            $fh = $stdin;
        } else {
            if (is_link($path) || !is_file($path)) {
                throw new InputError('the log could not be read (it must be a regular file, not a link)');
            }
            $fh = @fopen($path, 'rb');
            if ($fh === false) {
                throw new InputError('the log could not be read (it must be a regular file, not a link)');
            }
        }
        $data = stream_get_contents($fh, Log::MAX_BYTES + 1);
        if ($data === false) {
            throw new InputError('the log could not be read');
        }
        return $data;
    }

    /** Exit codes: 0 a plan, 2 bad usage or input. */
    public static function run(array $args, $stdin, $stdout, $stderr): int
    {
        try {
            $o = ['jack' => 25.0, 'green' => 14.0, 'bias' => 'medium', 'hand' => 'forehand', 'left' => false, 'stare' => 2.0, 'rink' => 5.5, 'svg' => false, 'log' => null];
            $seen = [];
            while ($args) {
                $a = array_shift($args);
                if (isset($seen[$a])) {
                    throw new InputError('each option may be given once');
                }
                $seen[$a] = true;
                match ($a) {
                    '--jack' => $o['jack'] = self::num(array_shift($args), '--jack', 20, 40),
                    '--green' => $o['green'] = self::num(array_shift($args), '--green', 8, 25),
                    '--stare' => $o['stare'] = self::num(array_shift($args), '--stare', 1, 5),
                    '--rink' => $o['rink'] = self::num(array_shift($args), '--rink', 4.3, 5.8),
                    '--bias' => $o['bias'] = array_shift($args) ?? '',
                    '--hand' => $o['hand'] = array_shift($args) ?? '',
                    '--log' => $o['log'] = array_shift($args) ?? throw new InputError('--log needs a file'),
                    '--left' => $o['left'] = true,
                    '--svg' => $o['svg'] = true,
                    default => throw new InputError(''),
                };
            }
            if (!in_array($o['hand'], ['forehand', 'backhand'], true)) {
                throw new InputError('--hand is forehand or backhand');
            }
            $fit = null;
            if ($o['log'] !== null) {
                if (isset($seen['--bias']) || isset($seen['--green'])) {
                    throw new InputError('a log sets the bowls and the green: leave out --bias and --green');
                }
                $fit = Log::parse(self::read($o['log'], $stdin))->fit();
                $bowls = $fit['bowls'];
                $o['green'] = $fit['seconds'];
                if ($o['green'] < 8 || $o['green'] > 25) {
                    throw new InputError('the log implies a green outside 8 to 25 seconds: check the timed bowls');
                }
            } else {
                $bowls = Bowls::preset($o['bias']);
            }
            $shot = new Shot($bowls, $o['green'], $o['jack']);
            // A right-hander's forehand is aimed right and curves left; backhand and left-handers mirror.
            $aimRight = ($o['hand'] === 'forehand') !== $o['left'];
            $side = $aimRight ? 'right' : 'left';
            $hand = ($o['left'] ? 'left-handed ' : '') . $o['hand'];
            fwrite($stdout, $o['svg']
                ? Report::svg($shot, $side, $o['rink'], sprintf('Grassline: %s, %.1f m jack', $hand, $o['jack']))
                : Report::text($shot, $hand, $side, $o['stare'], $o['rink'], $fit));
            return 0;
        } catch (InputError $e) {
            fwrite($stderr, $e->getMessage() === '' ? self::USAGE : 'grassline: ' . $e->getMessage() . "\n");
            return 2;
        }
    }
}
