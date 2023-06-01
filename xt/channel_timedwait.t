#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Time::HiRes 'time';
use Mutex;

my $mutex = Mutex->new( impl => 'Channel' );

is($mutex->impl(), 'Channel', 'implementation name');

sub task {
    $mutex->lock_exclusive;
    sleep(1) for 1..5;
    $mutex->unlock;
}
sub spawn {
    my $pid = fork;
    task(), exit() if $pid == 0;
    return $pid;
}

my $pid   = spawn(); sleep 1;
my $start = time; my $ret = $mutex->timedwait(2);
my $end   = time;

waitpid($pid, 0);

my $success = ($end - $start < 3) ? 1 : 0;
is($success, 1, 'mutex timedwait');
is($ret, '', 'mutex timedwait value');

done_testing;

