package Dryleg::Route;
# Reads a route file: settings for the day, then the route as a list of places in order.
# Every check dies with "Dryleg::Error: ..." and a message that never repeats the input.
use strict;
use warnings;
use Exporter qw(import);

our @EXPORT_OK = qw(parse_route clock_minutes format_clock MAX_BYTES);

use constant {
    MAX_BYTES  => 16 * 1024,
    MAX_LINE   => 200,
    MAX_POINTS => 60,
};

sub fail {
    my ($line, $msg) = @_;
    die 'Dryleg::Error: ' . ($line ? "line $line: " : '') . "$msg\n";
}

# "07:30" -> 450 minutes after midnight.
sub clock_minutes {
    my ($text) = @_;
    return undef unless defined $text && $text =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/;
    return $1 * 60 + $2;
}

sub format_clock {
    my ($minutes) = @_;
    my $m = int($minutes + 0.5);
    my $day = int($m / 1440);
    $m %= 1440;
    return sprintf('%02d:%02d', int($m / 60), $m % 60) . ($day ? ' (+1 day)' : '');
}

my $NAME   = qr/\A[\p{L}\p{N}][\p{L}\p{N} '().,&\/-]{0,39}\z/;
my $NUMBER = qr/\A\d{1,3}(?:\.\d{1,2})?\z/;

sub number_in {
    my ($text, $lo, $hi, $what, $line) = @_;
    fail($line, "$what must be a number from $lo to $hi")
        unless defined $text && $text =~ /\A-?\d{1,3}(?:\.\d{1,2})?\z/ && $text >= $lo && $text <= $hi;
    return 0 + $text;
}

sub parse_route {
    my ($text) = @_;
    fail(0, 'the file is larger than 16 KB') if length($text) > MAX_BYTES;
    # Control characters and invisible characters that can disguise text in a terminal.
    fail(0, 'the file has control or invisible characters')
        if $text =~ /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\x{80}-\x{9F}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{FEFF}]/;

    my %r = (
        trail => 'Route', start => undef, low => 15, high => 25, light => 6 * 60, dark => 19 * 60 + 30,
        pace => 4.0, capacity => 4.0, reserve => 0.5, trust => 'reliable', points => [],
    );
    my %seen;
    my $n = 0;
    for my $raw (split /\r?\n/, $text, -1) {
        $n++;
        fail($n, 'the line is longer than ' . MAX_LINE . ' characters') if length($raw) > MAX_LINE;
        (my $line = $raw) =~ s/(?:\A|\s)#.*\z//;
        $line =~ s/\A\s+|\s+\z//g;
        next if $line eq '';
        my ($key, @w) = split /\s+/, $line;

        if ($key eq 'trail') {
            my $name = join ' ', @w;
            fail($n, 'a trail name must be 1 to 40 letters, digits, spaces or \' ( ) . , & / -') unless $name =~ $NAME;
            $r{trail} = $name;
        } elsif ($key eq 'start-time' || $key eq 'light' || $key eq 'dark') {
            my $m = clock_minutes($w[0]);
            fail($n, "$key must be a time like 07:30") unless defined $m && @w == 1;
            $r{ $key eq 'start-time' ? 'start' : $key } = $m;
        } elsif ($key eq 'temp') {
            fail($n, 'write temp as: temp LOW HIGH (degrees C)') unless @w == 2;
            $r{low}  = number_in($w[0], -20, 50, 'the low temperature', $n);
            $r{high} = number_in($w[1], -20, 55, 'the high temperature', $n);
            fail($n, 'the high temperature must not be below the low') if $r{high} < $r{low};
        } elsif ($key eq 'pace') {
            fail($n, 'write pace as: pace KMH') unless @w == 1;
            $r{pace} = number_in($w[0], 1, 8, 'pace (km/h)', $n);
        } elsif ($key eq 'capacity' || $key eq 'reserve') {
            fail($n, "write $key as: $key LITRES") unless @w == 1;
            $r{$key} = number_in($w[0], 0, $key eq 'capacity' ? 20 : 5, "$key (litres)", $n);
        } elsif ($key eq 'trust') {
            fail($n, 'trust must be reliable or seasonal') unless @w == 1 && $w[0] =~ /\A(?:reliable|seasonal)\z/;
            $r{trust} = $w[0];
        } elsif ($key eq 'water' || $key eq 'point' || $key eq 'end') {
            fail($n, 'more than ' . MAX_POINTS . ' places on the route') if @{ $r{points} } >= MAX_POINTS;
            fail($n, 'nothing can come after the end') if @{ $r{points} } && $r{points}[-1]{kind} eq 'end';
            my ($at) = grep { $w[$_] =~ $NUMBER } 0 .. $#w;
            fail($n, "write it as: $key NAME KM [+CLIMB or -DESCENT]" . ($key eq 'water' ? ' RELIABILITY' : ''))
                unless defined $at && $at > 0;
            my $name = join ' ', @w[0 .. $at - 1];
            fail($n, 'a place name must be 1 to 40 letters, digits, spaces or \' ( ) . , & / -') unless $name =~ $NAME;
            fail($n, 'two places have the same name') if $seen{ lc $name }++;
            my %p = (kind => $key, name => $name, km => 0 + $w[$at], up => 0, down => 0, reliability => '');
            my @rest = @w[$at + 1 .. $#w];
            if (@rest && $rest[0] =~ /\A([+-])(\d{1,4})\z/) {
                $p{ $1 eq '+' ? 'up' : 'down' } = 0 + $2;
                shift @rest;
            }
            if ($key eq 'water') {
                fail($n, 'a water source needs: reliable, seasonal or unreliable')
                    unless @rest == 1 && $rest[0] =~ /\A(?:reliable|seasonal|unreliable)\z/;
                $p{reliability} = $rest[0];
            } elsif (@rest) {
                fail($n, "write it as: $key NAME KM [+CLIMB or -DESCENT]");
            }
            my $prev = $r{points}[-1];
            if (!$prev) {
                fail($n, 'the route must start at km 0') unless $p{km} == 0;
            } elsif ($p{km} <= $prev->{km}) {
                fail($n, 'places must be in order, each further along than the last');
            }
            push @{ $r{points} }, \%p;
        } else {
            fail($n, 'start the line with trail, start-time, temp, light, dark, pace, capacity, reserve, trust, water, point or end');
        }
    }
    my $pts = $r{points};
    fail(0, 'the route needs at least a start and an end') unless @$pts >= 2;
    fail(0, 'the route must finish with an end line') unless $pts->[-1]{kind} eq 'end';
    fail(0, 'the route must start at a water source (fill up before you leave)') unless $pts->[0]{kind} eq 'water';
    fail(0, 'the reserve must be less than what you can carry') unless $r{reserve} < $r{capacity};
    fail(0, 'first light must be before dark') unless $r{light} < $r{dark};
    return \%r;
}

1;
