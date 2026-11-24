%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           inutil-music
Version:        %{app_version}
Release:        1
Summary:        Reproductor y gestor musical multiplataforma
License:        Proprietary
URL:            https://github.com/CesarHGlez13/inutil-music
Vendor:         Inutix Music
BuildArch:      x86_64
AutoReqProv:    no

Requires:       gtk3
Requires:       mpv-libs
Requires:       sqlite-libs
Requires:       libsecret
Requires:       glibc
Requires:       libstdc++

%description
Inutix Music permite buscar, reproducir, descargar y organizar musica,
playlists y favoritos desde una interfaz construida con Flutter.

%install
mkdir -p "%{buildroot}"
cp -a "%{staging_root}/." "%{buildroot}/"

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
fi

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t /usr/share/icons/hicolor || true
fi

%files
/opt/inutil-music
/usr/bin/inutil-music
/usr/share/applications/com.inutilmusic.app.desktop
/usr/share/icons/hicolor/512x512/apps/com.inutilmusic.app.png
