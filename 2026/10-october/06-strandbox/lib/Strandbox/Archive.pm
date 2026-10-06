package Strandbox::Archive;

# A file <-> a pool of oligos.
#
# In a test tube there is no "first" or "last": every strand floats freely,
# some go missing and some get damaged. So each oligo carries its own number
# and its own checksum, and every group of data oligos gets one extra
# "parity" oligo that can rebuild any single lost member of the group.
#
# Layout of one oligo before it is turned into DNA (24 bytes -> 144 bases):
#
#     2 bytes   number   (top bit set = parity oligo for that group)
#    20 bytes   payload  (whitened)
#     2 bytes   CRC-16 of the 22 bytes above
#
# Oligo 0 is the header: format version, file length and the file's CRC-32.

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(encode decode damage read_fasta write_fasta stats);

use Strandbox::Codec qw(bytes_to_dna dna_to_bytes crc16 crc32 whiten gc_fraction longest_run);

use constant {
    PAYLOAD       => 20,
    GROUP         => 8,                 # data oligos per parity oligo
    PARITY_FLAG   => 0x8000,
    VERSION       => 1,
    MAX_FILE      => 256 * 1024,        # bytes that can be stored
    MAX_FASTA     => 16 * 1024 * 1024,  # bytes of FASTA that will be read
    MAX_LINE      => 4096,
    OLIGO_LENGTH  => 144,
};

sub _pack_oligo {
    my ( $number, $payload ) = @_;
    my $body = pack( 'n', $number ) . whiten( $payload, $number );
    return bytes_to_dna( $body . pack( 'n', crc16($body) ) );
}

# Returns (number, payload) or nothing if the oligo is damaged.
sub _unpack_oligo {
    my ($dna) = @_;
    return unless length $dna == OLIGO_LENGTH;
    my $bytes = dna_to_bytes($dna);
    return unless defined $bytes;
    my $body = substr $bytes, 0, 2 + PAYLOAD;
    return unless crc16($body) == unpack 'n', substr( $bytes, 2 + PAYLOAD );
    my $number = unpack 'n', $body;
    return ( $number, whiten( substr( $body, 2 ), $number ) );
}

sub _xor {
    my ( $x, $y ) = @_;
    return $x ^ $y;    # Perl XORs two byte strings character by character
}

# Turns file contents into a list of DNA strings.
sub encode {
    my ($data) = @_;
    die "file is larger than @{[MAX_FILE]} bytes\n" if length $data > MAX_FILE;

    my $header = pack( 'C N N', VERSION, length $data, crc32($data) );
    my @chunks = ( $header . ( "\0" x ( PAYLOAD - length $header ) ) );
    for ( my $at = 0 ; $at < length $data ; $at += PAYLOAD ) {
        my $chunk = substr $data, $at, PAYLOAD;
        push @chunks, $chunk . ( "\0" x ( PAYLOAD - length $chunk ) );
    }

    my @oligos;
    for ( my $start = 0 ; $start < @chunks ; $start += GROUP ) {
        my $parity = "\0" x PAYLOAD;
        for my $number ( $start .. $start + GROUP - 1 ) {
            last if $number > $#chunks;
            push @oligos, _pack_oligo( $number, $chunks[$number] );
            $parity = _xor( $parity, $chunks[$number] );
        }
        push @oligos, _pack_oligo( PARITY_FLAG | ( $start / GROUP ), $parity );
    }
    return @oligos;
}

# Rebuilds the file from oligos in any order. Returns a report:
#   { data => bytes or undef, total, damaged, duplicates, recovered => [...], missing => [...], error }
sub decode {
    my (@oligos) = @_;
    my %report = ( total => scalar @oligos, damaged => 0, duplicates => 0, recovered => [], missing => [] );
    my ( %data, %parity );
    for my $dna (@oligos) {
        my ( $number, $payload ) = _unpack_oligo($dna);
        if ( !defined $number ) { $report{damaged}++; next; }
        my $store = $number & PARITY_FLAG ? \%parity : \%data;
        my $key   = $number & ~PARITY_FLAG & 0xFFFF;
        if ( exists $store->{$key} ) { $report{duplicates}++; next; }
        $store->{$key} = $payload;
    }

    # The header might itself be the lost oligo, so repair its group first.
    _repair_group( 0, \%data, \%parity, \%report );
    if ( !exists $data{0} ) {
        $report{error} = 'the header oligo is missing and could not be rebuilt';
        return \%report;
    }
    my ( $version, $length, $checksum ) = unpack 'C N N', $data{0};
    if ( $version != VERSION || $length > MAX_FILE ) {
        $report{error} = 'the header is not from a version of Strandbox this program understands';
        return \%report;
    }

    my $last = int( ( $length + PAYLOAD - 1 ) / PAYLOAD );    # number of the last data oligo
    for ( my $group = 1 ; $group * GROUP <= $last ; $group++ ) {
        _repair_group( $group, \%data, \%parity, \%report, $last );
    }
    _repair_group( 0, \%data, \%parity, \%report, $last );
    push @{ $report{missing} }, grep { !exists $data{$_} } 1 .. $last;
    if ( @{ $report{missing} } ) {
        $report{error} = 'too many oligos were lost to rebuild the file';
        return \%report;
    }

    my $data = substr join( '', map { $data{$_} } 1 .. $last ), 0, $length;
    if ( crc32($data) != $checksum ) {
        $report{error} = 'the rebuilt file does not match its checksum';
        return \%report;
    }
    $report{data} = $data;
    return \%report;
}

# If exactly one oligo of a group is missing and the parity oligo survived,
# XOR-ing the parity with everything that did survive gives back the missing
# one. $last is the number of the final data oligo; it is undef while the
# header (which says how long the file is) has not been found yet.
sub _repair_group {
    my ( $group, $data, $parity, $report, $last ) = @_;
    return unless exists $parity->{$group};
    my $first = $group * GROUP;
    my $end   = $first + GROUP - 1;
    $end = $last if defined $last && $end > $last;
    my @members = ( $first .. $end );
    my @absent  = grep { !exists $data->{$_} } @members;
    if ( !defined $last ) {
        return if exists $data->{0};
        @absent = (0);    # assume the header is the only loss; checked below
    }
    return unless @absent == 1;

    my $rebuilt = $parity->{$group};
    $rebuilt = _xor( $rebuilt, $data->{$_} ) for grep { exists $data->{$_} } @members;
    if ( !defined $last ) {
        # Accept it only if it has the shape of a header. If a second oligo
        # of the group was also lost, the XOR is garbage and fails this test.
        my ( $version, $length ) = unpack 'C N', $rebuilt;
        return unless $version == VERSION && $length <= MAX_FILE && substr( $rebuilt, 9 ) eq "\0" x ( PAYLOAD - 9 );
    }
    $data->{ $absent[0] } = $rebuilt;
    push @{ $report->{recovered} }, $absent[0];
    return;
}

# Simulates storage and sequencing. A real tube holds many copies of every
# strand, and a sequencer reads a random sample of them, so each oligo is
# read $copies times. Each read is lost with probability $loss, and each
# base of a surviving read is misread with probability $error.
sub damage {
    my ( $oligos, $loss, $error, $copies, $random ) = @_;
    my @bases = qw(A C G T);
    my @out;
    for my $dna ( map { ($_) x $copies } @$oligos ) {
        next if $random->() < $loss;
        my @letters = split //, $dna;
        for my $letter (@letters) {
            $letter = $bases[ int( $random->() * 4 ) ] if $random->() < $error;
        }
        push @out, join '', @letters;
    }
    # Strands in a tube have no order: shuffle them.
    for ( my $i = $#out ; $i > 0 ; $i-- ) {
        my $j = int( $random->() * ( $i + 1 ) );
        @out[ $i, $j ] = @out[ $j, $i ];
    }
    return @out;
}

sub write_fasta {
    my (@oligos) = @_;
    my $number = 0;
    return join '', map { sprintf( ">oligo_%05d\n%s\n", ++$number, $_ ) } @oligos;
}

# Reads sequences from FASTA text. Dies with a safe message on anything odd.
sub read_fasta {
    my ($text) = @_;
    die "FASTA input is larger than @{[MAX_FASTA]} bytes\n" if length $text > MAX_FASTA;
    my ( @oligos, $current );
    my $line_number = 0;
    for my $line ( split /\r?\n/, $text ) {
        $line_number++;
        die "line $line_number: line is longer than @{[MAX_LINE]} characters\n" if length $line > MAX_LINE;
        next if $line =~ /^\s*$/;
        if ( $line =~ /^>/ ) {
            push @oligos, $current if defined $current;
            $current = '';
            next;
        }
        die "line $line_number: sequence data before the first '>' header\n" unless defined $current;
        ( my $bases = uc $line ) =~ s/\s+//g;
        # N is what a sequencer writes for a base it could not read.
        die "line $line_number: only the letters A, C, G, T and N are allowed in a sequence\n" if $bases =~ /[^ACGTN]/;
        $current .= $bases;
        die "line $line_number: a sequence is longer than @{[MAX_LINE]} bases\n" if length $current > MAX_LINE;
    }
    push @oligos, $current if defined $current;
    return @oligos;
}

sub stats {
    my (@oligos) = @_;
    my $all = join '', @oligos;
    my ( $low, $high ) = ( 1, 0 );
    for my $dna (@oligos) {
        my $gc = gc_fraction($dna);
        $low  = $gc if $gc < $low;
        $high = $gc if $gc > $high;
    }
    return {
        oligos      => scalar @oligos,
        bases       => length $all,
        gc          => gc_fraction($all),
        gc_low      => @oligos ? $low : 0,
        gc_high     => $high,
        longest_run => longest_run( join 'x', @oligos ),
    };
}

1;
