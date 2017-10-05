#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 4;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-v" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with only -v should exit with error code 1');
like($stderr, qr/Verbosity level increased by 1/, 'Running with single -v increases verbosity level by 1');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-v", "-v" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with only 2x -v should exit with error code 1');
like($stderr, qr/Verbosity level increased by 2/, 'Running with 2x -v increases verbosity level by 2');
