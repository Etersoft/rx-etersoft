%define cups_root %_prefix/lib
Name: freenx-server
Version: 0.7.4
Release: alt19.5

Summary: Freenx application/thin-client server
Group: Networking/Remote access
License: GPLv2
Url: http://freenx.berlios.de

Packager: Boris Savelev <boris@altlinux.org>

Source: ftp://updates.etersoft.ru/pub/Etersoft/RX@Etersoft/unstable/sources/tarball/%name-%version.tar.bz2
Source1: %name.init
Source2: %name.outformat
Source3: cups-additional.conf
Source4: fast-share-mount.conf
Source5: linux-forum-additional.conf
Source6: sudoers.conf
Source7: mount-additional.conf
Source8: terminate-suspend-nx.sh
Source9: numlockx.conf
Source10: node.conf

Obsoletes: freenx
Provides: freenx = %version

Requires: nx
Requires: openssl
Requires: netcat
Requires: expect
Requires: foomatic-db-engine
%if %_vendor == "alt"
Requires: dbus-tools-gui
Requires: binutils
Requires: Xdialog
Requires: /usr/bin/xvt
Requires: schedutils
%endif
BuildPreReq: rpm-build-compat
BuildRequires: imake xorg-cf-files gccmakedep

%description
Freenx is an application/thin-client server based on nx technology.
NoMachine nx is the next-generation X compression and roundtrip suppression
scheme. It can operate remote X11 sessions over 56k modem dialup links
or anything better. This package contains a free (GPL) implementation
of the nxserver component.

%prep
%setup -q

%build
%make_build

%install

# Debian based distr haven't /var/lock/subsys
if [ -d %_var/lock/subsys ] ; then
    LOCKDIR=%_var/lock/subsys
else
    LOCKDIR=%_var/lock
fi

# wrong install path
sed -i "s|/usr/lib|%_libdir|g" nxredir/Makefile
sed -i "s|%_libdir/cups|%cups_root/cups|g" Makefile
# install use nxloadconfig
sed -i "s|/usr/lib|%_libdir|g" nxloadconfig
sed -i "s|%_libdir/cups|%cups_root/cups|g" nxloadconfig
sed -i "s|\$NX_DIR/lib|%_libdir|g" nxloadconfig
# nxredir nxsmb
sed -i "s|/usr/lib|%_libdir|g" nxredir/nxredir
sed -i "s|/usr/lib|%_libdir|g" nxredir/nxsmb
sed -i "s|%_libdir/cups|%cups_root/cups|g" nxredir/nxsmb

%makeinstall_std
mkdir -p %buildroot%_initdir
install -m 755 %SOURCE1 %buildroot%_initdir/%name
sed -i "s|@LOCKDIR@|$LOCKDIR|g" %buildroot%_initdir/%name
install -m644 %SOURCE10 %buildroot%_sysconfdir/nxserver/node.conf
%if %_vendor == "alt"
sed -i "s|@startgnome@|/usr/bin/startgnome2|g" %buildroot%_sysconfdir/nxserver/node.conf
%else
install -m 755 %SOURCE2 %buildroot%_initdir
sed -i "s|@startgnome@|/usr/bin/gnome-session|g" %buildroot%_sysconfdir/nxserver/node.conf
%endif

mkdir -p %buildroot%_var/lib/nxserver/home
mkdir -p %buildroot%_var/lib/nxserver/db
mkdir -p %buildroot%_sysconfdir/nxserver/node.conf.d
mkdir -p %buildroot%_datadir/%name/node.conf.d
mkdir -p %buildroot%_sysconfdir/logrotate.d
mkdir -p %buildroot%_sysconfdir/sudo.d
mkdir -p %buildroot%_sysconfdir/dbus-1/system.d/
mkdir -p %buildroot%_sysconfdir/cron.hourly
mkdir -p %buildroot%_sysconfdir/sysconfig
cp -p data/logrotate %buildroot%_sysconfdir/logrotate.d/freenx-server
cp -p nx-session-launcher/ConsoleKit-NX.conf %buildroot%_sysconfdir/dbus-1/system.d/
mv nx-session-launcher/README nx-session-launcher/README.suid
install -m755 data/fixkeyboard %buildroot%_sysconfdir/nxserver
install -m644 data/Xkbmap %buildroot%_sysconfdir/nxserver
install -m644 %SOURCE3 %buildroot%_sysconfdir/nxserver/node.conf.d
install -m644 %SOURCE4 %buildroot%_sysconfdir/nxserver/node.conf.d
install -m644 %SOURCE5 %buildroot%_sysconfdir/nxserver/node.conf.d
install -m644 %SOURCE7 %buildroot%_sysconfdir/nxserver/node.conf.d
install -m644 %SOURCE9 %buildroot%_sysconfdir/nxserver/node.conf.d
install -m400 %SOURCE6 %buildroot%_sysconfdir/sudo.d/nxserver
install -m700 %SOURCE8 %buildroot%_sysconfdir/cron.hourly

cat >> %buildroot%_sysconfdir/sysconfig/%name << EOF
#Time to live SUSPENDED freenx session in seconds for cron task.
#If not set default value is 3600.
#Cron task enable if value greater than 0.
SESSION_TTL=0
EOF

%pre
%groupadd nx 2> /dev/null ||:
%useradd -g nx -G utmp -d /var/lib/nxserver/home/ -s %_bindir/nxserver \
        -c "NX System User" nx 2> /dev/null ||:
if [ ! -d %_datadir/fonts/misc ] && [ ! -e %_datadir/fonts/misc ] && [ -d %_datadir/fonts/bitmap/misc ]
then
    ln -s %_datadir/fonts/bitmap/misc %_datadir/fonts/misc
fi

%files
%doc AUTHORS ChangeLog CONTRIB nxcheckload.sample node.conf.sample nx-session-launcher/README.suid
%dir %_sysconfdir/nxserver
%dir %_sysconfdir/nxserver/node.conf.d
%config(noreplace) %_sysconfdir/nxserver/node.conf
%_sysconfdir/nxserver/node.conf.sample
%config(noreplace) %_sysconfdir/nxserver/node.conf.d/*.conf
%config %_sysconfdir/logrotate.d/freenx-server
%attr(0400,root,root) %config(noreplace) %_sysconfdir/sudo.d/nxserver
%config %_sysconfdir/dbus-1/system.d/ConsoleKit-NX.conf
%config(noreplace) %_sysconfdir/nxserver/Xkbmap
%_sysconfdir/nxserver/fixkeyboard
%_sysconfdir/sysconfig/%name
%_sysconfdir/cron.hourly/terminate-suspend-nx.sh
%_initdir/%name
%if %_vendor == "alt"
%else
%_initdir/%name.outformat
%endif
%attr(4711,nx,root) %_bindir/nx-session-launcher-suid
%_bindir/nx*
%dir %_libdir/%name
%attr(755,root,root) %_libdir/%name/libnxredir.so.0
%cups_root/cups/backend/nx*
%attr(2750,nx,nx) %_var/lib/nxserver/home
%attr(2750,root,nx) %_var/lib/nxserver/db
%_datadir/%name

%changelog
* Tue Dec 29 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt19.5
- fix COMMAND_START_GNOME for ALTLinux (fix eter#4725)
- don't start numlockx during session startup by default. Add additional config for numlockx

* Wed Dec 02 2009 Eugeny A. Rostovtsev (REAL) <real at altlinux.org> 0.7.4-alt19.4.1
- Rebuilt with python 2.6

* Fri Nov 20 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt19.4
- disable terminate-suspend-nx.sh cron task by default

* Thu Nov 12 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt19.3
- add Requires schedutils for ALT-system (fix eter#4421)
- add cron-script for terminate suspended sessions (fix eter#4436)

* Wed Oct 07 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt19.2
- fix perm on nxserver sudo config (closes: #21860)

* Tue Oct 06 2009 Vitaly Lipatov <lav@altlinux.ru> 0.7.4-alt19.1
- fix mount-additional.conf packing

* Wed Sep 30 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt19
- add patch for Server mode CUPS
  and SMB per-user share mount (from dimbor)

* Tue Sep 22 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.12
- fix CUPSLogLevel config parser

* Thu Jul 30 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.11
- fix restoring suspended sessions

* Wed Jul 29 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.10
- fix new bash regexp syntax

* Wed Jul 29 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.9
- fix new bash regexp syntax

* Mon Jul 27 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.8
- add patch from Mario Becroft (increase nxserver work speed)

* Mon Jul 27 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.7
- increase timeout for hangup session

* Tue Jul 21 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.6
- fix typo in nxnode

* Tue Jul 21 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.5
- fix typo in nxnode. Affected non-ALT systems

* Tue Jul 14 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.4
- add additional conf for mount share and CUPS

* Sat Jun 13 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.3
- xrdb merge /etc/X11/Xresources on startup

* Tue Jun 09 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.2
- use %_bindir/xvt if possible for ALT (ALT#20381)

* Sat Jun 06 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18.1
- add requires Xdialog (ALT#20325)

* Sat Apr 11 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt18
- include patch from Jeffrey J. Kosowsky for CUPS

* Thu Apr 09 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt17
- 2 small fixes
- move fixkeyboard and etc to /etc/nxserver

* Tue Mar 10 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt16.1
- fix COMMAND_SMBMOUNT redifines

* Tue Mar 10 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt16
- build with for new nx

* Sat Mar 07 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt15
- force umount
- merge with teambzr upstream

* Fri Feb 27 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt14
- fix export CUPS_SERVER with Win-client

* Thu Feb 26 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt13
- don't use Xsession for start desktop

* Wed Feb 25 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt12
- move libnxredir to %%_libdir/%name
- check for first run in init-script

* Wed Feb 25 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt11
- add bungle for fixkeyboard
- fix perm on libnxredir (hack, will be fixed soon)

* Sun Feb 22 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt10
- logrotate rule.
- add LSB header.
- patches from Ubuntu.
- implementation of guest login.
- nx-session-launcher:
    + add DBUS rules
    + fix permission on nx-session-launcher-suid
    + add README for nx-session-launcher

* Fri Feb 20 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt9
- fix nxloadconfig for Etersoft SHARE_FAST_MOUNT

* Thu Feb 19 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt8
- fix eterbug #3226 (patch from horch)
- add sleeping wait for valid display (fixkeyboard fails)

* Thu Jan 08 2009 Boris Savelev <boris@altlinux.org> 0.7.4-alt7
- fix path to cups backends on x86_64 (alt bug #18462)
- fix path to LOCKDIR on Debian (eter bug #3094)

* Tue Dec 16 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt6
- fix path to cups
- run "numlockx on" on session start

* Sun Nov 23 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt5
- fix permission on nx homedir

* Sat Nov 22 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt4
- add support nx 3.3

* Tue Nov 11 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt3
- add /var/lib/nxserver

* Fri Sep 05 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt2
- Fixed non-encrypted session mode. You might need to set EXTERNAL_PROXY_IP in node.conf.

* Thu Aug 28 2008 Boris Savelev <boris@altlinux.org> 0.7.4-alt1
- Opened the 0.7.4 development.
- Fixed missing export of NX_ETC_DIR in Makefile, so node.conf.sample is installed correctly.
- Fixed broken round-robin load balance algorithm.
- Fixed --terminate|--suspend|--force-terminate for load balancing case.
- Fixed --terminate|--suspend|--force-terminate for usermode case.

* Sat Aug 23 2008 Boris Savelev <boris@altlinux.org> 0.7.3-alt3
- Changed type for external agents to windows-helper or vnc-helper so that those sessions can be mirrored / shadowed as well.
- Added nxshadowacl.sample component to be able to shadow foreign sessions.
- Prepared shadowing foreign users for VNC-shadowing.
- Added shadow support to --listsession command.
- Added shadow mode as nxagent target.
- Fixed shadow mode and made it usable.

* Mon Aug 18 2008 Boris Savelev <boris@altlinux.org> 0.7.3-alt2
- Build from git
- Finally checked for all service ports. (cups, media, samba) and also checked it on the host where the load balancing actually leads to.
- Fixed broken fallback logic if SSH_CLIENT variables cannot be read correctly.
- Overhauled the usermode:
- There are now two modes of operation.
- One statically setting the ENABLE_USERMODE_AUTHENTICATION key in node.conf. (old behavior)
- Or using nxserver-usermode as startup binary, which directly goes into the 103 stage.
- Fixed using commandline parameters like --cleanup for static usermode.
- Enabled the root commandline parameters in usermode.
- Fixed usage of "nx" user as normal user in usermode.
- Disabled slave mode and load balancing for usermode.
- Fixed creation of the logfile directory.
- Fixed nxnode usage of SSH_CLIENT using fallback mechanism.
- Added disabled nxserver-suid wrapper with help from Google. To enable it uncomment the suid_install target in Makefile.
- Automatically disabled slave mode, when load balancing is activated.
- Made ENABLE_SLAVE_MODE="1" the new default as its faster and more reliable. If you encounter any problems with it, disable it in node.conf.

* Mon Aug 11 2008 Boris Savelev <boris@altlinux.org> 0.7.3-alt1
- svn update to r565
- fix x86_64 build

* Tue Jul 15 2008 Boris Savelev <boris@altlinux.org> 0.7.2-alt2
- svn update to r546

* Fri Jun 13 2008 Boris Savelev <boris@altlinux.org> 0.7.2-alt1
- new version
- fix altbug #16049
- new init-script

* Mon Jan 14 2008 Igor Zubkov <icesik@altlinux.org> 0.7.2-alt5.r430
- fix path for libXrender

* Sun Jan 06 2008 Igor Zubkov <icesik@altlinux.org> 0.7.2-alt4.r430
- fix font path (#13830)

* Thu Jan 03 2008 Igor Zubkov <icesik@altlinux.org> 0.7.2-alt3.r430
- update from svn

* Fri Dec 28 2007 Igor Zubkov <icesik@altlinux.org> 0.7.2-alt2.r427
- mark %_sysconfdir/nxserver/node.conf a config(noreplace)
- own %_sysconfdir/nxserver dir
- add requires nx

* Mon Dec 24 2007 Igor Zubkov <icesik@altlinux.org> 0.7.2-alt1.r427
- build for Sisyphus

