# Site plan and build log (project `AGENTS.md`)

Write these sections into the **project's** `AGENTS.md` (below the managed bolt-skills block).
Every session starts by reading them; every gate updates them. The intake IDs (E1, S3, O6 …)
refer to `intake.md`.

```markdown
## Site plan
<!-- bolt-build: decisions every phase depends on. Approved at Checkpoint 0 on <date>. -->

### Environment
- Project: new from bolt/project | existing; Bolt <version>; database SQLite (Bolt default .env), set up without fixtures   (E1)
- Local URL (BOLT_BASE_URL): https://127.0.0.1:8000, started with `symfony serve -d`         (E4)
- Hosting: Apache, document root = public/ | project root | Nginx; Docker: no | yes            (E5, E6)
- Domain: example.cz; staging: —  → SYMFONY_TRUSTED_HOSTS='^(www\.)?example\.cz$'           (E7)
- Deployment: SFTP upload | git pull | CI; admin access: open | IP allowlist | basic auth   (E11, E12)
- Theme folder: <theme>                                                                       (E8)
- CI: GitLab | GitHub Actions | none; commits after every gate, push: no                      (E9, E10)

### Languages
- Default: cs; secondary: en; translations: agent drafts, operator reviews                    (S1, S2)

### Design
- Source: Figma <url> | Pencil <path.pen> | images <folder> | existing site <url> | brief      
- Breakpoints in the design: 1440, 375; missing mobile layouts adapted by the agent           (D1)
- Fonts: <family> (licence, WOFF2 source); logo: <files>; icons: <set>                        (D2, D3, D5)
- Fidelity: close match, screenshot-checked                                                   (D6)
- Notes and reference screenshots: var/bolt-build/design/

### Structure
- Menu profile: landing | catalog | conditional                                               (S4)
- Pages and URLs (per locale):
  - / (homepage) — sections: #o-nas, #sluzby, #reference, #kontakt
  - /sluzby/{slug} — services listing + detail
  - /zasady-ochrany-osobnich-udaju — static (bolt-cookie-consent)
- ContentTypes:                                                                               (S5)
  - homepage — singleton, routable; fields: …
  - settings — singleton, viewless; fields: …
  - services — listing, routable; fields: …
- Static pages (TemplateController routes): /zasady-ochrany-osobnich-udaju, …
- Features: gallery no, downloads no, carousel yes, catalog no, articles no                   (S6)
- Forms: contact form via <solution>                                                          (S7)
- Content: <source>; images: <source>; entered by: agent | operator                           (S8–S10)
- Error-page metaphor: <object or scene>                                                      (S11)

### Operator, privacy, tracking
- Contact (theme.yaml contact:): name, IČO, address, e-mail, phone, hours, bio; socials       (O1)
- Tracking: Google Ads <id|[DOPLNIT]>, GA4 <id>, Sklik <id>; Consent Mode basic               (O2, O4, O9)
- Embeds: YouTube                                                                             (O3)
- Privacy: controller model single; controllers …; purposes web_operation, contact_form, …   (O5–O8)
- API consumers: none → disable fully                                                         (O10)
- SEO: site title, default description, sharing image; llms.txt description                 (O11, O12)

### Autonomy
- Checkpoints: 0 only | 0 and 5 | every gate; failing gate: 3 attempts, then Open issues      (A1, A3)
- Allowed without asking: composer, npm, bin/console, database setup                         (A2)
- Parallel agents: no | yes                                                                  (A4)

### Expected verification warnings
- bolt-runtime-extensions: FileSizeExtension removed (no downloads)
- …

## Build progress
<!-- bolt-build: one row per phase; update at every gate. The next session resumes at the first row that is not "done". -->

| Phase | Status | Commit | Notes |
| :--- | :--- | :--- | :--- |
| 0 Intake & site plan | done | — | approved <date> |
| 1 Environment & security | not started | | |
| 2 Web server & caching | not started | | |
| 3 Extensions & runtime PHP | not started | | |
| 4 Theme, layout shell, tokens | not started | | |
| 5 Content model & navigation | not started | | |
| 6 Templates & features | not started | | per page: built / visual QA rounds |
| 7 Content, translations, build | not started | | |
| 8 QA & sign-off | not started | | |

Status: not started · in progress (step) · done · done with open issues · blocked (reason).

## Decisions log
<!-- Every choice the agent made without asking: the default it applied, or a judgement call. -->
- <date> Phase 4: `--breakpoint-menu` set to 64rem — design shows the burger menu below 1024 px. (judgement)
- <date> Phase 5: `services.excerpt` added — cards show 2 lines of text not present on the detail page. (judgement)
- <date> Round 3 D4: hover states derived from accent-hover — default, not confirmed.

## Open issues
<!-- Problems the agent could not solve; each with what was tried and what is needed. -->
- [ ] Phase 6: /sluzby listing differs from the design at 375 px (cards 1 column vs. 2) — screenshot var/bolt-build/qa/sluzby-375.png. Needs: confirm intended layout.

## Handover — questions for the operator
<!-- Every [DOPLNIT] left in theme.yaml, catalogs or content, and every unconfirmed default. -->
- [ ] theme.yaml privacy.controllers.0.registry — zápis v obchodním rejstříku
- [ ] Google Ads conversion ID and label
```
