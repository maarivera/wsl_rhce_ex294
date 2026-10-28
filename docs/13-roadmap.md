# 13. Two-week RHCE preparation plan

**Assumes:** RHCSA-level Linux skills, ~3 hours on weekdays, ~5 hours on weekends.
**Rule:** every day ends with `rhcelab reset` and a short written note of what you
had to look up. Tomorrow starts by redoing those items from memory.

## Week 1 - Foundations to intermediate

| Day | Topics | Exercises | Repetitions | Done when |
|---|---|---|---|---|
| 1 | Lab tour, inventory, `ansible.cfg`, ad-hoc commands | B01-B05, B19 | B01 ×3 from an empty workspace (`rhcelab reset --workspace`) | B01 in < 5 min without notes |
| 2 | Playbook structure, files, packages, services, users, groups | B06-B10 | B08-B10 as one playbook ×2 | `rhcelab practice B` all green |
| 3 | Variables, facts, magic variables, `lineinfile`/`copy`, firewalld, cron | B11-B18, B20 | B12 and B15 ×2 | can explain `group_names`, `hostvars`, `inventory_hostname` |
| 4 | Loops, conditionals, registered variables, `changed_when`/`failed_when` | I01-I04, I12 | I03, I04 ×2 | no `{{ }}` inside `when` |
| 5 | Handlers, templates, Jinja2 loops over hostvars, group_vars | I05-I07, I10, I20 | I07 ×3 | `/etc/lab-hosts` from memory |
| 6 | Vault, tags, block/rescue/always, delegation | I08, I09, I11, I13, I19 | I09 ×2, I13 ×2 | vault create/edit/view/rekey without `--help` |
| 7 | Storage, repositories, SELinux contexts, cron files + **review** | I14-I18; redo every failed task of the week | full `rhcelab practice B,I` | ≥ 90% of B and I tasks green on first try |

## Week 2 - RHCE level and exam simulation

| Day | Topics | Exercises | Repetitions | Done when |
|---|---|---|---|---|
| 8 | Roles: structure, defaults vs vars, handlers in roles; Galaxy requirements | R01, R08, R09 | R01 ×2 (from `ansible-galaxy role init`) | role apache in < 15 min |
| 9 | RHEL system roles, SELinux module, assertions | R02, R03, R13 | R02 ×2 using only `/usr/share/doc/rhel-system-roles` | no copy-paste from the internet needed |
| 10 | LVM with fallback logic, facts-driven reports | R04, R05, R15 | R04 ×3 (the classic `lv.yml`) | handles all 3 cases (fits / too small / no VG) |
| 11 | Users from vaulted lists, vault IDs, hostvars | R06, R07, R16 | R06 ×2 | `selectattr` + `password_hash` from memory |
| 12 | Services end-to-end, downloads, sysctl, fetch/run_once | R10-R12, R14, R17-R19 | R11, R18 ×2 | services survive `wsl --terminate` + `rhcelab up` |
| 13 | **Mock exam #1** (4 h, timed) + review | `rhcelab exam-start` → mock exam → `rhcelab grade` | redo every lost task twice | ≥ 210 / 300 |
| 14 | Integration, speed, **mock exam #2** | R20 in the morning; mock exam again in the afternoon, without notes | - | ≥ 270 / 300 in < 3 h |

### Daily routine (example 3-hour weekday)

| Time | Activity |
|---|---|
| 0:00-0:20 | Redo yesterday's "had to look up" list from memory |
| 0:20-0:50 | Read `ansible-doc` for today's modules; write snippets in `~/notes.yml` |
| 0:50-2:30 | Today's exercises; check each with `rhcelab practice <ID>` |
| 2:30-2:50 | Repetitions from an empty workspace |
| 2:50-3:00 | `rhcelab reset`; write the "had to look up" list |

## Recommended lab repetitions

| Drill | Target | Frequency |
|---|---|---|
| `ansible.cfg` + inventory from scratch | < 5 min | daily |
| Repositories (ad-hoc and playbook) | < 5 min | every other day |
| Role skeleton with handler + template | < 15 min | 3× in week 2 |
| `lv.yml` with block/rescue | < 10 min | 3× |
| Users from list + vault | < 15 min | 3× |
| hosts.j2 loop over `groups['all']` | < 5 min | 3× |
| Full mock exam | < 3 h, ≥ 270 points | 2× (days 13 and 14), more if possible |

## Readiness criteria

You are ready to book the exam when:

- [ ] `rhcelab practice all` passes on a fresh run, done from memory
- [ ] Two mock exam runs ≥ 270 / 300, each in under 3 hours
- [ ] You can find any module's options with `ansible-doc` in under a minute
- [ ] You can explain *why* each mock exam solution works (variable precedence,
      fact scope, handler timing, delegation context)
- [ ] You have practised SELinux booleans/ports and reboots on a real Rocky/RHEL VM
      (the only exam objectives WSL2 cannot run)

## Exam-day strategy (summary)

1. Read everything first (15 min). 2. `ansible.cfg`, inventory, repos. 3. Quick wins.
4. Run and verify each playbook immediately. 5. Skip after 5 minutes stuck.
6. Re-run everything in the last 30 minutes. 7. Never break SSH or sudo.
Details: [12-exam-tips.md](12-exam-tips.md).
