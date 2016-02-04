%define rbname astute
%{!?version: %define version 9.0.0}
%{!?release: %define release 1}
%if 0%{?rhel} == 6
%global gem_dir %(ruby -rubygems -e 'puts Gem::dir' 2>/dev/null)
%endif
%global geminstdir %{gem_dir}/gems/%{gemname}-%{version}
%define gembuilddir %{buildroot}%{gem_dir}

Summary: Orchestrator for OpenStack deployment
Version: %{version}

%if 0%{?rhel} == 6
Name: ruby21-rubygem-astute
Release: %{release}
Provides: ruby21(Astute) = %{version}
%else
Name: rubygem-astute
Release: %{release}
Provides: ruby(Astute) = %{version}
%endif

Group: Development/Ruby
License: Distributable
URL: http://fuel.mirantis.com
Source0: %{rbname}-%{version}.tar.gz

# Make sure the spec template is included in the SRPM
BuildRoot: %{_tmppath}/%{rbname}-%{version}-root
%if 0%{?rhel} == 6
Requires: ruby21 >= 2.1
Requires: ruby21-rubygem-activesupport = 3.0.10
Requires: ruby21-rubygem-mcollective-client = 2.4.1
Requires: ruby21-rubygem-symboltable = 1.0.2
Requires: ruby21-rubygem-rest-client = 1.6.7
Requires: ruby21-rubygem-bunny
Requires: ruby21-rubygem-raemon = 0.3.0
Requires: ruby21-rubygem-net-ssh = 2.8.0
Requires: ruby21-rubygem-net-ssh-gateway = 1.2.0
Requires: ruby21-rubygem-net-ssh-multi = 1.2.0
BuildRequires: ruby21 >= 2.1
BuildRequires: rubygems21
%else
Requires: ruby
Requires: rubygem-activesupport
Requires: rubygem-mcollective-client
Requires: rubygem-symboltable
Requires: rubygem-rest-client
Requires: rubygem-bunny
Requires: rubygem-raemon
Requires: rubygem-net-ssh
Requires: rubygem-net-ssh-gateway
Requires: rubygem-net-ssh-multi
BuildRequires: ruby
BuildRequires: rubygems-devel
%endif
BuildArch: noarch
Requires: openssh-clients

%if 0%{?fedora} > 16 || 0%{?rhel} > 6
Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units
BuildRequires: systemd-units
%endif

%description
Deployment Orchestrator of Puppet via MCollective. Works as a library or from
CLI.


%prep
%setup -cq -n %{rbname}-%{version}

%build
cd %{_builddir}/%{rbname}-%{version}/ && gem build *.gemspec

%install
mkdir -p %{gembuilddir}
gem install --local --install-dir %{gembuilddir} --force %{_builddir}/%{rbname}-%{version}/%{rbname}-%{version}.gem
mkdir -p %{buildroot}%{_bindir}
mv %{gembuilddir}/bin/* %{buildroot}%{_bindir}
rmdir %{gembuilddir}/bin
install -d -m 750 %{buildroot}%{_sysconfdir}/astute
cat > %{buildroot}%{_bindir}/astuted <<EOF
#!/bin/bash
ruby -r 'rubygems' -e "gem 'astute', '>= 0'; load Gem.bin_path('astute', 'astuted', '>= 0')" -- \$@
EOF
install -d -m 755 %{buildroot}%{_localstatedir}/log/astute
install -D -m644 %{_builddir}/%{rbname}-%{version}/%{rbname}.sysconfig %{buildroot}/%{_sysconfdir}/sysconfig/%{rbname}
#nailgun-mcagents
mkdir -p %{buildroot}/usr/libexec/mcollective/mcollective/agent/
cp -rf %{_builddir}/%{rbname}-%{version}/mcagents/* %{buildroot}/usr/libexec/mcollective/mcollective/agent/

%if %{defined _unitdir}
install -D -m644 %{_builddir}/%{rbname}-%{version}/%{rbname}.service %{buildroot}/%{_unitdir}/%{rbname}.service
%endif

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root)
%{gem_dir}/gems/%{rbname}-%{version}/bin/*
%{gem_dir}/gems/%{rbname}-%{version}/lib/*
%{gem_dir}/gems/%{rbname}-%{version}/spec/*
%{gem_dir}/gems/%{rbname}-%{version}/examples/*

%dir %attr(0750, naily, naily) %{_sysconfdir}/%{rbname}
%dir %attr(0755, naily, naily) %{_localstatedir}/log/%{rbname}
%config(noreplace) %{_bindir}/astuted
%config(noreplace) %{_sysconfdir}/sysconfig/%{rbname}

%doc %{gem_dir}/doc/%{rbname}-%{version}
%{gem_dir}/cache/%{rbname}-%{version}.gem
%{gem_dir}/specifications/%{rbname}-%{version}.gemspec

%if %{defined _unitdir}
/%{_unitdir}/%{rbname}.service

%post
%systemd_post %{rbname}.servive

%preun
%systemd_preun %{rbname}.service

%postun
%systemd_postun_with_restart %{rbname}.service

%endif

%if 0%{?rhel} == 6
%package -n ruby21-nailgun-mcagents

Summary:   MCollective Agents
Version:   %{version}
Release:   %{release}
License:   GPLv2
Requires:  ruby21-mcollective >= 2.2
URL:       http://mirantis.com

%description -n ruby21-nailgun-mcagents
MCollective agents

%files -n ruby21-nailgun-mcagents
/usr/libexec/mcollective/mcollective/agent/*
%endif

%package -n nailgun-mcagents

Summary:   MCollective Agents
Version:   %{version}
Release:   %{release}
License:   GPLv2
Requires:  mcollective >= 2.2
Requires:  network-checker
URL:       http://mirantis.com

%description -n nailgun-mcagents
MCollective agents

%files -n nailgun-mcagents
/usr/libexec/mcollective/mcollective/agent/*
