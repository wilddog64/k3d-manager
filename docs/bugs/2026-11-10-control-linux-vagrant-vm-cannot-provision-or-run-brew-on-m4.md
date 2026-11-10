# Bug: control-linux Vagrant VM cannot provision, and Homebrew crashes in it on the M4

**Status:** OPEN — E2 FAILED 2026-11-10 on `dfb29052` (landed fix `4cf6a95b` incomplete: flags dropped by grub, Ansible targets no host); fix proven live, see "E2 failure"
**Priority:** P3
**Waiting on:** fix running — since 2026-11-10 (correction round, Flash, slug `control-linux-vagrant-m4-r2`; same intents M1, M2, N1, N2)
**Introduced by:** `4bd764b9` (v1.43.15, `scripts/etc/machine/vagrant/control-linux/Vagrantfile`)
**Should have been caught by:** live check (the Vagrantfile was never run end to end before E3)
**Prior art:** `make find-similar-docs` not run (vector store unreachable from the M4, 2026-11-10); exact-slug glob: none
**Severity:** test harness only. The control-node live check E3 cannot run as documented; it needs two manual workarounds.
**Approval:** operator, 2026-11-10: "go ahead to file P3 and dispatch to Luna"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "go ahead for your two suggestions"
**Dispatch:** operator 2026-11-10: "when allow, please dispatch this to Flash 3.8" (confirmed: P3 to Flash, P2 stays on Luna), `--agent agy --model gemini-3.8-flash-medium`, slug `control-linux-vagrant-m4`; next free WIP slot
**Filed:** 2026-11-10
**Detected by:** Claude, 2026-11-10, live E3 of `docs/plans/v1.43.15-control-node-linux.md`
**Branch:** `k3d-manager-v1.43.15`
**Release:** v1.43.15

## Symptom and proof (M4, VirtualBox 7.2.22, Vagrant 2.4.9, box `bento/ubuntu-24.04` 202502.21.0 aarch64, kernel 6.8.0-53, 2026-11-10)

1. **Provisioning fails before the role runs.** `vagrant provision` with `ansible.install_mode = "pip"`:
   `error: externally-managed-environment` (PEP 668, Ubuntu 24.04 Python 3.12), rc 1, twice. Workaround that worked:
   `apt-get install -y ansible-core` (2.16.3) in the VM, then `ANSIBLE_ROLES_PATH=/vagrant ansible-playbook -i
   tests/inventory -c local -e homebrew_user=k3dm-control -e provision_homebrew_scope=prereqs tests/playbook-prereqs.yml`:
   run 1 `changed=3 failed=0`, run 2 `changed=0 failed=0`. (`ansible.cfg` in the vboxsf share sets `roles_path = ..`; a
   world-writable directory makes Ansible ignore it, hence the env var.)
2. **Homebrew's portable Ruby dies with SIGILL.** The pinned installer runs, then `Pouring
   portable-ruby-4.0.9.arm64_linux.bottle.tar.gz` → `Illegal instruction (core dumped)` → `Failed to install ruby 4.0.9!`.
   The guest `/proc/cpuinfo` lists `sve2` and `sme`/`sme2`; the M4 has SME but no SVE outside streaming mode. Probe: a C
   program running one `rdvl` (SVE) instruction, `gcc -march=armv8-a+sve`, exits 132 (SIGILL); a plain `int main(){return 0;}`
   exits 0. After adding `arm64.nosve arm64.nosme` to `GRUB_CMDLINE_LINUX_DEFAULT`, `update-grub` and a reboot,
   `/proc/cmdline` carries both flags, `/proc/cpuinfo` lists no `sve`/`sme` feature, and `brew --version` prints
   `Homebrew 7.0.13`. (Setup then stops on `docs/bugs/2026-11-10-machine-setup-linux-exits-on-first-missing-formula.md`.)

## Fix

In `scripts/etc/machine/vagrant/control-linux/Vagrantfile`:

1. `ansible.install_mode = "default"` (Ubuntu's `ansible-core`), and `ANSIBLE_ROLES_PATH` set for the provisioner
   (`ansible.extra_vars` cannot; use `ansible.galaxy_roles_path` or an env setting the provisioner supports, proven in
   the run), so the role resolves from `/vagrant`.
2. A shell provisioner that runs **before** the Ansible one: add `arm64.nosve arm64.nosme` to
   `GRUB_CMDLINE_LINUX_DEFAULT` when absent, `update-grub`, and reboot (or `vagrant reload` documented as one step).
   Only when `uname -m` is `aarch64`.
3. `docs/howto/machine-setup.md` "Linux control node": the VM sequence as it now runs, and why the kernel flags.

The E3 `/etc` checks (`/etc/sudoers`, `/etc/profile`, `/etc/zshrc`) are unaffected: the grub edit touches only
`/etc/default/grub`, VM-only.

## E2 failure (Claude, M4, 2026-11-10, on `dfb29052`; Vagrant 2.4.9, VirtualBox 7.2.22, box 202502.21.0)

`vagrant up --no-provision`, `vagrant provision`, `vagrant reload`, `vagrant provision`. Log:
scratchpad `control-e3/run.log` and `provision1.log`. Two defects, both live-proven:

1. **Kernel flags never reach the kernel (spec defect: item 2 above named the wrong variable).** The shell step ran
   and `update-grub` succeeded, but after reload `/proc/cmdline` ends at `autoinstall ds=nocloud-net` and
   `/proc/cpuinfo` still lists `sme2 sve2`. bento's `GRUB_CMDLINE_LINUX_DEFAULT` is
   `"autoinstall ds=nocloud-net;s=http://10.0.2.2:8237/ubuntu/"`; the generated `grub.cfg` line 170 is
   `linux /vmlinuz-... ro net.ifnames=0 biosdevname=0  autoinstall ds=nocloud-net;s=http://... arm64.nosve arm64.nosme`,
   and grub ends the `linux` command at the unquoted `;`, so everything appended after it is dropped.
   **Proven fix:** put the flags at the start of `GRUB_CMDLINE_LINUX`, which grub emits before DEFAULT. Live probe in
   the same VM: `GRUB_CMDLINE_LINUX="arm64.nosve arm64.nosme net.ifnames=0 biosdevname=0 "`, `update-grub`,
   `vagrant reload` → `/proc/cmdline` = `... ro arm64.nosve arm64.nosme net.ifnames=0 biosdevname=0 autoinstall ds=nocloud-net`,
   and no sve/sve2/sme/sme2 in `/proc/cpuinfo`.
2. **Ansible targets no host.** `[WARNING]: Could not match supplied host pattern, ignoring: default` then
   `[ERROR]: Specified inventory, host pattern and/or --limit leaves us with no hosts to target.` The role repo's
   `tests/inventory` (provision-homebrew `845eaef`) lists only `localhost`, and Vagrant 2.4.9 passes
   `--limit=<machine name>` unless `ansible.limit` is set (`plugins/provisioners/ansible/provisioner/base.rb:159-164`
   in `/opt/vagrant/embedded/gems/gems/vagrant-2.4.9`). **Proven fix:** `ansible.limit = "all"`. Live probe:
   `sudo ansible-playbook -i tests/inventory -c local --limit all tests/playbook-prereqs.yml` → `failed=0`.

Also observed: `install_mode = "default"` on Ubuntu installs ansible-core `2.21.5-1ppa~noble` from the Ansible PPA,
not Ubuntu's archive. Not pip, so N1 holds; the how-to should say "Ansible PPA", not "Ubuntu's ansible-core".

### Correction round (same intents M1, M2, N1, N2; E1 strengthened)

- Vagrantfile: flags at the start of `GRUB_CMDLINE_LINUX` (still aarch64-guarded, still idempotent via the
  `arm64.nosve` grep); `ansible.limit = "all"`.
- `control_linux_vagrant.bats`: fail if the flags are written to `GRUB_CMDLINE_LINUX_DEFAULT`, or if `ansible.limit`
  is unset while `inventory_path` is set. Red on `4cf6a95b`'s Vagrantfile.
- How-to: "Ansible PPA"; one line on why the flags go in `GRUB_CMDLINE_LINUX`.
- How-to VM sequence: `make test` runs in k3dm-control's own clone
  (`~/src/gitrepo/personal/k3d-manager`, after `git checkout <release branch>`), not in `/vagrant/k3d-manager`. Probe:
  `/vagrant/k3d-manager` is the host's synced folder owned by `vagrant`, and `make test` there exits at once with
  `scratch/test-logs/all/...log: Permission denied`. `make machine-setup` from `/vagrant/k3d-manager` is fine (it only
  reads the tree).

Probe of the rest of E3 in the same VM after the two manual fixes (scratchpad `control-e3/run2.log`): role rerun
`changed=0`; `/etc/sudoers` and `/etc/profile` sha256 unchanged, `/etc/zshrc` absent before and after; k3dm-control
`groups=1001(k3dm-control)`, "not allowed to run sudo"; prefix `k3dm-control 755`; `make machine-setup ROLE=control`
rc 0 with every Linux formula installed, both repos cloned (https remotes, no credential), macOS steps
`skipped (linux)`; `make machine-check ROLE=control` all ok; Homebrew 7.0.13, shellcheck 0.11.0 (M4: 0.11.0),
Bats 1.14.0; no `~/.ssh` before or after.

### Correction round: worker definition of done

- Read the "E2 failure" and "Correction round" sections above; change only the three files in the Files table.
- Do not run Vagrant or VirtualBox. Show `bats scripts/tests/bin/control_linux_vagrant.bats` green, then red with
  each mutant: flags written to `GRUB_CMDLINE_LINUX_DEFAULT` (today's line), and `ansible.limit` removed. Paste
  command, rc and proving lines for each. `ruby -c` the Vagrantfile. Leave changes uncommitted; Claude reviews,
  lands and reruns E2.

## Files

| File | Change |
|---|---|
| `scripts/etc/machine/vagrant/control-linux/Vagrantfile` | provisioner install mode, roles path, SVE/SME kernel flags |
| `docs/howto/machine-setup.md` | VM sequence |
| `scripts/tests/bin/machine_setup.bats` or a new small bats file | static checks below |

## Contract readers

None outside the VM: the Vagrantfile is read only by `vagrant` in `scripts/etc/machine/vagrant/control-linux`
(`git grep -n control-linux`, 2026-11-10: the how-to and the plan). Hostinger (x86_64) is not affected.

## Acceptance

```yaml
must:
  - id: M1
    text: "vagrant up on the M4 provisions the VM with the prereqs role without a manual Ansible install; a second vagrant provision reports changed=0."
  - id: M2
    text: "On an aarch64 guest the kernel boots with arm64.nosve and arm64.nosme before Homebrew is installed, so brew --version works for k3dm-control."
must_not:
  - id: N1
    text: "The Vagrantfile never installs Ansible with pip."
  - id: N2
    text: "The kernel-flag step never runs on a non-aarch64 guest and never edits /etc/sudoers, /etc/profile or /etc/zshrc."
evidence:
  - {id: E1, proves: [N1, N2], kind: offline, intent: "You will see a bats test read the Vagrantfile and fail if install_mode is pip, if the shell provisioner is missing or runs after Ansible, or if the grub step is not guarded by aarch64; it fails on today's Vagrantfile."}
  - {id: E2, proves: [M1, M2], kind: live, intent: "Claude runs vagrant destroy, vagrant up on the M4, and sees the role run twice (changed=0 on the second), /proc/cmdline with both flags, and brew --version as k3dm-control."}
interface:
  - "scripts/etc/machine/vagrant/control-linux/Vagrantfile"
  - "vagrant up / vagrant provision from that directory"
```

## Worker definition of done

- Do not run Vagrant or VirtualBox (Claude runs E2). Static test only, shown red on today's Vagrantfile; mutant shown red:
  set `install_mode = "pip"` back.
- `ruby -c` the Vagrantfile if Ruby is available; paste command, rc and proving lines. Leave changes uncommitted; Claude
  reviews and lands.
