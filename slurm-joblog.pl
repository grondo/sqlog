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
$conf{stmt_v1} = qq(INSERT INTO slurm_job_log    VALUES (?,?,?,?,?,?,?,?,?,?,?,?));
$conf{confdir} = "/etc/slurm";

# enables / disables node tracking per job in version 2 schema
$conf{track} = 1;

# assume neither version 1 nor version 2 are available
$conf{version}{1} = 0;
$conf{version}{2} = 0;

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

    # enable / disable per job node tracking
    $conf{track} = $conf::TRACKNODES if (defined $conf::TRACKNODES);

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
    # if a job is cancelled before it starts, set reasonable defaults for missing variables
    #   PROCS may be set to the number of requested processors (don't know), force it to 0
    #   NODECNT may be set to the number of requested nodes (don't know), we don't use this anyway
    if (not $ENV{NODES}) {
        $ENV{NODES} = "";
        $ENV{PROCS} = 0;
    }

    # set fields in conf corresponding to each SLURM variable
    for my $var (@SLURMvars) {
        exists $ENV{$var} or
            log_fatal "$var not set in script environment! Aborting...\n";
        $conf{lc $var} = $ENV{$var};
    }

    # get username
    $conf{username}  = getpwuid($conf{uid});

    # set nodecount to 0 if no nodelist is specified, otherwise count the number of nodes
    $conf{nodecount} = ($conf{nodes} =~ /^\s*$/) ? 0 : expand($conf{nodes});
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

########################################
# These following functions are similar to those in sqlog-db-util
# TODO: Move these to a perl module?
########################################

# cache for name ids, saves us from hitting the database over and over at the cost of more memory
# not really needed in this case (insert of a single job), but this way, the functions are the same as sqlog-db-util
my %IDcache = ();
%{$IDcache{nodes}} = ();

# execute (do) sql statement on dbh
sub do_sql {
    my ($dbh, $stmt) = @_;
    if (!$dbh->do ($stmt)) {
      log_error ("SQL failed: $stmt\n");
      return 0;
    }
    return 1;
}

# returns 1 if table exists, 0 otherwise
sub table_exists
{
    my $dbh   = shift @_;
    my $table = shift @_;

    # check whether our database has a table by the proper name
    my $sth = $dbh->prepare("SHOW TABLES;");
    if ($sth->execute()) {
        while (my ($name) = $sth->fetchrow_array()) {
            if ($name eq $table) { return 1; }
        }
    }

    # didn't find it
    return 0;
}

# return the auto increment value for the last inserted record
sub get_last_insert_id
{
    my $dbh = shift @_;
    my $id = undef;

    my $sql = "SELECT LAST_INSERT_ID();";
    my $sth = $dbh->prepare($sql);
    if ($sth->execute()) {
        ($id) = $sth->fetchrow_array();
    } else {
        log_error ("Fetching last id: $sql\n");
    }

    return $id;
}

# given a table and name, read id for name from table and add to id cache if found
sub read_id
{
    my $dbh   = shift @_;
    my $table = shift @_;
    my $name  = shift @_;

    my $id = undef;

    # if name is not set, don't try to look it up in hash, just return undef
    if (not defined $name) { return $id; }

    if (not defined $IDcache{$table}) { %{$IDcache{$table}} = (); }
    if (not defined $IDcache{$table}{$name}) {
        my $q_name = $dbh->quote($name);
        my $sql = "SELECT * FROM `$table` WHERE `name` = $q_name;";
        my $sth = $dbh->prepare($sql);
        if ($sth->execute ()) {
            my ($table_id, $table_name) = $sth->fetchrow_array ();
            if (defined $table_id and defined $table_name) {
                $IDcache{$table}{$name} = $table_id;
                $id = $table_id;
            }
        } else {
            log_error ("Reading record: $sql --> " . $dbh->errstr . "\n");
        }
    } else {
        $id = $IDcache{$table}{$name};
    }

    return $id;
}

# insert name into table if it does not exist, and return its id
sub read_write_id
{
    my $dbh   = shift @_;
    my $table = shift @_;
    my $name  = shift @_;

    # attempt to read the id first, if not found, insert it and return the last insert id
    my $id = read_id ($dbh, $table, $name);
    if (not defined $id) {
        my $q_name = $dbh->quote($name);
        my $sql = "INSERT IGNORE INTO `$table` (`id`,`name`) VALUES (NULL,$q_name);";
        my $sth = $dbh->prepare($sql);
        if ($sth->execute ()) {
            # user read_id here instead of get_last_insert_id to avoid race conditions
            $id = read_id ($dbh, $table, $name);
            if (not defined $id) {
                log_error ("Error inserting new record (id undefined): $sql\n");
                $id = 0;
            } elsif ($id == 0) {
                log_error ("Error inserting new record (id=0): $sql\n");
                $id = 0;
            }
        } else {
            log_error ("Error inserting new record: $sql --> " . $dbh->errstr . "\n");
            $id = 0;
        }
    }

    return $id;
}

# given a reference to a list of nodes, read their ids from the nodes table and add them to the id cache
sub read_node_ids
{
    my $dbh       = shift @_;
    my $nodes_ref = shift @_;
    my $success = 1;

    # build list of nodes not in our cache
    my @missing_nodes = ();
    foreach my $node (@$nodes_ref) {
        if (not defined $IDcache{nodes}{$node}) { push @missing_nodes, $node; }
    }

    # if any missing nodes, try to look up their values
    if (@missing_nodes > 0) {
        my @q_nodes = map $dbh->quote($_), @missing_nodes;
        my $in_nodes = join(",", @q_nodes);
        my $sql = "SELECT * FROM `nodes` WHERE `name` IN ($in_nodes);";
        my $sth = $dbh->prepare($sql);
        if ($sth->execute ()) {
            while (my ($table_id, $table_name) = $sth->fetchrow_array ()) {
                $IDcache{nodes}{$table_name} = $table_id;
            }
        } else {
            log_error ("Reading nodes: $sql --> " . $dbh->errstr . "\n");
            $success = 0;
        }
    }

    return $success;
}

# given a reference to a list of nodes, insert them into the nodes table and add their ids to the id cache
sub read_write_node_ids
{
    my $dbh       = shift @_;
    my $nodes_ref = shift @_;
    my $success = 1;

    # read node_ids for these nodes into our cache
    read_node_ids($dbh, $nodes_ref);

    # if still missing nodes, we need to insert them
    my @missing_nodes = ();
    foreach my $node (@$nodes_ref) {
        if (not defined $IDcache{nodes}{$node}) { push @missing_nodes, $node; }
    }
    if (@missing_nodes > 0) {
        my @q_nodes = map $dbh->quote($_), @missing_nodes;
        my $values = join("),(", @q_nodes);
        my $sql = "INSERT IGNORE INTO `nodes` (`name`) VALUES ($values);";
        my $sth = $dbh->prepare($sql);
        if (not $sth->execute ()) {
            log_error ("Inserting nodes: $sql --> " . $dbh->errstr . "\n");
            $success = 0;
        }

        # fetch ids for just inserted nodes
        read_node_ids($dbh, $nodes_ref);
    }

    return $success;
}

# given a job_id and a nodelist, insert jobs_nodes records for each node used in job_id
sub insert_job_nodes
{
    my $dbh      = shift @_;
    my $job_id   = shift @_;
    my $nodelist = shift @_;
    my $success = 1;

    if (defined $job_id and defined $nodelist and $nodelist ne "") {
        my $q_job_id = $dbh->quote($job_id);

        # clean up potentially bad nodelist
        if ($nodelist =~ /\[/ and $nodelist !~ /\]/) {
            # found an opening bracket, but no closing bracket, nodelist is probably incomplete
            # chop back to last ',' or '-' and replace with a ']'
            $nodelist =~ s/[,-]\d+$/\]/;
        }

        # get our nodeset
        my @nodes = Hostlist::expand($nodelist);

        # this will fill our node_id cache
        read_write_node_ids($dbh, \@nodes);

        # get the node_id for each node
        my @values = ();
        foreach my $node (@nodes) {
            if (defined $IDcache{nodes}{$node}) {
                my $q_node_id = $dbh->quote($IDcache{nodes}{$node});
                push @values, "($q_job_id,$q_node_id)";
            }
        }

        # if we have any nodes for this job, insert them
        if (@values > 0) {
            my $sql = "INSERT DELAYED IGNORE INTO `jobs_nodes` (`job_id`,`node_id`) VALUES " . join(",", @values) . ";";
            my $sth = $dbh->prepare($sql);
            if (not $sth->execute ()) {
                log_error ("Inserting jobs_nodes records for job id $job_id: $sql --> " . $dbh->errstr . "\n");
                $success = 0;
            }
        }
    }

    return $success;
}

# compute time since epoch, attempt to account for DST changes via timelocal
sub get_seconds
{
    my ($date) = @_;
    use Time::Local;

    my ($y, $m, $d, $H, $M, $S) = ($date =~ /(\d\d\d\d)\-(\d\d)\-(\d\d) (\d\d):(\d\d):(\d\d)/);
    $y -= 1900;
    $m -= 1;

    return timelocal ($S, $M, $H, $d, $m, $y);
}

# given hash of values, create mysql values string for insert statement
sub value_string_v2
{
    my $dbh = shift @_;
    my $h   = shift @_;

    # given start and end times, compute the number of seconds the job ran for
    # TODO: unsure whether this correctly handles jobs that straddle DST changes
    my $seconds = 0;
    if (defined $h->{StartTime} and $h->{StartTime} !~ /^\s*$/ and
        defined $h->{EndTime}   and $h->{EndTime}   !~ /^\s*$/)
    {
         my $start = get_seconds($h->{StartTime});
         my $end   = get_seconds($h->{EndTime});
         $seconds = $end - $start;
         if ($seconds < 0) { $seconds = 0; }
    }

    # if Procs is not set, but ppn is specified and NodeCnt is set, compute Procs
    # (assumes all processors on the node were allocated to the job, only use for clusters
    # which use whole-node allocation)
#    if (not defined $h->{Procs} and defined $conf{ppn} and defined $h->{NodeCnt}) {
#      $h->{Procs} = $h->{NodeCnt} * $conf{ppn};
#    }

    # insert the field values, order matters
    my @parts = ();
    push @parts, (defined $h->{Id}) ? $dbh->quote($h->{Id}) : "NULL";
    push @parts, $dbh->quote($h->{JobId});
    push @parts, $dbh->quote(read_write_id($dbh, "usernames",  $h->{UserName}));
    push @parts, $dbh->quote($h->{UserNumb});
    push @parts, $dbh->quote(read_write_id($dbh, "jobnames",   $h->{Name}));
    push @parts, $dbh->quote(read_write_id($dbh, "jobstates",  $h->{JobState}));
    push @parts, $dbh->quote(read_write_id($dbh, "partitions", $h->{Partition}));
    push @parts, $dbh->quote($h->{TimeLimit});
    push @parts, $dbh->quote($h->{StartTime});
    push @parts, $dbh->quote($h->{EndTime});
    push @parts, $dbh->quote($seconds);
    push @parts, $dbh->quote($h->{NodeList});
    push @parts, $dbh->quote($h->{NodeCnt});
    push @parts, (defined $h->{Procs}) ? $dbh->quote($h->{Procs}) : 0;

    # finally, return the ('field1','field2',...) string
    return "(" . join(',', @parts) . ")";
}

########################################
# The above functions are similar to those in sqlog-db-util
# TODO: Move these to a perl module?
########################################

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

    # check whether we have version 1 and version 2 schemas
    $conf{version}{1} = table_exists ($dbh, 'slurm_job_log');
    $conf{version}{2} = table_exists ($dbh, 'jobs');

    # Check for tables, if not found, try to create them
    if (not $conf{version}{1} and not $conf{version}{2}) {
        log_msg ("SLURM job log table doesn't exist in DB. Creating.\n");
        create_db () or return (0);
    }

    # if we have schema 2 use it, otherwise, try schema 1
    # if neither is found, print an error
    if ($conf{version}{2}) {
        # value_string_v2 expects certain field names, so convert conf
        my %h = ();
        $h{JobId}     = $conf{jobid};
        $h{UserName}  = $conf{username};
        $h{UserNumb}  = $conf{uid};
        $h{Name}      = $conf{jobname};
        $h{JobState}  = $conf{jobstate};
        $h{Partition} = $conf{partition};
        $h{TimeLimit} = $conf{limit};
        $h{StartTime} = convtime_db("start");
        $h{EndTime}   = convtime_db("end");
        $h{NodeList}  = $conf{nodes};
        $h{NodeCnt}   = $conf{nodecount};
        $h{Procs}     = $conf{procs};

        # convert hash to VALUES clause
        my $value_string = value_string_v2 ($dbh, \%h);

        # insert into v2 schema
        my $sql = "INSERT INTO `jobs` VALUES $value_string;";
        if (not do_sql ($dbh, $sql)) {
            log_error "Problem inserting into slurm table: $sql: error: ", $dbh->errstr, "\n"; 
            return 0;
        }

        # insert nodes used by this job if node tracking is enabled
        if ($conf{track}) {
            my $job_id = get_last_insert_id ($dbh);
            if (defined $job_id and $job_id != 0) {
                insert_job_nodes ($dbh, $job_id, $h{NodeList});
            }
        }
    } elsif ($conf{version}{1}) {
        # insert into v1 schema
        my @params_v1 = @params;
        pop @params_v1;

        my $sth_v1 = $dbh->prepare($conf{stmt_v1}) 
            or log_error "prepare: ", $dbh->errstr, "\n";

        if (not $sth_v1->execute("NULL", map {convtime_db($_)} @params_v1)) {
            log_error "Problem inserting into slurm table: ", $dbh->errstr, "\n"; 
            return 0;
        }
    } else {
        log_error "No tables found to insert record into\n"; 
        return 0;
    }

    $dbh->disconnect;
    return 1;
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
				  "NodeCnt=%s Procs=%s\n", 
        map {convtime($_)} @params;

	close (JOBLOG);
}

# vi: ts=4 sw=4 expandtab
