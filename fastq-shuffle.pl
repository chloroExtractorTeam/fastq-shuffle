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

=head1 OPTIONS

=over 4

=item -1/--reads

Input file for first read.

=item -2/--mates

Input file for second read.

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

my %option = (
    'num-temp-files'     => 'auto',
    'temp-directory'     => undef,
    'shuffle-block-size' => '1G'
    );

GetOptions(
    \%option, qw(
          1|reads=s
          2|mates=s
          num-temp-files|t=s
          shuffle-block-size|s=s
          version|V
          verbose|v
          debug|D
          help|h
     ) ) or pod2usage(1);


# help
$option{help} && pod2usage(1);


