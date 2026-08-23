# Hermes integration

NeoFLGPT Parallel can use Nous Research Hermes Agent as an agent/tool execution layer while retaining NeoFL-specific trading reasoning, memory schema, risk policy, and MT5 execution controls.

## Design

- Hermes: coding, terminal, skills, MCP/tool orchestration, sub-agents.
- NeoFLGPT Parallel: trading-domain brain, strategy context, memory integration, risk/execution policy.
- Real-time engine: deterministic market/event processing; do not send every tick through an LLM.
- MT5: execution actuator behind an authenticated gateway.
- Model provider: pluggable. Hermes still requires an underlying LLM for language/reasoning; local CPU inference or a remote provider can be selected later.

## Server install

Hermes officially supports Linux and provides an installer. The recommended installation is:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Then configure the provider/model with `hermes model` and tools with `hermes tools`.

For this project, run Hermes as a dedicated unprivileged service user where practical, and do not grant the agent unrestricted production trading credentials. Keep MT5 execution behind the NeoFL authenticated gateway.

## Integration boundary

The initial adapter should expose Hermes through a local process/HTTP boundary and pass only approved NeoFL tools. It must not give Hermes direct database superuser access or unrestricted order execution.

## Validation

After installation, verify:

```bash
hermes doctor
hermes --help
```

Then validate the NeoFL adapter in dry-run mode before enabling any live execution path.
