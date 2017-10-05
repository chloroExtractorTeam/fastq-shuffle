#!/usr/bin/env perl

use Test::More;

eval "use Test::Script::Run";
plan skip_all => "Test::Script::Run required for testing pod coverage" if $@;

plan tests => 2;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl");

is(Test::Script::Run::last_script_exit_code(), 1, 'Running without file arguments should exit with error code 1');
like($stderr, qr/required parameter are --reads and --mates/m, 'Running without argument prints a help message');
