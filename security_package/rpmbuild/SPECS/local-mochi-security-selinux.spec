%global selinuxtype targeted
%{!?pkgver:%{error:pkgver is required. Pass --define "pkgver X.Y"}}
%{!?pkgrelease:%{error:pkgrelease is required. Pass --define "pkgrelease N"}}

Name:           local-mochi-security-selinux
Version:        %{pkgver}
Release:        %{pkgrelease}%{?dist}
Summary:        Local SELinux policy module for systemd-socket-proxyd port forwarding
License:        MIT
BuildArch:      noarch

# SELinux policy build tooling
BuildRequires:  selinux-policy-devel
BuildRequires:  checkpolicy
BuildRequires:  policycoreutils

# Runtime: only when SELinux is used, macros handle gating via selinuxenabled
Requires:       selinux-policy-targeted
Requires(post): policycoreutils
Requires(preun): policycoreutils
%{?selinux_requires}

Source0:        local_mochi_security.te
Source1:        LICENSE

%description
This package ships a local SELinux policy module (local_mochi_security)
to allow systemd_socket_proxyd_t to bind/connect HTTP-related ports.

%prep
# no sources to unpack

%build
# Build .pp from .te using the SELinux devel Makefile if available.
# Fallback to explicit tools to keep it robust in minimal build roots.
mkdir -p build
cp %{SOURCE0} build/local_mochi_security.te
cd build
if [ -f /usr/share/selinux/devel/Makefile ]; then
  make -f /usr/share/selinux/devel/Makefile local_mochi_security.pp
else
  checkmodule -M -m -o local_mochi_security.mod local_mochi_security.te
  semodule_package -o local_mochi_security.pp -m local_mochi_security.mod
fi

%install
# Install policy package into standard location (targeted)
install -D -m 0644 build/local_mochi_security.pp \
  %{buildroot}%{_datadir}/selinux/%{selinuxtype}/local_mochi_security.pp
install -D -m 0644 %{SOURCE1} \
  %{buildroot}%{_defaultlicensedir}/%{name}/LICENSE

%post
# Install module; on transactional systems this will not load policy immediately.
%selinux_modules_install -s %{selinuxtype} %{_datadir}/selinux/%{selinuxtype}/local_mochi_security.pp

%postun
# Remove module on uninstall; on transactional systems takes effect on next boot.
if [ "$1" -eq 0 ]; then
  %selinux_modules_uninstall -s %{selinuxtype} local_mochi_security
fi

%files
%license %{_defaultlicensedir}/%{name}/LICENSE
%{_datadir}/selinux/%{selinuxtype}/local_mochi_security.pp

%changelog
* Wed Dec 17 2025 ab-ten <3223197+ab-ten@users.noreply.github.com> - 1.1-2
- build process updated.

* Wed Dec 17 2025 ab-ten <3223197+ab-ten@users.noreply.github.com> - 1.1-1
- allow https proxy

* Sun Dec 14 2025 ab-ten <3223197+ab-ten@users.noreply.github.com> - 1.0-1
- Initial package
