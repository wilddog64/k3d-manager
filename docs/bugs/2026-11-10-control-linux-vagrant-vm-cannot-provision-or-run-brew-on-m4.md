# Bug: control-linux Vagrant VM cannot provision, and Homebrew crashes in it on the M4

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-10 (WIP 3/3)
**Introduced by:** `4bd764b9` (v1.43.15, `scripts/etc/machine/vagrant/control-linux/Vagrantfile`)
**Should have been caught by:** live check (the Vagrantfile was never run end to end before E3)
**Prior art:** `make find-similar-docs` not run (vector store unreachable from the M4, 2026-11-10); exact-slug glob: none
**Severity:** test harness only. The control-node live check E3 cannot run as documented; it needs two manual workarounds.
**Approval:** operator, 2026-11-10: "go ahead to file P3 and dispatch to Luna"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** "go ahead for your two suggestions"
**Dispatch:** operator go 2026-11-10 ("dispatch to Luna"), `--agent codex --model gpt-6-luna`, slug `control-linux-vagrant-m4`; waits for intent approval and a WIP slot
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
