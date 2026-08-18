# NeoFL Cognitive Layer

NeoFL is an agentic trading intelligence system, not an LLM. LLMs are pluggable cognitive components used for language-heavy reasoning, research, hypothesis generation, adversarial critique and synthesis.

Deterministic engines remain authoritative for market mathematics, Greeks, risk, account limits, data quality, execution and other precision-sensitive operations.

## Model roles

- `REASONER`: interprets specialist evidence and develops structured hypotheses.
- `RESEARCHER`: extracts and compares theories, theses and evidence from approved knowledge sources.
- `ADVERSARIAL`: challenges assumptions and constructs failure cases.
- `SYNTHESIZER`: helps the Soul organize competing evidence.

The contracts are provider-neutral so model providers can be changed without changing NeoFL's brain protocols.

## Safety boundary

LLM output is evidence/reasoning input. It does not directly authorize live execution, change risk limits, or rewrite its own governing rules. Any proposed change follows the Experiment -> Validation -> Promotion pipeline.
