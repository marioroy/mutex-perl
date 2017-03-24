###############################################################################
## ----------------------------------------------------------------------------
## Utility functions for Mutex.
##
###############################################################################

package Mutex::Util;

use strict;
use warnings;

no warnings qw( threads recursion uninitialized );

our $VERSION = '1.000';

## no critic (BuiltinFunctions::ProhibitStringyEval)

use Socket qw( PF_UNIX PF_UNSPEC SOCK_STREAM SOL_SOCKET SO_SNDBUF SO_RCVBUF );
use Time::HiRes qw( sleep time );

my ($is_MSWin32, $is_winenv, $zero_bytes);

BEGIN {
    $is_MSWin32 = ( $^O eq 'MSWin32' ) ? 1 : 0;
    $is_winenv  = ( $^O =~ /mswin|mingw|msys|cygwin/i ) ? 1 : 0;
    $zero_bytes = "\x00\x00\x00\x00";
}

###############################################################################
## ----------------------------------------------------------------------------
## Public functions.
##
###############################################################################

sub destroy_pipes {

    my ($obj, @params) = @_;

    local ($!,$?); local $SIG{__DIE__};

    for my $p (@params) {
        next unless (defined $obj->{$p});

        if (ref $obj->{$p} eq 'ARRAY') {
            for my $i (0 .. @{ $obj->{$p} } - 1) {
                next unless (defined $obj->{$p}[$i]);
                close $obj->{$p}[$i];
                undef $obj->{$p}[$i];
            }
        }
        else {
            close $obj->{$p};
            undef $obj->{$p};
        }
    }

    return;
}

sub destroy_socks {

    my ($obj, @params) = @_;

    local ($!,$?,$@); local $SIG{__DIE__};

    for my $p (@params) {
        next unless (defined $obj->{$p});

        if (ref $obj->{$p} eq 'ARRAY') {
            for my $i (0 .. @{ $obj->{$p} } - 1) {
                next unless (defined $obj->{$p}[$i]);
                if (fileno $obj->{$p}[$i]) {
                    syswrite($obj->{$p}[$i], '0') if $is_winenv;
                    eval q{ CORE::shutdown($obj->{$p}[$i], 2) };
                }
                close $obj->{$p}[$i];
                undef $obj->{$p}[$i];
            }
        }
        else {
            if (fileno $obj->{$p}) {
                syswrite($obj->{$p}, '0') if $is_winenv;
                eval q{ CORE::shutdown($obj->{$p}, 2) };
            }
            close $obj->{$p};
            undef $obj->{$p};
        }
    }

    return;
}

sub pipe_pair {

    my ($obj, $r_sock, $w_sock, $i) = @_;

    local $!;

    if (defined $i) {
        pipe($obj->{$r_sock}[$i], $obj->{$w_sock}[$i])
            or die "pipe: $!\n";

        # IO::Handle->autoflush not available in older Perl.
        select(( select($obj->{$w_sock}[$i]), $| = 1 )[0]);
    }
    else {
        pipe($obj->{$r_sock}, $obj->{$w_sock})
            or die "pipe: $!\n";

        select(( select($obj->{$w_sock}), $| = 1 )[0]); # Ditto.
    }

    return;
}

sub sock_pair {

    my ($obj, $r_sock, $w_sock, $i) = @_;

    my $size = 16384; local $!;

    if (defined $i) {
        socketpair( $obj->{$r_sock}[$i], $obj->{$w_sock}[$i],
            PF_UNIX, SOCK_STREAM, PF_UNSPEC ) or die "socketpair: $!\n";

        if ($^O ne 'aix' && $^O ne 'linux') {
            setsockopt($obj->{$r_sock}[$i], SOL_SOCKET, SO_SNDBUF, int $size);
            setsockopt($obj->{$r_sock}[$i], SOL_SOCKET, SO_RCVBUF, int $size);
            setsockopt($obj->{$w_sock}[$i], SOL_SOCKET, SO_SNDBUF, int $size);
            setsockopt($obj->{$w_sock}[$i], SOL_SOCKET, SO_RCVBUF, int $size);
        }

        # IO::Handle->autoflush not available in older Perl.
        select(( select($obj->{$w_sock}[$i]), $| = 1 )[0]);
        select(( select($obj->{$r_sock}[$i]), $| = 1 )[0]);
    }
    else {
        socketpair( $obj->{$r_sock}, $obj->{$w_sock},
            PF_UNIX, SOCK_STREAM, PF_UNSPEC ) or die "socketpair: $!\n";

        if ($^O ne 'aix' && $^O ne 'linux') {
            setsockopt($obj->{$r_sock}, SOL_SOCKET, SO_SNDBUF, int $size);
            setsockopt($obj->{$r_sock}, SOL_SOCKET, SO_RCVBUF, int $size);
            setsockopt($obj->{$w_sock}, SOL_SOCKET, SO_SNDBUF, int $size);
            setsockopt($obj->{$w_sock}, SOL_SOCKET, SO_RCVBUF, int $size);
        }

        select(( select($obj->{$w_sock}), $| = 1 )[0]); # Ditto.
        select(( select($obj->{$r_sock}), $| = 1 )[0]);
    }

    return;
}

sub sock_ready {

    return 1 unless $is_MSWin32;

    my ($socket, $timeout) = @_;

    my $val_bytes = "\x00\x00\x00\x00";
    my $ptr_bytes = unpack( 'I', pack('P', $val_bytes) );
    my ($count, $start) = (1, time);

    $timeout += time if $timeout;

    while (1) {
        # MSWin32 FIONREAD
        ioctl($socket, 0x4004667f, $ptr_bytes);

        return '' if $val_bytes ne $zero_bytes;
        return  1 if $timeout && time > $timeout;

        if ($count) {
            # delay after a while to not consume a CPU core
            $count = 0 if ++$count % 50 == 0 && time - $start > 0.005;
            next;
        }

        sleep 0.030;
    }
}

1;

__END__

###############################################################################
## ----------------------------------------------------------------------------
## Module usage.
##
###############################################################################

=head1 NAME

Mutex::Util - Utility functions for Mutex

=head1 VERSION

This document describes Mutex::Util version 1.000

=head1 SYNOPSIS

   # Mutex::Util functions are beneficial inside a class.

   package Foo::Bar;

   use strict;
   use warnings;

   our $VERSION = '0.001';

   use Mutex::Util;

   my $has_threads = $INC{'threads.pm'} ? 1 : 0;
   my $tid = $has_threads ? threads->tid() : 0;

   sub CLONE {
       $tid = threads->tid() if $has_threads;
   }

   sub new {
       my ($class, %obj) = @_;
       $obj{_init} = $has_threads ? $$ .'.'. $tid : $$;

       ($^O eq 'MSWin32')
           ? Mutex::Util::pipe_pair(\%obj, qw(_r_sock _w_sock))
           : Mutex::Util::sock_pair(\%obj, qw(_r_sock _w_sock));

       ...

       return bless \%obj, $class;
   }

   sub DESTROY {
       my ($pid, $obj) = ($has_threads ? $$ .'.'. $tid : $$, @_);

       if ($obj->{_init} eq $pid) {
           ($^O eq 'MSWin32')
               ? Mutex::Util::destroy_pipes($obj, qw(_w_sock _r_sock))
               : Mutex::Util::destroy_socks($obj, qw(_w_sock _r_sock));
       }

       return;
   }

   1;

=head1 DESCRIPTION

Useful functions for managing pipe and socket handles stored in a hashref.

=head1 API DOCUMENTATION

=head2 destroy_pipes ( hashref, list )

Destroy pipes in the hash for given key names.

   Mutex::Util::destroy_pipes($hashref, qw(_w_sock _r_sock));

=head2 destroy_socks ( hashref, list )

Destroy sockets in the hash for given key names.

   Mutex::Util::destroy_socks($hashref, qw(_w_sock _r_sock));

=head2 pipe_pair ( hashref, r_name, w_name [, idx ] )

Creates a pair of connected pipes and stores the handles into the hash
with given key names representing the two read-write handles. Optionally,
pipes may be constructed into an array stored inside the hash.

   Mutex::Util::pipe_pair($hashref, qw(_r_sock _w_sock));

   $hashref->{_r_sock};
   $hashref->{_w_sock};

   Mutex::Util::pipe_pair($hashref, qw(_r_sock _w_sock), $_) for 0..3;

   $hashref->{_r_sock}[0];
   $hashref->{_w_sock}[0];

=head2 sock_pair ( hashref, r_name, w_name [, idx ] )

Creates an unnamed pair of sockets and stores the handles into the hash
with given key names representing the two read-write handles. Optionally,
sockets may be constructed into an array stored inside the hash.

   Mutex::Util::sock_pair($hashref, qw(_r_sock _w_sock));

   $hashref->{_r_sock};
   $hashref->{_w_sock};

   Mutex::Util::sock_pair($hashref, qw(_r_sock _w_sock), $_) for 0..3;

   $hashref->{_r_sock}[0];
   $hashref->{_w_sock}[0];

=head2 sock_ready ( socket, [ timeout ] )

This method applies to the Windows platform only. It blocks until the
socket contains data. A false value is returned if the timeout is
reached, and a true value otherwise.

The windows platform sometimes needs this extra step prior to reading
subsequently. Otherwise an empty socket may stall while other threads
are spawning threads or threads exiting.

   ## Notify the manager process (barrier-sync begin).
   print {$CMD_W_SOCK} "sync_beg\n";

   ## Wait until all participating workers have synced.
   Mutex::Util::sock_ready($BSB_R_SOCK) if $is_MSWin32;  # important
   sysread $BSB_R_SOCK, $buf, 1;

   ## Notify the manager process (barrier-sync end).
   print {$CMD_W_SOCK} "sync_end\n";

   ## Wait until all participating workers have un-synced.
   sysread $BSE_R_SOCK, $buf, 1;

=head1 AUTHOR

Mario E. Roy, S<E<lt>marioeroy AT gmail DOT comE<gt>>

=cut

