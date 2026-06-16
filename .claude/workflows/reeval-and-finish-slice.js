export const meta = {
  name: 'reeval-and-finish-slice',
  description: 'Independently RE-EVALUATE the "v0.4 slice complete + every AC PROVEN" claim with mutation testing, then FINISH the auto-buildable slice-polish gaps + deferred LOW bugs + write VERIFICATION.md, then re-audit. Blocked-by-spec meta work is flagged, never invented.',
  phases: [
    { title: 'Preflight', detail: 'safety re-snapshot + real gate baseline' },
    { title: 'Re-eval', detail: 'parallel read-only: challenge each PROVEN verdict, propose mutation experiments' },
    { title: 'Mutate', detail: 'sequential mutation testing: flip impl, confirm the test goes RED, restore' },
    { title: 'Plan', detail: 'synthesize an ordered, buildable worklist; classify blocked-by-spec out' },
    { title: 'Complete', detail: 'sequential build: falsified-verdict fixes -> LOW bugs -> slice-polish features' },
    { title: 'Audit', detail: 'parallel read-only on the NEW work; each finding adversarially verified' },
    { title: 'Remediate', detail: 'fix confirmed findings sequentially, re-gate' },
    { title: 'Report', detail: 'regenerate spec-coverage.md + write VERIFICATION.md + reeval-report.md + final gate' },
  ],
}

const REPO = '/Users/nick/Documents/GitHub/Mining Game'

const CONTEXT = `Repo: ${REPO} (Godot 4.6.3, Rapier 2D NON-deterministic, gdUnit4 headless). The v0.4
slice is reportedly COMPLETE + audited (304 tests, both gates green, every slice AC PROVEN per
reports/spec-coverage.md). Your job is to INDEPENDENTLY re-verify that and FINISH remaining work.
READ FIRST when relevant: spec/SPEC.md (v0.4 + the v0.4.1 changelog), spec/VERTICAL_SLICE.md (its 0
salvage map + 1 scope), reports/spec-coverage.md (the AC->test matrix to be skeptical of),
CLAUDE.md (conventions + Audit discipline).
NON-NEGOTIABLE conventions:
- Tunables live in /data JSON (extend it; never hardcode balance). Pure logic in scripts/core/.
- v0.4: NO physics determinism, NO preview==actual; aim preview = initial arc to first bounce only;
  blast radius FUZZY via an INJECTED seeded RNG (fixed seed -> fixed; golden-pinned); FastNoiseLite
  coherent gen; NO lose state (free unlimited charge always in tray); dig ends by collecting the
  RELIC -> bank prestige (power growth); end_dig idempotent.
- Every test extends GdUnitTestSuite and cites the AC it covers. Do NOT rely on injected InputEvents
  (they do not fire headless). Golden files MUST fail on a missing pin. Structural claims must assert.
- "Green is necessary, not sufficient" -- a verdict only holds if a plausible bug would turn the test RED.
- SCOPE GUARD: this run FINISHES the polished slice. Do NOT build blocked-by-spec meta work (the full
  prestige TREE shape/costs, mine hub / buy-access roster+pricing+hardness curve, authored ending,
  narrative/reveal content). If a task needs a design decision not already in SPEC v0.4, STOP and FLAG
  it -- never invent it.
Gates (use Bash; must exit 0): tools/validate_data.sh ; tools/run_tests.sh tests
Single suite for the fast loop: tools/run_tests.sh tests/unit/test_NAME.gd or tests/integration/...`

// ---------- schemas ----------
const VERIFY = {
  type: 'object', additionalProperties: false,
  required: ['data_gate_pass', 'test_gate_pass', 'summary'],
  properties: {
    data_gate_pass: { type: 'boolean' }, test_gate_pass: { type: 'boolean' },
    total_cases: { type: 'integer' }, failures: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' }, raw_tail: { type: 'string' },
  },
}
const REEVAL = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'verdict_challenges', 'proposed_mutations', 'residual_issues', 'summary'],
  properties: {
    dimension: { type: 'string' },
    verdict_challenges: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['ac', 'claimed_verdict', 'my_assessment', 'reason'],
        properties: {
          ac: { type: 'string' }, claimed_verdict: { type: 'string' },
          my_assessment: { type: 'string', enum: ['PROVEN', 'WEAK', 'TAUTOLOGY', 'MISSING', 'UNSURE'] },
          test: { type: 'string' }, reason: { type: 'string' },
        },
      },
    },
    proposed_mutations: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['ac', 'file', 'change', 'suite', 'expected_red'],
        properties: {
          ac: { type: 'string' }, file: { type: 'string' }, line: { type: 'string' },
          change: { type: 'string', description: 'a single concrete edit that SHOULD break behavior' },
          suite: { type: 'string', description: 'the test path to run, e.g. tests/unit/test_blast.gd' },
          expected_red: { type: 'boolean' },
        },
      },
    },
    residual_issues: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['title', 'severity', 'file', 'detail', 'ac'],
        properties: {
          title: { type: 'string' }, severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          file: { type: 'string' }, line: { type: 'string' }, detail: { type: 'string' }, ac: { type: 'string' },
        },
      },
    },
    low_bugs_confirmed: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}
const MUT = {
  type: 'object', additionalProperties: false,
  required: ['ac', 'file', 'applied', 'went_red', 'verdict_holds', 'restored', 'note'],
  properties: {
    ac: { type: 'string' }, file: { type: 'string' }, suite: { type: 'string' },
    applied: { type: 'boolean' }, went_red: { type: 'boolean' },
    verdict_holds: { type: 'boolean', description: 'true iff went_red matched expected_red (test really covers the AC)' },
    restored: { type: 'boolean', description: 'the mutated file was restored to its original content' },
    note: { type: 'string' },
  },
}
const PLAN = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'work_items', 'blocked_by_spec'],
  properties: {
    summary: { type: 'string' },
    work_items: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'title', 'kind', 'detail'],
        properties: {
          id: { type: 'string' }, title: { type: 'string' },
          kind: { type: 'string', enum: ['regression_fix', 'weak_test_fix', 'low_bug', 'feature'] },
          files: { type: 'array', items: { type: 'string' } },
          acs: { type: 'array', items: { type: 'string' } },
          detail: { type: 'string' },
        },
      },
    },
    blocked_by_spec: { type: 'array', items: { type: 'string' } },
    verifier_e_remaining: { type: 'array', items: { type: 'string' } },
  },
}
const IMPL = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'files_changed', 'gate_passed', 'gate_output'],
  properties: {
    summary: { type: 'string' }, files_changed: { type: 'array', items: { type: 'string' } },
    tests_added: { type: 'array', items: { type: 'string' } }, ac_covered: { type: 'array', items: { type: 'string' } },
    gate_passed: { type: 'boolean' }, gate_output: { type: 'string' },
  },
}
const FINDINGS = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'findings', 'summary'],
  properties: {
    dimension: { type: 'string' },
    findings: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['title', 'severity', 'confidence', 'file', 'detail', 'ac'],
        properties: {
          title: { type: 'string' }, severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          confidence: { type: 'number' }, file: { type: 'string' }, line: { type: 'string' },
          ac: { type: 'string' }, detail: { type: 'string' }, suggested_fix: { type: 'string' },
        },
      },
    },
    summary: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object', additionalProperties: false,
  required: ['is_real', 'reason'],
  properties: { is_real: { type: 'boolean' }, reason: { type: 'string' } },
}
const REPORT = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'files_written'],
  properties: {
    summary: { type: 'string' }, files_written: { type: 'array', items: { type: 'string' } },
    data_gate_pass: { type: 'boolean' }, test_gate_pass: { type: 'boolean' }, total_cases: { type: 'integer' },
  },
}

// ==================== PREFLIGHT ====================
phase('Preflight')
const baseline = await agent(
  `${CONTEXT}

PREFLIGHT. With Bash:
1) Safety re-snapshot of the CURRENT green tree (preserve the existing .salvage-backup; make a fresh
   one): rm -rf .reeval-backup && mkdir -p .reeval-backup && cp -R scripts tests data scenes project.godot .reeval-backup/ . Confirm it copied (ls it).
2) Run tools/validate_data.sh then tools/run_tests.sh tests. Report real exit codes + total cases.
Change nothing else.`,
  { label: 'preflight', phase: 'Preflight', schema: VERIFY }
)

// ==================== RE-EVAL (parallel, read-only) ====================
const DIMS = [
  { key: 'gen-grid-blast', prompt: `Re-evaluate U2/U3/U4 ACs (5.1.2/3/4/5/6/7, 5.2.1-7, 5.4.6): block_gen.gd (FastNoiseLite coherence + determinism + relic placement + golden), block_grid.gd (depth/mine-scaled HP, per-cell side-array store), blast.gd (fuzzy seeded radius, single-source radius, no-chain-prop, crack stages, free-charge-breaks-floor). Read each cited test AND the impl; decide whether a plausible bug would actually fail it.` },
  { key: 'physics-aim', prompt: `Re-evaluate U5/U6 ACs (5.3.1/2/3/6/7/8, 5.4.1/2): charge.gd (detonation modes incl. sticky + on_rest-no-impact, floori cell fix), throw_params.gd, aim.gd + aim_controller (initial-arc-to-first-bounce preview from muzzle, data-sourced impulse, shared mouse/touch path, no determinism leftovers, no lose state).` },
  { key: 'economy-dig-prestige', prompt: `Re-evaluate U8/U9 ACs (5.5.1/2/3/4/5, 5.6.1/2/3/4, 5.12.1/2, 5.4.3/4/5): economy.gd (credit-once, EV+gem monotonic loot, per-dig reset), run_state.gd + prestige.gd (free unlimited charge never decremented, relic-ends-dig banks once + idempotent, reproducible pack RNG, pity not-a-tautology, buy_upgrade makes next dig stronger).` },
  { key: 'data-validator', prompt: `Re-evaluate U1 + the data gate (5.1.5, 5.4.1/3, 5.5.4/5, 5.10.3, 5.8.5): data_validator.gd + registry.gd + data/*.json + test_data_integrity. Confirm each NEW v0.4 rule has a real NEGATIVE (mutation) test: falloff==radius, full explosive shape, paid>free efficiency, fuse-present, no-stall-with-worst-case-fuzz, EV/gem monotonicity, palette luminance/glyph, touch-target/edge-margin. Flag any validated-but-unused field.` },
  { key: 'assembly-art-save-audio-ui', prompt: `Re-evaluate U10 + pulled-forward features: mine.gd (thin controller? real authored mine.tscn? GPUParticles2D not ColorRect? camera not hard-set per frame?), block_art.gd (5.10.2/3), save_codec.gd/save_manager.gd (5.11.1-4 round-trip/migration/atomic/recovery), audio.gd (5.13.x bus+events+web-unlock), ui_layout.gd/hud.gd/tray.gd (5.8.5 safe-area+touch-target+tray-scroll). Read the cited tests; flag PROVEN-structural rows whose real assertion is weaker than claimed.` },
  { key: 'completeness-and-lowbugs', prompt: `Two jobs. (a) COMPLETENESS: confirm every in-slice v0.4 AC (SPEC 5 intersect VERTICAL_SLICE 1) appears in reports/spec-coverage.md with a real asserting test; flag any AC missing from the matrix or any test citing NO AC. (b) Re-confirm the "Confirmed-but-deferred LOW bugs" list at the bottom of spec-coverage.md is accurate (block_gen bit-31 truncation; per-cell FastNoiseLite re-instantiation; hardcoded fuse 0.15 / block_pixel_size 64 / max_steps 240; explosion SceneTree-timer cleanup; depth readout uses target_row; flaky AudioStreamPlaybackWAV leaked-at-exit) -- which are still present?` },
]

phase('Re-eval')
const reeval = await parallel(DIMS.map(d => () =>
  agent(
    `${CONTEXT}

READ-ONLY RE-EVALUATION -- change NO files. Dimension: ${d.key}.
${d.prompt}
For EACH AC: state the claimed verdict from spec-coverage.md and YOUR independent assessment
(PROVEN/WEAK/TAUTOLOGY/MISSING/UNSURE) with a reason. Where you have any doubt a test truly covers its
AC, PROPOSE a concrete mutation experiment: the file, a single one-line change that SHOULD break the
behavior, the suite to run, and expected_red=true (the test should go red). Also list residual_issues
(real problems) and which LOW bugs you can still see. Be adversarial; cite file:line.`,
    { label: `reeval:${d.key}`, phase: 'Re-eval', schema: REEVAL }
  )
))
const proposed = reeval.filter(Boolean).flatMap(r => r.proposed_mutations || [])
const challenged = reeval.filter(Boolean).flatMap(r => (r.verdict_challenges || []).filter(c => ['WEAK', 'TAUTOLOGY', 'MISSING'].includes(c.my_assessment)))
log(`Re-eval: ${proposed.length} mutation experiments proposed; ${challenged.length} verdict(s) challenged as weaker than reported.`)

// ==================== MUTATE (sequential mutation testing) ====================
phase('Mutate')
const MUT_CAP = 14
const toMutate = proposed.slice(0, MUT_CAP)
if (proposed.length > MUT_CAP) log(`Capping mutation experiments at ${MUT_CAP} of ${proposed.length} (highest-value first).`)
const mutResults = []
for (let i = 0; i < toMutate.length; i++) {
  const m = toMutate[i]
  const r = await agent(
    `${CONTEXT}

MUTATION TEST (sequential, ${i + 1}/${toMutate.length}) for ${m.ac}. Do this EXACTLY and SAFELY:
1) Back up the target file: cp "${m.file}" /tmp/mut_orig with Bash (use a unique name).
2) Apply this single mutation to ${m.file}: ${m.change}
3) Run: tools/run_tests.sh ${m.suite || 'tests'}  (a focused suite if given, else full).
4) Record went_red = did that suite now FAIL? verdict_holds = (went_red === ${m.expected_red}).
5) RESTORE the original: copy /tmp/mut_orig back over ${m.file}; confirm with a diff that it is
   byte-identical to the original (set restored=true only if confirmed). If restore is uncertain,
   recover the file from .reeval-backup/ (same relative path) and set restored accordingly.
A verdict_holds=false means the test does NOT actually cover its AC (a real coverage gap to fix).`,
    { label: `mutate:${m.ac}#${i}`, phase: 'Mutate', schema: MUT }
  )
  mutResults.push(r)
}
// integrity gate: ensure the tree is back to green after all the mutate/restore cycles
const integrity = await agent(
  `${CONTEXT}

INTEGRITY CHECK after mutation testing. With Bash run tools/validate_data.sh then
tools/run_tests.sh tests. If EITHER is red, a mutation was not restored: restore the offending files
from .reeval-backup/ (same relative paths), then re-run until both gates exit 0. Report final results.`,
  { label: 'mutate:integrity', phase: 'Mutate', schema: VERIFY }
)
const falsified = mutResults.filter(Boolean).filter(r => r.verdict_holds === false)
log(`Mutation testing: ${mutResults.filter(Boolean).filter(r => r.verdict_holds).length} verdict(s) confirmed, ${falsified.length} FALSIFIED (test did not cover its AC). Integrity gate: data=${integrity && integrity.data_gate_pass} test=${integrity && integrity.test_gate_pass}.`)

// ==================== PLAN ====================
phase('Plan')
const plan = await agent(
  `${CONTEXT}

PLAN the FINISH work. Synthesize an ordered, BUILDABLE worklist from:
- FALSIFIED verdicts (tests that did not go red under mutation -> must be strengthened to truly cover
  the AC): ${JSON.stringify(falsified.map(f => ({ ac: f.ac, file: f.file, note: f.note })))}
- Challenged verdicts (re-eval thought weaker than reported): ${JSON.stringify(challenged)}
- Residual issues + confirmed LOW bugs from re-eval: ${JSON.stringify(reeval.filter(Boolean).flatMap(r => (r.residual_issues || []).concat((r.low_bugs_confirmed || []).map(b => ({ title: b, severity: 'low', file: '', detail: b, ac: '' })))))}
- The auto-buildable slice-polish gaps that need NO new design decision: settings UI sliders
  (AC-5.10.1: motion/screen-shake + UI text scale + SFX/Music volume, over the existing Audio buses +
  motion/text-scale systems), nav->overlay screens (AC-5.8.3: Shop over the existing buy_pack, Upgrades
  over the existing prestige buy_upgrade, Settings over 5.10.1; Mine stays instanced+paused),
  Credits screen rendered from a NEW ATTRIBUTIONS.md (AC-5.8.7), full text-scale reflow/abbreviation
  (AC-5.8.6), web save: persistence-unavailable detection + manual export/import + namespaced user://
  (AC-5.11.5, the headless-buildable parts).
Order: regression/weak-test fixes FIRST, then LOW bugs, then features (dependency-aware). For EACH item
give kind, files, acs, detail. SEPARATELY list blocked_by_spec items you are NOT planning (full
prestige tree, mine hub/buy-access/roster/pricing, authored ending, narrative/reveal content,
AC-5.10.4 reveal-a11y which needs that content) and verifier_e_remaining (web COLOR/audio-resume,
on-device 60fps/safe-area, palette adoption, 5-target export smoke, optimization-feel gate). Change no files.`,
  { label: 'plan', phase: 'Plan', schema: PLAN }
)
const items = (plan && plan.work_items) || []
log(`Plan: ${items.length} buildable work item(s); ${(plan && plan.blocked_by_spec || []).length} blocked-by-spec (flagged, not built).`)

// ==================== COMPLETE (sequential, mutating) ====================
phase('Complete')
const done = []
for (let i = 0; i < items.length; i++) {
  const it = items[i]
  await agent(
    `${CONTEXT}

COMPLETE work item ${it.id} [${it.kind}]: ${it.title}
Files: ${JSON.stringify(it.files || [])}  ACs: ${JSON.stringify(it.acs || [])}
Detail: ${it.detail}
Implement it per SPEC v0.4 + conventions, with REAL tests that cite the AC and would go red on a
plausible bug (no tautologies; if this is a weak_test_fix, the new test MUST fail under the mutation
that previously slipped through). For features, author scenes in the editor format (not built in
_ready); keep UI thin. Run BOTH gates with Bash and ITERATE until they exit 0 with the FULL suite green
(no regressions/orphans). If the item turns out to need a design decision not in SPEC v0.4, STOP and say
so in summary instead of inventing. Paste passing gate output.`,
    { label: `impl:${it.id}`, phase: 'Complete', schema: IMPL }
  )
  let v = null, round = 0
  const MAX_FIX = 3
  while (round <= MAX_FIX) {
    v = await agent(
      `${CONTEXT}

INDEPENDENT VERIFY work item ${it.id} (round ${round}) -- do not trust prior claims. Run both gates
with Bash; report real results, totals, failing tests. Also confirm the item's ACs are asserted by
real (non-vacuous) tests. Change nothing.`,
      { label: `verify:${it.id}#${round}`, phase: 'Complete', schema: VERIFY }
    )
    if (v && v.data_gate_pass && v.test_gate_pass) break
    if (round === MAX_FIX) break
    log(`${it.id}: red on round ${round} -- fixing.`)
    await agent(
      `${CONTEXT}

FIX work item ${it.id}. Gates red:
${JSON.stringify((v && (v.failures || v.summary)) || v, null, 2)}
Patch what is actually wrong per SPEC v0.4 (code, tests, or /data). Do not weaken tests to pass. Re-run
both gates until green. Report changes.`,
      { label: `fix:${it.id}#${round}`, phase: 'Complete', schema: IMPL }
    )
    round++
  }
  const green = !!(v && v.data_gate_pass && v.test_gate_pass)
  done.push({ id: it.id, title: it.title, green })
  if (!green) { log(`WARNING ${it.id} did not reach green after ${MAX_FIX} rounds -- halting Complete to avoid building on red.`); break }
}
const allDone = done.length === items.length && done.every(d => d.green)

// ==================== AUDIT (new work, parallel + adversarial) ====================
phase('Audit')
let confirmed = []
if (done.length) {
  const changedTitles = done.map(d => `${d.id}: ${d.title}`)
  const LENSES = [
    { key: 'new-features-faithfulness', prompt: `Audit the NEWLY built/changed work for AC-faithfulness: do the new settings UI / nav overlays / credits / text-scale reflow / web-save / strengthened tests actually satisfy their SPEC v0.4 ACs (5.10.1, 5.8.3, 5.8.7, 5.8.6, 5.11.5), with the Mine staying instanced+paused under overlays, and identical mouse/touch paths? Items built this run: ${JSON.stringify(changedTitles)}` },
    { key: 'anti-gaming', prompt: `Anti-gaming sweep over the NEW/changed tests: hunt vacuous/tautological/conditionally-skipped assertions, tests written to pass rather than verify, and any newly-added self-healing golden. Confirm any "weak_test_fix" items now have a test that would go RED under the previously-slipping mutation. Items built this run: ${JSON.stringify(changedTitles)}` },
    { key: 'regression-and-scope', prompt: `Confirm NO regression in the previously-PROVEN slice ACs and NO scope creep: verify nothing blocked-by-spec (prestige tree / mine hub / ending / narrative) was silently invented, and the full 304+ suite still covers the original ACs. Spot-check a few original PROVEN rows still hold.` },
  ]
  const audited = await pipeline(
    LENSES,
    L => agent(`${CONTEXT}

READ-ONLY AUDIT of the NEW work -- change NO files. Lens: ${L.key}. ${L.prompt}
Cite file:line + the AC; set confidence 0..1 per finding.`,
      { label: `audit:${L.key}`, phase: 'Audit', schema: FINDINGS }),
    (res, L) => {
      const dim = (res && res.dimension) || L.key
      if (!res || !res.findings || !res.findings.length) return { dimension: dim, findings: [] }
      return parallel(res.findings.map(f => () =>
        parallel([0, 1, 2].map(k => () =>
          agent(`${CONTEXT}

READ-ONLY. A prior auditor claims this is a real problem in the FINISHED slice:
TITLE: ${f.title}
FILE: ${f.file} ${f.line || ''}
AC: ${f.ac}
DETAIL: ${f.detail}
Skeptic pass ${k}: TRY TO REFUTE it by reading the actual code/tests. is_real=true only if it is a
genuine, current problem against SPEC v0.4; default is_real=false if uncertain or out-of-slice-scope.`,
            { label: `refute:${L.key}#${k}`, phase: 'Audit', schema: VERDICT })))
          .then(votes => Object.assign({}, f, { confirmed: votes.filter(Boolean).filter(v => v.is_real).length >= 2 }))
      )).then(arr => ({ dimension: dim, findings: arr.filter(Boolean) }))
    }
  )
  confirmed = audited.filter(Boolean).flatMap(a => (a.findings || []).filter(f => f.confirmed))
  log(`Audit of new work: ${confirmed.length} confirmed finding(s) after adversarial verification.`)
}

// ==================== REMEDIATE (sequential) ====================
phase('Remediate')
if (confirmed.length) {
  await agent(
    `${CONTEXT}

REMEDIATE the confirmed audit findings. Fix what is genuinely wrong per SPEC v0.4; STRENGTHEN tests
where the finding is "does not assert the AC" (never weaken). Run both gates until green; paste tail.
CONFIRMED:
${JSON.stringify(confirmed.map(f => ({ title: f.title, severity: f.severity, file: f.file, line: f.line, ac: f.ac, detail: f.detail, fix: f.suggested_fix })), null, 2)}`,
    { label: 'remediate', phase: 'Remediate', schema: IMPL }
  )
  await agent(
    `${CONTEXT}

INDEPENDENT VERIFY after remediation. Run both gates with Bash; report results + totals + failures.
Change nothing.`,
    { label: 'remediate:verify', phase: 'Remediate', schema: VERIFY }
  )
} else {
  log('No confirmed findings to remediate.')
}

// ==================== REPORT ====================
phase('Report')
const report = await agent(
  `${CONTEXT}

FINAL REPORTS -- WRITE these files, then run the final confidence gate:
1) reports/reeval-report.md -- the RE-EVALUATION result: which previously-PROVEN AC verdicts were
   independently CONFIRMED via mutation testing vs FALSIFIED, what was fixed this run, and the residual
   LOW bugs. Mutation results: ${JSON.stringify(mutResults.filter(Boolean).map(r => ({ ac: r.ac, verdict_holds: r.verdict_holds, went_red: r.went_red, note: r.note })))}
2) reports/spec-coverage.md -- REGENERATE/UPDATE the AC->test matrix to include the newly finished ACs
   (5.10.1, 5.8.3, 5.8.7, 5.8.6, 5.11.5 as built) with PASS/WEAK/MISSING + the asserting test file:line;
   keep the honest Verifier-E half-rows; re-tally.
3) VERIFICATION.md (repo root) -- the human-only Verifier-E checklist that CI cannot prove: the
   optimization-feel gate (free charge usable; a bought efficient charge visibly improves ore-per-throw
   / time-to-relic; prestige makes the next dig stronger); 60fps-on-device (phone + browser tab +
   desktop); CVD palette simulation + that palette.json is an adopted CB-safe palette; iOS/macOS Safari
   render + the 5-target export smoke (COLOR-on-WebGL2, web-audio-resume); on-device safe-area; real
   mouse/touch (real-thumb) parity. Each item: what to do, a pass/fail box, notes. State clearly these
   are NOT auto-verified.
Then run tools/validate_data.sh and tools/run_tests.sh tests once more; confirm both exit 0 and report
totals. Confirm (do NOT delete) that the goldens fail on a missing pin. List files_written.`,
  { label: 'report', phase: 'Report', schema: REPORT }
)

return {
  baseline,
  reeval_dimensions: reeval.filter(Boolean).length,
  mutations_run: mutResults.filter(Boolean).length,
  verdicts_falsified: falsified.length,
  work_items_built: done,
  all_items_green: allDone,
  audit_confirmed: confirmed.length,
  blocked_by_spec: (plan && plan.blocked_by_spec) || [],
  verifier_e_remaining: (plan && plan.verifier_e_remaining) || [],
  final: report,
}
