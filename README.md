# Inútil Music — canal de actualizaciones OTA

Repositorio **sólo de artefactos**: aquí se publican las Releases con los
paquetes que la app descarga e instala desde dentro (`Ajustes → Actualizaciones`
y la pantalla de actualización obligatoria). El código fuente vive en el
repositorio local de la app y no se publica aquí.

## Contenido de cada Release `v<versión>`

| Asset | Para qué |
| --- | --- |
| `app-arm64-v8a-release.apk` | teléfonos ARM de 64 bits (el enlace por defecto del manifiesto) |
| `app-armeabi-v7a-release.apk` | teléfonos ARM de 32 bits |
| `app-x86_64-release.apk` | emuladores / tablets x86_64 |
| `inutil_music_linux_x64.tar.gz` | el bundle de Linux que la app de PC reemplanta en `~/.local/share/inutil-music` |
| `release.json` | manifiesto que lee `InutilUpdateService.checkForUpdate` (`latestVersion`, `minSupportedVersion`, `mandatory`, URLs por ABI, tamaños y SHA-256) |

La app consulta, en este orden: la URL de Ajustes, `INUTIL_RELEASE_MANIFEST_URL`,
`releases/latest/download/release.json` de este repo, el bucket de Cloud Storage,
el documento Firestore `app_config/release`, un PC de la misma red y, por último,
su caché local.

## Publicar una versión

```bash
flutter build apk --release --split-per-abi
flutter build linux --release && bash tool/package_linux.sh
bash tool/publish_release.sh <versión> --dry-run     # revisa el release.json
FIREBASE_ACCESS_TOKEN=… bash tool/publish_release.sh <versión> --github
```

`minSupportedVersion` queda por defecto en la versión publicada: las anteriores
dejan de funcionar y la app muestra el letrero de actualización obligatoria.
Detalle completo: `docs/RELEASES.md` del repositorio de la app.
