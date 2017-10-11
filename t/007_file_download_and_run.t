#!/usr/bin/env perl
use strict;
use warnings;

use File::Temp;
use LWP::Simple;
use Archive::Extract;
use Digest::MD5;

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing" if $@;

#plan tests => 8;

my %files = (
    'at_simulated1.fq' => "87ca3af8458674083db501f50cf33770",
    'at_simulated2.fq' => "c2820f062704c7572e487368030b1ecd"
    );

my $filelocation = 'https://github.com/chloroExtractorTeam/simulate/releases/download/v1.1reduced/v1.1reduced_result.tar.bz2';

# Download the testset to a temporary folder
my $tempdir = File::Temp::tempdir( CLEANUP => 1 );

my $downloadlocation = $tempdir."/v1.1reduced_result.tar.bz2";

my $code = getstore($filelocation, $downloadlocation);
my $ae = Archive::Extract->new( archive => $downloadlocation );

my $ok = $ae->extract( to => $tempdir ) || die $ae->error;

# check if the correct md5sums are downloadable
my $correct_checksums = 0;
foreach my $file (keys %files)
{
    my $md5 = Digest::MD5->new;
    my $filelocation = $tempdir.'/'.$file;
    open(my $fh, "<", $filelocation) || die "Unable to open file '$filelocation': $!\n";
    $md5->addfile($fh);
    close($fh) || die "Unable to close file '$filelocation': $!\n";

    my $md5hex = $md5->hexdigest();
    if ($md5hex eq $files{$file})
    {
	$correct_checksums++;
    }
    
    is($md5hex, $files{$file}, sprintf('Checksum of file %s is correct', $file));
}

# we can skip further testing, if the download is not correct
unless ($correct_checksums == int(keys %files))
{    
    diag("Since the download of the test set failed, no further tests are performed");
    done_testing;
    exit;
}

# where are the input reads
my @filenames = map { $tempdir.'/'.$_ } (sort keys %files);

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", $filenames[0], "-2", $filenames[1] ]);

is(Test::Script::Run::last_script_exit_code(), 0, 'Running with simulated data should exit with error code 0');
like($stderr, qr/Maximum filesize was estimated to be 267\.95 MB/, 'Maxmim filesize message present');
like($stderr, qr/Random generator was initialized with the value/, 'Random generator initialization message present');
like($stderr, qr/Starting processing of file pair \S+at_simulated1.fq --- \S+at_simulated2.fq/, 'Starting processing message present');
like($stderr, qr/Import of 431264 sequence blocks finished. Starting shuffling.../, 'Import successful message present and correct number imported');

done_testing;
