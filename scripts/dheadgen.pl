#!/usr/bin/perl -w

#
# Copyright 2007 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer. 
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in  
#      the documentation and/or other materials provided with the       
#      distribution.
#    * Neither the name of the above-listed copyright holders nor the names
#      of its contributors may be used to endorse or promote products derived
#      from this software without specific prior written permission.  
#       
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED  
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,     
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR      
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING    
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS      
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# ident	"@(#)dheadgen.pl	1.4	07/06/24 SMI"

#
# DTrace Header Generator
# -----------------------
#
# This script is meant to mimic the output of dtrace(1M) with the -h
# (headergen) flag on system that lack native support for DTrace. This script
# is intended to be integrated into projects that use DTrace's static tracing
# facilities (USDT), and invoked as part of the build process to have a
# common build process on all target systems. To facilitate this, this script
# is licensed under a BSD license. On system with native DTrace support, the
# dtrace(1M) command will be invoked to create the full header file; on other
# systems, this script will generated a stub header file.
#
# Normally, generated macros take the form PROVIDER_PROBENAME().  It may be
# desirable to customize the output of this script and of dtrace(1M) to
# tailor the precise macro name. To do this, edit the emit_dtrace() subroutine
# to pattern match for the lines you want to customize.
#

use strict;

my @lines;
my @tokens = ();
my $lineno = 0;
my $newline = 1;
my $eof = 0;
my $infile;
my $outfile;
my $force = 0;

sub emit_dtrace {
	my ($line) = @_;

	#
	# Insert customization here. For example, if you want to change the
	# name of the macros you may do something like this:
	#
	# $line =~ s/(\s)[A-Z]+_/\1TRACE_MOZILLA_/;
	#

	print $line;
}

#
# The remaining code deals with parsing D provider definitions and emitting
# the stub header file. There should be no need to edit this absent a bug.
#

#
# Emit the two relevant macros for each probe in the given provider:
#    PROVIDER_PROBENAME(<args>)
#    PROVIDER_PROBENAME_ENABLED() (0)
#
sub emit_provider {
	my ($provname, @probes) = @_;

	$provname = uc($provname);

	foreach my $probe (@probes) {
		my $probename = uc($$probe{'name'});
		my $argc = $$probe{'argc'};
		my $line;

		$probename =~ s/__/_/g;

		$line = "#define\t${provname}_${probename}(";
		for (my $i = 0; $i < $argc; $i++) {
			$line .= ($i == 0 ? '' : ', ');
			$line .= "arg$i";
		}
		$line .= ")\n";
		emit_dtrace($line);
		
		$line = "#define\t${provname}_${probename}_ENABLED() (0)\n";
		emit_dtrace($line);
	}

	emit_dtrace("\n");
}

sub emit_prologue {
	my ($filename) = @_;

	$filename =~ s/.*\///g;
	$filename = uc($filename);
	$filename =~ s/\./_/g;

	emit_dtrace <<"EOF";
/*
 * Generated by dheadgen(1).
 */

#ifndef\t_${filename}
#define\t_${filename}

#ifdef\t__cplusplus
extern "C" {
#endif

EOF
}

sub emit_epilogue {
	my ($filename) = @_;

	$filename =~ s/.*\///g;
	$filename = uc($filename);
	$filename =~ s/\./_/g;

	emit_dtrace <<"EOF";
#ifdef  __cplusplus
}
#endif

#endif  /* _$filename */
EOF
}

#
# Get the next token from the file keeping track of the line number.
#
sub get_token {
	my ($eof_ok) = @_;
	my $tok;

	while (1) {
		while (scalar(@tokens) == 0) {
			if (scalar(@lines) == 0) {
				$eof = 1;
				return if ($eof_ok);
				die "expected more data at line $lineno";
			}

			$lineno++;
			push(@tokens, split(/(\s+|\n|[(){},#;]|\/\*|\*\/)/,
			    shift(@lines)));
		}

		$tok = shift(@tokens);
		next if ($tok eq '');
		next if ($tok =~ /^[ \t]+$/);

		return ($tok);
	}
}

#
# Ignore newlines, comments and typedefs
#
sub next_token {
	my ($eof_ok) = @_;
	my $tok;

	while (1) {
		$tok = get_token($eof_ok);
		return if ($eof_ok && $eof);
		if ($tok eq "typedef" or $tok =~ /^#/) {
		  while (1) {
		    $tok = get_token(0);
		    last if ($tok eq "\n");
		  }
		  next;
		} elsif ($tok eq '/*') {
			while (get_token(0) ne '*/') {
				next;
			}
			next;
		} elsif ($tok eq "\n") {
			next;
		}

		last;
	}

	return ($tok);
}

sub expect_token {
	my ($t) = @_;
	my $tok;

	while (($tok = next_token(0)) eq "\n") {
		next;
	}

	die "expected '$t' at line $lineno rather than '$tok'" if ($t ne $tok);
}

sub get_args {
	expect_token('(');

	my $tok = next_token(0);
	my @args = ();

	return (@args) if ($tok eq ')');

	if ($tok eq 'void') {
		expect_token(')');
		return (@args);
	}

	my $arg = $tok;

	while (1) {
		$tok = next_token(0);
		if ($tok eq ',' || $tok eq ')') {
			push(@args, $arg);
			$arg = '';
			last if ($tok eq ')');
		} else {
			$arg = "$arg $tok";
		}
	}

	return (@args);
}

sub usage {
	die "usage: $0 [-f] <filename.d>\n";
}

usage() if (scalar(@ARGV) < 1);
if ($ARGV[0] eq '-f') {
	usage() if (scalar(@ARGV < 2));
	$force = 1;
	shift;
}
$infile = $ARGV[0];
usage() if ($infile !~ /(.+)\.d$/);

#
# If the system has native support for DTrace, we'll use that binary instead.
#
if (-x '/usr/sbin/dtrace' && !$force) {
	open(my $dt, '-|', "/usr/sbin/dtrace -C -h -s $infile -o /dev/stdout")
	    or die "can't invoke dtrace(1M)";

	while (<$dt>) {
		emit_dtrace($_);
	}

	close($dt);

	exit(0);
}

emit_prologue($infile);

open(my $d, '<', $infile) or die "couldn't open $infile";
@lines = <$d>;
close($d);

while (1) {
	my $nl = 0;
	my $tok = next_token(1);
	last if $eof;

	if ($newline && $tok eq '#') {
		while (1) {
			$tok = get_token(0);

			last if ($tok eq "\n");
		}
		$nl = 1;
	} elsif ($tok eq "\n") {
		$nl = 1;
	} elsif ($tok eq 'provider') {
		my $provname = next_token(0);
		my @probes = ();
		expect_token('{');

		while (1) {
			$tok = next_token(0);
			if ($tok eq 'probe') {
				my $probename = next_token(0);
				my @args = get_args();

				next while (next_token(0) ne ';');

				push(@probes, {
				    'name' => $probename,
				    'argc' => scalar(@args)
				});

			} elsif ($tok eq '}') {
				expect_token(';');

				emit_provider($provname, @probes);

				last;
			}
		}

	} else {
		die "syntax error at line $lineno near '$tok'\n";
	}

	$newline = $nl;
}

emit_epilogue($infile);

exit(0);
