package Tallyhook::Parse;
# Reads a crochet pattern written in the usual US abbreviations into rounds of instructions.
#
#   Rnd 1: 6 sc in magic ring (6)
#   Rnd 2: inc in each st around (12)
#   Rnd 3: *sc in next st, inc; rep from * around (18)
#   Rnds 4-6: sc in each st around (18)
#   Row 2: ch 1, sc in each st across, turn (20)
#
# Every instruction becomes a small node: a stitch (how many it works into, how many it makes),
# "in each st" (as many as are left), or a group repeated a number of times or "around".
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(parse_pattern clean MAX_BYTES MAX_ROUNDS MAX_TIMES);

use constant MAX_BYTES  => 64 * 1024;
use constant MAX_ROUNDS => 500;
use constant MAX_TIMES  => 1000;

my $ST = qr/(?:sc|hdc|dc|tr|sl st|esc|ehdc)/;

# Makes text safe to print: no control characters, at most 50 characters.
sub clean {
    my ($s) = @_;
    $s =~ s/[^\x20-\x7e\x{a0}-\x{2027}\x{2030}-\x{fffd}]/?/g;
    $s = substr($s, 0, 47) . '...' if length $s > 50;
    return $s;
}

sub fail { die { line => $_[0], msg => $_[1] } }

# Returns a list of rounds: { label, first, last, kind (rnd|row), items, stated, line }.
sub parse_pattern {
    my ($text) = @_;
    fail(0, 'the pattern is larger than 64 KB') if length $text > MAX_BYTES;
    fail(0, 'the pattern has a NUL byte') if $text =~ /\0/;
    my @rounds;
    my $n = 0;
    for my $raw (split /\r?\n/, $text) {
        $n++;
        my $line = lc $raw;
        $line =~ s/\s+/ /g;
        $line =~ s/^\s+|\s+$//g;
        next unless $line =~ /^(rnds?|rounds?|rows?)\s+(\d{1,4})(?:\s*(?:-|to|\x{2013})\s*(\d{1,4}))?\s*[:.]\s*(.+)$/;
        my ($kind, $first, $last, $body) = ($1, $2, $3 // $2, $4);
        $kind = $kind =~ /^row/ ? 'row' : 'rnd';
        fail($n, 'the round numbers go backwards') if $last < $first;
        fail($n, 'at most ' . MAX_ROUNDS . ' rounds') if @rounds && $last > MAX_ROUNDS || $first > MAX_ROUNDS;
        my $stated;
        if ($body =~ s/\s*(?:[(\[]\s*(\d{1,6})\s*(?:sts?|stitches|sc|dc|hdc)?\s*[)\]]|(?:-|\x{2013}|\x{2014}|=)\s*(\d{1,6})\s*(?:sts?|stitches)?)\s*\.?\s*$//) {
            $stated = $1 // $2;
        }
        $body =~ s/\.\s*$//;
        my $items = parse_seq($body, $n);
        push @rounds, { label => ucfirst($kind) . " $first" . ($last != $first ? "-$last" : ''), first => $first + 0,
                        last => $last + 0, kind => $kind, items => $items, stated => $stated, line => $n };
        fail($n, 'at most ' . MAX_ROUNDS . ' rounds') if @rounds > MAX_ROUNDS;
    }
    fail(0, 'no rounds or rows found (lines should start like "Rnd 1:" or "Row 2:")') unless @rounds;
    return \@rounds;
}

# Splits at top-level commas and semicolons, keeping bracketed groups together.
sub split_top {
    my ($s, $n) = @_;
    my @parts;
    my ($cur, $depth) = ('', 0);
    for my $c (split //, $s) {
        if ($c eq '(' || $c eq '[') { $depth++ }
        elsif ($c eq ')' || $c eq ']') { $depth--; fail($n, 'a bracket closes without opening') if $depth < 0 }
        if (($c eq ',' || $c eq ';') && $depth == 0) { push @parts, $cur; $cur = ''; next }
        $cur .= $c;
    }
    fail($n, 'a bracket is never closed') if $depth;
    push @parts, $cur;
    return grep { length } map { my $t = $_; $t =~ s/^\s+|\s+$//g; $t } @parts;
}

sub parse_seq {
    my ($s, $n, $depth) = @_;
    $depth //= 0;
    fail($n, 'brackets nested too deeply') if $depth > 4;
    my @out;
    my $star;    # index in @out where a *repeat* began
    for my $part (split_top($s, $n)) {
        # A star starts a repeat that a later "rep from *" closes.
        if ($part =~ s/^\*\s*//) {
            fail($n, 'two * repeats open at once') if defined $star;
            $star = scalar @out;
            next unless length $part;
        }
        # "*sc, inc* around": the closing star sits on the last part, with the count.
        if (defined $star && $part =~ /^(.*?)\s*\*\s*(.*)$/ && $part !~ /^rep/) {
            my ($last, $rest) = ($1, $2);
            push @out, atom($last, $n) if length $last;
            my @body = splice @out, $star;
            push @out, { t => 'group', items => \@body, times => times_of($rest, $n, 1) };
            undef $star;
            next;
        }
        if ($part =~ /^rep(?:eat)?\s+from\s+\*\s*(.*)$/) {
            fail($n, '"rep from *" without a *') unless defined $star;
            my $times = times_of($1, $n, 1);
            my @body = splice @out, $star;
            push @out, { t => 'group', items => \@body, times => $times };
            undef $star;
            next;
        }
        # A group in brackets with a count: (sc, inc) x 6, [sc in next 2 sts, inc] 6 times, (...) around.
        if ($part =~ /^[(\[](.*)[)\]]\s*(.*)$/) {
            my ($inner, $rest) = ($1, $2);
            push @out, { t => 'group', items => parse_seq($inner, $n, $depth + 1), times => times_of($rest, $n, 0) };
            next;
        }
        push @out, atom($part, $n);
    }
    # A star with no "rep from *" (as in "*sc, inc* around") is closed by "* around" in the same part.
    fail($n, 'a * repeat is never closed with "rep from *"') if defined $star;
    return [ grep { $_->{t} ne 'skip' } @out ];
}

# How many times a group repeats: "x 6", "6 times", "5 more times" (6 in all), "around".
# A bracketed group with no count is worked once; "rep from *" must say how many times.
sub times_of {
    my ($s, $n, $after_rep) = @_;
    $s =~ s/^\s+|\s+$//g;
    return 'around' if $s =~ /^(?:around|across|(?:across\s+)?to\s+(?:the\s+)?end|in each st around)$/;
    if ($s =~ /^(?:x\s*|\x{d7}\s*)?(\d{1,4})(\s+more)?(?:\s+times?)?(?:\s+total)?$/) {
        my $t = $1 + ($2 ? 1 : 0);
        fail($n, 'a repeat count should be from 1 to ' . MAX_TIMES) if $t < 1 || $t > MAX_TIMES;
        return $t;
    }
    return 1 if $s eq '' && !$after_rep;
    fail($n, 'how many times to repeat is unclear: "' . clean($s) . '"');
}

# One instruction.
sub atom {
    my ($p, $n) = @_;
    my $num = sub { my $v = shift; fail($n, 'a stitch count should be from 1 to 10000') if $v < 1 || $v > 10000; $v + 0 };
    # Starting: a magic ring or a foundation chain.
    return { t => 'ring', make => $num->($1) } if $p =~ /^(\d+)\s*$ST\s+in\s+(?:a\s+|the\s+)?(?:magic ring|magic loop|mr|ring|adjustable ring)$/;
    return { t => 'chain', make => $num->($1) } if $p =~ /^(?:ch|chain)\s*(\d+)(?:\s*,?\s*turn)?$/;
    # The first row worked into a foundation chain: "sc in 2nd ch from hook (and in each ch across)".
    if ($p =~ /^$ST\s+in\s+(\d)(?:st|nd|rd|th)\s+ch\s+from\s+(?:the\s+)?hook(\s+and\s+(?:in\s+)?(?:each|every)\s+ch\s+across)?$/) {
        return { t => 'hook', from => $1 + 0, each => $2 ? 1 : 0 };
    }
    # Things that make no stitches.
    return { t => 'skip' } if $p =~ /^(?:turn|join|fasten off.*|sl st (?:to|in|into) (?:the )?(?:first|beg|top|1st).*|join with (?:a )?sl st.*|change (?:to )?(?:colour|color|yarn).*|stuff.*|place marker.*|pm|blo|flo|in blo|in flo|working in (?:blo|flo|back loops?|front loops?)(?: only)?)$/;
    # Every remaining stitch.
    return { t => 'each', take => 1, make => 1 } if $p =~ /^$ST(?:\s+(?:blo|flo))?\s+(?:in\s+(?:each|every)\s+st(?:itch)?(?:es)?\s+)?(?:around|across|to end)$/
        || $p =~ /^$ST\s+in\s+(?:each|every)\s+(?:st(?:itch)?(?:es)?|ch)(?:\s+(?:around|across))?$/;
    return { t => 'each', take => 1, make => 2, inc => 1 } if $p =~ /^(?:inc|2\s*$ST\s+in\s+(?:each|every)\s+st)(?:\s+in\s+(?:each|every)\s+st)?(?:\s+(?:around|across))?$/ && $p =~ /around|across|each|every/;
    return { t => 'each', take => 2, make => 1, dec => 1 } if $p =~ /^(?:dec|invdec|sc2tog)\s+(?:around|across)$/;
    # Increases and decreases.
    if ($p =~ /^(\d+)\s*$ST\s+in\s+(?:next|same|the next|each of next)\s+st$/) {
        my $k = $num->($1);
        return { t => 'st', take => 1, make => $k, inc => $k > 1 ? 1 : 0 };
    }
    return { t => 'st', take => 1, make => 2, inc => 1, rep => $num->($1 // 1) } if $p =~ /^(?:(\d+)\s*)?(?:inc|increase)s?(?:\s+in\s+next\s+st)?$/;
    return { t => 'st', take => 2, make => 1, dec => 1, rep => $num->($1 // 1) } if $p =~ /^(?:(\d+)\s*)?(?:dec|invdec|inv dec|decrease|sc2tog|hdc2tog|dc2tog)s?$/;
    return { t => 'st', take => 3, make => 1, dec => 1, rep => $num->($1 // 1) } if $p =~ /^(?:(\d+)\s*)?(?:sc3tog|dc3tog)$/;
    # Plain stitches.
    return { t => 'st', take => 1, make => 1, rep => $num->($1) } if $p =~ /^$ST(?:\s+(?:blo|flo))?\s+in\s+(?:the\s+)?next\s+(\d+)\s+st(?:itch)?(?:es|s)?$/;
    return { t => 'st', take => 1, make => 1, rep => $num->($1) } if $p =~ /^$ST(?:\s+(?:blo|flo))?\s+(\d+)$/;
    return { t => 'st', take => 1, make => 1, rep => $num->($1 // 1) } if $p =~ /^(?:(\d+)\s*)?$ST(?:\s+(?:blo|flo))?(?:\s+in\s+(?:the\s+)?next\s+st(?:itch)?)?$/;
    return { t => 'st', take => $num->($1), make => 0 } if $p =~ /^(?:sk|skip)\s+(?:next\s+)?(\d+)\s*(?:sts?|stitches)?$/;
    return { t => 'st', take => 1, make => 0 } if $p =~ /^(?:sk|skip)\s+(?:next\s+)?(?:st|stitch)$/;
    fail($n, 'can\'t read "' . clean($p) . '"');
}

1;
