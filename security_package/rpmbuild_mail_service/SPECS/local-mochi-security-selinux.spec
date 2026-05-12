%global selinuxtype targeted
%{!?pkgver:%{error:pkgver is required. Pass --define "pkgver X.Y"}}
%{!?pkgrelease:%{error:pkgrelease is required. Pass --define "pkgrelease N"}}
%{!?rpmname:%{error:rpmname is required. Pass --define "rpmname NAME"}}

Name:           %{rpmname}
Version:        %{pkgver}
Release:        %{pkgrelease}%{?dist}
Summary:        Local SELinux policy module for mail_service socket proxying
License:        MIT
BuildArch:      noarch

# SELinux ポリシーのビルドに必要なツールです。
BuildRequires:  selinux-policy-devel
BuildRequires:  checkpolicy
BuildRequires:  policycoreutils

# 実行時は SELinux が有効な環境でのみマクロが処理します。
Requires:       selinux-policy-targeted
Requires(post): policycoreutils
Requires(preun): policycoreutils
%{?selinux_requires}

Source0:        local_mochi_mail_service_security.te
Source1:        LICENSE

%description
This package ships a local SELinux policy module
(local_mochi_mail_service_security) to allow systemd_socket_proxyd_t
to bind mail service ports and connect to mail_service backend high ports.

%prep
# 展開するソースはありません。

%build
# SELinux devel Makefile が利用可能な場合は、.te から .pp を生成します。
# 最小構成のビルド環境では、個別のツールを使用します。
mkdir -p build
cp %{SOURCE0} build/local_mochi_mail_service_security.te
cd build
if [ -f /usr/share/selinux/devel/Makefile ]; then
  make -f /usr/share/selinux/devel/Makefile local_mochi_mail_service_security.pp
else
  checkmodule -M -m -o local_mochi_mail_service_security.mod local_mochi_mail_service_security.te
  semodule_package -o local_mochi_mail_service_security.pp -m local_mochi_mail_service_security.mod
fi

%install
# policy package を targeted の標準ディレクトリへ配置します。
install -D -m 0644 build/local_mochi_mail_service_security.pp \
  %{buildroot}%{_datadir}/selinux/%{selinuxtype}/local_mochi_mail_service_security.pp
install -D -m 0644 %{SOURCE1} \
  %{buildroot}%{_defaultlicensedir}/%{name}/LICENSE

%post
# モジュールを導入します。transactional system では即時に読み込まれません。
%selinux_modules_install -s %{selinuxtype} %{_datadir}/selinux/%{selinuxtype}/local_mochi_mail_service_security.pp

%postun
# アンインストール時にモジュールを削除します。transactional system では次回起動時に反映されます。
if [ "$1" -eq 0 ]; then
  %selinux_modules_uninstall -s %{selinuxtype} local_mochi_mail_service_security
fi

%files
%license %{_defaultlicensedir}/%{name}/LICENSE
%{_datadir}/selinux/%{selinuxtype}/local_mochi_mail_service_security.pp

%changelog
* Tue May 12 2026 ab-ten <3223197+ab-ten@users.noreply.github.com> - 1.0-1
- Initial mail_service policy package
