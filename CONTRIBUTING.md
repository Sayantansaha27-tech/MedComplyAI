# Contributing to MedComplyAI

## Development Setup

Follow the [Manual Setup](README.md#manual-setup) section in the README to get the stack running locally.

## Code Style

- **Python**: PEP 8. Use type hints everywhere. Docstrings on all public functions.
- **TypeScript**: Strict mode. No `any`. Prefer `interface` over `type` for object shapes.
- **Commits**: Conventional Commits format (`feat:`, `fix:`, `docs:`, `refactor:`).

## Adding a Compliance Framework Evaluator

All framework evaluators live under `backend/app/gap/`. To add a new one (e.g., ISO 13485):

1. **Create the rules file** (`backend/app/gap/iso13485_evaluator.py`)
   - Define `ISO_RULES: Dict[str, Dict[str, List[str]]]` with `strong` and `weak` cue lists per requirement ID.
   - Implement `build_iso13485_coverage_item(...)` following the same signature as `iso14971_evaluator.py`.
   - Keep it deterministic: no LLM calls in the core classification logic.

2. **Register the requirements** in `backend/app/gap/requirement_registry.py`
   - Add `RequirementDef` entries with `framework`, `requirement_id`, `title`, `criticality`, `clause`.

3. **Wire into the advanced gap orchestrator** (`backend/app/services/advanced_gap_orchestrator_service.py`)
   - Add a feature flag `ENABLE_ISO13485_AUDIT` in `config.py`.
   - Dispatch to the evaluator when the flag is enabled.

4. **Add a policy pack** (`backend/app/policy/packs_registry.py`)
   - Define weights and criticality overrides for the new framework.

5. **Write tests** in `backend/tests/gap/test_iso13485_evaluator.py`
   - Test the `_classify_strength` function with synthetic chunks.
   - Test the threshold logic (met/partial/not_met/not_assessed transitions).

## Adding a Co-Pilot Workflow

1. Create `backend/app/services/copilot/workflow_<name>.py`
2. Implement `run_<name>_workflow(request, context) -> List[CoPilotStep]`
3. Register in `copilot_orchestrator.py` with a new `CoPilotWorkflow` enum variant
4. Add a feature flag `ENABLE_COPILOT_<NAME>` in `config.py`

## Pull Request Checklist

- [ ] All new public functions have type annotations and docstrings
- [ ] New evaluators include unit tests for classification thresholds
- [ ] No secrets or credentials committed
- [ ] `requirements.txt` updated if new dependencies added
- [ ] README updated if a new feature flag or endpoint is added
