# Installation reporting groundwork

OpenClaw hosted setup can store an owner-created Agent Passport installation
handoff after the plugin is listed and the existing hosted smoke check succeeds.
Set `APORT_INSTALLATION_HANDOFF_FILE` to the path of the handoff JSON file before
running setup. The file must be owned by the current user, be a regular file
without additional hard links, and have no group or other permissions. Its
reporter endpoints must match the configured API origin. Keep the file private:
setup reads it but does not delete it.

The protected APort directory stores only the installation ID and reporter token
in the binding record. A fingerprint of the framework, passport ID, and server
origin determines the record name. A different identity cannot reuse an
installation already bound in that directory. An existing identity can accept a
rotated token for the same installation only when `APORT_INSTALLATION_ROTATE=1`
is explicitly set; a different installation ID is refused.
A concurrent or stale binding lock prevents changes until it is resolved.

This is incomplete integration: setup does not yet send an installation receipt,
and the plugin, other adapters, mode changes, resets, and enterprise scripts do
not yet report installation evidence. Setup reports a valid existing binding as
unverified, an absent binding as not configured, and unsafe or unreadable state
as unresolved. Do not use the stored binding as proof of a connected installation.
