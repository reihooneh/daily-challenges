package Dryleg::CLI;
# The command line, kept in a module so the tests can run it without a terminal.
use strict;
use warnings;
use Exporter qw(import);
use Encode qw(decode FB_CROAK);
use File::Basename qw(basename);
use Dryleg::Route qw(parse_route MAX_BYTES);
use Dryleg::Plan qw(plan best_start);
use Dryleg::Report qw(render);

our @EXPORT_OK = qw(run read_limited safe_name);

my $USAGE = "usage: dryleg ROUTEFILE   (use - for standard input)\n";

# Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, and
# decodes them strictly as UTF-8.
sub read_limited {
    my ($path, $stdin) = @_;
    my $fh;
    if ($path eq '-') {
        $fh = $stdin;
    } else {
        die "Dryleg::Error: the route file could not be read\n" unless -f $path && open($fh, '<:raw', $path);
    }
    my ($data, $got) = ('', 0);
    while ($got <= MAX_BYTES) {
        my $n = read($fh, $data, MAX_BYTES + 1 - $got, $got);
        die "Dryleg::Error: the route file could not be read\n" unless defined $n;
        last if $n == 0;
        $got += $n;
    }
    close $fh if $path ne '-';
    die "Dryleg::Error: the file is larger than 16 KB\n" if length($data) > MAX_BYTES;
    my $text = eval { decode('UTF-8', $data, FB_CROAK) };
    die "Dryleg::Error: the file is not valid UTF-8 text\n" unless defined $text;
    return $text;
}

# Only plain characters from a file name reach the terminal.
sub safe_name {
    my ($path) = @_;
    return 'standard input' if $path eq '-';
    (my $name = basename($path)) =~ s/[^A-Za-z0-9._ -]/?/g;
    return substr($name, 0, 60);
}

# Exit codes: 0 the plan works, 1 it needs more water than you can carry or ends after
# dark, 2 bad input.
sub run {
    my ($args, $stdin, $out, $err) = @_;
    if (@$args == 1 && $args->[0] =~ /\A(?:-h|--help)\z/) {
        print {$out} $USAGE;
        return 0;
    }
    my $code = eval {
        die "Dryleg::Error: give exactly one route file\n" unless @$args == 1 && ($args->[0] eq '-' || $args->[0] !~ /\A-/);
        my $r = parse_route(read_limited($args->[0], $stdin));
        my $best = best_start($r);
        my $p = defined $r->{start} ? plan($r, $r->{start}) : $best;
        print {$out} render($r, $p, $best, safe_name($args->[0]));
        ($p->{too_heavy} || $p->{after_dark}) ? 1 : 0;
    };
    return $code if defined $code;
    my $e = $@;
    die $e unless $e =~ /\ADryleg::Error: (.*)/s;    # a bug, not bad input
    print {$err} "dryleg: $1$USAGE";
    return 2;
}

1;
