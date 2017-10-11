#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 8;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", "first.fq", "-2", "second.fq", "-1", "firstB.fq" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with 2x -1 and only 1x -2 should exit with error code 1');
like($stderr, qr/ERROR Number of first and second read files are different/, 'Returning correct error message');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "--reads", "first.fq", "--mates", "second.fq", "--reads", "firstB.fq" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with 2x --reads and only 1x --mates should exit with error code 1');
like($stderr, qr/ERROR Number of first and second read files are different/, 'Returning correct error message');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-1", "first.fq", "-2", "second.fq", "-2", "secondB.fq" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with only 1x -1 and 2x -2 should exit with error code 1');
like($stderr, qr/ERROR Number of first and second read files are different/, 'Returning correct error message');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "--reads", "first.fq", "--mates", "second.fq", "--mates", "secondB.fq" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with only 1x --reads and 2x --mates should exit with error code 1');
like($stderr, qr/ERROR Number of first and second read files are different/, 'Returning correct error message');
