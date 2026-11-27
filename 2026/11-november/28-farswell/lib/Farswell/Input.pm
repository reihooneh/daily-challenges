package Farswell::Input;
# Reads and validates buoy readings. Everything that comes from outside the
# program passes through here, so every value is checked and bounded.
use strict;
use warnings;
use Carp qw(croak);
use Time::Local qw(timegm_modern);
use Exporter qw(import);

our @EXPORT_OK = qw(read_file parse_text parse_time parse_beach
  MAX_BYTES MAX_BUOYS MAX_READINGS);

use constant {
    MAX_BYTES    => 1_048_576,    # 1 MiB input file
    MAX_LINES    => 20_000,
    MAX_LINE_LEN => 200,
    MAX_BUOYS    => 12,
    MAX_READINGS => 600,          # per buoy (Theil-Sen is quadratic)
    MIN_PERIOD   => 4.0,          # seconds; shorter is local wind sea
    MAX_PERIOD   => 30.0,
};

my $NAME_RE = qr/^[A-Za-z][A-Za-z0-9_.\-]{0,31}$/;
my $NUM_RE  = qr/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/;

# Reads a regular file (no symlinks, devices or FIFOs) of bounded size.
sub read_file {
    my ($path) = @_;
    croak 'no input file given' unless defined $path && length $path;
    croak 'file name too long' if length $path > 4096;
    croak 'file name contains a NUL byte' if $path =~ /\0/;
    my @l = lstat $path;
    croak "cannot read '$path': $!" unless @l;
    croak "'$path' is a symbolic link; give the real file" if -l _;
    croak "'$path' is not a regular file" unless -f _;
    croak "'$path' is larger than " . MAX_BYTES . ' bytes' if $l[7] > MAX_BYTES;
    open my $fh, '<:raw', $path or croak "cannot open '$path': $!";
    my $text = '';
    my $n    = read $fh, $text, MAX_BYTES + 1;
    close $fh;
    croak "cannot read '$path'" unless defined $n;
    croak "'$path' is larger than " . MAX_BYTES . ' bytes' if $n > MAX_BYTES;
    return parse_text($text);
}

# "2026-11-20T03:00Z" or "2026-11-20T03:00:00Z" (UTC only) -> epoch seconds.
sub parse_time {
    my ($s) = @_;
    croak 'missing time' unless defined $s;
    my ($y, $mo, $d, $h, $mi, $se) =
      $s =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)(?::(\d\d))?Z$/
      or croak "bad time '$s' (use UTC like 2026-11-20T03:00Z)";
    $se //= 0;
    croak "year $y out of range 1970-2100" if $y < 1970 || $y > 2100;
    croak "bad date '$s'" if $mo < 1 || $mo > 12 || $d < 1 || $d > 31;
    croak "bad time of day '$s'" if $h > 23 || $mi > 59 || $se > 59;
    my $t = eval { timegm_modern($se, $mi, $h, $d, $mo - 1, $y) };
    croak "no such date '$s'" unless defined $t;
    return $t;
}

sub _num {
    my ($v, $what, $lo, $hi, $line) = @_;
    croak "line $line: missing $what" unless defined $v;
    croak "line $line: $what '$v' is not a number" unless $v =~ $NUM_RE;
    croak "line $line: $what $v is outside $lo..$hi" if $v < $lo || $v > $hi;
    return 0 + $v;
}

# Text format:
#   buoy NAME LAT LON          starts a buoy
#   TIME PERIOD [DIRECTION]    one reading: peak period (s), direction FROM (deg)
#   # comment
sub parse_text {
    my ($text) = @_;
    croak 'empty input' unless defined $text && length $text;
    croak 'input is larger than ' . MAX_BYTES . ' bytes'
      if length $text > MAX_BYTES;
    croak 'input contains a NUL byte' if $text =~ /\0/;
    $text =~ s/^\x{EF}\x{BB}\x{BF}//;    # byte-order mark
    my @lines = split /\r?\n/, $text, MAX_LINES + 2;
    croak 'more than ' . MAX_LINES . ' lines' if @lines > MAX_LINES;

    my (@buoys, %seen, $cur);
    my $ln = 0;
    for my $raw (@lines) {
        $ln++;
        croak "line $ln is longer than " . MAX_LINE_LEN . ' characters'
          if length $raw > MAX_LINE_LEN;
        (my $line = $raw) =~ s/#.*//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        my @f = split /\s+/, $line;
        if (lc $f[0] eq 'buoy') {
            croak "line $ln: use 'buoy NAME LAT LON'" unless @f == 4;
            my $name = $f[1];
            croak "line $ln: buoy name must be 1-32 letters, digits, _ . -"
              unless $name =~ $NAME_RE;
            croak "line $ln: buoy '$name' given twice" if $seen{ lc $name }++;
            croak 'more than ' . MAX_BUOYS . ' buoys' if @buoys >= MAX_BUOYS;
            $cur = {
                name => $name,
                lat  => _num($f[2], 'latitude',  -85,  85,  $ln),
                lon  => _num($f[3], 'longitude', -180, 180, $ln),
                obs  => [],
            };
            push @buoys, $cur;
            next;
        }
        croak "line $ln: reading before any 'buoy' line" unless $cur;
        croak "line $ln: use 'TIME PERIOD [DIRECTION]'" if @f < 2 || @f > 3;
        my $t = eval { parse_time($f[0]) };
        unless (defined $t) { (my $e = $@) =~ s/ at .*//s; croak "line $ln: $e" }
        my $T = _num($f[1], 'period', MIN_PERIOD, MAX_PERIOD, $ln);
        my $dir = @f == 3 ? _num($f[2], 'direction', 0, 360, $ln) : undef;
        croak "line $ln: more than " . MAX_READINGS . " readings for $cur->{name}"
          if @{ $cur->{obs} } >= MAX_READINGS;
        push @{ $cur->{obs} }, { t => $t, T => $T, dir => $dir, line => $ln };
    }
    croak 'no buoys found' unless @buoys;
    for my $by (@buoys) {
        my $n = @{ $by->{obs} };
        croak "buoy $by->{name} needs at least 4 readings (has $n)" if $n < 4;
        @{ $by->{obs} } = sort { $a->{t} <=> $b->{t} } @{ $by->{obs} };
        my $span = $by->{obs}[-1]{t} - $by->{obs}[0]{t};
        croak "buoy $by->{name}: readings span more than 30 days" if $span > 30 * 86400;
        croak "buoy $by->{name}: readings must cover at least 3 hours" if $span < 3 * 3600;
    }
    my @all = sort { $a <=> $b } map { map { $_->{t} } @{ $_->{obs} } } @buoys;
    croak 'readings from all buoys must fall within 30 days'
      if $all[-1] - $all[0] > 30 * 86400;
    return \@buoys;
}

# "NAME:LAT:LON" for --beach
sub parse_beach {
    my ($s) = @_;
    croak 'use --beach NAME:LAT:LON' unless defined $s && length $s <= 80;
    my @f = split /:/, $s, -1;
    croak 'use --beach NAME:LAT:LON' unless @f == 3;
    croak 'beach name must be 1-32 letters, digits, _ . -' unless $f[0] =~ $NAME_RE;
    return {
        name => $f[0],
        lat  => _num($f[1], 'beach latitude',  -85,  85,  'arg'),
        lon  => _num($f[2], 'beach longitude', -180, 180, 'arg'),
    };
}

1;
