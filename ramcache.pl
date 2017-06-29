#!/usr/bin/perl -wT
# ramcache.pl - create ramdisks for Safari, Chrome, and Opera disk 
#               caches on OSX
# $Id: ramcache.pl 1314 2013-04-24 20:38:57Z ranga $
#
# For background information about this program, please see:
#
# http://hints.macworld.com/article.php?story=2011010204203424
#
# History
#
# v. 0.1.3 (06/28/2017) - Add Opera support
# v. 0.1.2 (04/24/2013) - Reduce default cache size to 16MB
# v. 0.1.1 (03/27/2011) - Fix unmount bug, secure permissions for
#                         cache directories
# v. 0.1.0 (03/26/2011) - Initial Release
#
# Copyright (c) 2011-2017 Sriranga R. Veeraraghavan <ranga@calalum.org>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 5.006_001;

use strict;
use Getopt::Std;

#
# main
#

# secure the environment

$ENV{'PATH'} = '/bin:/usr/bin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

# global variables

my $SAFARI_CACHE_SUFFIX = "com.apple.Safari";
my $CHROME_CACHE_SUFFIX = "Google/Chrome";
my $OPERA_CACHE_SUFFIX = "com.operasoftware.Opera";
my $DEF_LIB_DIR = "Library/Caches";
my $DEF_CACHE_SZ = 32768; 

my $RC = -1;
my $EC = 0;
my $VERBOSE = 0;
my $UNMOUNT = 0;
my $MOUNTED = 0;
my %OPTS = ();
my $DIR = "";
my $DEV = "";
my $HOME_DIR = "";
my $CACHE_DIR = "";
my %CACHE_DIRS = ('Safari' => "",
                  'Chrome' => "",
                  'Opera'  => "");
my $CACHE_SZ = 0;

# verify that the necessary commands exist and are executable

my $CMD = "";
my %CMDS = ('MOUNT'   => "/sbin/mount",
            'HDID'    => "/usr/bin/hdid",
            'HDIUTIL' => "/usr/bin/hdiutil",
            'NEWFS'   => "/sbin/newfs_hfs",
            'UMOUNT'  => "/sbin/umount");

foreach $CMD (keys(%CMDS)) {
    if (-x $CMDS{$CMD}) { next; }
    printError("Not executable: " . $CMDS{$CMD});
    $EC = 1;
}

if ($EC != 0) { exit($EC); }

#
# parse the command line options:
#   -d [dir]  - base cache directory (default $HOME/Library/Caches)
#   -s [size] - size for cache directories, in MB (default 16MB)
#   -u        - unmount cache directories
#   -v        - verbose (debug) mode
#   -h        - help (prints usage message)
#

getopts("d:s:vuh", \%OPTS);

# if help mode is requested, print the usage message and exit

if (defined $OPTS{'h'}) {
    printUsage();
    exit(0);
}

# enable verbose mode if -v specified

$VERBOSE = (defined($OPTS{'v'}) ? 1 : 0);

# enable unmount mode if -u specified

$UNMOUNT = (defined($OPTS{'u'}) ? 1 : 0);

#
# if a cache directory is specified, use it.  Otherwise use the default
# cache directory: $HOME/Library/Caches
#

$CACHE_DIR = $OPTS{'d'};
if (defined($CACHE_DIR) && $CACHE_DIR ne "") {
    $CACHE_DIRS{'Safari'} = $CACHE_DIR . "/" . $SAFARI_CACHE_SUFFIX;
    $CACHE_DIRS{'Chrome'} = $CACHE_DIR . "/" . $CHROME_CACHE_SUFFIX;
    $CACHE_DIRS{'Opera'} = $CACHE_DIR . "/" . $OPERA_CACHE_SUFFIX;
} else {
    $HOME_DIR = $ENV{'HOME'};
    if (defined($HOME_DIR) && $HOME_DIR ne "") {
        $CACHE_DIRS{'Safari'} =
            $HOME_DIR . "/" . $DEF_LIB_DIR . "/" . $SAFARI_CACHE_SUFFIX;
        $CACHE_DIRS{'Chrome'} =
            $HOME_DIR . "/" . $DEF_LIB_DIR . "/" . $CHROME_CACHE_SUFFIX;
        $CACHE_DIRS{'Opera'} =
            $HOME_DIR . "/" . $DEF_LIB_DIR . "/" . $OPERA_CACHE_SUFFIX;            
    } else {
        printError("Cannot determine cache directories");
        printUsage();
        exit(1);
    }
}

#
# if a cache size is specified, use it.  Otherwise use the default cache
# size.  Multiple each by 2048 to get the number of sectors (1 sector =
# 512KB)
#

$CACHE_SZ = $OPTS{'s'};
if (defined($CACHE_SZ) && ($CACHE_SZ+0) > 0) {
    $CACHE_SZ = ($CACHE_SZ+0) * 2048;
} else {
    $CACHE_SZ = $DEF_CACHE_SZ;
}

foreach $DIR (keys(%CACHE_DIRS)) {

	printInfo("Checking: " . $DIR);
	
    # verify that the cache directory exists

    if (! -d $CACHE_DIRS{$DIR}) {
        printError("No such directory: " . $CACHE_DIRS{$DIR});
        $EC = 1;
        next;
    }

    # determine if the cache directory already mounted

    $MOUNTED = 0;
    $DEV = isMounted($CACHE_DIRS{$DIR});
    if (defined($DEV) && $DEV ne "") {
        $MOUNTED = 1;
        printInfo("Mounted: " . $CACHE_DIRS{$DIR});
    }

    # unmount the ramdisk if running in unmount mode

    if ($UNMOUNT == 1) {

        if ($MOUNTED != 1) {
            printInfo("Not mounted, skipping: " . $CACHE_DIRS{$DIR});
            next;
        }

        $RC = unmountRamDisk($CACHE_DIRS{$DIR});
        if ($RC != 0) {
            printError("Error unmounting ramdisk: " . $CACHE_DIRS{$DIR});
            $EC = 1;
            next;
        }

        # detach the device

        detachDisk($DEV);

        next;
    }

    # skip this directory, if it is already mounted

    if ($MOUNTED) { next; }

    # make the ramdisk

    $RC = makeRamDisk($CACHE_DIRS{$DIR}, $CACHE_SZ, "$DIR Cache");
    if ($RC != 0) {
        printError("Error creating ramdisk for: " . $CACHE_DIRS{$DIR});
        $EC = 1;
    }
}

exit(0);

#
# subroutines
#

#
# isMounted - check to see if a directory is already mounted
#             returns 0 if mounted, 1 if not mounted, -1 on error
#

sub isMounted
{
    my $line = "";
    my $dir = "";
    my $dev = "";
    my $mount_point = "";
    my $mounted = "";

    $dir = shift (@_);
    if (! defined($dir) || ! -d $dir) {
        printError("isMounted: no such directory: " . $dir);
        return $mounted;
    }

    if (! open(MOUNT, "-|", $CMDS{'MOUNT'})) {
        printError("isMounted: cannot run: " . $CMDS{'MOUNT'});
        return $mounted;
    }

    while($line = <MOUNT>) {
        chomp($line);
        ($dev, $mount_point) = $line =~ /^(.*)\ on\ (.*)\ \(.*$/;
        if (!defined($dev)) { $dev = "" ; }
        if (!defined($mount_point)) { $mount_point = ""; }
        printInfo("isMounted: ##$dev## ##$mount_point##");
        if ($mount_point eq $dir) { $mounted = $dev; }
    }

    close(MOUNT);

    printInfo("isMounted: returning: ##$mounted##");

    return $mounted;
}

#
# makeRamDisk - create a ram disk for a given mount point
#

sub makeRamDisk
{
    my $line = "";
    my $dir = "";
    my $abs_path = "";
    my $disk = "";
    my $disk_name = "";
    my $size = 0;
    my @cmd = ();

    # directory for the ram disk

    $dir = shift @_;
    if (! defined($dir) || ! -d ($dir)) {
        printError("makeRamDisk: no such directory: " . $dir);
        return -1;
    }

    # size of the ram disk

    $size = shift @_;
    if (! defined($size) || ($size+0) <= 0) {
        printError("makeRamDisk: invalid cache size: " . $size);
        return -1;
    }

    # volume name for the ram disk

    $disk_name = shift @_;

    # create the ramdisk with hdid using the nomount and nobrowse
    # options to keep the Finder from displaying the ramdisk

    @cmd = ($CMDS{'HDID'}, "-nomount", "-nobrowse", "ram://$size");
    printInfo("makeRamDisk: ", @cmd);
    if (! open(HDID, "-|", @cmd)) {
        printError("makeRamDisk: cannot run: ", @cmd);
        return -1;
    }

    # read the disk id generated by hdid

    chomp($disk = <HDID>);
    if (! defined($disk)) { $disk = ""; }
    $disk =~ s/^\s+//;
    $disk =~ s/\s+$//;

    if (! close(HDID) || $disk !~ /^\/dev\/disk/) {
        printError("makeRamDisk: cannot run: ", @cmd, $?);
        return -1;
    }

    # make a new HFS+ filesystem on the ramdisk, using the
    # specified name (if any)

    if (defined ($disk_name) && $disk_name ne "") {
        @cmd = ($CMDS{'NEWFS'}, "-v", $disk_name, $disk);
    } else {
        @cmd = ($CMDS{'NEWFS'}, $disk);
    }

    printInfo("makeRamDisk: ", @cmd);
    if (! open(NEWFS, "-|", @cmd)) {
        printError("makeRamDisk: cannot run: ", @cmd);
        return -1;
    }

    while($line = <NEWFS>) { }

    if (! close(NEWFS)) {
        detachDisk($disk);
        return -1;
    }

    # mount the ramdisk
    # options: -t hfs       mount ramdisk as a HFS volume
    #          -o -j        ignore the journal
    #             -m 0700   read, write, exec for user only
    #             nobrowse  hide in the finder
    #             nodev     no device files on the ramdisk
    #             noexec    no execution of programs from the ramdisk
    #             nosuid    ignore setuid bits for files on the ramdisk
    #             noatime   don't update the access fime

    @cmd = ($CMDS{'MOUNT'}, "-t", "hfs", "-o",
            "nobrowse,nodev,noexec,nosuid,noatime,-j,-m=0700",
            $disk, $dir);
    printInfo("makeRamDisk: ", @cmd);
    if (! open(MOUNT, "-|", @cmd)) {
        printError("makeRamDisk: cannot run: ", @cmd);
        return -1;
    }

    while($line = <MOUNT>) { }

    if (! close(MOUNT)) {
        detachDisk($disk);
        return -1;
    }

    return 0;
}

#
# unmountRamDisk - unmount the specified ramdisk

sub unmountRamDisk
{
    my $line = "";
    my $dir = "";
    my @cmd = ();

    $dir = shift (@_);
    if (! defined($dir) || ! -d $dir) {
        printError("unmountRamDisk: no directory: " . $dir);
        return -1;
    }

    @cmd = ($CMDS{'UMOUNT'}, $dir);
    printInfo("unmountRamDisk: ", @cmd);
    if (! open(UMOUNT, "-|", @cmd)) {
        printError("unmountRamDisk: cannot run: " . $CMDS{'UMOUNT'});
        return -1;
    }

    while($line = <UMOUNT>) { }

    if (! close(UMOUNT)) {
        return -1;
    }

    return 0;
}

#

#
# detachDisk - detach the specified disk using hdiutil
#

sub detachDisk
{
    my @cmd = ();
    my $disk = "";
    my $line = "";

    $disk = shift @_;
    if (! defined($disk)) {
        printError("detachDisk: no disk specified");
        return -1;
    }

    @cmd = ($CMDS{'HDIUTIL'}, "detach", $disk);
    printInfo("detachDisk: ", @cmd);
    if (! open(HDIUTIL, "-|", @cmd)) {
        printError("detachDisk: cannot run: ", @cmd);
        return -1;
    }

    while ($line = <HDIUTIL>) { }

    close(HDIUTIL);

    return 0;
}

#
# printInfo - print an informational message
#

sub printInfo
{
    if ($VERBOSE != 0) { print "INFO: @_\n"; }
}

#
# printError - print an error message
#

sub printError
{
    print STDERR "ERROR: @_\n";
}

#
# printUsage - prints the usage statement
#

sub printUsage
{
    my $pgm = $0;
    $pgm =~ s/^.*\///;
    print "usage: $pgm [-v] [-u] [-d dir]\n";
    print "       $pgm [-v] [-d dir] [-s [size (MB)]]\n";
    print "       $pgm [-h]\n";
}
