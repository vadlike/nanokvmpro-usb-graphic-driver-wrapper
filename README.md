# NanoKVMPro USB Graphic Driver Wrapper

[![Download Latest Release](https://img.shields.io/badge/Download-Latest%20Release-2ea44f?style=for-the-badge)](https://github.com/vadlike/nanokvmpro-usb-graphic-driver-wrapper/releases/latest)

![](https://github-visitor-counter-tau.vercel.app/api?username=vadlike&repo=nanokvmpro-usb-graphic-driver-wrapper&displayMode=topCountries&theme=github)

NanoKVM Pro is a compact IP-KVM for remote computer access with BIOS-level control, low-latency video streaming, and network-based keyboard and mouse control.

This repository provides a ready-to-use Windows driver package and helper tool for installing and removing the NanoKVMPro USB Graphic driver.

Latest release:
`https://github.com/vadlike/nanokvmpro-usb-graphic-driver-wrapper/releases/latest`

![NanoKVM Pro](assets/nanokvm-pro.png)

Image source: Sipeed Wiki  
https://wiki.sipeed.com/hardware/en/kvm/NanoKVM_Pro/introduction.html

Author: [vadlike](https://github.com/vadlike)

## Source

Official driver archive used as the base:

`https://github.com/sipeed/NanoKVM-Pro/releases/download/v1.0.5/nanokvmpro_usb_graphic_win.zip`

The official archive contains only the packaged driver files:

- `nanokvm_usb_graphic.inf`
- `nanokvm_usb_graphic.dll`
- `nanokvm_usb_graphic.cat`

It does not include the original Windows driver source code.

## What Was Changed

This repository is not a raw mirror of the official archive.

Changes made in this package:

- the `INF` was adjusted to match `USB\VID_3346&PID_1009`
- the driver package was rebuilt for local installation
- the package was signed with a local test certificate
- a single launcher, `driver-tool.cmd`, was added for install/remove operations

## Why This Installer Is Useful

The main goal of this package is simple installation on a normal Windows system.

With `driver-tool.cmd`:

- you do not need to run `bcdedit /set testsigning on`
- you do not need to boot Windows in Test Mode
- the required certificate is installed automatically during setup
- install and removal work from one menu out of the box

## Usage

Run:

```bat
driver-tool.cmd
```

Menu actions:

- `1` show driver status
- `2` install the driver with UAC elevation
- `3` remove the driver with UAC elevation
- `4` export the current signer certificate

## Files

Main package files:

- `driver-tool.cmd`
- `nanokvm_usb_graphic.inf`
- `nanokvm_usb_graphic.cat`
- `nanokvm_usb_graphic.dll`
- `tools/driver-tool.ps1`
- `tools/install-driver-elevated.ps1`
- `tools/remove-driver-elevated.ps1`
- `cert/nanokvm_usb_graphic-test.cer`

## Important

- this package is intended for local/manual installation on Windows
- this is a modified package, not the untouched official Sipeed release asset
- the signing certificate is a local test certificate, not a production WHQL signature
