The sqlog package contains a set of scripts useful for creating,
populating, and issuing queries to a SLURM job log database and/or
the queue of running jobs.




---

## SUMMARY ##

sqlog was designed as a simple but powerful and easy-to-use tool
to query information about the job history on clusters running SLURM.
Queries using sqlog can be composed of simple job information such as
jobid, job name, nodes on which the job rate, job completion state,
username, number of nodes, number of CPUs, and start, end, and total
runtime. The **sqlog**(1) utility uses perl's Date::Manip module, and
thus supports a powerful range of date and time input formats.

## REQUIREMENTS ##

The sqlog package requires a mysql database, as well the perl modules
**Date::Manip** for date parsing, **DBI**, **DBD::mysql** and **Digest::SHA1**
for database access.


## COMPONENTS ##

  * **sqlog**: The "SLURM Query Log" utility. Provides a single interface to query jobs from the SLURM job log database and/or current list of running jobs.

  * **skewstats**: The "SLURM Queue Stats" utility. Reports simple SLURM job statistics, such as machine utilization, number and size of jobs, and job completion stats. Uses **sqlog** to query historical job data.

  * **slurm-joblog** : Logs completed jobs to the job log database using SLURM's _jobcomp/script_ interface. Optionally logs jobs to an additional text file.

  * **sqlog-db-util** : Administration utility for creation and update of the SLURM joblog. Also provides an interface to "backfill" the database using existing SLURM joblog files created by the _jobcomp/filetxt_ plugin.

  * **sqlog.conf** : World-readable config file.

  * **slurm-joblog.conf** : Private config file. Contains DB password, etc.

## CONFIGURATION ##

See the sqlog [README](http://sqlog.googlecode.com/svn/trunk/README) for
information about sqlog configuration.

## EXAMPLES ##

Display the job or jobs that were running on host55 on July 19, 4:00pm:
```
   sqlog --time="July 19, 4pm" --nodes=host55
```

Display at most 25 jobs that were running at midnight yesterday:

```
   sqlog --time=yesterday,midnight
```

Display all jobs that failed between 8:00AM and  9:00AM  this  morning,
sorted by descending endtime:

```
   sqlog --all --end=8am..9am --states=F --sort=-end
```

Display all jobs that started today:

```
   sqlog --start=+midnight --all
```

Display  all  jobs  that  have  run  between 3 and 4 hours on the nodes
host30 through host65, and that didn't complete normally

```
   sqlog -L 0 -T=3h..4h -n 'host[30-65]' -xs completed
```

Display all jobs that were running yesterday with 1000 nodes or greater
and completed normally:

```
   sqlog -t yesterday,12am..12am -s CD -N +1000
```

List current queue, sorted by number of nodes (ascending):

```
   sqlog --all --no-db --sort=nnodes
```

List the top 10 longest running jobs, and then the 5 oldest jobs:

```
   sqlog --sort=runtime --limit=10
   sqlog --sort=-start --limit=5
```

## USAGE ##

<pre>
Usage: sqlog [OPTIONS]...<br>
<br>
Query information about jobs from the SLURM job log database and/or the<br>
current queue of running jobs.<br>
<br>
-j, --jobids=LIST...     Comma-separated list of jobids.<br>
-J, --job-names=LIST...  Comma-separated list of job names.<br>
-n, --nodes=LIST...      Comma-separated list of nodes or node lists.<br>
-p, --partitions=LIST... Comma-separated list of partitions.<br>
-s, --states=LIST...     Comma-separated list of job states.<br>
Use '--states=list' to list valid state names.<br>
-u, --users=LIST...      Comma-separated list of users.<br>
<br>
--regex              Enable regular expression matching for the above.<br>
<br>
-x, --exclude            Exclude the following list of jobids, users,<br>
states, partitions, or nodes.<br>
<br>
-N, --nnodes=N           List all jobs that ran on N nodes. N may be<br>
specified using the RANGE syntax described below.<br>
--minnodes=N         Explicitly specify the minimum number of nodes.<br>
--maxnodes=N         Explicitly specify the maximum number of nodes.<br>
<br>
-C, --ncores=N           List all jobs that ran on N cores. N may be<br>
specified using the RANGE syntax described below.<br>
--mincores=N         Explicitly specify the minimum number of cores.<br>
--maxcores=N         Explicitly specify the maximum number of cores.<br>
<br>
-T, --runtime=DURATION   List jobs that ran for DURATION, e.g., '4:30:00' or<br>
'4h30m'. RANGE operators apply.<br>
--mintime=DURATION   Explicitly specify the minimum runtime.<br>
--maxtime=DURATION   Explicitly specify the maximum runtime.<br>
<br>
-t, --time, --at=TIME    List jobs which were running at a particular date<br>
and time, e.g., '04/14 13:30:00' or 'today,2pm'.<br>
TIME may also be specified using RANGE operators.<br>
<br>
-S, --start=TIME         List all jobs that started at TIME.<br>
--start-before=TIME  Explicitly specify maximum start time.<br>
--start-after=TIME   Explicitly specify minimum start time.<br>
<br>
-E, --end=TIME           List all jobs that ended at TIME.<br>
--end-before=TIME    Explicitly specify maximum end time.<br>
--end-after=TIME     Explicitly specify minimum end time.<br>
<br>
-X, --no-running         Don't query running jobs (no current queue).<br>
--no-db              Include only running jobs (don't query joblog DB).<br>
<br>
-H, --no-header          Don't print a header row.<br>
-o, --format=LIST        Specify a list of format keys to display or a<br>
format type, or both using the form 'TYPE:keys,..'<br>
Use --format=list to list valid keys and types.<br>
<br>
-P, --sort=LIST          Specify a list of keys to sort output.<br>
<br>
-L, --limit=N            Limit the number of records to report (default=25).<br>
-a, --all                Report all matching records (Same as --limit=0).<br>
<br>
-h, --help               Display this message.<br>
-v, --verbose            Increase output verbosity.<br>
--dry-run            Don't actually do anything.<br>
<br>
TIME, DURATION, and NUMERIC arguments may optionally use one of the RANGE<br>
operators +, -, or '..', where<br>
+N      N or more (at N or later)<br>
-N      N or less (at N or earlier)<br>
N..M      Between N and M, inclusive<br>
N or @N   Exactly N (exactly at N) (use @ if 'N' begins with '+' or '-').<br>
<br>
LIST refers to a comma-separated list of words. All options except --format<br>
which take a LIST argument may also be specified multiple times<br>
(e.g. --users=sally,tim --users=frank). Node lists may be specified using<br>
the host list form, e.g. "host[34-36,67]".<br>
<br>
TIME arguments are parsed using the perl Date::Manip(3pm) package, and thus<br>
may be specified in one of many formats. Examples include '12pm',<br>
'yesterday,noon', '12/25-15:30:33', and so on. See the Date::Manip(3pm)<br>
manpage for more examples.<br>
</pre>

---
