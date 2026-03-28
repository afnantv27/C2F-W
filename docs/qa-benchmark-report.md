# ClimateScan QA Benchmark Report

Date: 2026-03-27  
Scope: macOS app build, unit tests, UI smoke coverage, script-based performance validation, and Instruments-ready profiling

## Objective
Establish a repeatable QA baseline for ClimateScan so future product work is measured against:
- build stability
- workflow correctness
- UI navigation coverage
- portfolio-scale query performance
- disclosure discovery performance
- forecast-feed loading performance
- Instruments trace readiness

## Test Surfaces

### Xcode schemes
- `ClimateScan`
  - unit tests
  - performance tests
- `ClimateScanUITests`
  - UI smoke and navigation tests

### Build-layer validation
- `Build/engine-rewrite/tests/run_disclosure_milestone.sh`
- `Build/india-risk-data/tests/run_data_milestone.sh`
- `Build/engine-rewrite/tests/run_performance_validation.sh`
- `Build/engine-rewrite/tests/run_instruments_profile.sh`

## Coverage Inventory

### Unit and workflow regression coverage
- run-config round-trip
- forecast evidence promotion separation
- disclosure review-root resolution
- TCFD approval gating
- TCFD threshold-breach action validation

### UI smoke coverage
- dashboard launcher visibility
- dashboard → climate simulation navigation
- dashboard → forecast intelligence navigation
- dashboard → TCFD dashboard navigation
- app launch performance metric

### Performance validation
- simulation output-tree build
- forecast metric-card construction
- run-config round-trip
- TCFD bundle discovery at larger bundle scale
- India nearby query benchmark at portfolio scale
- India grouped portfolio rollup benchmark at portfolio scale
- processed forecast-feed loading

## Benchmark Thresholds

### Xcode performance targets
- simulation output-tree build: should remain under `0.10s` on the current synthetic fixture
- forecast metric-card build: should remain under `1.50s`
- run-config round-trip: should remain under `0.02s`

### Build performance targets
- TCFD discovery across `300` bundles: each pass should remain under `2.0s`
- India nearby queries across `50,000` assets:
  - `200` repeated lookups should remain under `2.0s`
- India grouped portfolio rollups across `50,000` assets:
  - `50` repeated summaries should remain under `2.5s`
- processed forecast-feed loading:
  - current fixture set should remain under `2.0s`

## Latest Measured Baseline

This section should be updated whenever the benchmark suite is rerun after material architecture changes.

| Suite | Metric | Result | Interpretation |
|---|---|---:|---|
| Xcode unit/perf | forecast evidence promotion regression | pass (`0.004s`) | executive/disclosure separation is stable |
| Xcode unit/perf | run-config round-trip regression | pass (`0.001s`) | config contract remains deterministic |
| Xcode unit/perf | TCFD approval gating regression | pass (`0.001s`) | approval evidence remains enforced |
| Xcode unit/perf | TCFD threshold-action regression | pass (`0.000s`) | threshold workflow rules remain enforced |
| Xcode performance | simulation output-tree build | `0.067s` | responsive at current synthetic output scale |
| Xcode performance | forecast metric-card build | `1.266s` | acceptable but now the slowest XCTest performance path |
| Xcode performance | run-config round-trip | `0.006s` | serialization overhead is negligible |
| UI smoke | dashboard launcher | `3.291s` | launcher remains stable and discoverable |
| UI smoke | climate simulation navigation | `9.623s` | route works, but this is currently the heaviest UI smoke path |
| UI smoke | forecast navigation | `5.125s` | window routing is stable |
| UI smoke | TCFD navigation | `3.830s` | disclosure window routing is stable |
| UI smoke | launch metric average | `0.447s` | healthy launch-time baseline for current app size |
| Build perf | TCFD discovery across 300 bundles | first `0.030s`, second `0.031s` | strong disclosure discovery headroom |
| Build perf | India nearby queries across 50,000 assets | `0.104s` | site screening is performant at larger synthetic scale |
| Build perf | India grouped rollups across 50,000 assets | `2.112s` | acceptable, but this is the current portfolio hotspot |
| Build perf | processed forecast-feed loading | `0.071s` | forecast ingestion overhead is low |

## Instruments Profiling Workflow

Use:

```bash
bash /Users/afnan/Desktop/Build/engine-rewrite/tests/run_instruments_profile.sh
```

The script:
- builds `ClimateScan` in a dedicated derived-data directory
- records an `App Launch` trace
- records a `Time Profiler` trace
- exports trace table-of-contents XML for downstream inspection
- writes artifacts under `Build/engine-rewrite/artifacts/instruments/<timestamp>/`

Latest successful trace run:
- `/Users/afnan/Desktop/Build/engine-rewrite/artifacts/instruments/20260327-235732`

This is intentionally separate from the automated benchmark suite because Instruments traces are heavier and more environment-sensitive than fast regression checks.

## Interpretation Standard

### Green
- all build/test suites pass
- performance checks stay inside thresholds
- Instruments traces generate successfully

### Yellow
- correctness passes, but one or more thresholds regress by less than `25%`
- requires profiling and targeted follow-up before merging larger workflow changes

### Red
- build/test failure
- any disclosure, forecast, or portfolio benchmark materially breaches threshold
- Instruments tracing fails due to app launch instability

## Remaining Gaps
- UI smoke still covers only primary launcher routes, not full disclosure editing paths
- no Instruments-driven interaction script yet for post-launch workflows such as TCFD refresh or portfolio drill-in
- no portfolio hierarchy benchmark yet for multi-business-unit company structures
- no sustained-memory or long-session benchmark yet
- the India grouped rollup benchmark is acceptable but is now the clearest performance candidate for query/index optimization

## Next QA Additions
1. TCFD review action smoke path in UI tests
2. portfolio drill-in UI smoke path
3. larger multi-business-unit rollup benchmark
4. scripted Instruments session for launch plus disclosure refresh
