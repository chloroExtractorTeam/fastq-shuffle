#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 4;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "--debug" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with --debug should exit with error code 1');
like($stderr, qr/Verbosity level set to DEBUG/, 'Running with --debug sets verbosity level to DEBUG');

( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl", [ "-D" ]);

is(Test::Script::Run::last_script_exit_code(), 1, 'Running with -D  should exit with error code 1');
like($stderr, qr/Verbosity level set to DEBUG/, 'Running with -D sets verbosity level to DEBUG');
