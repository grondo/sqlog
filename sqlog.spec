Name:      sqlog
Version:   See META
Release:   See META

Summary:   SLURM job completion database utilities
Group:     Applications/System
License:   GPL
Source:    %{name}-%{version}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}
BuildArch: noarch
Requires: slurm perl-DateManip gendersllnl

%define debug_package %{nil}

%description
sqlog provides a system for creation, query, and population of a 
database of SLURM job history. 

%{!?_slurm_sysconfdir: %define _slurm_sysconfdir %{_sysconfdir}/slurm}
%{!?_perl_path: %define _perl_path /usr/bin/perl}

%prep 
%setup

%build
#NOOP

%install
rm -rf "$RPM_BUILD_ROOT"
mkdir -p "$RPM_BUILD_ROOT"
mkdir -p -m0755 $RPM_BUILD_ROOT/%{_libexecdir}/sqlog

subst()
{
	FILE=$1
	CONFDIR=%{_slurm_sysconfdir}
	PERL=%{_perl_path}
	perl -ple "s|/usr/bin/perl|$PERL|; s|/etc/slurm|$CONFDIR|;" $FILE \
		  > $FILE.tmp
	mv $FILE.tmp $FILE
}

for f in sqlog sqlog-db-util slurm-joblog.pl; do
    subst $f
done

install -D -m 755 sqlog  ${RPM_BUILD_ROOT}/%{_bindir}/sqlog
install -D -m 644 sqlog.1 ${RPM_BUILD_ROOT}/%{_mandir}/man1/sqlog.1
install -D -m 755 sqlog-db-util ${RPM_BUILD_ROOT}/%{_sbindir}/sqlog-db-util
install -D -m 755 sqlog-db-util.8 ${RPM_BUILD_ROOT}/%{_mandir}/man8/sqlog-db-util.8
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
