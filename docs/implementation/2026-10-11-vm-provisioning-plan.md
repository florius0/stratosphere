# VM provisioning implementation plan

**Goal:** Declare ordinary guest provisioning in Nix, excluding MDM/permission management, and rename the VM preparation interface/data.

- [x] Add guest declarations/generated script and behavioral checks in `nix/vm-guest.nix` and `nix/vm-guest-tests.nix`, using native command readbacks and isolated execution guards.
- [x] Add `nix/vm-provisioning.nix` to compose internal image setup, runtime credentials, bounded owned boot, SSH provisioning, key-only/GUI verification and owned cleanup. Test failure and interruption behavior through synthetic boundaries.
- [x] Rename command/check/data namespaces to vm-provisioning, migrate the existing ignored source/key/receipt records without rebuilding any image, and preserve historical evidence.
- [x] Update README/testing/environment/verification documents; keep manual permission gates explicit and source credentials outside the store.
- [x] Run `nix flake check`, Python-free docs checks, final review and actual provisioning of the retained template. Verify idempotent rerun and no restored clean image.

Work continues in the existing checkout to preserve all accepted tooling changes and uncommitted product documents. No commits, MDM enrollment, permission edits or host-user settings changes are authorized by this task.
