package Downthrow::App;
# The command line, with its handles passed in so the tests can drive it.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use Encode qw(decode FB_CROAK);
use Downthrow::Parse qw(parse_survey MAX_INPUT);
use Downthrow::Report qw(analyse render);

our @EXPORT_OK = qw(run read_bounded);

my $USAGE = "usage: downthrow <survey.txt>   (or - to read standard input)\n"
  . "Fits the dip and strike of a rock horizon and looks for a fault that breaks it.\n";

# Reads at most MAX_INPUT + 1 bytes from a regular file or a handle, then decodes UTF-8 strictly.
sub read_bounded {
    my ($path, $stdin) = @_;
    my $fh;
    if ($path eq '-') {
        $fh = $stdin;
    } else {
        die { input => 'the survey could not be read (it must be a readable file)' } unless -f $path && -r _;
        # Three-argument open: the path is never interpreted as a command or mode.
        open($fh, '<:raw', $path) or die { input => 'the survey could not be read (it must be a readable file)' };
    }
    binmode $fh, ':raw';
    my $data = '';
    while (length($data) <= MAX_INPUT) {
        my $got = read($fh, $data, MAX_INPUT + 1 - length($data), length($data));
        die { input => 'the survey could not be read' } unless defined $got;
        last if $got == 0;
    }
    close $fh if $path ne '-';
    die { input => 'the survey is larger than 64 KB' } if length($data) > MAX_INPUT;
    my $text = eval { decode('UTF-8', $data, FB_CROAK) };
    die { input => 'the survey is not valid UTF-8' } unless defined $text;
    return $text;
}

sub run {
    my ($args, $in, $out, $err) = @_;
    if (@$args != 1 || $args->[0] =~ /\A(?:-h|--help)\z/) {
        print {$err} $USAGE;
        return 2;
    }
    my $report = eval { render(analyse(parse_survey(read_bounded($args->[0], $in)))) };
    if (!defined $report) {
        my $e = $@;
        die $e unless ref $e eq 'HASH' && defined $e->{input};
        print {$err} "downthrow: $e->{input}\n";
        return 2;
    }
    binmode $out, ':encoding(UTF-8)';
    print {$out} $report;
    return 0;
}

1;
