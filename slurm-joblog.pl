#!/usr/bin/perl -w
###############################################################################
# $Author: grondo $
# $Date: 2007-07-13 12:53:05 -0700 (Fri, 13 Jul 2007) $
# $Rev: 6233 $
###############################################################################
#
# To be run by slurm controller to insert
# job completion data into MySQL database
#
# Creator: Adam Moody <moody20@llnl.gov>
# Modified by Mark Grondona <mgrondona@llnl.gov>
#
require 5.005;
use strict;
use lib qw();	# Required for _perl_libpaths RPM option
use DBI;
use File::Basename;
use POSIX qw(strftime);
use Hostlist qw(expand);

# Required for _path_env_var RPM option
$ENV{PATH} = '/bin:/usr/bin:/usr/sbin';

my $prog = basename $0;

#  List of job variables provided in ENV by SLURM.
#
my @SLURMvars = qw(JOBID UID JOBNAME JOBSTATE PARTITION LIMIT START END NODES PROCS);

#  List of parameters (in order) to pass to SQL execute command below.
#  
my @params    = qw(jobid username uid jobname jobstate partition limit
		           start end nodes nodecount procs);

# 
#  Set up SQL parameters
#
my %conf = ();
$conf{db}      = "slurm";
$conf{sqluser} = "slurm";
$conf{sqlpass} = "";
$conf{sqlhost} = "sqlhost";
$conf{stmt}    = qq(INSERT INTO slurm_job_log VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?));
$conf{confdir} = "/etc/slurm";

#
#  Autocreate slurm_job_log DB if it doesn't exist?
#
$conf{autocreate} = 0;

#
#  Default job logfile. If empty, no logfile is used.
#
$conf{joblogfile} = "/var/log/slurm/joblog";

#
#  Read db, user, password, host from config files:
#
read_config ();
#
#  Get SLURM-provided env vars and add to config
#
get_slurm_vars ();

#  Append job log to database.
my $success = append_job_db ();

#  Append to text file.if requested or DB failed.
if ($conf{joblogfile} || !$success) {
    append_joblog ();
}

exit 0;


#
#  Error logging functions:
#
sub log_msg 
{
    my @msg = @_;
    my $logfile = "/var/log/slurm/jobcomp.log";

    if (!open (LOG, ">>$logfile")) {
        print STDERR @msg;
        return;
    }
    print LOG @msg;
    close (LOG);
}

sub log_error
{
    log_msg "$prog: Error: ", @_;
}

sub log_fatal
{
    log_msg "$prog: Fatal: ", @_;
    exit 1;
}


sub read_config
{
    my $ro = "$conf{confdir}/sqlog.conf";
    my $rw = "$conf{confdir}/slurm-joblog.conf";

    # First read sqlog config to get SQLHOST and SQLDB
    #  (ignore SQLUSER)
    unless (my $rc = do $ro) {
        log_fatal ("Couldn't parse $ro: $@\n") if $@;
        log_fatal ("couldn't run $ro\n") if (defined $rc && !$rc);
    }
    $conf{sqlhost} = $conf::SQLHOST if (defined $conf::SQLHOST);
    $conf{db}      = $conf::SQLDB   if (defined $conf::SQLDB);

    undef $conf::SQLUSER;
    undef $conf::SQLPASS;

    # Now read slurm-joblog.conf
    -r $rw  || log_fatal ("Unable to read required config file: $rw.\n");
    unless (my $rc = do $rw) {
        log_fatal ("Couldn't parse $rw: $@\n") if $@;
        log_fatal ("couldn't run $rw\n") if (defined $rc && !$rc);
    }

    $conf{sqluser}    = $conf::SQLUSER    if (defined $conf::SQLUSER);
    $conf{sqlpass}    = $conf::SQLPASS    if (defined $conf::SQLPASS);
    $conf{joblogfile} = $conf::JOBLOGFILE if (defined $conf::JOBLOGFILE);
    $conf{autocreate} = $conf::AUTOCREATE if (defined $conf::AUTOCREATE);
}


sub get_slurm_vars
{
    $ENV{NODES} = " " if (!$ENV{NODES}); 
    for my $var (@SLURMvars) {
        exists $ENV{$var} or
            log_fatal "$var not set in script environment! Aborting...\n";
        $conf{lc $var} = $ENV{$var};
    }

    #
    #  Get username and count nodes
    $conf{username}  = getpwuid($conf{uid});
    $conf{nodecount} = expand($conf{nodes});
}

sub create_db
{
    if (!$conf{autocreate}) {
        log_error ("Failed to connect to DB at $conf{sqlhost}\n");
        return (0);
    }

    my $cmd = "sqlog-db-util --create";
    system ($cmd);
    if ($?>>8) {
        log_error ("'$cmd' exited with exit code ", $?>>8, "\n");
        return (0);
    }

    log_msg ("Created DB $conf{db} at host $conf{sqlhost}\n");

    return (1);
}

sub slurm_job_log_table_exists
{
    my ($dbh) = @_;
    $dbh->do ("SELECT * FROM slurm_job_log LIMIT 1") || return 0;
    return 1;
}

#
#  Append data to SLURM job log (database)
#
sub append_job_db
{
    #  Ignore if no sqlhost, just append to txt joblog
    #
    if (!$conf{"sqlhost"}) {
        log_error "No SQLHOST found $conf{sqlhost}\n";
        return 0;
    }

    my $str = "DBI:mysql:database=$conf{db};host=$conf{sqlhost}";
    my $dbh = DBI->connect($str, $conf{sqluser}, $conf{sqlpass});

    if (!$dbh) {
        create_db() 
            or return (0);
        $dbh = DBI->connect($str, $conf{sqluser}, $conf{sqlpass})
            or return (0);
    }

    # Check for slurm_job_log table
    if (!slurm_job_log_table_exists ($dbh)) {
        log_msg ("SLURM job log table doesn't exist in DB. Creating.\n");
        create_db () or return (0);
    }

    my $sth = $dbh->prepare($conf{stmt}) 
        or log_error "prepare: ", $dbh->errstr, "\n";

    $sth->execute("NULL", map {convtime_db($_)} @params) or
        log_error "Problem inserting into slurm table: ", $dbh->errstr, "\n"; 

    $dbh->disconnect;
}

sub convtime_db
{
    my ($var) = @_;
    my $fmt = "%Y-%m-%d %H:%M:%S";

    $var =~ /^(start|end)$/ && return strftime $fmt, localtime ($conf{$var});
    return $conf{$var};
}


sub convtime
{
    my ($var) = @_;
    my $fmt = "%Y-%m-%dT%H:%M:%S";

    $var =~ /^(start|end)$/ && return strftime $fmt, localtime ($conf{$var});
    return $conf{$var};
}

#
#  Append data to SLURM job log (text file)
#
sub append_joblog
{
	my $joblog = $conf{joblogfile};

	if (!open (JOBLOG, ">>$joblog")) {
		log_error  "Unable to open $joblog: $!\n";
		return 0;
	}

	printf JOBLOG "JobId=%s UserId=%s(%s) Name=%s JobState=%s Partition=%s " .
		          "TimeLimit=%s StartTime=%s EndTime=%s NodeList=%s " .
				  "NodeCnt=%s\n", 
        map {convtime($_)} @params;

	close (JOBLOG);
}

# vi: ts=4 sw=4 expandtab
