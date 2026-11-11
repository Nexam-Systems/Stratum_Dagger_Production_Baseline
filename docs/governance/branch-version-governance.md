# [PINNED · GOVERNANCE] Stratum_Dagger_Production_Baseline — Branch, Version & Integration Governance

**Repo:** `Nexam-Systems/Stratum_Dagger_Production_Baseline` (GCS, public)
**Authority:** NXM-SW-GOV-001 · **Owner:** Eng Lead (ground), CEO sign-off
**Status:** STANDING — rules apply continuously.

These are the standing branch, version, and integration rules for this repository. The one-time work to bring the repo into compliance is tracked in the reconciliation issue in `dagger-integration` (#[B]).

## Repository

STRATUM is the ground control station for the Dagger Block-1 single-vehicle baseline. Related repos `Stratum-MVO-DAG` and `STRATUM-Desktop` are out of Block-1 scope and not governed by this freeze.

## Branch model

- **`main`** — the integrated, released configuration, and the only branch a freeze manifest may reference.
- **`flight_test`** — staging branch. `[CONFIRM]` Define explicitly: is `flight_test` a staging branch that promotes to `main` through a named gate, or a scratch branch to be collapsed? A staging branch that never promotes becomes an unmanaged second trunk — the failure this governance exists to prevent.
- **Feature / story branches** — one per issue (incl. `story/KAN-<n>`), named per the taxonomy; merged to `flight_test` for integration, promoted to `main` only through the gate.

### Promotion gate (`flight_test` → `main`) `[DEFINE]`
Name the conditions to promote: required reviewers, test evidence, version stamp, sign-off. No promotion without a named `main` owner.

### Branch naming (six-class taxonomy)
- `story/KAN-<n>` or `feature/issue-<n>-<slug>` — capability
- `fix/issue-<n>-<slug>` — defect fix
- `[CONFIRM]` remaining classes and prefixes per NXM-SW-GOV-001.

## Version alignment

- STRATUM carries an explicit Block version, reconciled with the PX4 firmware version across IF-1 (the contract-version gate, CI-GND-1, hard-gates STRATUM to compatible NEXAM firmware).
- `[CONFIRM]` Versioning scheme, tag convention, protected-branch rules.

## Build variants & bypass toggles

STRATUM produces two MSI builds (CI-GND-18):
- **Client MSI** — parameter access hidden (`STRATUM_DEV_BUILD` OFF).
- **Dev MSI** — parameters exposed (`STRATUM_DEV_BUILD` ON).

Rule: every enforcement-bypass toggle must be hidden in the Client MSI. Block-1 has two:
1. `ENG_GATE_EN` (engage-gate bypass, PX4 side).
2. Firmware-compat admin enforce/bypass toggle (CI-GND-1, PR#24, ground side).

Both are only fully locked when the Client MSI hides them and the GCS trust handshake (IF-5) blocks foreign ground stations. A third such toggle is not permitted without this discipline (R-15 / D-9).

## Standing engineering rules

- [ ] One branch per issue, conforming name.
- [ ] Features integrate on `flight_test`, promote to `main` only through the gate.
- [ ] `main` always represents a releasable, version-stamped configuration.
- [ ] Stale/behind branches (e.g. `story/KAN-8` at +3/−53) rebased or closed.
- [ ] Experimental branches (e.g. `KAN-17 / test-new-ui`) kept off-baseline until promoted to a CI.
- [ ] Default-credential and trust-boundary items (operator login `op1`; GCS handshake #7) carry a disposition.

## Current compliance gaps (rev 0.7)

Remediated via #[B]:
- `main` (`a3f42b6`) carries 3 CIs; `flight_test` (`a8aadfa`) is +46 ahead and un-promoted (R-13).
- No declared trunk status for `flight_test`; no `main` owner; no promotion gate (D-13).
- `story/KAN-8` (GND-6) stale at +3/−53.
- TGEO (#2) reopened — `main` trails the C12-expanded requirement (R-16); DESIG (#3) closed with no artifact (R-14).
