#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use POSIX;
use File::Temp;
use File::Basename;
use File::Spec;

my $random_state;

my @temp_files = ();

my %buffer = (
    input    => "",       # unshuffled input
    index    => []        # index for input
    );

=head1 fastq-shuffle.pl

A small program to shuffle huge fastq files using external memory
according to Sanders (1998) "Random Permutations on Distributed,
External and Hierarchical Memory".

=head1 SYNOPSIS

    fastq-shuffle.pl -1 reads.fq -2 mates.fq

    # multiple input files
    fastq-shuffle.pl -1 reads1.fq,reads2.fq -2 mates1.fq,mates2.fq

    # alternative form of multiple input files
    fastq-shuffle.pl -1 reads1.fq -2 mates1.fq -1 reads2.fq -2 mates2.fq

=head1 OUTPUT

The shuffled output files are returned with the same name as the input
files with the additional suffix C<.shuffled>. Therefore, the file
C<read.fq> would be returned as C<read.fq.shuffled>. All output files
are stored in the same folder as the input files unless a specific
output directory is specified using C<--outdir> option.

=head1 OPTIONS

=over 4

=item -1/--reads and -2/--mates

Input file(s) for first and seconde read. Might be used several times
or multiple files seperated by comma are provided. WARNING: The order
of files for first and second read has to match, but will be displayed
for a check.

=item -t/--num-temp-files [0/auto]

Number of temporary files, the input is split in. The split files are
loaded into memory entirely for shuffling. A value of 0 or auto
calulates the number of temporary files based on the shuffle block
size

=item -s/--shuffle-block-size [1G]

The size of a single shuffle block. The entire input will be split
into blocks of that size in bytes. Unit signs might be used for
mega-(m/M), kilo-(k/K), or giga-(g/G) byte. The default value is 1
gigabyte.

=item -d/--temp-directory

The temporary files are created inside the given folder. One might use
that option to put the temporary files onto fast disks, eg. SSDs or
into a RAM disk.

=item -r/--seed/--randomseed [ current unixtime stamp ]

The seed for the random generator. Strings can be used as seed due to
the basis is a cryptographic hash algorithm (SHA-256). Used to provide
reproducebility. In case the same input files (in same order) and the
same random seed is provided, the shuffle results are identical.

=item -o/--outdir

Specifies the output directory for the shuffled files. The shuffled
file names will be extended by the suffix C<.shuffled> and stored into
the specified directory. If no output directory is provided, the files
will be stored into the folder of the input files.

=back

=head1 CHANGELOG

=over 4

=item v0.9.0

First version is able to shuffle fastq files

=item v0.9.1

Fixed an issue with the temporary file parameter.

=item v0.9.2

First release candidate.

Adds a changelog and licence information to the README.md and to the
program documentaton.

=back

=head1 LICENCE

MIT License

Copyright (c) 2017 chloroExtractorTeam

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

use version 0.77; our $VERSION = version->declare("v0.9.2");

my %option = (
    'num-temp-files'     => 'auto',
    'temp-directory'     => undef,
    'shuffle-block-size' => '1G',
    'reads'              => [],
    'mates'              => [],
    'seed'               => time(),
    'outdir'             => undef
    );

GetOptions(
    \%option, qw(
          reads|1=s@
          mates|2=s@
          num-temp-files|t=s
          shuffle-block-size|s=s
          temp-directory|d=s
          version|V
          verbose|v+
          debug|D
          help|h
          seed|randomseed|r=s
          outdir|o=s
     ) ) or pod2usage(1);


# help requested?
if (exists $option{help} && $option{help})
{
    pod2usage(1);
}

# version requested?
if (exists $option{version} && $option{version}) {
    print "$VERSION\n";
    exit 0;
}

use Log::Log4perl qw(:easy :no_extra_logdie_message);
Log::Log4perl->easy_init($WARN);
my $logger = get_logger();
if (exists $option{verbose})
{
    $logger->more_logging($option{verbose});
    ALWAYS "Verbosity level increased by ".$option{verbose};
}

if (exists $option{debug})
{
    Log::Log4perl->easy_init($DEBUG);
    ALWAYS "Verbosity level set to DEBUG";
}

# check input files
@{$option{reads}} = split(",", join(",", @{$option{reads}}));
@{$option{mates}} = split(",", join(",", @{$option{mates}}));

# is the file list empty?
if (@{$option{reads}}==0 && @{$option{mates}}==0)
{
    $logger->logdie("ERROR: required parameter are --reads and --mates, please provide at least on pair of input files");
}

# same number of files?
unless (@{$option{reads}} == @{$option{mates}})
{
    $logger->logdie(sprintf("ERROR Number of first and second read files are different (%d vs. %d), but need to be the same!", 0+@{$option{reads}}, 0+@{$option{mates}}));
}

# do all files exist?
my @missing_files = grep { ! -e $_ } (@{$option{reads}}, @{$option{mates}});
if (@missing_files)
{
    $logger->logdie("ERROR The following files can not be accessed: ", join(", ", map {"'$_'"} @missing_files));
}

# estimate file size
my $filesize = estimate_filesize($option{reads}, $option{mates});
ALWAYS "Maximum filesize was estimated to be ".formatfilesize($filesize);

# calculate the buffer size and number of temporary files
$option{'shuffle-block-size'} = parse_size_spec($option{'shuffle-block-size'}) || $logger->logdie("Unable to parse the shuffle-block-size");

# if the number of temporary files was specified, then it will overwrite the value of shuffle-block-size
$option{'num-temp-files'} =~ s/^\s+|\s+$//g;
if (uc($option{'num-temp-files'}) ne "AUTO")
{
    if ($option{'num-temp-files'} =~ /^\d+$/ && $option{'num-temp-files'} > 0)
    {
	$option{'shuffle-block-size'} = ceil($filesize/$option{'num-temp-files'});
    } else {
	$logger->error("Seems that you specify 0 as number of temporary files, therefore the value 'auto' is assumed");
	$option{'num-temp-files'}="AUTO";
    }
}

if (uc($option{'num-temp-files'}) eq "AUTO")
{
    $option{'num-temp-files'} = ceil($filesize/$option{'shuffle-block-size'});
}

# if buffer size is larger than file size we can shuffle in memory
if ($option{'shuffle-block-size'} >= $filesize)
{
    $option{'num-temp-files'} = 0;
    ALWAYS "Buffer size is larger than size of input file, therefore in memory shuffle will be used and no temporary files will be generated";
} else {
    ALWAYS sprintf("Size of buffer for shuffle will be %d %s and %d temporary files will be used", formatfilesize($option{'shuffle-block-size'}), $option{'num-temp-files'});

    # check if a temp-directory was specified and create a temporary folder inside that directory
    my $tempdir;
    if (defined $option{'temp-directory'})
    {
	unless (-d $option{'temp-directory'})
	{
	    $logger->logdie("Specified temporary directory ('".$option{'temp-directory'}."') does not exist. Please specify an existing directory!");
	}

	$tempdir = File::Temp::tempdir( DIR => $option{'temp-directory'}, CLEANUP => 1) || $logger->logdie("Unable to create temporary directory: $!");
    } else {

	$tempdir = File::Temp::tempdir( TMPDIR => 1, CLEANUP => 1) || $logger->logdie("Unable to create temporary directory: $!");
    }

    # generate the list of temporary files
    if ($option{'num-temp-files'} > 1)
    {
	foreach (2..$option{'num-temp-files'})
	{
	    push(@temp_files, { filename => File::Temp::tempnam($tempdir, "shuffleXXXXXX") });
	}
    }
}

# initialize the random number generator
ALWAYS "Random generator was initialized with the value '".::srand($option{seed})."'";

# Processing file pairs
for(my $i=0; $i<@{$option{reads}}; $i++)
{
    ALWAYS "Starting processing of file pair ".join(" --- ", ($option{reads}[$i], $option{mates}[$i]));

    $logger->debug("Opening temporary files, if required");
    foreach my $tmpfile (@temp_files)
    {
	$tmpfile->{indexfilename}=$tmpfile->{filename}.".idx";

	open(my $fh_tempfile, ">", $tmpfile->{filename}) || $logger->logdie("$!");
	open(my $fh_indexfile, ">", $tmpfile->{indexfilename}) || $logger->logdie("$!");

	$tmpfile->{file} = $fh_tempfile;
	$tmpfile->{idx} = $fh_indexfile;
    }

    my ($reads_out, $mates_out) = create_output_filenames($option{reads}[$i], $option{mates}[$i], $option{outdir});

    my ($first_infile, $second_infile);

    open($first_infile, "<", $option{reads}[$i]) || $logger->logdie($!);
    open($second_infile, "<", $option{mates}[$i]) || $logger->logdie($!);

    my $num_blocks = 0;

    while (! (eof($first_infile) || eof($second_infile)))
    {
	# read one fastq dataset per input file
	my $first_block = join("", (scalar <$first_infile>, scalar <$first_infile>, scalar <$first_infile>, scalar <$first_infile>));
	my $second_block = join("", (scalar <$second_infile>, scalar <$second_infile>, scalar <$second_infile>, scalar <$second_infile>));

	$num_blocks++;

	# get the temporary file for the block if
	my $which_tempfile=0;
	if (@temp_files)
	{
	    $which_tempfile = int(::rand(@temp_files+1));
	}

	if ($which_tempfile == 0)
	{
	    # store current position in buffer
	    my $offset = length($buffer{input});
	    push(@{$buffer{index}}, { offset => $offset, lenA => length($first_block), lenB => length($second_block) });
	    $buffer{input} .= $first_block . $second_block;
	} else {
	    write_to_temp_file(\$first_block, \$second_block, $temp_files[$which_tempfile-1]);
	}
    }

    close($first_infile) || $logger->logdie($!);
    close($second_infile) || $logger->logdie($!);

    # close the temporary files if required
    if (@temp_files)
    {
	foreach my $temp_file (@temp_files)
	{
	    foreach my $fh (map {$temp_file->{$_}} qw(file idx))
	    {
		close($fh) || $logger->logdie("$!");
	    }
	}
    }

    ALWAYS "Import of $num_blocks sequence blocks finished. Starting shuffling...";

    for (my $i=-1; $i<@temp_files; $i++)
    {
	# reinitialize the random number generator to
	my $reseed = ::srand($option{seed}."$i");
	$logger->debug("Reseeded random number generator with '$reseed'");

	if ($i != -1)
	{
	    read_from_temp_file($temp_files[$i]{filename}, $temp_files[$i]{indexfilename}, \%buffer);
	}

	shuffle_memory_and_write_files(\%buffer, $reads_out, $mates_out);
    }

}

# estimates the filesize of a paired end set
sub estimate_filesize
{
    my ($filelist_reads, $filelist_mates) = @_;

    my $filesize = 0;

    for (my $i=0; $i<@{$filelist_reads}; $i++)
    {
	my $new_filesize = -s $filelist_reads->[$i];
	$new_filesize += -s $filelist_mates->[$i];

	if ($new_filesize > $filesize)
	{
	    $filesize = $new_filesize;
	}
    }

    return $filesize;
}

# Random generator is based on the implementation at
# http://wellington.pm.org/archive/200704/randomness/#slide19
# (paragraph Cryptographic random number generators)
use Digest;

sub srand{
    my $seed = shift || (time());
    $random_state = {
        digest => new Digest ("SHA-256"),
        counter => 0,
        waiting => [],
        prev    => $seed
    };

    return $seed;
}

sub rand{
    my $range = shift || 1.0;
    ::srand() unless defined $random_state;

    if (! @{$random_state->{waiting}}){
        $random_state->{digest}->reset();
        $random_state->{digest}->add($random_state->{counter} ++ .
                                     $random_state->{prev});
        $random_state->{prev} = $random_state->{digest}->digest();
        my @ints = unpack("Q*", $random_state->{prev}); # 64 bit unsigned integers
        $random_state->{waiting} = \@ints;
    }
    my $int = shift @{$random_state->{waiting}};
    return $range * $int / 2**64;
}

sub formatfilesize {
    my ($size, $si, $base) = @_;

    my $units = [qw(B KB MB GB TB PB)];

    unless (defined $base)
    {
	$base = 1024;
    }

    if ($base == 1024 || $base == 2)
    {
	$base = 1024;
    } elsif ($base == 1000 || $base == 10)
    {
	$base = 1000;
    } else {
	die "Base has to be 2 or 10 or 1024/1000\n";
    }

    if($base == 1024 && $si)
    {
	$units = [qw(B KiB MiB GiB TiB PiB)];
    }

    my $exp = 0;

    for (@$units) {
        last if $size < $base;
        $size /= $base;
        $exp++;
    }
    return wantarray ? ($size, $units->[$exp]) : sprintf("%.2f %s", $size, $units->[$exp]);
}

# returns a number of bytes based on a formated string like 1.6 GB
# containing a (float) number and a unit string allowed units are
# B(Byte), kB/kiB (kilobyte), MB/MiB (Megabyte), GB/GiB (Gigabyte),
# PB/PiB (Petabyte) unit is case insensitive
sub parse_size_spec
{
    my ($input, $base) = @_;

    if (! defined $base)
    {
	$base = 1024;
    }

    my $uc_input = uc($input);
    unless ($uc_input =~ /^\s*([0-9.]+)\s*([KMGP]*)I?B?\s*$/)
    {
	$logger->error("Unable to parse number '$input'");
	return undef;
    }

    my $number = $1;
    my $unit = $2;

    # check if number contains only on "."
    unless ($number =~ /^[0-9]*\.*[0-9]+$|^[0-9]+$/)
    {
	$logger->error("Unable to parse number '$number'");
	return undef;
    }
    $number = $number+0;

    my $factor = 1;
    if ($unit eq "")
    {
	$factor = 1;
    }
    elsif ($unit eq "K")
    {
	$factor = $base;
    }
    elsif ($unit eq "M")
    {
	$factor = $base * $base;
    }
    elsif ($unit eq "G")
    {
	$factor = $base * $base * $base;
    }
    elsif ($unit eq "P")
    {
	$factor = $base * $base * $base * $base;
    }

    return sprintf("%.0f", $number * $factor);
}

sub create_output_filenames
{
    my ($file1, $file2, $outdir) = @_;

    # generate new filenames
    my ($file1_fn, $file1_dir) = fileparse($file1);
    my ($file2_fn, $file2_dir) = fileparse($file2);

    # write output to shuffled files
    if (defined $outdir)
    {
	$file1_dir = $outdir;
	$file2_dir = $outdir;
    }

    my $outfile1 = File::Spec->catfile($file1_dir, $file1_fn.".shuffled");
    my $outfile2 = File::Spec->catfile($file2_dir, $file2_fn.".shuffled");

    # check if the files exist
    my @existing_files = grep {-e $_} ($outfile1, $outfile2);

    if(@existing_files)
    {
	$logger->logdie(sprintf("Outputfile(s) (%s) exist! Please delete and restart or specify another output directory", join(", ", map { "'$_'" } (@existing_files))));
    }

    return ($outfile1, $outfile2);
}

sub shuffle_memory_and_write_files
{
    my ($ref_buffer, $file1, $file2) = @_;

    # shuffle in memory
    for(my $i = @{$ref_buffer->{index}}-1; $i >= 1; $i--)
    {
	my $j = ::rand($i);

	($ref_buffer->{index}[$i], $ref_buffer->{index}[$j]) = ($ref_buffer->{index}[$j], $ref_buffer->{index}[$i]);
    }

    open(my $f1, ">>", $file1) || $logger->logdie($!);
    open(my $f2, ">>", $file2) || $logger->logdie($!);

    foreach my $next_item (@{$ref_buffer->{index}})
    {
	print $f1 substr($ref_buffer->{input}, $next_item->{offset}, $next_item->{lenA});
	print $f2 substr($ref_buffer->{input}, $next_item->{offset}+$next_item->{lenA}, $next_item->{lenB});
    }

    close($f1) || $logger->logdie($!);
    close($f2) || $logger->logdie($!);
}


sub read_from_temp_file
{
    my ($file, $index, $buffer) = @_;

    $buffer->{input} = "";
    $buffer->{index} = [];

    open(FH, "<", $file) || $logger->logdie($!);
    {
	local $/;
	$buffer->{input} = <FH>;
    }
    close(FH) || $logger->logdie($!);

    open(FH, "<", $index) || $logger->logdie($!);
    {
	local $/;
	my @dat = unpack("(QLL)*", scalar <FH>);

	for(my $i=0; $i<@dat; $i+=3)
	{
	    push(@{$buffer->{index}}, { offset => $dat[$i], lenA => $dat[$i+1], lenB => $dat[$i+2] });
	}
    }
    close(FH) || $logger->logdie($!);
}

sub write_to_temp_file
{
    my ($blockA, $blockB, $temp_file) = @_;

    my $fh = $temp_file->{file};
    my $idx = $temp_file->{idx};

    my $offset = tell($fh);
    my $index_entry = pack("QLL", $offset, length($$blockA), length($$blockB));
    print $idx $index_entry;
    print $fh $$blockA, $$blockB;
}
