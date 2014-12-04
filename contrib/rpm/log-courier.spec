# Debug packaging does not work due to the go build building in extra debug sections RPM does not understand
# Maybe we patch something later to fix this, but for now just don't build a debug package
%define debug_package %{nil}

Summary: Log Courier
Name: log-courier
Version: 1.2
Release: 4%{dist}
License: GPL
Group: System Environment/Libraries
Packager: Jason Woods <packages@jasonwoods.me.uk>
URL: https://github.com/driskell/log-courier
Source: https://github.com/driskell/log-courier/archive/v%{version}.zip
BuildRoot: %{_tmppath}/%{name}-%{version}-root

BuildRequires: golang >= 1.2
BuildRequires: git
BuildRequires: zeromq3-devel

# Maybe tests in future - mock won't build ffi gem
#BuildRequires: ruby >= 1.9.3, ruby-devel >= 1.9.3
#BuildRequires: rubygem-bundler

%if 0%{?rhel} >= 7
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd
BuildRequires: systemd
%endif

Requires: zeromq3
Requires: logrotate

%description
Log Courier is a tool created to transmit log files speedily and securely to
remote Logstash instances for processing whilst using small amounts of local
resources. The project is an enhanced fork of Logstash Forwarder 0.3.1 with many
enhancements and behavioural improvements.

%prep
%setup -q -n %{name}-%{version}

%build
make with=zmq3
# See notes above for BuildRequires ruby
#make with=zmq3 test

%install
# Install binaries
mkdir -p %{buildroot}%{_sbindir}
install -m 0755 bin/log-courier %{buildroot}%{_sbindir}/log-courier
mkdir -p %{buildroot}%{_bindir}
install -m 0755 bin/lc-admin %{buildroot}%{_bindir}/lc-admin
install -m 0755 bin/lc-tlscert %{buildroot}%{_bindir}/lc-tlscert

# Install example configuration
mkdir -p %{buildroot}%{_sysconfdir}/log-courier %{buildroot}%{_sysconfdir}/log-courier/examples/
install -m 0644 docs/examples/* %{buildroot}%{_sysconfdir}/log-courier/examples/

# Make the run dir
mkdir -p %{buildroot}%{_var}/run %{buildroot}%{_var}/run/log-courier
touch %{buildroot}%{_var}/run/log-courier/admin.socket

# Install init script and related paraphernalia
%if 0%{?rhel} >= 7
mkdir -p %{buildroot}%{_unitdir}
# No systemd script in log-courier release yet
install -m 0644 contrib/initscripts/systemd.service %{buildroot}%{_unitdir}/log-courier.service
%else
mkdir -p %{buildroot}%{_sysconfdir}/init.d
install -m 0755 contrib/initscripts/redhat-sysv.init %{buildroot}%{_sysconfdir}/init.d/log-courier
touch %{buildroot}%{_var}/run/log-courier.pid
%endif

# Make the state dir
mkdir -p %{buildroot}%{_var}/lib/log-courier
touch %{buildroot}%{_var}/lib/log-courier/.log-courier

%clean
rm -rf $RPM_BUILD_ROOT

%post
%if 0%{?rhel} >= 7
%systemd_post log-courier.service
%else
/sbin/chkconfig --add log-courier
%endif

%preun
%if 0%{?rhel} >= 7
%systemd_preun log-courier.service
%else
if [ $1 -eq 0 ]; then
	/sbin/service log-courier stop >/dev/null 2>&1
	/sbin/chkconfig --del log-courier
fi
%endif

%postun
%if 0%{?rhel} >= 7
%systemd_postun_with_restart log-courier.service
%else
if [ $1 -ge 1 ]; then
	/sbin/service log-courier restart >/dev/null 2>&1
fi
%endif

%files
%defattr(0755,root,root,0755)
%{_sbindir}/log-courier
%{_bindir}/lc-admin
%{_bindir}/lc-tlscert
%if 0%{?rhel} >= 7
%{_unitdir}/log-courier.service
%else
%{_sysconfdir}/init.d/log-courier
%endif

%defattr(0644,root,root,0755)
%{_sysconfdir}/log-courier
%if 0%{?rhel} < 7
%ghost %{_var}/run/log-courier.pid
%endif
%dir %attr(0700,root,root) %{_var}/run/log-courier
%ghost %{_var}/run/log-courier/admin.socket
%dir %{_var}/lib/log-courier
%ghost %{_var}/lib/log-courier/.log-courier

%changelog
* Sat Nov 8 2014 Jason Woods <devel@jasonwoods.me.uk> - 1.2-4
- Upgrade to v1.2
- Fix stop message on future upgrade

* Wed Nov 5 2014 Jason Woods <devel@jasonwoods.me.uk> - 1.1-4
- Build with ZMQ 3 support

* Mon Nov 3 2014 Jason Woods <devel@jasonwoods.me.uk> - 1.1-3
- Fix init/systemd registration

* Sun Nov 2 2014 Jason Woods <devel@jasonwoods.me.uk> - 1.1-2
- Package for EL7
- Restart service on upgrade

* Fri Oct 31 2014 Jason Woods <devel@jasonwoods.me.uk> 1.1-1
- Released 1.1
- Cleanup for EL7 build

* Mon Oct 13 2014 Jason Woods <packages@jasonwoods.me.uk> 0.15.1-1
- Rebuild from v0.15 develop to fix more issues
- Label as v0.15.1

* Thu Sep 4 2014 Jason Woods <packages@jasonwoods.me.uk> 0.14.rc2-1
- Rebuild from develop to fix more issues and enable unix socket
	for administration
- Label as v0.14.rc2

* Wed Sep 3 2014 Jason Woods <packages@jasonwoods.me.uk> 0.14.rc1-1
- Rebuild from develop to fix various reconnect hang issues
- Label as v0.14.rc1

* Mon Sep 1 2014 Jason Woods <packages@jasonwoods.me.uk> 0.13-1
- Initial build of v0.13
