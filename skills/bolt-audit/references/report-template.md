# Audit report template

Write `AUDIT.md` into the report directory (next to `summary.md`). Keep the structure; drop
sections that are empty. Every finding must point to evidence (file and line, log line, HTTP
response) — no finding from a guess.

## Severity levels

| Level | Meaning | Examples |
| :--- | :--- | :--- |
| **Critical** | Security hole, legal exposure or data loss now | API or `.env` reachable, tracking before consent, no privacy policy |
| **High** | Visible bug or significant risk | dates shifting on save, wrong singleton record, unstyled components, thumbnails not cached |
| **Medium** | Works, but fragile, slow or inaccessible; convention deviation worth aligning | theme without Component/Container/Page structure, missing `hreflang`, contrast below AA |
| **Low** | Polish, maintainability | naming, leftover blueprint text, code style |
| **Info** | Observation, no action needed | optional extension not installed, deliberate deviation recorded in the site plan |

Effort: **S** (< 1 h), **M** (half a day), **L** (a day or more).

---

```markdown
# Audit: <project name>

<one paragraph: what was audited (commit, Bolt version, live or not), the overall state in one
sentence, and the three things to fix first>

| | Critical | High | Medium | Low | Info |
| :--- | ---: | ---: | ---: | ---: | ---: |
| Findings | 0 | 0 | 0 | 0 | 0 |

## Fix first
1. <finding title> — <skill> — effort <S/M/L>
2. …
3. …

## Skills

| Skill | Script | Assessment | Findings |
| :--- | :--- | :--- | :--- |
| bolt-timezone | PASS / WARN / FAIL / N/A | compliant · defects · deviation (convention not used) · not applicable | C0 H1 M0 L0 |
| … | | | |

## Findings

### C1 · <short title>  — Critical · <skill> · effort S
- **Where:** `path/to/file:42` (or URL / log line)
- **What:** what is wrong, in one or two sentences.
- **Why it matters:** the rule it breaks — skill section or requirement ID (e.g. bolt-cookie-consent CB-01).
- **Fix:** the concrete change, or the skill step / scaffold command that makes it (`bolt-disable-api` § 1).

### H1 · …

## Deviations from the skills' conventions
One line per skill that is built differently but works: what differs, and what aligning would cost
(or "keep — record in the site plan").

## Not checked
What the audit could not verify and why: live checks without `--base-url`, Apache rules against
a non-Apache server, questions for the operator (API consumers, Consent Mode decision, legal facts).

## Next steps
Which skills to run, in WORKFLOWS.md phase order, to fix the findings.
```
