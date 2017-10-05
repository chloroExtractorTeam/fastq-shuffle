#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 4;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-h" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with -h should exit with error code 1');
like($stdout, qr/^Usage.+^Options:/ms, 'Running with -h prints the help message');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "--help" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with --help should exit with error code 1');
like($stdout, qr/^Usage.+^Options:/ms, 'Running with --help prints the help message');
