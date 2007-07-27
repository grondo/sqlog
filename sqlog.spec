Name:      sqlog
Version:   See META
Release:   See META

Summary:   SLURM job completion database utilities
Group:     Applications/System
License:   GPL
Source:    %{name}-%{version}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}
BuildArch: noarch
Requires: slurm

%define debug_package %{nil}

%description
numa-maps is a simple script which parses /proc/PID/numa_maps
and /proc/PID/maps to display NUMA information for running
processes.


%prep 
%setup

%build
#NOOP

%install
rm -rf "$RPM_BUILD_ROOT"
mkdir -p "$RPM_BUILD_ROOT"
install -D -m 755 sqlog  ${RPM_BUILD_ROOT}/%{_bindir}/sqlog
install -D -m 644 sqlog.1 ${RPM_BUILD_ROOT}/%{_mandir}/man1/sqlog.1
install -D -m 755 slurm-joblog.pl \
			${RPM_BUILD_ROOT}/%{_libexecdir}/sqlog/slurm-joblog

%clean
rm -rf "$RPM_BUILD_ROOT"

%files
%defattr(-,root,root)
%doc ChangeLog
%{_bindir}/sqlog
%{_mandir}/*/*
%{_libexecdir}/sqlog/slurm-joblog
