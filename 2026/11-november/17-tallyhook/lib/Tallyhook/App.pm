package Tallyhook::App;
# The command line: tallyhook PATTERN.txt (or - for standard input).
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
use Tallyhook::Parse qw(parse_pattern MAX_BYTES);
use Tallyhook::Count qw(tally);
use Tallyhook::Report qw(report);
our @EXPORT_OK = qw(run check_text);

# Checks a pattern's text; returns (report, number of rounds with problems).
sub check_text {
    my ($text, $name) = @_;
    my $rounds = parse_pattern($text);
    my $res = tally($rounds);
    my $bad = grep { @{ $_->{errors} } } @$res;
    return (report($res, $name), $bad);
}

sub run {
    my ($args, $in, $out, $err) = @_;
    if (@$args != 1 || $args->[0] =~ /^-(?:h|-help)$/) {
        print {$err} "usage: tallyhook PATTERN.txt   (or - to read standard input)\n";
        return 2;
    }
    my $path = $args->[0];
    my $text;
    if ($path eq '-') {
        my $got = read($in, $text, MAX_BYTES + 1) // 0;
        $text //= '';
    } else {
        if (!-e $path) { print {$err} "tallyhook: the pattern file was not found\n"; return 1 }
        if (-l $path || !-f _) { print {$err} "tallyhook: the pattern must be a plain file\n"; return 1 }
        if (-s _ > MAX_BYTES) { print {$err} "tallyhook: the pattern is larger than 64 KB\n"; return 1 }
        my $fh;
        if (!open($fh, '<:raw', $path)) { print {$err} "tallyhook: the pattern can't be read\n"; return 1 }
        local $/;
        $text = <$fh>;
        close $fh;
        $text //= '';
    }
    my ($rep, $bad);
    my $ok = eval {
        die { line => 0, msg => 'the pattern is larger than 64 KB' } if length $text > MAX_BYTES;
        utf8::decode($text) or die { line => 0, msg => 'the pattern is not valid UTF-8 text' };
        ($rep, $bad) = check_text($text, $path eq '-' ? 'standard input' : (split m{/}, $path)[-1]);
        1;
    };
    if (!$ok) {
        my $e = $@;
        if (ref $e eq 'HASH' && defined $e->{msg}) {
            print {$err} 'tallyhook: ' . ($e->{line} ? "line $e->{line}: " : '') . "$e->{msg}\n";
            return 1;
        }
        print {$err} "tallyhook: something went wrong reading the pattern\n";
        return 1;
    }
    binmode $out, ':utf8';
    print {$out} $rep;
    return $bad ? 3 : 0;
}

1;
