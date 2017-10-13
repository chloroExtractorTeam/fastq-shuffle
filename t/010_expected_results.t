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

plan tests => 13;

my %files = (
    'at_simulated1.fq' => "87ca3af8458674083db501f50cf33770",
    'at_simulated2.fq' => "c2820f062704c7572e487368030b1ecd"
    );

my %expected = (
    'default1_shuffled.fq' => "b365ae2447760a96e034a9d98251712c",
    'default2_shuffled.fq' => "94bccc1231c8a23d76a475ea487a0cb4",
    'reduced1_shuffled.fq' => "5af21a720f33f9995153e7d61e334980",
    'reduced2_shuffled.fq' => "16ab8c8fe9e121665377e0bc8c6668ca",
    'filenum1_shuffled.fq' => "5af21a720f33f9995153e7d61e334980",
    'filenum2_shuffled.fq' => "16ab8c8fe9e121665377e0bc8c6668ca"
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

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", $filenames[0], "-2", $filenames[1], "-t", 6, "-r", 1234567890 ]);
is(Test::Script::Run::last_script_exit_code(), 0, 'Running with simulated data should exit with error code 0');
rename($tempdir.'/'."at_simulated1.fq.shuffled", $tempdir.'/'."filenum1_shuffled.fq");
rename($tempdir.'/'."at_simulated2.fq.shuffled", $tempdir.'/'."filenum2_shuffled.fq");

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", $filenames[0], "-2", $filenames[1], "-s", "50M", "-r", 1234567890 ]);
is(Test::Script::Run::last_script_exit_code(), 0, 'Running with simulated data should exit with error code 0');
rename($tempdir.'/'."at_simulated1.fq.shuffled", $tempdir.'/'."reduced1_shuffled.fq");
rename($tempdir.'/'."at_simulated2.fq.shuffled", $tempdir.'/'."reduced2_shuffled.fq");

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", $filenames[0], "-2", $filenames[1], "-r", 1234567890 ]);
is(Test::Script::Run::last_script_exit_code(), 0, 'Running with simulated data should exit with error code 0');
rename($tempdir.'/'."at_simulated1.fq.shuffled", $tempdir.'/'."default1_shuffled.fq");
rename($tempdir.'/'."at_simulated2.fq.shuffled", $tempdir.'/'."default2_shuffled.fq");

# check if the content is complete for the shuffled files
my %output_content = ();
foreach my $file (grep {/1\.fq/ || /1_shuffled\.fq/} (keys %expected, keys %files))
{
    my $md5 = Digest::MD5->new;
    my $filelocation = $tempdir.'/'.$file;
    open(my $fh, "<", $filelocation) || die "Unable to open file '$filelocation': $!\n";
    $md5->add(sort <$fh>);
    close($fh) || die "Unable to close file '$filelocation': $!\n";

    my $md5hex = $md5->hexdigest();
    $output_content{$md5hex}++;
}
is((keys %output_content)+0, 1, "All forward read files contain the same content");

%output_content = ();
foreach my $file (grep {/2\.fq/ || /2_shuffled\.fq/} (keys %expected, keys %files))
{
    my $md5 = Digest::MD5->new;
    my $filelocation = $tempdir.'/'.$file;
    open(my $fh, "<", $filelocation) || die "Unable to open file '$filelocation': $!\n";
    $md5->add(sort <$fh>);
    close($fh) || die "Unable to close file '$filelocation': $!\n";

    my $md5hex = $md5->hexdigest();
    $output_content{$md5hex}++;
}
is((keys %output_content)+0, 1, "All reverse read files contain the same content");

# check if the correct output was produced
foreach my $file (keys %expected)
{
    my $md5 = Digest::MD5->new;
    my $filelocation = $tempdir.'/'.$file;
    open(my $fh, "<", $filelocation) || die "Unable to open file '$filelocation': $!\n";
    $md5->addfile($fh);
    close($fh) || die "Unable to close file '$filelocation': $!\n";

    my $md5hex = $md5->hexdigest();
    is($md5hex, $expected{$file}, sprintf('Checksum of file %s is correct', $file));
}
