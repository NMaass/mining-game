export const meta = {
  name: 'complete-and-audit-slice',
  description: 'Salvage the v0.3 mining-game slice to v0.4 (U1..U10, sequential on the shared tree) then adversarially audit it (AC-faithfulness, anti-gaming, completeness) and emit coverage + audit + human-verification reports',
  phases: [
    { title: 'Preflight', detail: 'safety snapshot, real gate baseline, harden goldens, retire QUALITY_PLAN' },
    { title: 'Salvage', detail: 'U1..U10 sequential: rework per VERTICAL_SLICE 0/U, gate, bounded fix-loop, independent verify' },
    { title: 'Audit', detail: 'parallel read-only: AC-faithfulness + anti-gaming + completeness, each finding adversarially verified' },
    { title: 'Remediate', detail: 'fix confirmed findings sequentially, re-gate to green' },
    { title: 'Report', detail: 'spec-coverage.md + audit-report.md + VERIFICATION.md + final confidence gate' },
  ],
}

const REPO = '/Users/nick/Documents/GitHub/Mining Game'
// Dependency-ordered. SEQUENTIAL by design: later units build on earlier files in the SHARED tree,
// so NO parallelism and NO worktree isolation across units (CLAUDE.md hard rule).
const ORDER = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'U7', 'U8', 'U9', 'U10']

const CONTEXT = `Repo: ${REPO} (Godot 4.6.3, Rapier 2D NON-deterministic, gdUnit4 headless).
READ FIRST every time: spec/SPEC.md (v0.4), spec/VERTICAL_SLICE.md (especially its 0 salvage map and
the unit's own section), CLAUDE.md (conventions). This is a v0.4 SALVAGE of code built against v0.3.
Non-negotiable conventions:
- Tunables live in /data JSON (extend it; never hardcode balance).
- Pure logic in scripts/core/ (no Node/scene/input deps) so it is headless-testable.
- v0.4: NO physics determinism, NO preview==actual. Aim preview = INITIAL ARC TO FIRST BOUNCE only.
  Blast radius is FUZZY via an INJECTED seeded RNG (fixed seed -> fixed result, golden-pinned;
  different seed -> different result). Generation uses FastNoiseLite (coherent -> ore veins), pure
  function of (mine_seed, cell). NO lose state: a free, unlimited, weak charge is always in the tray;
  a dig ends by collecting the RELIC -> bank prestige (power growth). end_dig must be idempotent.
- Every test extends GdUnitTestSuite and cites the AC-x.y.z it covers. Do NOT rely on injected
  InputEvents (they do not fire headless) -- test input math via pure functions.
- Golden files MUST fail on a missing pin (no self-write). Structural claims must actually assert.
- Tools needing a class_name script should preload it (class cache can be cold under -s).
Gates (use Bash; must exit 0): tools/validate_data.sh ; tools/run_tests.sh tests
A single suite for the fast loop: tools/run_tests.sh tests/unit/test_NAME.gd`

// ---------- schemas ----------
const IMPL = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'files_changed', 'gate_passed', 'gate_output'],
  properties: {
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests_added: { type: 'array', items: { type: 'string' } },
    deletions: { type: 'array', items: { type: 'string' } },
    ac_covered: { type: 'array', items: { type: 'string' } },
    gate_passed: { type: 'boolean' },
    gate_output: { type: 'string' },
  },
}
const VERIFY = {
  type: 'object', additionalProperties: false,
  required: ['data_gate_pass', 'test_gate_pass', 'summary'],
  properties: {
    data_gate_pass: { type: 'boolean' },
    test_gate_pass: { type: 'boolean' },
    v04_faithful: { type: 'boolean', description: 'true ONLY if the unit is reworked to v0.4 per VERTICAL_SLICE 0/U with real asserting tests, not merely green against v0.3' },
    already_done: { type: 'boolean' },
    total_cases: { type: 'integer' },
    failures: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    raw_tail: { type: 'string' },
  },
}
const FINDINGS = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'findings', 'uncovered_acs', 'summary'],
  properties: {
    dimension: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['title', 'severity', 'confidence', 'file', 'detail', 'ac'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          confidence: { type: 'number' },
          file: { type: 'string' },
          line: { type: 'string' },
          ac: { type: 'string' },
          detail: { type: 'string' },
          suggested_fix: { type: 'string' },
        },
      },
    },
    uncovered_acs: { type: 'array', items: { type: 'string' } },
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
    summary: { type: 'string' },
    files_written: { type: 'array', items: { type: 'string' } },
    data_gate_pass: { type: 'boolean' },
    test_gate_pass: { type: 'boolean' },
    total_cases: { type: 'integer' },
  },
}

// ==================== PREFLIGHT ====================
phase('Preflight')
const snapshot = await agent(
  `${CONTEXT}

PREFLIGHT step 1 -- SAFETY SNAPSHOT then BASELINE. With Bash:
1) Create a revert point WITHOUT git (the repo has no commits): run
   rm -rf .salvage-backup && mkdir -p .salvage-backup && cp -R scripts tests data scenes project.godot .salvage-backup/
   Confirm the copy succeeded (ls the backup).
2) Run tools/validate_data.sh then tools/run_tests.sh tests. Report real exit codes and total test
   cases. Change nothing else.`,
  { label: 'preflight:snapshot+baseline', phase: 'Preflight', schema: VERIFY }
)

await agent(
  `${CONTEXT}

PREFLIGHT step 2 -- AUDIT-HARDEN + retire the superseded plan (small, surgical edits only):
1) In tests/unit/test_blast.gd AND tests/unit/test_block_gen.gd the golden tests SELF-HEAL: if the
   golden file is missing they write it and pass. Change them to FAIL with a clear message when the
   golden is missing -- never auto-write. They must still PASS when the committed golden exists and
   matches.
2) spec/QUALITY_PLAN.md is the superseded v0.3 recovery plan. Prepend a clear DEPRECATION banner at
   its top stating it is retired and replaced by spec/VERTICAL_SLICE.md 0 (the v0.4 salvage map).
   Do not delete the file.
3) Re-run BOTH gates; they must still exit 0. Paste the tail and report exactly what you changed.`,
  { label: 'preflight:harden', phase: 'Preflight', schema: IMPL }
)

// ==================== SALVAGE (strictly sequential) ====================
phase('Salvage')
const built = []
for (let i = 0; i < ORDER.length; i++) {
  const u = ORDER[i]

  const pre = await agent(
    `${CONTEXT}

CHECK unit ${u}: per spec/VERTICAL_SLICE.md 0 (salvage map) and its ${u} section, is this unit ALREADY
reworked to v0.4 (NOT merely green against v0.3) AND do BOTH gates pass right now? Run the gates with
Bash. Set v04_faithful=true ONLY if the unit's v0.4 behavior AND real asserting tests exist (e.g.
FastNoiseLite coherent gen for U2; fuzzy seeded blast for U4; initial-arc-only preview + floori cell
fix + no determinism for U5/U6; free-unlimited-charge + relic-ends-dig + idempotent end_dig for U9;
real-scene mine.tscn smoke for U10) AND both gates exit 0. Change nothing.`,
    { label: `check:${u}`, phase: 'Salvage', schema: VERIFY }
  )
  if (pre && pre.v04_faithful && pre.data_gate_pass && pre.test_gate_pass) {
    log(`${u}: already v0.4-faithful and green -- skipping.`)
    built.push({ unit: u, green: true, faithful: true, skipped: true })
    continue
  }

  await agent(
    `${CONTEXT}

SALVAGE unit ${u} to v0.4. Follow spec/VERTICAL_SLICE.md 0 dispositions EXACTLY for the files this
unit owns (KEEP = minimal touch; REWORK = make the listed changes; DELETE = remove the dead code/test)
and implement its ${u} section (v0.4 goal, files, ACs, tests). Carry any design-independent bug fixes
from 0 that touch this unit (e.g. floori cell conversion, reproducible pack RNG, idempotent end_dig,
camera-not-hard-set, golden fail-on-missing). DELETE tests that pin removed v0.3 behavior rather than
making them pass. Run BOTH gates with Bash and ITERATE until they exit 0 and the FULL suite is green
with no regressions or new orphans. Paste passing gate output; never claim success without it.`,
    { label: `impl:${u}`, phase: 'Salvage', schema: IMPL }
  )

  let verify = null, round = 0
  const MAX_FIX = 3
  while (round <= MAX_FIX) {
    verify = await agent(
      `${CONTEXT}

INDEPENDENT VERIFY unit ${u} (round ${round}) -- do NOT trust prior claims. With Bash run
tools/validate_data.sh then tools/run_tests.sh tests. Report real exit results, totals, and failing
test names. ALSO judge v04_faithful: are the unit's v0.4 ACs actually ASSERTED by real (non-vacuous,
non-tautological) tests, with no dead v0.3 assumptions remaining? Change nothing.`,
      { label: `verify:${u}#${round}`, phase: 'Salvage', schema: VERIFY }
    )
    if (verify && verify.data_gate_pass && verify.test_gate_pass && verify.v04_faithful) break
    if (round === MAX_FIX) break
    log(`${u}: not green/faithful on round ${round} -- dispatching fix.`)
    await agent(
      `${CONTEXT}

FIX unit ${u}. Gates or v0.4-faithfulness are failing:
${JSON.stringify((verify && (verify.failures || verify.summary)) || verify, null, 2)}
Patch whatever is actually wrong per the v0.4 spec contract (code, tests, or /data). Do NOT weaken a
test to pass -- if a finding is "the test does not assert the AC", strengthen it. Re-run both gates
until green AND the v0.4 ACs are asserted by real tests. Report what you changed.`,
      { label: `fix:${u}#${round}`, phase: 'Salvage', schema: IMPL }
    )
    round++
  }
  const green = !!(verify && verify.data_gate_pass && verify.test_gate_pass)
  built.push({ unit: u, green, faithful: !!(verify && verify.v04_faithful), verified: verify })
  if (!green) {
    log(`WARNING ${u} did not reach green after ${MAX_FIX} fix rounds -- halting salvage to avoid building on red.`)
    break
  }
}
const allBuilt = built.length === ORDER.length && built.every(r => r.green)

// ==================== AUDIT (parallel, read-only, adversarially verified) ====================
const DIMS = [
  { key: 'gen-grid-blast', prompt: `Audit U2/U3/U4 (scripts/core/block_gen.gd, scripts/systems/block_grid.gd, scripts/core/blast.gd + their tests + tests/golden/*). Verify v0.4 AC-faithfulness: FastNoiseLite COHERENT noise -> ore veins, not salt-and-pepper (AC-5.1.7); gen is pure f(mine_seed,cell) (AC-5.1.3/4); HP = base_hp(hardness) x depth_mult x mine_hardness_mult applied once at chunk init, deeper cells higher HP (AC-5.2.1); per-cell HP in the side array proven by a REAL mutate/read-back assertion, not "is RefCounted" (AC-5.2.2); FUZZY blast via INJECTED seeded RNG -- fixed seed reproduces (golden) and different seeds differ (AC-5.2.3/4); no chain-prop vs pre-blast snapshot; crack-stage range pinned 0..stages-1 (AC-5.2.5); goldens FAIL on missing. Flag vacuous/tautological tests and any in-scope AC with no real asserting test.` },
  { key: 'physics-aim', prompt: `Audit U5/U6 (scripts/systems/charge.gd, scripts/core/throw_params.gd, scripts/core/aim.gd + tests). Verify: NO determinism reliance / NO physics golden / NO preview==actual (all removed in v0.4); aim preview = INITIAL ARC TO FIRST BOUNCE only, logic moved into core, gravity/dt from project settings or /data (AC-5.3.1); floori cell-conversion bug fixed (no negative-x off-by-one); detonation modes incl. sticky->freeze and on_rest-with-no-prior-impact all resolve and are tested (AC-5.4.2); free charge never decremented and a throw is always possible (AC-5.3.3/8); parity is one shared code path (structural). Flag any leftover determinism/tautology tests and any unasserted in-scope AC.` },
  { key: 'economy-dig-prestige', prompt: `Audit U8/U9 (scripts/systems/economy.gd, scripts/systems/run_state.gd, scripts/systems/prestige.gd + tests). Verify: the free UNLIMITED charge is a permanent tray slot, never decremented, tray never empty, NO lose state (AC-5.3.8/5.4.3/5.12.1); a dig ends by RELIC, banks prestige exactly once, end_dig idempotent, per-dig reset (AC-5.6.2/3); pack RNG reproducible from the run/mine seed, not re-seeded from mutable state (AC-5.4.5); buy_pack debits+grants, unaffordable rejected (AC-5.12.2); a minimal prestige purchase makes the next dig MEASURABLY stronger (AC-5.6.4); pity implemented+tested OR the field is absent (AC-5.4.4); ore credited exactly once per cell (AC-5.5.1). Flag any tray-exhaustion/starter-pack-of-N tests pinning the dead v0.3 model and the leaky tray getter.` },
  { key: 'data-validator', prompt: `Audit U1 (scripts/core/data_validator.gd, scripts/core/registry.gd, data/*.json + tests/unit/test_data_integrity.gd + test_registry.gd). Verify the NEW v0.4 validator rules EXIST and each has a NEGATIVE test (data-with-teeth): falloff length == blast_radius_cells+1; fuse-mode explosive has fuse_seconds>0; the free unlimited charge exists (flagged) and can break the shallowest floor -- no-stall (AC-5.5.5); starting_money/run_seed/body-caps present and sane; depth + per-mine HP multipliers present. Flag hardcoded balance fallbacks in registry.gd and any validated-but-unused field (e.g. vestigial hardness if not wired into HP).` },
  { key: 'assembly-test-integrity', prompt: `Audit U10 + WHOLE-SUITE test integrity. Verify scenes/mine.tscn is a REAL authored scene driven by a THIN controller (not a 600+ line god-object that builds nodes in _ready), explosions are GPUParticles2D (no ColorRect), camera follows the platform target via smoothing (not hard-set per frame): AC-5.8.1/2/4 + 5.9.1. tests/integration/test_level_smoke.gd must ACTUALLY instantiate mine.tscn (not re-new() the wiring inline). CROSS-CUTTING: hunt EVERY vacuous/gamed/tautological test across all suites (assert-it-runs, call-a-pure-fn-twice, "is RefCounted", conditionally-skipped asserts), confirm goldens fail-on-missing, and estimate what fraction of the suite genuinely verifies behavior. Cite file:line and the AC each weak test pretends to cover.` },
  { key: 'completeness', prompt: `COMPLETENESS CRITIC. Enumerate EVERY v0.4 acceptance criterion in spec/SPEC.md section 5 that is IN the slice scope (spec/VERTICAL_SLICE.md section 1), and for each state whether a real (non-vacuous) test asserts it -- grep tests for the AC id AND inspect the actual assertion. Put every uncovered or weakly-covered AC in uncovered_acs, and add one finding per uncovered/weak AC. This is the raw data for reports/spec-coverage.md. Also flag any test that cites NO AC.` },
]

phase('Audit')
let confirmed = []
let uncovered = []
let audited = []
if (allBuilt) {
  audited = await pipeline(
    DIMS,
    d => agent(
      `${CONTEXT}

READ-ONLY AUDIT -- change NO files. Dimension: ${d.key}.
${d.prompt}
Be adversarial and concrete: cite file:line and the AC id, and set confidence 0..1 per finding.`,
      { label: `audit:${d.key}`, phase: 'Audit', schema: FINDINGS }
    ),
    (res, d) => {
      const dim = (res && res.dimension) || d.key
      const uncov = (res && res.uncovered_acs) || []
      if (!res || !res.findings || !res.findings.length) return { dimension: dim, findings: [], uncovered_acs: uncov }
      // Adversarial verification: 3 skeptics per finding, each tries to REFUTE; keep if >=2 confirm.
      return parallel(res.findings.map(f => () =>
        parallel([0, 1, 2].map(k => () =>
          agent(
            `${CONTEXT}

READ-ONLY. A prior auditor claims this is a real problem in the v0.4 slice:
TITLE: ${f.title}
FILE: ${f.file} ${f.line || ''}
AC: ${f.ac}
DETAIL: ${f.detail}
Skeptic pass ${k}: TRY TO REFUTE it. Read the actual code/tests. Is it genuinely a real, CURRENT
problem against the v0.4 spec (is_real=true), or a false alarm / already-handled / out-of-slice-scope
(is_real=false)? Default to is_real=false if uncertain.`,
            { label: `refute:${d.key}#${k}`, phase: 'Audit', schema: VERDICT }
          )
        )).then(votes => {
          const real = votes.filter(Boolean).filter(v => v.is_real).length >= 2
          return Object.assign({}, f, { dimension: dim, confirmed: real })
        })
      )).then(arr => ({ dimension: dim, findings: arr.filter(Boolean), uncovered_acs: uncov }))
    }
  )
  confirmed = audited.filter(Boolean).flatMap(a => (a.findings || []).filter(f => f.confirmed))
  uncovered = audited.filter(Boolean).flatMap(a => a.uncovered_acs || [])
  log(`Audit: ${confirmed.length} confirmed finding(s) after adversarial verification; ${uncovered.length} uncovered/weak AC(s).`)
} else {
  log('Salvage halted before all units reached green -- skipping the deep audit; the report will record where it stopped.')
}

// ==================== REMEDIATE (sequential -- mutates files) ====================
phase('Remediate')
if (allBuilt && confirmed.length) {
  await agent(
    `${CONTEXT}

REMEDIATE the confirmed audit findings below. Fix what is genuinely wrong per the v0.4 spec (code,
tests, or /data). Do NOT weaken tests to pass -- where a finding is "the test does not assert the AC",
STRENGTHEN it. Run BOTH gates until green with no regressions; paste the tail.
CONFIRMED FINDINGS:
${JSON.stringify(confirmed.map(f => ({ title: f.title, severity: f.severity, file: f.file, line: f.line, ac: f.ac, detail: f.detail, fix: f.suggested_fix })), null, 2)}`,
    { label: 'remediate', phase: 'Remediate', schema: IMPL }
  )
  const reverify = await agent(
    `${CONTEXT}

INDEPENDENT VERIFY after remediation. Run BOTH gates with Bash; report real results, totals, and any
failures. Change nothing.`,
    { label: 'remediate:verify', phase: 'Remediate', schema: VERIFY }
  )
  log(`Post-remediation gates: data=${reverify && reverify.data_gate_pass} test=${reverify && reverify.test_gate_pass}`)
} else if (allBuilt) {
  log('No confirmed findings to remediate.')
}

// ==================== REPORT ====================
phase('Report')
const report = await agent(
  `${CONTEXT}

FINAL REPORTS -- WRITE these files, then run the final confidence gate:
1) reports/spec-coverage.md -- a table of EVERY in-scope v0.4 AC (spec/SPEC.md section 5 intersected
   with VERTICAL_SLICE section 1) -> asserting test file:line -> PASS / WEAK / MISSING. Build it by
   grepping the tests for AC ids and inspecting assertions. Flag any test citing no AC.
   Known uncovered/weak ACs from the audit: ${JSON.stringify(uncovered)}
2) reports/audit-report.md -- the confirmed findings (severity, file:line, AC, and whether remediated
   this run), the residual/unfixed ones, and the test-integrity estimate.
   Confirmed findings: ${JSON.stringify(confirmed.map(f => ({ title: f.title, severity: f.severity, file: f.file, ac: f.ac })))}
3) VERIFICATION.md (repo root) -- the human-only Verifier-E checklist that CI cannot prove: the
   optimization-feel gate (free charge usable, but a bought efficient charge visibly improves
   ore-per-throw / time-to-relic, and prestige makes the next dig stronger); 60fps-on-device (phone +
   browser tab + desktop); CVD palette simulation; iOS/macOS Safari render + the 5-target export
   smoke; real-thumb mouse/touch parity. Each item: what to do, pass/fail box, notes. State clearly
   these are NOT auto-verified.
Then run tools/validate_data.sh and tools/run_tests.sh tests once more; confirm both exit 0 and report
totals. Confirm (do NOT delete the goldens) that the golden tests would fail on a missing pin. List
files_written.`,
  { label: 'report', phase: 'Report', schema: REPORT }
)

return {
  baseline: snapshot,
  salvage: built,
  all_units_green: allBuilt,
  audit_confirmed: confirmed.length,
  uncovered_acs: uncovered,
  final: report,
  out_of_scope_remaining: 'ROADMAP U11..U26 (full game) and the section G / G4 / G5 spec decisions are intentionally NOT built here -- they are blocked-by-spec or post-slice. See spec/ROADMAP.md.',
}
