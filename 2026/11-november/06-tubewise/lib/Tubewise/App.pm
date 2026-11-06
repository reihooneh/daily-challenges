package Tubewise::App;
# The command line: options, the text or design file (checked strictly), and the output.
use strict;
use warnings FATAL => 'all';
use Exporter 'import';
our @EXPORT_OK = qw(run parse_design check_text);
use Encode ();
use Tubewise::Font qw(glyph_chars layout);
use Tubewise::Graph qw(build);
use Tubewise::Route qw(plan);
use Tubewise::Report qw(render svg);

use constant { MAX_INPUT => 64 * 1024, MAX_LINE => 300, MAX_STROKES => 400, MAX_POINTS => 50, MAX_TEXT => 24 };

my $USAGE = <<'END';
usage: tubewise [options] "TEXT"
       tubewise [options] --design FILE     (a file of strokes; - reads standard input)
Plans the glass for a neon sign: one continuous tube through every letter, with the least
blacked-out glass, cut into tubes a bender can handle.
  --height MM      letter height, 40 to 1000 (default 200)
  --max-tube MM    longest tube, 300 to 6000 (default 2000)
  --bend MM        extra glass for each jumper's bends, 0 to 200 (default 20)
  --svg            print a drawing (SVG) instead of the plan
END

sub _fail { die { msg => $_[0] } }

sub _number {
    my ($v, $what, $lo, $hi) = @_;
    _fail("$what must be a number like 200 or 12.5") unless defined $v && $v =~ /\A[0-9]{1,4}(?:\.[0-9]{1,2})?\z/;
    _fail("$what must be from $lo to $hi") if $v < $lo || $v > $hi;
    return 0 + $v;
}

# Control characters and invisible formatting characters (zero-width, bidirectional, BOM).
sub _hidden { my ($s) = @_; return $s =~ /[\x00-\x08\x0A-\x1F\x7F-\x9F\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{206F}\x{FEFF}]/ }

sub check_text {
    my ($raw) = @_;
    _fail('give the text for the sign, like "OPEN"') unless defined $raw && length $raw;
    _fail('the text has a control or invisible formatting character') if _hidden($raw);
    my $t = uc $raw;
    _fail('the text must be 1 to ' . MAX_TEXT . ' characters') if length($t) > MAX_TEXT;
    my $ok = quotemeta glyph_chars();
    _fail('the text may use only A-Z, 0-9, space, - ! and .') unless $t =~ /\A[$ok ]+\z/;
    _fail('the text needs at least one letter') unless $t =~ /\S/;
    return $t;
}

# A design file: lines "stroke x,y x,y ..." in millimetres (y up), and an optional "name ...".
sub parse_design {
    my ($bytes) = @_;
    _fail('the design file is larger than 64 KB') if length($bytes) > MAX_INPUT;
    my $text = eval { Encode::decode('UTF-8', $bytes, Encode::FB_CROAK) };
    _fail('the design file is not valid UTF-8 text') unless defined $text;
    $text =~ s/\A\x{FEFF}//;
    my ($name, @strokes) = ('Custom design');
    my $n = 0;
    for my $line (split /\n/, $text, -1) {
        $n++;
        $line =~ s/\r\z//;
        _fail("line $n: is longer than " . MAX_LINE . ' characters') if length($line) > MAX_LINE;
        _fail("line $n: contains a control or invisible formatting character") if _hidden($line);
        $line =~ s/#.*//;
        next unless $line =~ /\S/;
        if ($line =~ /\A\s*name\s+(.*?)\s*\z/) {
            my $nm = $1;
            _fail("line $n: the name is letters, digits, spaces and ' . , & ( ) ! - (up to 40)") unless $nm =~ /\A[A-Za-z0-9][A-Za-z0-9 '.,&()!-]{0,39}\z/;
            $name = $nm;
            next;
        }
        my ($head, @pts) = split ' ', $line;
        _fail("line $n: lines are 'name ...' or 'stroke x,y x,y ...'") unless $head eq 'stroke';
        _fail("line $n: a stroke has 2 to " . MAX_POINTS . ' points') if @pts < 2 || @pts > MAX_POINTS;
        my @p;
        for my $w (@pts) {
            _fail("line $n: points are x,y in millimetres, like 120,45.5") unless $w =~ /\A([0-9]{1,4}(?:\.[0-9]{1,2})?),([0-9]{1,4}(?:\.[0-9]{1,2})?)\z/;
            _fail("line $n: points must be within 5000 mm") if $1 > 5000 || $2 > 5000;
            push @p, [ 0 + $1, 0 + $2 ];
        }
        _fail('at most ' . MAX_STROKES . ' strokes') if @strokes >= MAX_STROKES;
        push @strokes, { char => 0, points => \@p };
    }
    _fail('the design has no strokes') unless @strokes;
    return ($name, \@strokes);
}

sub _read {
    my ($path, $stdin) = @_;
    my $fh;
    if ($path eq '-') {
        $fh = $stdin;
    } else {
        _fail('the design file could not be read (it must be a regular file, not a link)') if -l $path || !-f _;
        open $fh, '<:raw', $path or _fail('the design file could not be read (it must be a regular file, not a link)');
    }
    binmode $fh, ':raw';
    my $data = '';
    my $got = read $fh, $data, MAX_INPUT + 1;
    _fail('the design file could not be read') unless defined $got;
    return $data;
}

sub run {
    my ($argv, $stdin, $stdout, $stderr) = @_;
    my %o = (height => 200, max_tube => 2000, bend => 20);
    my ($text, $design, $svg);
    my $ok = eval {
        my @a = @$argv;
        while (@a) {
            my $x = shift @a;
            if    ($x eq '--svg')                     { $svg = 1 }
            elsif ($x =~ /\A--(height|max-tube|bend)\z/) {
                my $k = $1 =~ tr/-/_/r;
                my %range = (height => [ 40, 1000 ], max_tube => [ 300, 6000 ], bend => [ 0, 200 ]);
                $o{$k} = _number(shift(@a), "--$1", @{ $range{$k} });
            }
            elsif ($x eq '--design') { $design = shift @a; _fail('--design needs a file') unless defined $design }
            elsif ($x eq '-h' || $x eq '--help' || $x =~ /\A-/ && $x ne '-') { _fail('') }
            else { _fail('give one text') if defined $text; $text = $x }
        }
        _fail('give either a text or --design, not both') if defined $text && defined $design;
        my ($title, $strokes, $chars, $height);
        if (defined $design) {
            ($title, $strokes) = parse_design(_read($design, $stdin));
            $chars = [];
        } else {
            $text = Encode::decode('UTF-8', $text // '', Encode::FB_CROAK) if defined $text && !utf8::is_utf8($text);
            my $t = check_text($text);
            ($title, $strokes, $chars, $height) = (qq{"$t"}, layout($t, $o{height}), [ split //, $t ], $o{height});
        }
        my $p = plan(build($strokes), max_tube => $o{max_tube}, bend => $o{bend});
        print {$stdout} $svg ? svg($title, $p) : render($title, $chars, $height, $p);
        1;
    };
    return 0 if $ok;
    my $err = $@;
    if (ref $err eq 'HASH') {
        print {$stderr} length $err->{msg} ? "tubewise: $err->{msg}\n" : $USAGE;
        return 2;
    }
    if (!ref $err && $err =~ /\A(the sign has no strokes|the strokes can't all be joined)/) {
        print {$stderr} "tubewise: $err";
        return 2;
    }
    if (!ref $err && $err =~ /Malformed|does not map/) {
        print {$stderr} "tubewise: the text is not valid UTF-8\n";
        return 2;
    }
    die $err;
}

1;
