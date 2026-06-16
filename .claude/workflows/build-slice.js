export const meta = {
  name: 'build-slice',
  description: 'Build or repair the whole vertical slice (U1→U10) in dependency order, gating each unit, then a full-suite confidence pass',
  whenToUse: 'Run to advance the MVP slice with quality recovery. Resumable, but a unit is skipped only when its behavior and tests prove the ACs.',
  phases: [
    { title: 'Build', detail: 'U1→U10 sequentially; each unit implemented + gated + fix-looped' },
    { title: 'Confidence', detail: 'full data + test gates, clean, at the end' },
  ],
}

const REPO = '/Users/nick/Documents/GitHub/Mining Game'
// Dependency-ordered. Sequential by design: later units build on earlier files in the shared tree,
// so NO worktree isolation and no parallelism across units (avoids file conflicts).
const ORDER = ['U1', 'U2', 'U3', 'U4', 'U5', 'U6', 'U7', 'U8', 'U9', 'U10']

const CONTEXT = `Repo: ${REPO} (Godot 4.6.3, Rapier 2D, gdUnit4). Read spec/QUALITY_PLAN.md,
spec/VERTICAL_SLICE.md, spec/SPEC.md, spec/AGENTS.md first. Treat current "done" claims as
provisional unless independently proven. Conventions: tunables in /data JSON (never hardcoded),
pure logic in scripts/core/, typed GDScript, tests reference AC ids, no reliance on injected
InputEvents headless. Gates (use Bash, must exit 0): tools/validate_data.sh ; tools/run_tests.sh tests.
Green tests are necessary but not sufficient: the tests must exercise the AC behavior.`

const IMPL_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'files_changed', 'gate_passed', 'gate_output'],
  properties: {
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    tests_added: { type: 'array', items: { type: 'string' } },
    ac_covered: { type: 'array', items: { type: 'string' } },
    gate_passed: { type: 'boolean' },
    gate_output: { type: 'string' },
  },
}
const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['data_gate_pass', 'test_gate_pass', 'ac_coverage_pass', 'summary'],
  properties: {
    data_gate_pass: { type: 'boolean' }, test_gate_pass: { type: 'boolean' },
    ac_coverage_pass: { type: 'boolean', description: 'true only if the tests prove the unit ACs, not just helper behavior' },
    already_done: { type: 'boolean', description: 'true only if the unit behavior, test coverage, and gates all pass' },
    failures: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' }, raw_tail: { type: 'string' },
  },
}

async function buildUnit(u) {
  // Fast skip: is the unit already implemented, AC-covered, and green?
  const pre = await agent(
    `${CONTEXT}\n\nCHECK unit ${u}: per spec/VERTICAL_SLICE.md §${u}, are its source files AND its
test suite already present, do the tests exercise the listed AC behavior, is there no open P0 item
from spec/QUALITY_PLAN.md that invalidates this unit, and do BOTH gates pass right now? Run the gates
with Bash. Set already_done=true ONLY if files+tests exist, ac_coverage_pass=true, and both gates
exit 0. Change nothing.`,
    { label: `check:${u}`, phase: 'Build', schema: VERIFY_SCHEMA }
  )
  if (pre && pre.already_done && pre.ac_coverage_pass && pre.data_gate_pass && pre.test_gate_pass) {
    log(`${u}: already AC-covered and green — skipping.`)
    return { unit: u, green: true, skipped: true }
  }

  await agent(
    `${CONTEXT}\n\nIMPLEMENT unit ${u} exactly per spec/VERTICAL_SLICE.md §${u}: its source files
AND its gdUnit4 tests asserting the listed ACs. Run the gates with Bash and iterate until both exit
0 and the FULL suite is green (no regressions). Paste passing gate output; never claim success
without it.`,
    { label: `impl:${u}`, phase: 'Build', schema: IMPL_SCHEMA }
  )

  let verify = null, round = 0
  const MAX_FIX = 3
  while (round <= MAX_FIX) {
    verify = await agent(
      `${CONTEXT}\n\nINDEPENDENT VERIFY of unit ${u} (round ${round}). Don't trust prior claims. Run
tools/validate_data.sh then tools/run_tests.sh tests with Bash; report real exit results, totals,
and any failing test names. Also inspect the unit's required ACs/tests from spec/VERTICAL_SLICE.md
and set ac_coverage_pass=false if tests are missing, weak, or contradicted by an open P0 item in
spec/QUALITY_PLAN.md. Change nothing.`,
      { label: `verify:${u}#${round}`, phase: 'Build', schema: VERIFY_SCHEMA }
    )
    if (verify && verify.data_gate_pass && verify.test_gate_pass && verify.ac_coverage_pass) break
    if (round === MAX_FIX) break
    log(`${u}: red on round ${round} — fixing.`)
    await agent(
      `${CONTEXT}\n\nFIX unit ${u}. Gates RED. Failures:\n${JSON.stringify(verify && verify.failures || verify, null, 2)}\n
Patch whatever is actually wrong per the spec contract; re-run both gates until green; report changes.`,
      { label: `fix:${u}#${round}`, phase: 'Build', schema: IMPL_SCHEMA }
    )
    round++
  }
  const green = !!(verify && verify.data_gate_pass && verify.test_gate_pass && verify.ac_coverage_pass)
  if (!green) log(`⚠️  ${u} did not reach green after ${MAX_FIX} fix rounds — halting slice build.`)
  return { unit: u, green, verified: verify }
}

phase('Build')
const results = []
for (const u of ORDER) {
  const r = await buildUnit(u)
  results.push(r)
  if (!r.green) break // dependency-ordered: don't build on a red foundation
}

phase('Confidence')
const allGreen = results.length === ORDER.length && results.every(r => r.green)
let confidence = null
if (allGreen) {
  confidence = await agent(
    `${CONTEXT}\n\nFINAL CONFIDENCE PASS. Run BOTH gates clean with Bash (tools/validate_data.sh ;
tools/run_tests.sh tests) and report totals + exit codes. Also confirm spec/VERTICAL_SLICE.md
golden files exist for U2/U4/U5 if those units were built, and confirm no P0 item in
spec/QUALITY_PLAN.md still invalidates a claimed-complete unit. Change nothing.`,
    { label: 'confidence', phase: 'Confidence', schema: VERIFY_SCHEMA }
  )
}

return {
  built: results.map(r => ({ unit: r.unit, green: r.green, skipped: !!r.skipped })),
  complete: allGreen,
  confidence,
}
