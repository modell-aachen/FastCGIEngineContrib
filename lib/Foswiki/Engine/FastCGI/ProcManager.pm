# FastCGI Runtime Engine Component of Foswiki - The Free and Open Source Wiki,
# http://foswiki.org/
#
# Copyright (C) 2008-2015 Gilmar Santos Jr, jgasjr@gmail.com and Foswiki
# contributors. Foswiki contributors are listed in the AUTHORS file in the root
# of Foswiki distribution.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

=begin TML

---+!! UNPUBLISHED package Foswiki::Engine::FastCGI::ProcManager

Wrapper around FastCGI::ProcManager to make FastCGI engine re-execute itself
automatically upon configuration change.

=cut

package Foswiki::Engine::FastCGI::ProcManager;

use strict;
use warnings;

use FCGI::ProcManager::Constrained;
use FCGI::ProcManager qw($SIG_CODEREF);
use Foswiki::Engine::FastCGI ();
use POSIX qw(:signal_h);
use Carp qw(confess);
our @ISA = qw( FCGI::ProcManager::Constrained );

sub new {
    my $proto = shift;

    my $init = shift || {};
    $init->{pm_title} ||= 'foswiki-fcgi-pm',
    $init->{die_timeout} = 100,
    $init->{max_requests} = $ENV{PM_MAX_REQUESTS} || 0 unless defined $init->{max_requests};
    $init->{sizecheck_num_requests} = $ENV{PM_SIZECHECK_NUM_REQUESTS} || 0 unless defined $init->{sizecheck_num_requests};
    $init->{max_size} = $ENV{PM_MAX_SIZE} || 0 unless defined $init->{max_size};
    unshift @_, $init;

    my $self = $proto->SUPER::new(@_);

    return $self;
}

sub pm_die {
    my ($this,$msg,$n) = @_;

    # stop handling signals.
    undef $SIG_CODEREF;
    $SIG{HUP}  = 'DEFAULT';
    $SIG{TERM} = 'DEFAULT';

    # prepare to die no matter what.
    if (defined $this->die_timeout()) {
        $SIG{ALRM} = sub {
            if (my @pids = keys %{$this->{PIDS}}) {
                $this->pm_notify("sending TERM to PIDs, @pids");
                kill "TERM", @pids;
            }
            $this->pm_remove_pid_file();
            $this->pm_abort("wait timeout");
        };
        alarm $this->die_timeout();
    }

    # send a TERM to each of the servers.
    if (my @pids = keys %{$this->{PIDS}}) {
        $this->pm_notify("sending HUP to PIDs, @pids");
        kill "HUP", @pids;
    }

    # wait for the servers to die.
    while (%{$this->{PIDS}}) {
        $this->pm_wait();
    }

    # die already.
    $this->pm_remove_pid_file();
    $this->pm_exit("dying: ".$msg,$n);
}

sub sig_manager {
    my ($this,$name) = @_;
    if ($name eq "TERM") {
        $this->pm_notify("received signal $name");
        $this->pm_die("safe exit from signal $name");
    } elsif ($name eq "HUP") {
        # send a TERM to each of the servers, and pretend like nothing happened..
        if (my @pids = keys %{$this->{PIDS}}) {
            $this->pm_notify("sending HUP to PIDs, @pids");
            kill "HUP", @pids;
        }
    } else {
        $this->pm_notify("ignoring signal $name");
    }
}

sub pm_notify {
    my ($this, $msg) = @_;

    return if $this->{quiet};
    $this->SUPER::pm_notify($msg);
}

1;
