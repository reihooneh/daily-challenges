use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More;
use File::Temp qw(tempdir);
use Farswell::Input qw(read_file parse_text parse_time parse_beach MAX_BYTES);

my $ok = "buoy Sydney -33.77 151.42\n"
  . join('', map { sprintf "2026-11-20T%02d:00Z %.1f 190\n", $_ * 3, 20 - $_ } 0 .. 5);

my $b = parse_text($ok);
is(scalar @$b, 1, 'one buoy');
is(scalar @{ $b->[0]{obs} }, 6, 'six readings');
is($b->[0]{obs}[0]{dir}, 190, 'direction read');

# comments, blank lines, CRLF, BOM, mixed case keyword, unsorted readings
my $messy = "\x{EF}\x{BB}\x{BF}# hi\r\n\r\nBUOY Eden -37.3 150.18  # inline\r\n"
  . "2026-11-20T12:00Z 15\r\n2026-11-20T00:00Z 19\r\n2026-11-20T06:00Z 17\r\n2026-11-20T09:00:30Z 16\r\n";
my $m = parse_text($messy);
is($m->[0]{name}, 'Eden', 'messy file parsed');
ok($m->[0]{obs}[0]{t} < $m->[0]{obs}[1]{t}, 'readings sorted by time');
ok(!defined $m->[0]{obs}[0]{dir}, 'direction optional');

is(parse_time('1970-01-01T00:00Z'), 0, 'epoch');
is(parse_time('2026-11-28T06:30:15Z') - parse_time('2026-11-28T06:30Z'), 15, 'seconds');

my %bad = (
    ''                                                  => qr/empty/,
    "2026-11-20T00:00Z 19\n"                            => qr/before any 'buoy'/,
    "buoy X 1 2\n"                                      => qr/at least 4 readings/,
    "buoy X 100 2\n"                                    => qr/latitude 100 is outside/,
    "buoy X 1 200\n"                                    => qr/longitude 200 is outside/,
    "buoy X 1e3 2\n"                                    => qr/not a number/,
    "buoy X NaN 2\n"                                    => qr/not a number/,
    "buoy X inf 2\n"                                    => qr/not a number/,
    "buoy X 1\n"                                        => qr/buoy NAME LAT LON/,
    "buoy ../etc 1 2\n"                                 => qr/buoy name/,
    "buoy \$(rm) 1 2\n"                                 => qr/buoy name/,
    "buoy A 1 2\nbuoy a 3 4\n"                          => qr/given twice/,
    "buoy A 1 2\n2026-11-20T00:00 19\n"                 => qr/bad time/,
    "buoy A 1 2\n2026-02-30T00:00Z 19\n"                => qr/no such date/,
    "buoy A 1 2\n2026-13-01T00:00Z 19\n"                => qr/bad date/,
    "buoy A 1 2\n2026-11-01T25:00Z 19\n"                => qr/bad time of day/,
    "buoy A 1 2\n1900-11-01T00:00Z 19\n"                => qr/out of range/,
    "buoy A 1 2\n2026-11-01T00:00Z 2\n"                 => qr/period 2 is outside/,
    "buoy A 1 2\n2026-11-01T00:00Z 99\n"                => qr/period 99 is outside/,
    "buoy A 1 2\n2026-11-01T00:00Z 12 400\n"            => qr/direction 400 is outside/,
    "buoy A 1 2\n2026-11-01T00:00Z 12 4 5\n"            => qr/TIME PERIOD/,
    "a\0b"                                              => qr/NUL/,
    ('x' x 300)                                         => qr/longer than/,
    "buoy A 1 2\n" . ("2026-11-01T00:00Z 12\n" x 4)     => qr/at least 3 hours/,
    "buoy A 1 2\n2026-11-01T00:00Z 12\n2026-11-02T00:00Z 12\n2026-11-03T00:00Z 12\n2026-12-15T00:00Z 12\n" => qr/more than 30 days/,
    join('', map { "buoy B$_ 1 2\n" } 1 .. 13)          => qr/more than 12 buoys/,
    "buoy A 1 2\n" . ("2026-11-01T00:00Z 12\n" x 601)   => qr/more than 600 readings/,
    ("\n" x 20_001)                                     => qr/more than 20000 lines/,
);
for my $in (sort keys %bad) {
    eval { parse_text($in) };
    (my $show = substr($in, 0, 40)) =~ s/[^\x20-\x7e]/?/g;
    like($@, $bad{$in}, "refused: $show");
}
eval { parse_text('x' x (MAX_BYTES + 1)) };
like($@, qr/larger than/, 'oversized text refused');

# Files: regular files only, size capped, no symlinks
my $dir = tempdir(CLEANUP => 1);
my $good = "$dir/good.txt";
open my $fh, '>', $good or die; print $fh $ok; close $fh;
is(scalar @{ read_file($good) }, 1, 'reads a regular file');
SKIP: {
    skip 'no symlinks here', 1 unless eval { symlink $good, "$dir/link"; 1 } && -l "$dir/link";
    eval { read_file("$dir/link") };
    like($@, qr/symbolic link/, 'symlink refused');
}
eval { read_file($dir) };
like($@, qr/not a regular file/, 'directory refused');
eval { read_file("$dir/missing") };
like($@, qr/cannot read/, 'missing file refused');
eval { read_file("a\0b") };
like($@, qr/NUL/, 'NUL in path refused');
my $big = "$dir/big.txt";
open $fh, '>', $big or die; print $fh 'x' x (MAX_BYTES + 10); close $fh;
eval { read_file($big) };
like($@, qr/larger than/, 'big file refused before reading');
SKIP: {
    skip 'no /dev/zero', 1 unless -e '/dev/zero';
    eval { read_file('/dev/zero') };
    like($@, qr/not a regular file/, 'device refused');
}

is_deeply(parse_beach('Bondi:-33.89:151.27'), { name => 'Bondi', lat => -33.89, lon => 151.27 }, 'beach parsed');
for my $bb ('Bondi', 'Bondi:1', 'Bondi:1:2:3', ':1:2', 'Bo di:1:2', 'B:91:0', 'B:0:181', 'B:x:0', 'B:' . ('1' x 90) . ':0') {
    eval { parse_beach($bb) };
    ok($@, "beach refused: $bb");
}

done_testing;
