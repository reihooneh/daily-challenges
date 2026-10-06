use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Temp qw(tempdir);
use IPC::Open3;
use List::Util qw(shuffle);
use Symbol qw(gensym);
use Test::More;

use Strandbox::Codec qw(bytes_to_dna dna_to_bytes crc16 crc32 whiten gc_fraction longest_run);
use Strandbox::Archive qw(encode decode damage read_fasta write_fasta stats);

my $BIN = "$FindBin::Bin/../bin/strandbox";
srand 2026;
my $random_bytes = sub { join '', map { chr int rand 256 } 1 .. $_[0] };

# Runs the real program without a shell. Returns (exit code, stdout, stderr).
sub run_cli {
    my ( $stdin, @args ) = @_;
    my $pid = open3( my $in, my $out, my $err = gensym, $^X, $BIN, @args );
    binmode $_ for $in, $out, $err;
    print {$in} $stdin;
    close $in;
    local $/;
    my $stdout = <$out>;
    my $stderr = <$err>;
    waitpid $pid, 0;
    return ( $? >> 8, $stdout // '', $stderr // '' );
}

# ---- the code itself --------------------------------------------------------

is bytes_to_dna(''), '', 'nothing in, nothing out';
is length( bytes_to_dna('abc') ), 18, 'six bases per byte';
for my $value ( 0 .. 255 ) {
    my $dna = bytes_to_dna( chr $value );
    if ( dna_to_bytes($dna) ne chr $value ) { fail "byte $value does not round-trip"; last; }
    pass 'every byte value round-trips' if $value == 255;
}
{
    my $data = $random_bytes->(5000);
    my $dna  = bytes_to_dna($data);
    is dna_to_bytes($dna), $data, 'random data round-trips';
    is longest_run($dna), 1, 'no base ever appears twice in a row';
    is longest_run( bytes_to_dna( "\0" x 500 ) ), 1, 'not even for a file full of zeros';
    like $dna, qr/\A[ACGT]+\z/, 'output is only A, C, G and T';
}
is dna_to_bytes('CGTACG'),  "\0", 'a hand-worked example: six zero trits starting from A';
is dna_to_bytes('CGTAC'),   undef, 'wrong length is rejected';
is dna_to_bytes('CGTACN'),  undef, 'unknown letters are rejected';
is dna_to_bytes('CCGTAC'),  undef, 'a repeated base is rejected';
is dna_to_bytes('cgtacg'),  undef, 'lower case is rejected at this layer';
is dna_to_bytes('TGTGTG'),  undef, 'a value above 255 is rejected';

is crc16('123456789'), 0x29B1,     'CRC-16 matches the published check value';
is crc32('123456789'), 0xCBF43926, 'CRC-32 matches the published check value';
is crc32(''),          0,          'CRC-32 of nothing';

{
    my $data = $random_bytes->(64);
    is whiten( whiten( $data, 7 ), 7 ), $data, 'whitening twice gives the original back';
    isnt whiten( $data, 7 ), whiten( $data, 8 ), 'each oligo number gets a different pattern';
    my $zeros = whiten( "\0" x 4000, 3 );
    my %seen; $seen{$_}++ for unpack 'C*', $zeros;
    cmp_ok scalar( keys %seen ), '>', 200, 'whitened zeros use most byte values';
}
is gc_fraction('GGCC'), 1,   'GC of GGCC';
is gc_fraction('ACGT'), 0.5, 'GC of ACGT';
is gc_fraction(''),     0,   'GC of nothing';

# ---- whole files --------------------------------------------------------------

for my $size ( 0, 1, 19, 20, 21, 139, 140, 141, 160, 1000, 4096 ) {
    my $data   = $random_bytes->($size);
    my @oligos = encode($data);
    my $report = decode( shuffle @oligos );
    is $report->{data}, $data, "a $size-byte file survives shuffling";
    is scalar( grep { length != 144 } @oligos ), 0, "every oligo is 144 bases ($size bytes)";
}
{
    my @oligos = encode( "\0" x 20000 );
    my $s = stats(@oligos);
    is $s->{longest_run}, 1, 'a file of zeros still has no repeats';
    cmp_ok abs( $s->{gc} - 0.5 ), '<', 0.02, 'and its GC content is balanced';
    cmp_ok $s->{gc_low},  '>', 0.3, 'no oligo is GC-poor';
    cmp_ok $s->{gc_high}, '<', 0.7, 'no oligo is GC-rich';
}

# ---- loss and damage ------------------------------------------------------------

my $data   = $random_bytes->(1500);
my @oligos = encode($data);    # 76 chunks: 10 groups
{
    my $all_recovered = 1;
    for my $lost ( 0 .. $#oligos ) {
        my @pool = @oligos;
        splice @pool, $lost, 1;
        my $report = decode(@pool);
        $all_recovered &&= defined $report->{data} && $report->{data} eq $data;
    }
    ok $all_recovered, 'losing any single oligo (header and parity included) is survivable';
}
{
    my @pool = @oligos;
    splice @pool, 9 * $_, 1 for reverse 0 .. 8;    # one from each of the first nine groups
    my $report = decode( shuffle @pool );
    is $report->{data}, $data, 'one loss in every group is survivable';
    is scalar @{ $report->{recovered} }, 9, 'and each was rebuilt from parity';
}
{
    my @pool = @oligos;
    splice @pool, 10, 2;                           # two from the same group
    my $report = decode(@pool);
    is $report->{data}, undef, 'two losses in one group cannot be rebuilt';
    is_deeply $report->{missing}, [ 9, 10 ], 'and the report names exactly the missing oligos';
    like $report->{error}, qr/too many oligos were lost/, 'with a clear reason';
}
{
    my @pool = @oligos;
    splice @pool, 0, 2;                            # header and one neighbour
    my $report = decode(@pool);
    is $report->{data}, undef, 'a lost header plus a lost neighbour is reported, not guessed';
    like $report->{error}, qr/header/, 'with a clear reason';
}
{
    my $never_wrong = 1;
    my $detected    = 0;
    for my $trial ( 1 .. 300 ) {
        my @pool = @oligos;
        my $victim = int rand @pool;
        my $at     = int rand 144;
        my $old    = substr $pool[$victim], $at, 1;
        my ($new)  = grep { $_ ne $old } shuffle qw(A C G T);
        substr( $pool[$victim], $at, 1 ) = $new;
        my $report = decode(@pool);
        $detected++ if $report->{damaged} == 1;
        $never_wrong &&= defined $report->{data} && $report->{data} eq $data;
    }
    is $detected, 300, 'every single-base change is detected';
    ok $never_wrong, 'and repaired: the file is never silently wrong';
}
{
    my $wrong = 0;
    my $ok    = 0;
    for my $seed ( 1 .. 60 ) {
        srand $seed;
        my @aged = damage( \@oligos, 0.05, 0.001, 3, sub { rand } );
        my $report = decode(@aged);
        if    ( !defined $report->{data} ) { }
        elsif ( $report->{data} eq $data ) { $ok++ }
        else                               { $wrong++ }
    }
    is $wrong, 0, 'simulated ageing never produces a wrong file';
    cmp_ok $ok, '>=', 50, "and the file usually survives it ($ok of 60)";
}
is decode( @oligos, @oligos )->{duplicates}, scalar @oligos, 'duplicate strands are counted and ignored';
is decode()->{data}, undef, 'an empty pool gives no file';
is decode( map { 'ACGT' x 36 } 1 .. 50 )->{damaged}, 50, 'unrelated DNA is all rejected';
{
    my $forged = 'ACGT' x 36;
    my $report = decode( @oligos[ 1 .. $#oligos ], $forged );
    is $report->{data}, $data, 'a foreign strand in the pool does no harm';
}

# ---- FASTA ----------------------------------------------------------------------

{
    my $fasta = write_fasta(@oligos);
    is_deeply [ read_fasta($fasta) ], \@oligos, 'FASTA round-trips';
    ( my $wrapped = $fasta ) =~ s/([ACGT]{60})/$1\n/g;
    is_deeply [ read_fasta($wrapped) ], \@oligos, 'wrapped sequence lines are joined';
    ( my $windows = lc $fasta ) =~ s/\n/\r\n/g;
    is_deeply [ read_fasta($windows) ], \@oligos, 'lower case and Windows line endings are accepted';
    is_deeply [ read_fasta(">a\nACGN\n\n>b\n") ], [ 'ACGN', '' ], 'N and empty records are read (and later rejected as damaged)';
}
for my $case (
    [ "ACGT\n",                         qr/before the first/ ],
    [ ">x\nACGU\n",                     qr/only the letters/ ],
    [ ">x\nAC-GT\n",                    qr/only the letters/ ],
    [ ">x\n<script>alert(1)</script>\n", qr/only the letters/ ],
    [ ">x\n\e[2J\e]0;owned\a\n",        qr/only the letters/ ],
    [ ">x\n" . ( 'A' x 5000 ) . "\n",   qr/longer than 4096/ ],
    [ ">x\n" . ( "ACGT\n" x 2000 ),     qr/sequence is longer/ ],
  )
{
    my ( $text, $expected ) = @$case;
    eval { read_fasta($text) };
    like $@, $expected, 'bad FASTA is refused';
    unlike $@, qr/script|owned|\e|\a/, 'and the message does not repeat the input';
}
eval { encode( 'x' x ( 256 * 1024 + 1 ) ) };
like $@, qr/larger than/, 'oversized files are refused';

# ---- command line ---------------------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
{
    my ( $code, $fasta, $err ) = run_cli( $data, 'encode', '-' );
    is $code, 0, 'encode exits 0';
    like $err, qr/Stored 1500 bytes in \d+ oligos/, 'encode reports what it did';
    my ( $code2, $back, $err2 ) = run_cli( $fasta, 'decode', '-' );
    is $code2, 0, 'decode exits 0';
    ok $back eq $data, 'the command line round-trips binary data';
    like $err2, qr/Checksum matches/, 'decode confirms the checksum';

    my @lines = grep { !/^>/ } split /\n/, $fasta;
    my ($code3) = run_cli( join( '', map { ">x\n$_\n" } @lines[ 0 .. 5 ] ), 'decode', '-' );
    is $code3, 1, 'a pool that cannot be rebuilt exits 1';

    my ( $code4, $text ) = run_cli( $fasta, 'stats', '-' );
    like $text, qr/Longest repeat:\s+1 base in a row/, 'stats reports the longest repeat';

    my ( $c5, $aged )  = run_cli( $fasta, 'damage', '-', '--seed', '5' );
    my ( $c6, $aged2 ) = run_cli( $fasta, 'damage', '-', '--seed', '5' );
    is $aged, $aged2, 'the same seed gives the same damage';
}
{
    my $out = "$dir/out.fasta";
    my ($code) = run_cli( 'hello', 'encode', '-', '-o', $out );
    is $code, 0, 'writing to a new file works';
    my ( $code2, undef, $err ) = run_cli( 'other', 'encode', '-', '-o', $out );
    is $code2, 2, 'an existing file is not overwritten';
    like $err, qr/already exists/, 'and the reason is given';
    symlink '/etc/hostname', "$dir/link";
    my ($code3) = run_cli( 'hello', 'encode', '-', '-o', "$dir/link" );
    is $code3, 2, 'a symlink is not written through';
    my ($code4) = run_cli( 'other', 'encode', '-', '-o', $out, '--force' );
    is $code4, 0, '--force replaces the file';
}
for my $args (
    [], ['bogus'], ['encode'], [ 'encode', 'a', 'b' ], [ 'encode', '/no/such/file' ], [ 'encode', '/' ],
    [ 'encode', '../../../etc/shadow/x' ], [ 'encode', '| echo hacked' ], [ 'encode', '> /tmp/hacked' ],
    [ 'decode', '-', '--bogus' ], [ 'damage', '-', '--loss', '2' ], [ 'damage', '-', '--errors', '-1' ],
    [ 'damage', '-', '--copies', '0' ], [ 'damage', '-', '--copies', '9999' ], [ 'damage', '-', '--seed', 'abc' ],
  )
{
    my ( $code, $out, $err ) = run_cli( ">x\nACGT\n", @$args );
    is $code, 2, "bad usage exits 2: @$args";
    is $out, '', 'with nothing on standard output';
    like $err, qr/\Astrandbox: [^\n]+\n/, 'and a one-line reason first';
}
ok !-e '/tmp/hacked', 'a file name is never treated as a shell command';
{
    my ( $code, undef, $err ) = run_cli( 'x' x ( 256 * 1024 + 10 ), 'encode', '-' );
    is $code, 2, 'oversized input exits 2';
    like $err, qr/larger than/, 'with a clear reason';
}

done_testing;
