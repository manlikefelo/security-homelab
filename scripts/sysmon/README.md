# Sysmon config note

This folder deliberately does **not** vendor the Sysmon config XML. Instead,
[`install-sysmon.ps1`](install-sysmon.ps1) downloads the community-standard
**SwiftOnSecurity `sysmonconfig-export.xml`** at install time from:

<https://github.com/SwiftOnSecurity/sysmon-config>

Why reference rather than commit:
- It's actively maintained upstream — pinning a stale copy here would rot.
- It keeps this repo free of large third-party files.

If you need **offline/air-gapped** installs, download `sysmonconfig-export.xml` and
`Sysmon.zip` ahead of time and point the script's `-ConfigUrl`/`-SysmonUrl` (or a
local path) at them.
