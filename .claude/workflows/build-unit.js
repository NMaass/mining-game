export const meta = {
  name: 'build-unit',
  description: 'Build ONE vertical-slice unit (e.g. U2) to a green gate: implement → run gates → bounded fix loop → independent verify',
  whenToUse: 'Invoke with args = "U3" (or {unit:"U3"}) to build/repair a single unit from spec/VERTICAL_SLICE.md.',
  phases: [
    { title: 'Implement', detail: 'architect + write the unit files and its gdUnit4 tests, iterate to green' },
    { title: 'Verify', detail: 'independent agent runs the gates clean; bounded fix loop if red' },
  ],
}

const UNIT = (typeof args === 'string') ? args.trim()
  : (args && args.unit) ? String(args.unit).trim() : null
if (!UNIT) throw new Error('build-unit requires a unit id, e.g. args:"U3" or {unit:"U3"}')

const REPO = '/Users/nick/Documents/GitHub/Mining Game'
const CONTEXT = `Repo: ${REPO} (Godot 4.6.3, deterministic Rapier 2D physics, gdUnit4 headless tests).
Authoritative docs to read FIRST (in this repo):
- spec/QUALITY_PLAN.md   — current quality recovery plan; previous completion claims are provisional.
- spec/VERTICAL_SLICE.md  — find the section for unit ${UNIT}; it lists the goal, files, the exact
  acceptance criteria (AC-x.y.z), the required tests + assertions, and the gate command.
- spec/SPEC.md (v0.3)     — the design + AC definitions.
- spec/AGENTS.md          — engine conventions (typed GDScript, tunables-as-JSON, pure logic in
  scripts/core/, no hardcoded balance, per-cell HP in a side array, etc.).
Conventions that MUST hold:
- All balance values come from /data JSON (extend it if needed) — never hardcode.
- Pure logic goes in scripts/core/ (no Node/scene/input deps) so it is unit-testable headless.
- Every test references the AC id it covers in a comment.
- gdUnit4 test suites extend GdUnitTestSuite; do NOT rely on injected InputEvents (they don't fire
  headless) — test input math via the pure functions directly.
Gates (must exit 0; you have Bash — RUN them, do not assume):
- tools/validate_data.sh
- tools/run_tests.sh tests        (full suite must stay green — no regressions in other units)
You may also run a single suite for a fast loop, e.g. tools/run_tests.sh tests/unit/test_block_gen.gd.
Green tests are necessary but not sufficient: the tests must prove the AC behavior, not just helper
functions or nearby logic.`

const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'files_changed', 'tests_added', 'gate_passed', 'gate_output'],
  properties: {
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests_added: { type: 'array', items: { type: 'string' } },
    ac_covered: { type: 'array', items: { type: 'string' } },
    gate_passed: { type: 'boolean' },
    gate_output: { type: 'string', description: 'tail of the gate command output proving the result' },
    notes: { type: 'string' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['data_gate_pass', 'test_gate_pass', 'ac_coverage_pass', 'summary'],
  properties: {
    data_gate_pass: { type: 'boolean' },
    test_gate_pass: { type: 'boolean' },
    ac_coverage_pass: { type: 'boolean', description: 'true only when tests prove the unit ACs' },
    total_cases: { type: 'integer' },
    failures: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    raw_tail: { type: 'string' },
  },
}

phase('Implement')
const impl = await agent(
  `${CONTEXT}\n\nIMPLEMENT unit ${UNIT}. Architect briefly against the existing code, then write the
unit's source files AND its gdUnit4 test suite exactly per spec/VERTICAL_SLICE.md §${UNIT}. Run the
gates with Bash and ITERATE (read failures, patch, re-run) until BOTH gates exit 0 and the full
suite (tools/run_tests.sh tests) is green with no new errors/orphans. If you genuinely cannot reach
green and AC coverage, stop and report precisely what's failing. Do not claim success without
pasting the passing gate output and naming the ACs covered.`,
  { label: `impl:${UNIT}`, phase: 'Implement', schema: IMPL_SCHEMA }
)

phase('Verify')
let verify = null
let round = 0
const MAX_FIX = 3
while (round <= MAX_FIX) {
  verify = await agent(
    `${CONTEXT}\n\nINDEPENDENT VERIFY of unit ${UNIT} (round ${round}). Do NOT trust prior claims.
From a clean state run, with Bash:
  1) tools/validate_data.sh
  2) tools/run_tests.sh tests
Report the real exit results and a tail of each. data_gate_pass/test_gate_pass reflect actual exit
0. Also inspect spec/VERTICAL_SLICE.md and spec/QUALITY_PLAN.md: set ac_coverage_pass=false if this
unit's tests are missing, weak, or contradicted by an open P0 quality gap. List any failing test
names. Change NOTHING.`,
    { label: `verify:${UNIT}#${round}`, phase: 'Verify', schema: VERIFY_SCHEMA }
  )
  if (verify && verify.data_gate_pass && verify.test_gate_pass && verify.ac_coverage_pass) break
  if (round === MAX_FIX) break
  log(`Unit ${UNIT}: gates red on round ${round} — dispatching fix.`)
  await agent(
    `${CONTEXT}\n\nFIX unit ${UNIT}. The gates are RED. Failures reported:\n${JSON.stringify(verify && verify.failures || verify, null, 2)}\n
Diagnose and patch (code or tests or /data, whichever is actually wrong per the spec contract).
Re-run both gates with Bash until green. Report what you changed.`,
    { label: `fix:${UNIT}#${round}`, phase: 'Verify', schema: IMPL_SCHEMA }
  )
  round++
}

return {
  unit: UNIT,
  implemented: impl,
  verified: verify,
  green: !!(verify && verify.data_gate_pass && verify.test_gate_pass && verify.ac_coverage_pass),
}
