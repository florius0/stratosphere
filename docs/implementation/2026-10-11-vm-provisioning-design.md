# Declarative VM provisioning

The user approved guest provisioning through Nix on 2026-10-11, excluding MDM and permission grants, with the VM preparation command/data renamed to provisioning. Keep only necessary logic: Nix declares the pinned image, account, SSH key placement, automatic login and test-session settings; generated Bash performs runtime host/guest effects.

The implementation files now live under `nix/features/vm/`, composed by independent modules under `nix/modules/vm/`; see the [feature-module revision](2026-10-11-feature-modules-plan.md). The original file locations below describe the initial implementation.

## Scope and authority

NFR-01 and NFR-09 require pinned tools, macOS 26 Apple Silicon and truthful isolated verification. The existing testing approach requires dedicated guest access, active GUI login and persistent permission-aware paths. This change provisions the isolated test template; it never changes host accounts, host settings, SIP, TCC, Accessibility grants or MDM enrollment. Existing guest passwords are not reset. The deleted clean image is not recreated automatically.

The pinned vanilla image provides the bootstrap `admin` account, SSH and passwordless sudo. Provisioning verifies that contract, ensures the declared account/home/shell and installs the dedicated public key. It configures automatic login and idle sleep/screensaver settings using macOS-native tools, and verifies key-only SSH and GUI session readiness. Existing permissions stay separate and are checked by the native probe during E2E.

## Structure and interface

- `nix/vm-images.nix` retains image declarations and the internal image/adoption step.
- `nix/vm-guest.nix` declares guest settings and generates a portable native macOS script. It rejects execution outside VirtualMac before mutations and requires privileged execution inside the guest.
- `nix/vm-provisioning.nix` composes image management, credential bootstrap, owned VM boot, bounded SSH application/readback, reboot when required, and owned shutdown. `nix run .#vm-provisioning -- prepared` reconciles the guest. The clean profile performs image configuration only; explicit adoption remains available.
- Runtime SSH keys and login credentials stay outside the Nix store under `.local/vm-provisioning`, or caller-selected credential paths. Only the public key is sent to the guest. The vendor image's published initial password is a bootstrap default, overridable by a runtime password file.
- Preserve the adopted image record while migrating to `$TART_HOME/stratosphere-provisioning/`; save guest provisioning results separately from the image specification and permission qualification.

No guest Nix, Xcode, SDK, extra guest agent or unrelated software is required. Provisioning works in place on a stopped managed image; it does not clone/download another image for verification. Unexpected failures retain logs and stop only the VM boot owned by this invocation, without deleting the template or claiming success.

## Verification

Behavioral checks use synthetic native/Tart/SSH boundaries to cover host refusal, key preservation/idempotency, password privacy, native failure/readback, boot/application/reboot/cleanup and failed readiness. Run Nix checks and documentation validation. Exercise the generated provisioning on the retained prepared VM using its existing dedicated key; record actual outcomes without treating synthetic tests as native feasibility evidence.
