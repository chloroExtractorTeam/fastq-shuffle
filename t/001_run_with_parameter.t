#!/usr/bin/env perl

use Test::More tests => 2;
use Test::Script::Run;

my ( $ret, $stdout, $stderr ) = run_script("fastq-shuffle.pl");

is(Test::Script::Run::last_script_exit_code(), 1, 'Running without file arguments should exit with error code 1');
like($stderr, qr/required parameter are --reads and --mates/m, 'Running without argument prints a help message');
