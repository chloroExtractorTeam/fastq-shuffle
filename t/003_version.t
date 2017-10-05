#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 2;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "--version" ]);

is(Test::Script::Run::last_script_exit_code(), 0, 'Running with -version should exit with error code 0');
like($stdout, qr/^v\d+\.\d+\.\d+$/, 'Running with --version prints the version number');
