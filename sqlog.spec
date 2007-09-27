Name:      sqlog
Version:   See META
Release:   See META

Summary:   SLURM job completion database utilities
Group:     Applications/System
License:   GPL
Source:    %{name}-%{version}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}
BuildArch: noarch
Requires: slurm perl-DateManip perl-DBI perl-DBD-MySQL perl-Digest-SHA1 gendersllnl

%define debug_package %{nil}

%description
sqlog provides a system for creation, query, and population of a 
database of SLURM job history. 

%{!?_slurm_sysconfdir: %define _slurm_sysconfdir %{_sysconfdir}/slurm}
%{!?_perl_path: %define _perl_path %{__perl}}
%{!?_perl_libpaths: %define _perl_libpaths %{nil}}
%{!?_path_env_var: %define _path_env_var /bin:/usr/bin:/usr/sbin}

%prep 
%setup

%build
#NOOP

%install
rm -rf "$RPM_BUILD_ROOT"
mkdir -p "$RPM_BUILD_ROOT"
mkdir -p -m0755 $RPM_BUILD_ROOT/%{_libexecdir}/sqlog

perl -pli -e "s|/etc/slurm|%{_slurm_sysconfdir}|g;
	      s|/usr/bin/perl|%{_perl_path}|;
	      s|^use lib qw\(\);|use lib qw(%{_perl_libpaths});|;
	      s|^(\\\$ENV\{PATH\}) = '[^']*';|\$1 = '%{_path_env_var}';|;" \
	sqlog sqlog.1 sqlog-db-util sqlog-db-util.8 slurm-joblog.pl

install -D -m 755 sqlog  ${RPM_BUILD_ROOT}/%{_bindir}/sqlog
install -D -m 644 sqlog.1 ${RPM_BUILD_ROOT}/%{_mandir}/man1/sqlog.1
install -D -m 755 sqlog-db-util ${RPM_BUILD_ROOT}/%{_sbindir}/sqlog-db-util
install -D -m 644 sqlog-db-util.8 ${RPM_BUILD_ROOT}/%{_mandir}/man8/sqlog-db-util.8
install -D -m 755 slurm-joblog.pl \
			${RPM_BUILD_ROOT}/%{_libexecdir}/sqlog/slurm-joblog


%clean
rm -rf "$RPM_BUILD_ROOT"

%files
%defattr(-,root,root)
%doc README NEWS ChangeLog sqlog.conf.example slurm-joblog.conf.example
%{_bindir}/sqlog
%{_sbindir}/sqlog-db-util
%{_mandir}/*/*
%{_libexecdir}/sqlog
