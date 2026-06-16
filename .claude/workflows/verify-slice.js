export const meta = {
  name: 'verify-slice',
  description: 'Clean-room verification of the slice: run both gates, the golden determinism checks, and an AC→test coverage audit. Read-only.',
  whenToUse: 'Run any time to get an honest pass/fail on the current state without changing anything.',
  phases: [
    { title: 'Gates', detail: 'data + full test suite, real exit codes' },
    { title: 'Audit', detail: 'golden determinism + AC→test coverage map' },
  ],
}

const REPO = '/Users/nick/Documents/GitHub/Mining Game'
const CONTEXT = `Repo: ${REPO} (Godot 4.6.3, Rapier 2D, gdUnit4). This is READ-ONLY verification —
change NO files. Use Bash to run things. Docs: spec/QUALITY_PLAN.md, spec/VERTICAL_SLICE.md,
spec/SPEC.md. Treat previous completion claims as provisional.`

const GATES_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['data_gate_pass', 'test_gate_pass', 'summary'],
  properties: {
    data_gate_pass: { type: 'boolean' }, test_gate_pass: { type: 'boolean' },
    total_cases: { type: 'integer' }, failures: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' }, raw_tail: { type: 'string' },
  },
}
const AUDIT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'coverage'],
  properties: {
    golden_ok: { type: 'boolean' },
    golden_notes: { type: 'string' },
    coverage: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['unit', 'tests_present', 'acs_covered'],
        properties: {
          unit: { type: 'string' }, tests_present: { type: 'boolean' },
          acs_covered: { type: 'array', items: { type: 'string' } },
          acs_missing: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    p0_quality_gaps_open: { type: 'array', items: { type: 'string' } },
    gaps: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}

phase('Gates')
const gates = await agent(
  `${CONTEXT}\n\nRun tools/validate_data.sh then tools/run_tests.sh tests. Report real exit codes,
total test cases, and every failing test name. Read-only.`,
  { label: 'gates', phase: 'Gates', schema: GATES_SCHEMA }
)

phase('Audit')
const audit = await agent(
  `${CONTEXT}\n\nAUDIT coverage WITHOUT changing anything:
1) Read spec/QUALITY_PLAN.md and list any P0 quality gaps that are still open.
2) For each unit U1..U10 in spec/VERTICAL_SLICE.md, check whether its test suite exists and which of
   its listed AC-x.y.z ids are actually asserted by a test (grep the tests for the AC ids and the
   behaviors). Report acs_covered vs acs_missing per unit.
3) If golden files exist under tests/golden/, confirm the golden determinism tests pass and that the
   golden files are non-empty and referenced by a test (set golden_ok).
4) List any real coverage gaps (an AC with no asserting test, a unit with files but no tests, a scene
   test that does not boot the scene, etc.).`,
  { label: 'audit', phase: 'Audit', schema: AUDIT_SCHEMA }
)

return {
  green: !!(gates && gates.data_gate_pass && gates.test_gate_pass),
  gates,
  audit,
}
