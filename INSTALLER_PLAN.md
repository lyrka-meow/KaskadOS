# KaskadOS Installer: architecture and acceptance contract

This document is the persistent source of truth for the installer redesign. It exists so that implementation decisions do not depend on chat history.

## Decision

KaskadOS will own the installer UI, development preview and visual system. Calamares remains the installation engine.

We will not rewrite disk discovery, partition planning, encryption, mounting, filesystem creation, bootloader installation, user creation or the execution queue from scratch.

The current approach of rebuilding upstream QWidget pages in place is retired. UI code must not be spread through unrelated Calamares pages.

## Target structure

```text
components/kaskad-installer/
  ui/          shared QML pages, controls and design tokens
  preview/     unprivileged desktop preview with deterministic fake data
  calamares/   narrow adapters between the shared UI and Calamares modules
  tests/       interaction, layout, navigation and screenshot tests
```

The preview and production installer must load the same UI files. They differ only in their data provider:

- preview provider: deterministic fake disks, validation results, errors and progress;
- production provider: Calamares module configuration and validated installation state.

Calamares already provides supported integration points through `QmlViewStep`, external QML search paths and the QML variants of users, locale, keyboard, summary and finished modules. These should be used instead of hiding and reparenting controls from existing QWidget forms.

## Partitioning boundary

Partitioning is not currently a clean headless Calamares API. Planning logic is split between `PartitionCoreModule`, `Config`, `PartitionViewStep`, `ChoicePage` and the job implementations.

Therefore:

1. The real Calamares partition step remains functional during migration.
2. Manual partitioning remains the upstream implementation until its scenarios are covered by VM tests.
3. A narrow partition adapter is prototyped before the final disk-page design is accepted.
4. The custom disk page may display only data returned by that adapter and may submit only a validated plan.
5. Selecting a disk never starts installation and never jumps directly to summary.

## Current implementation defects to remove

- `UsersPage.cpp` hides the original form, clears its layout, reparents selected controls and rebuilds the page around them.
- The page uses fixed geometry (`1012`, `650`, `360`, `115`, `62`) and cannot adapt reliably.
- The start page scans `/sys/block` independently from Calamares' partition device model.
- `ViewManager::goToStep()` calls `onLeave()`, but bypasses normal `isNextEnabled()` / `isAtEnd()` sequencing and can skip intermediate modules.
- Quick install passes a raw device name through `GlobalStorage`, prepares erase mode and jumps to summary asynchronously.
- Page-local navigation and shell navigation both exist, so navigation has two owners.
- Preview-only branches change production partition behavior instead of replacing the provider.
- Preview settings omit summary although quick install attempts to navigate there.

## Installer flow

1. Language and accessibility
2. Region, time zone and keyboard
3. User account and device name
4. Disk, installation mode and encryption
5. Optional appearance selection
6. Review, including an explicit disk-change summary
7. Installation progress, with logs available on demand
8. Finish: restart or continue the live session

There is one navigation owner: the installer shell.

- Pages do not create their own Back, Continue or Install buttons.
- Install appears only on the review page.
- Forward navigation must pass the active module's validation.
- Completed earlier steps may be reopened for correction.
- Destructive disk changes require an explicit review showing device path, model, size, current layout and proposed layout.

## Layout contract

- No page-sized fixed width or height.
- Content fills the space between the shared header and shared navigation footer.
- Content may have a maximum width near 1120 px, but never a mandatory width.
- Two columns are allowed at 1200 px and above; narrower windows use one column and page-local scrolling.
- Primary navigation remains visible at 1280x720.
- Spacing uses only 4, 8, 12, 16, 24 and 32 px steps.
- Outer margins adapt between 24 and 48 px.
- Russian and English text must wrap without clipping.
- Required scale checks: 100%, 125%, 150% and 200%.

## Interaction contract

- Minimum pointer target: 44x44 px; primary actions should be at least 48 px high.
- The whole visible control is clickable.
- Every action has normal, hover, pressed, keyboard-focus, disabled and busy states.
- Tooltips never intercept pointer input.
- Invisible overlays may not cover enabled controls.
- One click triggers exactly one action.
- All actions are reachable with Tab and activatable with Enter or Space.
- Focus order follows visual reading order.

## Fast development loop

UI work does not require an ISO build.

1. Pure QML changes: run the standalone preview directly.
2. Adapter or Calamares C++ changes: incrementally rebuild only the Calamares component.
3. Run interaction and geometry tests offscreen and in the nested installer compositor.
4. Run real partition and installation tests only in a disposable VM using temporary qcow2 disks.
5. Build a complete ISO only when live-session integration, packaging or boot behavior changes, and at release checkpoints.

The existing `make calamares-preview` is transitional. Its current partition hooks and fake execution path must not be treated as proof that production behavior works.

## Automated checks required

- startup and page-loading test;
- navigation contract test with valid and invalid state;
- mouse click test at the visual center of every enabled control;
- Tab, Enter, Space and focus-order test;
- geometry assertions at 1280x720, 1366x768 and 1920x1080;
- scale-factor runs at 1.0, 1.25, 1.5 and 2.0;
- Russian and English runs;
- screenshot artifacts for review, backed by structural assertions rather than pixel-only comparison;
- fake disk scenarios: no disks, one empty disk, two disks, existing OS with free space, too-small disk, encrypted disk and read failure;
- VM scenarios: BIOS, UEFI, erase, encryption, alongside, manual partitioning and bootloader installation.

## Desktop layout editor contract

Right-click on a panel is only an optional shortcut, never the primary entry point.

Primary visible entry points:

- `Configure interface` in the system/control-center menu;
- `Edit interface` on the personalization settings page.

Edit mode covers the whole interface. A normal left click selects a panel, dock or widget. A compact contextual toolbar appears next to the selected object and offers move, configure, duplicate when supported, and delete. It must flip sides when space is insufficient and must not cover the selected object.

The persistent command bar contains only Add, Undo, Redo, Discard and Done. Import and Export live under an overflow menu. Add opens a side catalog instead of another floating toolbar.

Placement, ordering, add/remove and per-screen assignment exist only in edit mode. Global appearance and behavior remain in Settings. Both surfaces must call the same underlying inspector rather than duplicate settings.

Edit mode is transactional: entering creates a snapshot, Undo/Redo operate on the draft, Done commits, and Discard restores the snapshot.

## Implementation order

1. Preserve the current work and establish tests around known behavior.
2. Create the standalone shared-QML preview with fake providers.
3. Implement the shell and one owner for navigation.
4. Move locale, keyboard and users to supported QML-backed Calamares modules.
5. Prototype and test the partition adapter before finalizing the disk UI.
6. Remove quick jumps, duplicate disk discovery and preview branches from production modules.
7. Integrate summary, progress and finish pages.
8. Run disposable-VM installation scenarios.
9. Build and validate a full ISO at the checkpoint.

No UI mockup is accepted merely because it renders. A page is complete only when its states, validation, navigation, keyboard access and automated click tests pass.
