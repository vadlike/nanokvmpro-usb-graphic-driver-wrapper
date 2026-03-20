Modified Windows driver package for NanoKVM Pro USB Graphic based on the official Sipeed release asset:

`https://github.com/sipeed/NanoKVM-Pro/releases/download/v1.0.5/nanokvmpro_usb_graphic_win.zip`

Included in this release:

- corrected `INF` matching for `USB\\VID_3346&PID_1009`
- rebuilt and re-signed package for local Windows installation
- `driver-tool.cmd` for install, removal, and status checks
- ready-to-download package archive

Important notes:

- this is a modified wrapper package, not the untouched official Sipeed archive
- the driver package uses a local test certificate
- no `bcdedit /set testsigning on` is required for the included installer flow
