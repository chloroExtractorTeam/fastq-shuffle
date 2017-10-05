#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

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

=head1 OPTIONS

=over 4

=item -1/--reads and -2/--mates

Input file(s) for first and seconde read. Might be used several times
or multiple files seperated by comma are provided. WARNING: The order
of files for first and second read has to match, but will be displayed
for a check.

=item -t/--num-temp-files [0/auto]

Number of temporary files, the input is split in. The split files are
loaded into memory entirely for shuffling. A value of 0 or auto calulates the number of temporary files based on the shuffle block size

=item -s/--shuffle-block-size [1G]

The size of a single shuffle block. The entire input will be split
into blocks of that size in bytes. Unit signs might be used for
mega-(m/M), kilo-(k/K), or giga-(g/G) byte. The default value is 1
gigabyte.

=item -d/--temp-directory

The temporary files are created inside the given folder. One might use
that option to put the temporary files onto fast disks, eg. SSDs or
into a RAM disk.

=back

=cut

use version 0.77; our $VERSION = version->declare("v0.1.0");

my %option = (
    'num-temp-files'     => 'auto',
    'temp-directory'     => undef,
    'shuffle-block-size' => '1G',
    'reads'              => [],
    'mates'              => [],
    );

GetOptions(
    \%option, qw(
          reads|2=s@
          mates|1=s@
          num-temp-files|t=s
          shuffle-block-size|s=s
          version|V
          verbose|v+
          debug|D
          help|h
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
}

if (exists $option{debug})
{
    Log::Log4perl->easy_init($DEBUG);
}

# check input files
@{$option{reads}} = split(",", join(",", @{$option{reads}}));
@{$option{mates}} = split(",", join(",", @{$option{mates}}));

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


