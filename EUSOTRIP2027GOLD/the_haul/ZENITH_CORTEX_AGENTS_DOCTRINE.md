# THE ZENITH CORTEX AGENTS DOCTRINE
## Eusorone Technologies × OpenAI Agents Python SDK
### A 50-Agent Research Op, Synthesized into One Engineering Trunk

> **For:** Mike "Diego" Usoro, Founder & CEO, Eusorone Technologies, Inc.
> **From:** The 10-Lead Research Working Group, dispatched 2026-05-02
> **Subject:** Enhancing Zenith Cortex — our flagship autopilot — with the OpenAI Agents Python SDK as a portable substrate, voice-first surface, and role-aware spine for both web platform and the iOS app across all 24 user roles.

---

## FOREWORD

This doctrine answers one question: *how does the OpenAI Agents Python SDK enhance Zenith Cortex — the 50-agent autopilot already shipping inside EusoTrip — across web and iOS, for every one of our 24 user roles, without throwing away the eighteen months of substrate work that makes Cortex what it is?*

The answer is not a migration. It is a **substrate adoption**. The 50 agents stay. The 7-layer cortex (SENSORY, DISPATCH, MULTIMODAL, FLEET, COMPLIANCE, FINANCIAL, STRATEGIC) stays. The Memory Palace stays. The Synaptic Bus stays. The four-tier SkillTier governance ordering stays. The OpenClaw/NemoClaw guardrail moat stays. What changes is the *reasoning core* inside `BaseAgent.runCycle()` — it becomes an OpenAI Agents SDK `Runner.run()` invocation. What gets added is the things the SDK gives us for free that we shouldn't keep building ourselves: tracing, sessions, structured output validation, hosted tool fleet, voice + Realtime + MCP first-class.

The doctrine is structured in three parts. **Part I** (Pods 1–5, Leads 1–5) is the framework deep dive — every primitive of the OpenAI Agents Python SDK mapped against what we already have. **Part II** (Pods 6–9, Leads 6–9) is the applied logic — how each of our 50 agents migrates, how all 24 user roles consume them, and how web (tRPC) and iOS (Swift) achieve parity. **Part III** (Pod 10, Lead 10) is the synthesis — ESANG voice on Realtime, the Cortex MCP server for iOS consumption, The Haul × Cortex integration, the 6-phase 90-day ladder, the executive memo, and the Master Synthesis written for you personally.

Read order: skim the Pod synthesis at the end of each lead's section first. Then dive deep into the agents you own. Hand the whole document to the eusotrip-killers scheduled task team. They are the think tank that operationalizes the doctrine; we are the leads that wrote it.

— *The Synthesis Group, 2026-05-02*

---

## TABLE OF CONTENTS

**PART I — FRAMEWORK FOUNDATIONS (Pods 1-5)**

- Pod 1 (Lead 1): Core SDK Primitives — Agent, function_tool, Hosted Tools, Handoffs, Sessions
- Pod 2 (Lead 2): Multi-Agent Patterns — Triage, Supervisor, Swarm, Manager Fork-Join, Hierarchical Trees
- Pod 3 (Lead 3): Memory, State, and Tracing — Sessions, RunContext, Tracing, Lifecycle Hooks, Evals
- Pod 4 (Lead 4): Voice, Realtime, and MCP — VoicePipeline, Realtime API, MCP Hosting & Consumption, ComputerTool
- Pod 5 (Lead 5): Production Hardening — Streaming, Cost, Errors, Security, Observability

**PART II — CORTEX APPLICATION (Pods 6-9)**

- Pod 6 (Lead 6): Layer 1 + 2 Migration — 8 Sensory + 8 Dispatch agents
- Pod 7 (Lead 7): Layer 3 + 4 Migration — 6 Multimodal + 8 Fleet agents
- Pod 8 (Lead 8): Layer 5 + 6 + 7 Migration — 8 Compliance + 8 Financial + 6 Strategic agents
- Pod 9 (Lead 9): 24-Role Mapping + Cross-Platform Parity — Web tRPC + iOS Swift

**PART III — SYNTHESIS (Pod 10)**

- Pod 10 (Lead 10): ESANG Voice × Realtime, iOS MCP Surface, The Haul × Cortex, 6-Phase Ladder, Executive Memo, Master Synthesis for Diego

---

# PART I — FRAMEWORK FOUNDATIONS

# POD 1 — CORE SDK PRIMITIVES (Lead 1)

The five primitives the entire Agents SDK is built on. Read this before anything else.

## A1-1. Agent class

### What it is

`agents.Agent` (in `src/agents/agent.py`) is the SDK's atomic unit of work — a generic dataclass `Agent[TContext]` parameterised over a user-supplied context type. It bundles an LLM identity (`name`, `instructions`, `model`), the tools and handoffs available on each turn, optional structured output (`output_type`), input/output guardrails, lifecycle hooks (`AgentHooks`), and tuning knobs collected in `ModelSettings`. Crucially, the `Agent` itself is *stateless and immutable*; the actual loop lives in `Runner.run(agent, input, context=...)` which the SDK calls "the agent loop". `instructions` may be a string or a `Callable[[RunContextWrapper[TContext], Agent], str]`, which is how the SDK gives you per-invocation system prompts without subclassing.

### Code shape (Python)

```python
from agents import Agent, Runner, ModelSettings, function_tool
from pydantic import BaseModel

class DispatchPlan(BaseModel):
    load_id: str
    driver_id: str
    eta_iso: str
    rationale: str

@function_tool
def fetch_load(load_id: str) -> dict: ...

dispatch_commander = Agent(
    name="DispatchCommander",
    instructions="Assign drivers to loads, optimise for margin and HOS.",
    model="gpt-4.1",
    tools=[fetch_load],
    output_type=DispatchPlan,
    model_settings=ModelSettings(
        temperature=0.2,
        max_tokens=1500,
        parallel_tool_calls=True,
        tool_choice="auto",
    ),
)

result = await Runner.run(dispatch_commander, "Cover load LD-9911")
plan: DispatchPlan = result.final_output
```

### Maps onto our existing

Our `AgentConfig` interface in `core/types.ts` (lines 42-53) carries `id`, `name`, `cortexLayer`, `description`, `subscribesTo`, `publishesTo`, `runInterval`, `priority`, `dependencies`, `enabled`. The SDK's `Agent` covers `name`, `instructions` (analogue of `description` plus a system prompt), `model`, `tools`, `output_type`, and `model_settings` — but has zero awareness of `cortexLayer`, `subscribesTo/publishesTo`, `runInterval`, or `dependencies`. Those are pub/sub-topology concerns that live in `core/synapticBus.ts` and `core/agentRegistry.ts`. The SDK assumes a request/response loop; ours is a long-running periodic actor (see `scheduleNextRun()` in `core/baseAgent.ts` line 197). RBAC v2 identity binding (`setIdentity` in `core/baseAgent.ts` line 108) maps cleanly to the SDK's `RunContextWrapper[TContext]` — `AgentIdentity` becomes `TContext`.

### Migration recommendation

**Wrap, don't replace.** Keep `BaseAgent` as the lifecycle/scheduling shell (timer, subscribe, publish, RBAC ceiling, ReAct emission) and embed an SDK `Agent` as the *reasoning core* that `periodicRun()` invokes via `Runner.run`. The 50 agent IDs in `core/types.ts` lines 251-314 stay as bus addresses; each gets one SDK `Agent` instance whose `instructions` is loaded from a per-agent prompt file. `model_settings.tool_choice` and `parallel_tool_calls` give us behaviours we currently fake via `priorityArbitrator.ts`.

### Risks / gotchas

- The SDK `Agent` is a dataclass. Mutating `tools` after construction is supported (`agent.clone(tools=[...])`) but agents in pre-existing `Runner` calls keep their original tool list.
- `output_type=Pydantic` forces strict-schema JSON mode on supported models, which silently fails on models without that capability. Our agents need a model-capability gate before adopting `output_type`.
- `instructions` as a callable runs *every turn*, not once; expensive instruction builders compound across multi-turn loops.

---

## A1-2. function_tool decorator

### What it is

`@function_tool` (in `src/agents/tool.py`) converts a plain Python callable into a `FunctionTool` the model can invoke. The decorator inspects the function signature, builds a strict JSON Schema from type hints (Pydantic v2 under the hood), uses the docstring (Google or numpy style) as the tool description and per-parameter descriptions, and registers async or sync execution. The SDK distinguishes between regular tools (results fed back to the model) and `Agent.as_tool()` exposure plus a `tool_use_behavior` setting on the `Agent` (`"run_llm_again"`, `"stop_on_first_tool"`, or a custom function) that decides whether to loop after a tool call.

### Code shape (Python)

```python
from agents import function_tool, RunContextWrapper
from pydantic import BaseModel

class HosArgs(BaseModel):
    driver_id: str
    horizon_hours: int = 11

@function_tool(name_override="check_hours_of_service", strict_mode=True)
async def hos_check(ctx: RunContextWrapper, args: HosArgs) -> dict:
    """Check remaining HOS for a driver.

    Args:
        args.driver_id: The CDL driver ID.
        args.horizon_hours: Window to project forward (default 11).
    """
    return await ctx.context.eld_client.remaining(args.driver_id, args.horizon_hours)

@function_tool(failure_error_function=lambda ctx, err: f"HOS lookup failed: {err}")
def cancel_load(load_id: str) -> str:
    """Cancel a load; returns the cancellation receipt id."""
    ...
```

### Maps onto our existing

`skillRegistry.ts` lines 22-35 already has `inputSchema?: Record<string, string>` and `outputSchema?: Record<string, string>` on `SkillEntry`, plus `tier`, `tags`, `agentId`, `version`, `deprecated`. The SDK's `FunctionTool` is the *runtime callable*; our `SkillEntry` is the *registry record*. They are complementary, not duplicative. `toolCallValidator.ts` performs the role the SDK delegates to Pydantic — JSON-schema validation of model-emitted tool calls. `idempotencyService.ts` covers a domain (deterministic replay of side-effecting tools) the SDK *does not* — `function_tool` has no built-in idempotency.

### Migration recommendation

Build a `@eusotrip_tool` wrapper that calls `@function_tool` and *also* emits a `SkillRegistry.register()` call so every SDK tool auto-populates our skill catalogue with its tier and tags. Wrap the underlying callable in `idempotencyService` for any tool whose tier ≤ `SkillTier.BUSINESS`. Keep `toolCallValidator.ts` as a belt-and-braces second pass for `SkillTier.GOVERNANCE` tools where Pydantic alone is insufficient.

```python
def eusotrip_tool(*, tier: SkillTier, tags: list[str], idempotent: bool = True):
    def deco(fn):
        wrapped = idempotency_wrap(fn) if idempotent else fn
        ft = function_tool(wrapped)
        skill_registry.register(name=fn.__name__, tier=tier, tags=tags, ...)
        return ft
    return deco
```

### Risks / gotchas

- `@function_tool` *requires* fully-typed signatures. Untyped `**kwargs` raises at decoration time.
- Strict-schema mode (`strict_mode=True`, default) rejects `Optional[X]` unions with more than one non-`None` member on some models.
- The SDK looks up the docstring style heuristically; mixing Google and numpy formats produces inconsistent tool descriptions sent to the model.
- `tool_use_behavior="stop_on_first_tool"` on an `Agent` skips the post-tool reflection turn — silently bypasses our `reflect` ReAct phase emitted from `core/baseAgent.ts` line 277.

---

## A1-3. Hosted tools

### What it is

Hosted tools are `Tool` subclasses whose execution happens *inside the OpenAI Responses API*, not in your process. The SDK ships them in `src/agents/tool.py`: `WebSearchTool`, `FileSearchTool` (vector-store retrieval), `CodeInterpreterTool` (sandboxed Python), `ImageGenerationTool`, `ComputerTool` (computer-use loop), and `HostedMCPTool` (lets the model call a remote MCP server you point at). They are first-party tools that you simply add to `Agent.tools`; the SDK round-trips the tool call to OpenAI's hosted runtime and back.

### Code shape (Python)

```python
from agents import (
    Agent, WebSearchTool, FileSearchTool, CodeInterpreterTool,
    HostedMCPTool, ImageGenerationTool,
)

market_oracle = Agent(
    name="MarketOracle",
    instructions="Synthesize freight-market signal from news + internal lane data.",
    tools=[
        WebSearchTool(search_context_size="high"),
        FileSearchTool(vector_store_ids=["vs_eusotrip_lanes"], max_num_results=8),
        CodeInterpreterTool(),
        HostedMCPTool(
            tool_config={
                "type": "mcp",
                "server_label": "eusotrip_internal",
                "server_url": "https://mcp.eusotrip.com/sse",
                "require_approval": "never",
            },
        ),
    ],
)
```

### Maps onto our existing

Our autopilot has no equivalent of `CodeInterpreterTool` or `ImageGenerationTool`. `WebSearchTool` overlaps with `agents/sensory/newsSentimentNerve.ts` and `agents/strategic/marketOracle.ts` — both currently call our own news APIs. `FileSearchTool` competes with `core/inMemoryPalace.ts` + `core/mysqlPalace.ts` for retrieval, but only over an OpenAI vector store. `ComputerTool` has no analogue. `HostedMCPTool` is what we'd use to expose our existing MCP server (the `mcp__6c5de60a-…__*` family in the deferred tool registry) to an SDK agent without reimplementing every tool as a `@function_tool`.

### Migration recommendation

Use hosted tools surgically, not by default. Specifically: adopt `HostedMCPTool` immediately for our internal MCP fleet — that lets one SDK `Agent` instance get all 80+ MCP tools (search_loads, dispatch_board, hos_status, etc.) for free without the engineering cost of decorator-wrapping each. Use `FileSearchTool` only for content we'd lose nothing by uploading to OpenAI (public regulatory PDFs, FMCSA rules); keep proprietary lane data in `mysqlPalace.ts`. Avoid `WebSearchTool` until we evaluate cost — our strategic-layer agents tick frequently and per-tick web searches add up. Skip `CodeInterpreterTool` for now: our `kernelSandbox.ts` already provides sandboxed execution and our policy engine governs it.

### Risks / gotchas

- Hosted-tool calls show up only in the Responses API trace and are billed separately. A tight loop over `WebSearchTool` is a real cost surprise.
- `FileSearchTool` requires an OpenAI vector store ID — RESTRICTED-tier data per `PiiSensitivity` (types.ts line 99) cannot legally be uploaded there; `privacyRouter.ts` must gate this.
- `HostedMCPTool` with `require_approval="never"` bypasses our `approvalQueue.ts`. Always set `require_approval="always"` for any tool tagged `SkillTier.GOVERNANCE` or `SkillTier.SECURITY`.
- `ComputerTool` ties the agent to OpenAI's computer-use model family; not portable across providers.

---

## A1-4. Handoffs primitive

### What it is

A handoff (`src/agents/handoffs.py`, `Handoff` dataclass) is a special kind of tool the model can call to *transfer control* from the current agent to a target agent, optionally passing a structured payload. The convenience constructor `handoff(target_agent, on_handoff=..., input_type=..., input_filter=..., tool_name_override=..., tool_description_override=...)` produces the `Handoff` you place in `Agent.handoffs=[...]`. `on_handoff` is a sync or async callback fired with the typed payload at handoff time. `input_filter: Callable[[HandoffInputData], HandoffInputData]` lets you trim or rewrite the conversation history that the receiving agent sees — the SDK exposes `handoff_filters.remove_all_tools` as a built-in.

### Code shape (Python)

```python
from agents import Agent, handoff
from agents.extensions import handoff_filters
from pydantic import BaseModel

class ComplianceEscalation(BaseModel):
    load_id: str
    violation_code: str
    severity: str

async def on_compliance_handoff(ctx, payload: ComplianceEscalation):
    await audit_chain.record(ctx.context.identity, payload.dict())

compliance_sentinel = Agent(name="ComplianceSentinel", instructions="...")

dispatch_commander = Agent(
    name="DispatchCommander",
    instructions="Assign loads. Hand off to ComplianceSentinel on any HOS or hazmat violation.",
    handoffs=[
        handoff(
            agent=compliance_sentinel,
            on_handoff=on_compliance_handoff,
            input_type=ComplianceEscalation,
            input_filter=handoff_filters.remove_all_tools,
            tool_description_override="Escalate a load with a regulatory violation.",
        ),
    ],
)
```

### Maps onto our existing

`core/synapticBus.ts` (the `subscribe(pattern, handler, subscriberId, companyId)` API around line 80) already routes events between agents, but it's *broadcast/topic-based*. SDK handoffs are *direct, named, single-target* and *transfer the conversation context*, which the bus does not. `core/conflictResolver.ts` and `councilCoordinator.ts` provide the merge/escalate semantics for parallel decisions; those are still needed because handoffs are sequential.

### Migration recommendation

Use handoffs for *intra-conversation control transfer* (within one `Runner.run`), keep SynapticBus for *inter-agent eventing* (between separate `Runner.run` invocations). A clean mapping: every handoff's `on_handoff` callback also publishes a corresponding `agent.handoff` event onto SynapticBus so dashboards, `narrator.ts`, and `palaceMetrics.ts` see it. Our `EVENT_PERMISSION_MAP` (referenced in `core/baseAgent.ts` line 16) becomes the gate for which handoffs are even visible to which agent — populate `Agent.handoffs` from the permission set per-tenant.

### Risks / gotchas

- Handoffs can fan out at the LLM's discretion — once you give an agent N handoff targets the model decides; there's no priority or arbitration like in `agents/dispatch/priorityArbitrator.ts`. Bound the handoff list deliberately.
- `input_filter` runs *after* the LLM emits the handoff call but *before* the next agent sees it; if you forget to scrub PII the receiving agent inherits it regardless of `privacyRouter.ts`.
- Circular handoffs (A→B→A) are not detected by the SDK; `Runner` will loop until `max_turns`. Mirror our `core/agentRegistry.ts` dependency graph as a static check.

---

## A1-5. Sessions

### What it is

`Session` (in `src/agents/memory/`) is a protocol for conversation persistence — the SDK calls `session.get_items()` before each `Runner.run` and `session.add_items(new_items)` after. It removes the need to manually thread `previous_response_id` through turns. Built-in implementations: `SQLiteSession` (file-backed, thread-safe), `OpenAIConversationsSession` (uses OpenAI's hosted Conversations API), and a `SQLAlchemySession` shipped under `agents.extensions.memory.sqlalchemy_session` for Postgres/MySQL/SQLite via SQLAlchemy. You can implement the `Session` protocol yourself — it requires `session_id`, `get_items()`, `add_items()`, `pop_item()`, and `clear_session()`.

### Code shape (Python)

```python
from agents import Agent, Runner
from agents.extensions.memory import SQLAlchemySession

session = SQLAlchemySession.from_url(
    session_id=f"company-{company_id}-driver-{driver_id}",
    url="mysql+aiomysql://user:pass@host/eusotrip_sessions",
    create_tables=True,
)

result = await Runner.run(driver_wellness_ai, "How are you feeling today?", session=session)
# next turn — full history reconstructed automatically:
result = await Runner.run(driver_wellness_ai, "What about yesterday?", session=session)
```

### Maps onto our existing

`core/memoryStore.ts` is a *fact* store — it stores `MemoryEntry { agentId, key, value, confidence, decayFactor, sampleCount }` indexed by `agentId::key` with an LRU and DB persistence (line 48-80). It is *not* a conversation log. The Memory Palace (`core/palace/inMemoryPalace.ts`, `core/palace/sqlitePalace.ts`, `core/mysqlPalace.ts`) is the verbatim ReAct trajectory store with wing/room/hall structure. Neither is a `Session`. The closest fit is to implement a `EusoTripPalaceSession(Session)` adapter that reads/writes `hall_facts` drawers.

### Migration recommendation

Implement a custom `Session` backed by `mysqlPalace`. Session ID format: `${companyId}::${agentId}::${conversationId}`. `add_items` writes to `hall_advice` (model output) and `hall_events` (tool calls). `get_items` reads the latest N drawers in chronological order. Keep `MemoryStore` for what it does well — long-term distilled learnings with confidence decay — separate from per-conversation transcript storage. Critically, set `companyId` as a partition key in the session ID so OpenAI's `OpenAIConversationsSession` is *never* used for multi-tenant data (it has no isolation primitive).

```python
class PalaceSession(Session):
    def __init__(self, session_id: str, palace, company_id: int):
        self.session_id, self.palace, self.company_id = session_id, palace, company_id
    async def get_items(self, limit=None): ...
    async def add_items(self, items): ...
    async def pop_item(self): ...
    async def clear_session(self): ...
```

### Risks / gotchas

- `SQLiteSession` is fine for dev; in production on Azure App Service, the file is ephemeral per instance — use `SQLAlchemySession` against the existing MySQL pool used by `mysqlPalace.ts`.
- Sessions are *unbounded* by default. Without a windowing strategy, prompt cost grows linearly per turn. Enforce a max-items policy in the custom `Session`.
- `EncryptedSession` is a wrapper, not a built-in column-level encryption; it stores ciphertext in whatever underlying session you compose. RESTRICTED-tier data still must clear `privacyRouter.ts` before entering even an encrypted session.
- Switching `Session` mid-conversation throws away history silently.

---

## Pod 1 Synthesis

The five primitives compose into a coherent loop: an `Agent` (A1-1) with `function_tool` and hosted tools (A1-2, A1-3) bound to handoffs (A1-4) and a `Session` (A1-5), driven by `Runner.run` — that *is* the agent loop. We do not need to keep our hand-rolled equivalent in lockstep, but we should not throw it away. **Recommended path: keep BaseAgent, SynapticBus, and the Memory Palace as the substrate; bolt the SDK on top as the reasoning core.**

Concretely: `BaseAgent.periodicRun()` becomes a thin orchestrator that calls `Runner.run(sdkAgent, ..., session=PalaceSession(...), context=identity)`. `synapticBus` keeps inter-agent eventing and the 50-agent topology in `core/types.ts`; SDK handoffs handle intra-conversation transfers. `SkillRegistry` wraps `@function_tool` so every tool is tracked with tier, tags, and version. `idempotencyService`, `policyEngine`, `privacyRouter`, `approvalQueue`, and the four-rail guardrails compose around the Runner — they are governance layers the SDK genuinely lacks.

The substrate path keeps RBAC v2 isolation, multi-tenancy, the four-tier skill precedence model, the four-rail guardrails, and the Memory Palace audit trail intact while gaining the SDK's tracing, output_type validation, and hosted-tool fleet. A pure migration would force us to re-engineer every governance feature inside the SDK — net regression. Bolt-on wins.

---

# POD 2 — MULTI-AGENT PATTERNS (Lead 2)

The five canonical patterns the SDK supports for composing multiple agents, mapped against our existing dispatchCommander, councilCoordinator, synapticBus, conflictResolver, and 7-layer cortex.

## A2-1. Triage / Router Pattern

A single front-door agent (the "triage" or "router") receives every user request and decides which specialist agent should actually handle it. Routing happens through the SDK's first-class `handoffs` mechanism: when the triage agent invokes a handoff, the SDK swaps the active agent for the target and the conversation continues seamlessly. This is the pattern in `examples/agent_patterns/routing.py` in the openai-agents-python repo.

```python
from agents import Agent, Runner, handoff

billing_agent = Agent(name="Billing", instructions="…", tools=[lookup_invoice])
refunds_agent = Agent(name="Refunds", instructions="…", tools=[issue_refund])

triage = Agent(
    name="Triage",
    instructions="Classify the user intent and hand off to the right specialist.",
    handoffs=[handoff(billing_agent), handoff(refunds_agent)],
)

result = await Runner.run(triage, input=user_msg)
```

**Maps onto our existing:** This maps almost 1:1 onto `agents/dispatch/dispatchCommander.ts` (`AGENT_LOAD_MATCHER`). DispatchCommander already plays triage: it subscribes to `load.created`, `driver.available`, `load.cancelled`, `market.capacity_alert`, branches on `event.type` in `handleEvent`, and either invokes `attemptAssignment` or emits `dispatch.intermodal_redirect` to push the load over to MultimodalLayer. The `dispatch.intermodal_redirect` event is functionally a handoff — Dispatch is saying "I'm done; rail/vessel takes it now."

The difference is that DispatchCommander dispatches by *publishing topics* (`synapticBus.publish`) and trusting that `intermodalWeaver`/`railBrain`/`vesselBrain` are subscribed, while the SDK does it by *direct agent reference* with type-checked handoff tools. Our version is loosely coupled (good for fault tolerance, bad for traceability). The SDK version is tightly coupled and produces a single linear trace.

**Migration recommendation:** Wrap DispatchCommander in an SDK `Agent` named `dispatch_triage` whose `handoffs` list contains `intermodal_agent`, `truck_dispatch_agent`, `backhaul_agent`. Keep `synapticBus` underneath for cross-tenant federation and audit replay, but make the *primary* control-flow path a Runner-driven handoff. The `dispatch.intermodal_redirect` topic becomes a side-effect telemetry event rather than the routing primitive.

**Risks:** (1) A triage agent classifying every event becomes a bottleneck. Our `dispatchCommander` already has `priority: 99` which suggests we feel this. Mitigate by sharding triage by transport mode. (2) `synapticBus.publish` fans an event out to every matching subscriber; handoff is single-target. Don't collapse multi-subscriber topics into handoffs. (3) `autopilot_events` table records every published event; SDK handoffs only show in the run trace. Either dual-write or accept a thinner audit log.

---

## A2-2. Supervisor / Agents-as-Tools Pattern

Instead of handing off, an orchestrator agent invokes specialists *as tools*. The specialist runs, returns a structured result, and control returns to the orchestrator. The SDK exposes this via `Agent.as_tool(tool_name=..., tool_description=...)`, which wraps any agent into an `function_tool`-callable.

```python
spanish_agent = Agent(name="Spanish", instructions="Translate to Spanish.")
french_agent  = Agent(name="French",  instructions="Translate to French.")

orchestrator = Agent(
    name="Translator-Supervisor",
    instructions="Use the translation tools and stitch the answers together.",
    tools=[
        spanish_agent.as_tool(tool_name="translate_to_spanish",
                              tool_description="Translate text to Spanish"),
        french_agent.as_tool(tool_name="translate_to_french",
                             tool_description="Translate text to French"),
    ],
)
```

**Maps onto our existing:** This is exactly the shape of `councilCoordinator.ts` (`convene()`). The function picks 3–6 candidate agents from `agentRegistry.getAgentsByLayer()`, runs three rounds of `synthesizeRationale` / `synthesizeProposal`, then `confidence-weighted vote` picks `winningAgentId`. Each seated agent is being used as a *callable* — the council coordinator is the supervisor, the seats are tool calls, and `voteTally` is the aggregation step.

**Migration recommendation:** Refactor `councilCoordinator.convene()` to: (1) build each `AgentConfig` in `agentRegistry` into an SDK `Agent` (one-time at startup), (2) have `convene` instantiate a transient `Supervisor` agent whose `tools` are the seated agents' `.as_tool()` wrappers, (3) use `output_type=CouncilProposal` so the supervisor receives structured rationales it can vote on, (4) keep the `palace.write` of the composite drawer. This is a cleaner home for high-stakes decisions than triage handoffs because the supervisor *retains* control and writes a single audit row. `conflictResolver.ts` is also a prime candidate — wrap each agent's proposal as a tool call, let the supervisor adjudicate, drop the priority-table heuristic.

**Risks:** Token cost (a 6-seat, 3-round council = 18 LLM calls per high-stakes decision). Latency under high-stakes events (compliance violations need sub-second reactions). Keep priority-table fast-path in `conflictResolver.ts` for L5 (`COMPLIANCE`) — only escalate to supervisor when priorities tie. Recursive cost — `Agent.as_tool()` lets a child agent itself call other agents; without depth limits costs compound.

---

## A2-3. Decentralized Swarm / Peer Handoffs

No central router. Every agent in the swarm has handoffs to its peers and decides on its own when to pass control sideways. The SDK's `handoffs=[…]` list on every `Agent` makes this trivially expressible — there's no required "root."

```python
faq      = Agent(name="FAQ", instructions="…", tools=[faq_lookup])
booking  = Agent(name="Booking", instructions="…", tools=[create_booking])
cancel   = Agent(name="Cancel", instructions="…", tools=[cancel_booking])

faq.handoffs     = [booking, cancel]
booking.handoffs = [faq, cancel]
cancel.handoffs  = [faq, booking]

result = await Runner.run(faq, input=user_msg)
```

**Maps onto our existing:** This is the closest analog to `core/synapticBus.ts`. SynapticBus is exactly a decentralized swarm: agents subscribe to topics, publish events, no central router. Pattern-matching subscriptions, per-agent `LaneQueue` (FIFO serialization), dead-letter retry loop (`MAX_RETRIES = 3`) all replicate what a swarm-of-handoffs would need.

The big differences: SynapticBus is **multi-cast** (one publish, N subscribers); SDK handoffs are **single-target**. SynapticBus is **fire-and-forget**; handoffs **transfer control synchronously**. SynapticBus has **company isolation** baked in (`if (event.companyId && sub.companyId && event.companyId !== sub.companyId) return false`); the SDK has nothing equivalent.

**Migration recommendation:** **Don't migrate this layer to SDK handoffs.** The synapticBus design is *better* for our domain: trucking telemetry is genuinely multi-cast (a `weather.alert` should reach Dispatch, Fleet, and Compliance simultaneously, not pick one). What we should do instead is build a thin SDK adapter: when an SDK agent emits a tool call like `notify_swarm(topic, payload)`, route it through `synapticBus.publish`. Use SDK peer handoffs *only* inside small, pre-defined cliques where lateral transfer is the right semantic — e.g. `truckBrain ↔ railBrain ↔ vesselBrain` for intermodal transfer.

**Risks:** Handoff loops (without depth limit, three peer-connected agents can ping-pong forever). Loss of provenance ("why did this happen?" is hard with no central node). Conflicting state (two peers both believing they own the load).

---

## A2-4. Manager + Parallel Fork-Join

A manager agent fans out work to N children in parallel, awaits all of them, then aggregates. The SDK supports this through `asyncio.gather` over multiple `Runner.run(child_agent, …)` calls, or by giving the manager many `agent.as_tool()` tools and instructing it to call them concurrently.

```python
import asyncio
from agents import Agent, Runner

translators = [spanish_agent, french_agent, italian_agent]

async def fan_out(text: str):
    runs = [Runner.run(t, input=text) for t in translators]
    results = await asyncio.gather(*runs)
    return [r.final_output for r in results]

aggregator = Agent(name="Picker", instructions="Pick the best translation.")
candidates = await fan_out(user_msg)
final = await Runner.run(aggregator, input=str(candidates))
```

**Maps onto our existing:** The sensory layer (Cortex Layer 1) is already shaped exactly like this. Eight nerves — `marketNerve`, `weatherNerve`, `trafficNerve`, `fuelNerve`, `geopoliticalNerve`, `complianceNerve`, `eldStreamNerve`, `newsSentimentNerve` — run in parallel on `runInterval` timers, each emits its own topic, and `contextAssembly.ts` plus `dispatchCommander`/`fleetCortex` aggregate. The strategic layer has the same shape.

**Migration recommendation:** Introduce an explicit `SensoryManager` SDK agent that does the join. On a tick, fan out to all eight nerves with `asyncio.gather`, collect their outputs into a typed `SensorySnapshot` Pydantic model, write a single drawer to the palace. Downstream consumers read the snapshot instead of subscribing to eight separate topics. For strategic, do the same: a `StrategicManager` fan-joins growth/competitor/oracle/architect/sentinel/prophet outputs into a quarterly `MarketPosture` artifact.

**Risks:** Stragglers (`asyncio.gather` waits for the slowest — mitigate with `asyncio.wait(..., return_when=FIRST_COMPLETED, timeout=…)`). Cost on fan-out (eight LLM-driven nerves = 8× tokens; keep deterministic nerves deterministic). Aggregator logic creep ("which signal wins?" is its own conflict-resolution problem; reuse `conflictResolver.ts` rules).

---

## A2-5. Hierarchical Agent Trees with Depth-Bounded Delegation

Agents organized in a tree where parents delegate downward. To prevent infinite delegation loops, the SDK enforces depth/turn limits. The two relevant knobs: `Runner.run(..., max_turns=N)` caps total LLM turns; the delegation model itself: a child agent *can* be given handoffs to other children, but normal practice is children only have a handoff *back* to a coordinator, or no handoffs at all (leaf).

```python
class Escalation(BaseModel):
    reason: str
    needs_layer: str

leaf = Agent(name="HazmatChecker", output_type=HazmatResult | Escalation)
mid  = Agent(name="ComplianceMid",
             tools=[leaf.as_tool("check_hazmat", "…")],
             output_type=ComplianceVerdict | Escalation,
             handoffs=[escalation_agent])
root = Agent(name="ComplianceRoot", handoffs=[mid])

result = await Runner.run(root, input=load, max_turns=8)
```

**Maps onto our existing:** Our 7-layer cortex is exactly a hierarchical tree, and `conflictResolver.ts`'s `LAYER_PRIORITY` table gives compliance-over-strategic-over-sensory ordering. The `priority: 0-100` field on every `AgentConfig` is the within-layer tiebreaker. What we're missing: an explicit **delegation depth counter**. Today nothing prevents `dispatchCommander` → `councilCoordinator.convene()` → seated agent that itself triggers `convene()` recursively.

**Migration recommendation:** Three changes: (1) Add `delegationDepth: number` to `AgentEvent` (default 0). Increment on every handoff/delegation. `synapticBus.publish` rejects events with depth > `MAX_DEPTH=8`. (2) In `councilCoordinator.convene()`, refuse to seat an agent that's already in the calling chain. (3) When wrapping our agents in SDK form, always pass `max_turns=8` to `Runner.run`. Catch `MaxTurnsExceeded` and route to `approvalQueue.ts` for human review.

The 7-layer model is *correct* for trucking; the issue is enforcement. Today the layer-ordering only kicks in *after* a conflict happens. It should kick in *before* — by topology. Make handoffs between agents only legal in specific directions: `SENSORY → DISPATCH/MULTIMODAL/FLEET`; `DISPATCH → COMPLIANCE/FINANCIAL`; `STRATEGIC` reads everyone but writes only via `approvalQueue`. Encode this in a static `ALLOWED_HANDOFFS: Record<CortexLayer, CortexLayer[]>` map.

**Risks:** False ceilings (real loads can need 12+ delegation hops; set per-layer budgets, not a global one). Escalation deadlock (Compliance escalates to Strategic, Strategic asks Compliance for clarification). Layer rigidity (strict topology prevents legitimate cross-layer collaboration; keep councilCoordinator as an **escape hatch**).

---

## Pod 2 Synthesis — The Trunk of Zenith Cortex

**The trunk should be the Supervisor / Agents-as-Tools pattern (A2-2), with SynapticBus retained underneath as the multi-cast nervous system and per-layer Manager+Fork-Join (A2-4) feeding it.**

Triage handoffs (A2-1) make sense at one specific seam — DispatchCommander already plays it — but they are too unidirectional to be the spine. Decentralized swarms (A2-3) match SynapticBus too well to discard, but a fully decentralized control plane gives us no "who decided this and why" line, and we need that for FMCSA audit trails. Hierarchical trees (A2-5) are a *constraint* layer, not an architectural pattern in their own right; they belong as topology rules over whatever pattern we pick.

The Supervisor pattern wins because it is the only one that gives us **structured aggregation with a single auditable artifact** — exactly what `councilCoordinator.ts` already attempts and what `conflictResolver.ts` does in the priority-tie case. Wrapping each of our 50 agents as `Agent.as_tool()` lets a small number of supervisor agents (one per cortex layer + one root `ZenithSupervisor`) drive real LLM reasoning over their outputs, write one drawer per decision into the palace, and route through `approvalQueue.ts` cleanly.

**Keep the 7-layer model**, but enforce it as topology (allowed-handoffs map) rather than as a post-hoc priority table. The layers map cleanly onto domain reality (sensory → operational → governance → strategic) and removing them would erase years of compliance reasoning.

---

# POD 3 — MEMORY, STATE, AND TRACING (Lead 3)

## A3-1. Session Memory Backends

OpenAI's Agents SDK ships a `Session` protocol that handles conversation history automatically across `Runner.run()` calls. The protocol is a small async interface: `get_items(limit)`, `add_items(items)`, `pop_item()`, `clear_session()`. Built-ins: `SQLiteSession`, `SQLAlchemySession.from_url()` (Postgres/MySQL/MSSQL), in-memory, `OpenAIConversationsSession` (hosted by OpenAI). Custom sessions are common, backed by Redis, DynamoDB, or a vector store.

```python
from agents import Agent, Runner, SQLiteSession
from agents.memory.session import SQLAlchemySession

agent = Agent(name="Dispatcher", instructions="...")
session = SQLiteSession("user-42-load-99", "conversations.db")

result = await Runner.run(agent, "What's the status of load 99?", session=session)
result2 = await Runner.run(agent, "Re-route it through Laredo.", session=session)
```

**Maps onto our existing:** `memoryStore.ts` is a key/value learning store, not a conversation log. Conversation continuity lives implicitly inside SynapticBus event replay and the Memory Palace's `hall_events` drawers under `wing=company:N / room=layer:X`. Closest analog to `get_items(session_id)` is `palace.getRun(wing, runId)` in `palaceAdapter.ts:149`.

**Migration recommendation:** Implement a `PalaceSession` adapter satisfying the OpenAI `Session` protocol but writing drawers into `hall_events` with `wing=wingFor(companyId)` and `room=roomForAgent(agentId)`. `session_id` becomes `runId`. `get_items` calls `palace.getRun()`. `add_items` calls `palace.write()` for each item. `pop_item` writes a tombstone drawer rather than truly deleting.

**Risks:** OpenAI Sessions store model "items" (system/user/assistant messages, tool calls). The Palace's verbatim rule says drawers are NEVER summarized — these align. But `pop_item`'s rollback semantics conflict with our append-only audit posture; tombstones are required. OpenAI's `session_id` is a flat string — encode `companyId::agentId::runId` and validate on read. `OpenAIConversationsSession` exfiltrates data to OpenAI infrastructure — disable for any tenant under HIPAA or EU residency contracts.

---

## A3-2. RunContext Typed Dependency Injection

`RunContextWrapper[TContext]` is the generic wrapper passed to every tool, hook, guardrail, and dynamic instruction function during a run. The actual user-supplied object lives at `wrapper.context`; the wrapper itself adds `usage` (token counters) and SDK-internal metadata. `context` is **not** sent to the LLM — it's local-process state.

```python
from dataclasses import dataclass
from agents import Agent, Runner, RunContextWrapper, function_tool

@dataclass
class CompanyDeps:
    company_id: int
    user_id: int
    role: str
    db: AsyncSession
    permissions: set[str]

@function_tool
async def fetch_load(wrapper: RunContextWrapper[CompanyDeps], load_id: int) -> str:
    if "loads.read" not in wrapper.context.permissions:
        return "DENIED"
    return await wrapper.context.db.fetch_load(load_id, wrapper.context.company_id)

agent = Agent[CompanyDeps](name="Dispatcher", tools=[fetch_load])
deps = CompanyDeps(company_id=42, user_id=7, role="DISPATCH", db=db, permissions={"loads.read"})
await Runner.run(agent, "Show load 99.", context=deps)
```

**Maps onto our existing:** Precise twin of our `AgentIdentity` interface in `core/agentIdentity.ts:51`. `AgentIdentity` carries `enabledByUserId`, `enabledByRole`, `companyId`, `permissions`, `transportModes`. Equivalent of `wrapper.context.permissions` is `BaseAgent.identity?.permissions`, checked at `baseAgent.ts:488` in `isActionAllowed`. `buildAgentIdentity()` is our equivalent of constructing a `CompanyDeps` instance.

The big delta: OpenAI SDK contexts are **per-run**, ours are **per-agent-instance** (set once via `setIdentity`). For multi-tenant SaaS, per-run is safer.

**Migration recommendation:** When porting an agent, replace `BaseAgent.identity` with a dataclass `AgentIdentityContext` that matches `AgentIdentity` field-for-field plus a `decision_logger` callable. Pass it into `Runner.run(agent, input, context=identity)`. Keep `buildAgentIdentity()` as the construction site.

**Risks:** Per-run vs. per-instance drift — tools written to read `self.identity` won't translate. Pydantic strict-mode rejects unknown keys. Forgetting `context=` silently passes `None`.

---

## A3-3. Tracing System

The Agents SDK has built-in tracing on by default. Every `Runner.run()` produces a `Trace` containing nested `Span`s: `agent_span`, `generation_span` (LLM calls), `function_span` (tool calls), `handoff_span`, `guardrail_span`, plus custom spans via `with custom_span("name"):`. The trace processor system is pluggable: `add_trace_processor(processor)` appends, `set_trace_processors([...])` replaces.

```python
from agents import Runner, RunConfig
from agents.tracing import add_trace_processor, custom_span, trace

class PalaceTraceProcessor:
    def on_span_end(self, span):
        palace.write_drawer(...)
    def on_trace_end(self, trace):
        palace.flush(trace.trace_id)

add_trace_processor(PalaceTraceProcessor())

with trace("load-dispatch", group_id=f"company:{cid}", metadata={"runId": run_id}):
    with custom_span("rate-evaluation"):
        result = await Runner.run(agent, input, context=deps)
```

**Maps onto our existing:** This is our `ReActStep` schema (`reactTrajectory.ts:15`) and `emitReActStep` helper (`baseAgent.ts:38`) almost line-for-line. `Trace` ↔ `runId`. `Span` ↔ `ReActStep`. `agent_span` ↔ `act` phase. `generation_span` ↔ `think` phase. `function_span` ↔ `act` payload's tool/args/result. The `trace processor` interface is structurally identical to our SynapticBus subscriber on `BUS_TOPIC_TRAJECTORY`.

**Migration recommendation:** Build `PalaceTraceProcessor` as our canonical processor: `on_span_start` writes a thin opening drawer, `on_span_end` writes the verbatim drawer using `wingFor(companyId)`, `roomForLayer(span.attributes['cortex_layer'])`, and the four-hall mapping. Keep OpenAI's hosted processor in parallel for dev/staging dashboards; disable in production via env flag (spans contain prompt content — PII risk). Add a `LangfuseProcessor` as a third for managed eval/replay UI. Critically, propagate `companyId` through `trace(metadata={...})`.

**Risks:** PII in spans (default tracing captures full prompts and tool args). Backpressure (default processor batches every 5s; overflow silently dropped). `group_id` tenancy (forgotten `group_id` merges traces from two tenants).

---

## A3-4. Lifecycle Hooks

Two parallel hook surfaces: `RunHooks` (one set, fires for every agent across the run) and `AgentHooks` (per-agent). Both expose: `on_agent_start`, `on_agent_end`, `on_handoff`, `on_tool_start`, `on_tool_end`, `on_llm_start`, `on_llm_end`. Wire via `Runner.run(agent, input, hooks=MyRunHooks())` for run-level, or on the agent itself for agent-level.

```python
from agents import RunHooks, AgentHooks

class PalaceRunHooks(RunHooks[CompanyDeps]):
    async def on_agent_start(self, ctx, agent):
        palace.write(drawer(phase="observe", agent=agent.name, ctx=ctx.context))
    async def on_tool_start(self, ctx, agent, tool):
        approval_queue.maybe_gate(tool.name, ctx.context)
    async def on_tool_end(self, ctx, agent, tool, result):
        palace.write(drawer(phase="act", tool=tool.name, result=result))
    async def on_agent_end(self, ctx, agent, output):
        palace.write(drawer(phase="reflect", outcome=output))

await Runner.run(agent, input, hooks=PalaceRunHooks(), context=deps)
```

**Maps onto our existing:** `BaseAgent.start()` (`baseAgent.ts:122`) and `stop()` correspond to `on_agent_start` and `on_agent_end`, but our hooks fire on **process lifecycle** while OpenAI's fire on **per-invocation lifecycle**. `BaseAgent.initialize()` and `cleanup()` are setup/teardown like a Python class `__init__`/destructor. Where we have no direct equivalent: **per-run, per-tool granularity**. The auto-emitted ReAct trajectory at `baseAgent.ts:216–292` is a hardcoded approximation.

**Migration recommendation:** Define a `RunHooksFromBase` that bridges: wraps `BaseAgent.publishEvent`, `recordDecision`, and `submitForApproval` so existing autopilot agents ported to Python keep emitting to SynapticBus + ApprovalQueue. `on_tool_start` calls `isActionAllowed` and short-circuits if RBAC denies. `on_handoff` writes a tunnel drawer.

**Risks:** Hook latency (`on_tool_start` runs synchronously before the tool — fire-and-forget unless gating). Exception in hooks can either kill the run or be swallowed. Hook + custom span double-counting.

---

## A3-5. Evals & Feedback Loops

OpenAI's eval framework: a **dataset** (inputs + reference outputs or graders), a **suite** of test cases, and an **eval run** that produces pass/fail + score per case. Three grader styles: deterministic (string match, JSON schema, regex, numeric tolerance), model-graded (judge model scores against a rubric), custom Python. Eval runs integrate with tracing.

```python
import openai
client = openai.OpenAI()

dataset = client.evals.datasets.create(name="dispatch-regression")
client.evals.datasets.items.create(dataset.id, item={
    "input": "What's status of load 99?",
    "expected_output": "delivered",
})

eval_def = client.evals.create(
    name="dispatch-eval",
    data_source_config={"type": "stored_completions", "dataset_id": dataset.id},
    testing_criteria=[
        {"type": "string_check", "name": "contains_status",
         "input": "{{sample.output}}", "operation": "ilike", "reference": "%delivered%"},
        {"type": "label_model", "name": "polite", "model": "gpt-4o",
         "input": "{{sample.output}}", "labels": ["polite","rude"], "passing_labels": ["polite"]},
    ],
)
```

**Maps onto our existing:** `DecisionRecord` with `feedbackScore` and `outcome` (`memoryStore.ts:237`) is our feedback ingestion layer. `learnFromOutcome` at `baseAgent.ts:574` is our grader-equivalent. `dream.ts` is structurally **agent-graded eval offline**: at night, `runOneDreamRound()` pulls reflect drawers, picks one success and one failure, runs counterfactual reasoning. We have no concept of versioned datasets, no diff between runs, and no regression detection across model swaps.

**Migration recommendation:** Stand up a `zenith-evals` directory with three pieces. (1) Curated datasets — nightly job extracts highest-impact decisions from `autopilot_decisions` into a versioned JSONL dataset. (2) Graders — deterministic for `recordOutcome` outcomes, agent-graded for free-text reasoning quality, custom Python for domain checks (HOS compliance, FSMA, USMCA). (3) Regression CI — every prompt/model change runs the dataset and writes a `hall_discoveries` drawer summarizing score deltas. Bridge to OpenAI's Datasets API by exporting our cases through the same `stored_completions` shape.

**Risks:** Cost (re-running 10K historical decisions through GPT-4o is expensive — sample stratified). Grader overfit (pin judge model version). Privacy (eval cases derived from production loads contain shipper/carrier names). Dream-to-eval feedback loop (promoting a dream insight as both a dataset case AND an A/B test risks the eval grading itself).

---

## Pod 3 Synthesis — Sessions, Palace, Dream

**Complement, with a clear seam.** OpenAI's `Session` is short-horizon conversation history. The Memory Palace is long-horizon, spatial, multi-tenant, lineage-aware verbatim storage with a tenancy invariant (`assertWing`), generational ancestry, and halls-by-phase taxonomy that delivered ~24% recall improvement over flat storage. Sessions cannot replace the Palace; equally, the Palace cannot replace Sessions without an adapter.

**Recommended path.** Implement `PalaceSession(companyId, agentId)` satisfying the OpenAI `Session` protocol. Internally `add_items` writes to `wing=company:N / room=agent:X / hall=hall_events`, `get_items` calls `palace.getRun()`, `pop_item` writes a tombstone. Run all OpenAI-SDK Python agents through this adapter. `RunContextWrapper[AgentIdentity]` carries our existing identity object. `PalaceTraceProcessor` ingests every span as a drawer. `PalaceRunHooks` enforce the approval queue at `on_tool_start`.

**dream.ts integrates as the offline consolidator.** Sessions accumulate live conversation drawers in `hall_events`; the trace processor adds reflect drawers to `hall_discoveries`. At 23:00 local, `runOneDreamRound` already pulls reflect drawers and writes counterfactual `dream` drawers tunneled to their sources. Extend it to (a) sample from the new `hall_events` session items, and (b) feed the highest-confidence dreams into the `zenith-evals` dataset table as candidate regression cases. The morning briefing then doubles as eval-suite update notes.

---

# POD 4 — VOICE, REALTIME, AND MCP (Lead 4)

## A4-1. Voice Agents Pipeline

The Agents Python SDK ships a first-class `voice` subpackage that stitches three components into a single end-to-end loop: a **Speech-to-Text model (`STTModel`)**, an **`Agent`**, and a **Text-to-Speech model (`TTSModel`)**. The orchestrator is `VoicePipeline`, fed by an `AudioInput` (single bounded utterance) or `StreamedAudioInput` (continuous mic) and emitting an `AudioOutput` stream. `VoicePipelineConfig` controls STT/TTS provider (OpenAI's `whisper-1` / `gpt-4o-transcribe` / `tts-1` / `gpt-4o-tts` are defaults).

```python
from agents import Agent, function_tool
from agents.voice import VoicePipeline, SingleAgentVoiceWorkflow, AudioInput, VoicePipelineConfig

@function_tool
async def hos_status(driver_id: str) -> dict:
    return await trpc.call("hos.status", driver_id=driver_id)

esang = Agent(
    name="ESANG-Voice",
    instructions="You are the EusoTrip driver copilot. Be terse on the wrist.",
    tools=[hos_status, accept_load, log_arrival, find_rest_stop],
)

pipeline = VoicePipeline(
    workflow=SingleAgentVoiceWorkflow(esang),
    config=VoicePipelineConfig(tracing_disabled=False),
)

audio_buffer = sd.rec(...).reshape(-1)
result = await pipeline.run(AudioInput(buffer=audio_buffer))
async for event in result.stream():
    if event.type == "voice_stream_event_audio":
        play(event.data)
    elif event.type == "voice_stream_event_lifecycle":
        emit_status(event.event)
```

**Maps onto our existing:** `ESangVoiceInputController` does STT today via `Speech.framework` + `AVAudioEngine` and ships finalized transcript to chat composer. `VoiceActionDispatcher.swift` (Watch) consumes structured `VoiceAction`s. The web platform's "mic mode" is the shape we want for iOS parity.

**Migration recommendation:** Keep `Speech.framework` STT on iOS for ultra-low-latency partial transcripts (Apple-platform UX win we can't match server-side). Use `VoicePipeline` only on the *response* side: feed it the finalized transcript as text, then stream `gpt-4o-tts` back. This gives: (a) Apple-quality on-device partials, (b) cheaper, faster server path, (c) uniform `Agent`/tools layer for both watch and phone.

**Risks:** TTS latency (~400-800ms first-byte; need "ESANG is thinking" earcon to mask). Codec mismatch (24 kHz mono int16 vs iOS 44.1 kHz default — explicit resampler). Slow tools cap voice quality (wrap every voice-exposed `function_tool` with `with_timeout(1500)`). PII in TTS (route any TTS-bound text through `scrubPii(..., maxPiiTier=PUBLIC)` before synthesis).

---

## A4-2. Realtime API Integration

The OpenAI Realtime API is a single bidirectional WebSocket (or WebRTC) connection that swallows STT, the LLM, and TTS into one model with **no pipeline boundaries**. Stream PCM up, get PCM down, and turn-taking, interruption, and tool-calling all happen inline. Model: `gpt-4o-realtime-preview`. The Agents SDK exposes this via `agents.realtime`: `RealtimeAgent`, `RealtimeRunner`, `RealtimeSession`.

```python
from agents.realtime import RealtimeAgent, RealtimeRunner

esang_rt = RealtimeAgent(
    name="ESANG-Realtime",
    instructions="You are EusoTrip's hands-free driver copilot. Confirm "
                 "destructive actions before invoking tools.",
    tools=[hos_status, accept_load, log_arrival, find_rest_stop, sos_escalate],
)

runner = RealtimeRunner(starting_agent=esang_rt)

async with await runner.run() as session:
    await session.send_audio(pcm_chunk_24khz)
    async for event in session:
        match event.type:
            case "audio":           ws_to_device.send(event.audio)
            case "audio_interrupted": ws_to_device.send({"cmd":"flush"})
            case "tool_call":       await dispatch_voice_action(event)
            case "history_added":   log_transcript(event.item)
```

**Maps onto our existing:** This is the *hands-free driving* mode the watch Pulse orb was built to host. Today the watch does push-to-talk; with Realtime, the orb instead opens a persistent WebRTC pipe; the driver speaks naturally, the model answers naturally, `VoiceActionDispatcher` consumes tool-call events as they happen.

**Migration recommendation:** Stand up a thin **realtime relay** in our Azure Python service: client opens WebRTC to *us*, we open WS to OpenAI, we forward audio both ways and proxy tool calls into our existing `skillRegistry`. Why relay vs direct: (a) sign tool calls with user's tRPC session, (b) PII-scrub tool outputs before spoken, (c) single place to switch models / fall back to `VoicePipeline`, (d) ephemeral tokens minted server-side avoid shipping API keys to mobile. Ship hands-free as a *separate UX state* — orb gets long-press to "go hands-free" and tap to fall back to existing PTT.

**Risks:** Cost (Realtime audio tokens are ~5-10× text tokens — meter per tenant, gate on subscription tier). Bargein false-positives (server VAD treats truck cabin noise as speech — configure aggressively, prefer client-side push-to-mute). Tool call atomicity (slow `accept_load` produces awkward filler — cap at 800ms, return "in-progress" intents). Session length cap (30-min today; relay must reconnect transparently).

---

## A4-3. MCP Server Hosting

Model Context Protocol (MCP) is the open spec for exposing tools, resources, and prompts to LLM clients. An **MCP server** publishes a typed tool catalog over `stdio`, `SSE`, or `streamable HTTP`. Python reference SDK is `mcp` (the `modelcontextprotocol` org). A server is constructed by decorating Python functions with `@mcp.tool()`; the framework auto-derives JSON schema from type hints + docstrings.

```python
from mcp.server.fastmcp import FastMCP
from typing import Literal
import httpx

mcp = FastMCP("eusotrip-cortex", version="1.0.0")
TRPC = "https://api.eusotrip.com/trpc"

@mcp.tool()
async def hos_status(driver_id: str) -> dict:
    """Return current HOS clock for a driver. Tier: confidential."""
    async with httpx.AsyncClient() as c:
        r = await c.post(f"{TRPC}/hos.status", json={"driverId": driver_id},
                         headers=auth_headers())
        return r.json()["result"]["data"]

@mcp.tool()
async def accept_load(load_id: str, driver_id: str,
                      confirm: Literal["yes"]) -> dict:
    """Accept a load. DESTRUCTIVE — requires confirm='yes'."""
    return await trpc("loads.accept", loadId=load_id, driverId=driver_id)

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8765)
```

**Maps onto our existing:** `skillRegistry.ts` is already a typed catalog with `inputSchema`, `outputSchema`, `tags`, `tier`. The MCP server is the natural **public face** of that registry: every entry where `tier <= INTERNAL` and the underlying handler is idempotent becomes an `@mcp.tool()`. We get the schema from `SkillEntry.inputSchema` essentially for free; one TS-side script can codegen Python stubs.

**Migration recommendation:** Stand up **`cortex-mcp`** as a sidecar Python service in the same Azure container app group. Codegen its tool list from `skillRegistry.ts`. Expose two transports: `streamable-http` for our iOS client (over TLS, with bearer auth), `stdio` for desktop dev tooling. Gate every destructive tool behind a `confirm` literal. Version the server (`cortex-mcp@1.0.0`) and pin clients to a major.

**Risks:** Permission sprawl (one rogue prompt to "accept all open loads" is a real risk — every destructive tool needs `confirm` gate AND out-of-band confirmation). Schema drift (codegen must run in CI and reject merges where Python server hasn't been regenerated). Auth model (use OAuth 2.1 bearer tokens scoped to tenant + driver, 1h TTL). Tool inflation (group by persona — different MCP server per persona).

---

## A4-4. MCP Server Consumption

The Agents Python SDK lets *our* agents *consume* third-party MCP servers as if their tools were locally defined. The `agents.mcp` module exposes four client classes: `MCPServerStdio`, `MCPServerSse`, `MCPServerStreamableHttp`, and `HostedMCPServerTool`.

```python
from agents import Agent, Runner
from agents.mcp import MCPServerStreamableHttp, MCPServerStdio, HostedMCPServerTool

cortex = MCPServerStreamableHttp(
    params={"url": "https://cortex-mcp.eusotrip.com/mcp",
            "headers": {"Authorization": f"Bearer {tenant_token}"}},
    cache_tools_list=True,
    name="eusotrip-cortex",
)

here = MCPServerStreamableHttp(
    params={"url": "https://here-mcp.eusotrip.internal/mcp"},
    name="here-lbs",
)

dispatcher = Agent(
    name="DispatchAgent",
    instructions="...",
    mcp_servers=[cortex, here],
)

async with cortex, here:
    out = await Runner.run(dispatcher, "Reroute load 7142 around the I-10 closure.")
```

**Maps onto our existing:** We already speak MCP outward (the eusorone-web-apps MCP); this section is about consuming MCP *inward* into our autopilot's 50 agents. Every external integration that's currently a hand-rolled tRPC adapter (HERE, FMCSA, FreightWaves, Stripe Connect) is a candidate to be re-wrapped as an MCP server.

**Migration recommendation:** Three-tier hierarchy: (1) **Internal MCP servers** (we author): `cortex-mcp`, `here-mcp`, `compliance-mcp`. Use `MCPServerStreamableHttp`. Cache tool lists. (2) **Hosted-by-OpenAI** (`HostedMCPServerTool`): use only for high-latency-from-Azure servers. (3) **Stdio** (`MCPServerStdio`): dev-loop only. For the iOS app: the iOS client speaks tRPC, not MCP directly. Recommendation: server-side consumption, tRPC façade.

**Risks:** Tool-list cache staleness (bust on `version` header change). Server fan-out latency (pre-warm at boot). Approval prompts (`HostedMCPServerTool` defaults to interactive — set `require_approval="never"` for autonomous agents and gate destructively at the tool layer). Transport selection (SSE is legacy; new code = `streamable-http`).

---

## A4-5. Computer-Use Tool

`ComputerTool` is an SDK primitive that lets an agent drive a browser or desktop via screenshots + mouse/keyboard actions. Wraps the underlying `computer-use-preview` model: agent sees screenshot, decides on action (`click(x,y)`, `type(text)`, `scroll`, `keypress`), tool executes (typically against Playwright-controlled browser), feeds back new screenshot.

```python
from agents import Agent, Runner, ComputerTool
from agents.computer import AsyncComputer
from playwright.async_api import async_playwright

class PlaywrightComputer(AsyncComputer):
    @property
    def environment(self): return "browser"
    @property
    def dimensions(self): return (1280, 800)

    async def screenshot(self) -> str:
        return base64.b64encode(await self.page.screenshot()).decode()
    async def click(self, x, y, button="left"):
        await self.page.mouse.click(x, y, button=button)
    async def type(self, text): await self.page.keyboard.type(text)

async with async_playwright() as p:
    browser = await p.chromium.launch(headless=True)
    page = await browser.new_page()
    await page.goto("https://www.vucem.gob.mx/")
    pc = PlaywrightComputer(page)

    filer = Agent(
        name="CartaPorteFiler",
        instructions="File a Carta Porte 3.1 declaration. Stop and ask if "
                     "the page asks for OTP — never bypass MFA.",
        tools=[ComputerTool(computer=pc)],
        model="computer-use-preview",
    )
    await Runner.run(filer, json.dumps(load_payload))
```

**Maps onto our existing:** Cross-border filing problem is the perfect fit: SAT's VUCEM portal and CBP's ACE Secure Data Portal are *human-only* web UIs with no programmatic API for the workflows we care about. The 50-agent autopilot already has cross-border compliance agents producing *advice*, not *filings*. `ComputerTool` closes the last mile. Same story for HOS audit (FMCSA's eRODS portal).

**Migration recommendation:** Build a sandboxed **`computer-use-runner`** Azure Container App: ephemeral Playwright browsers, network-policied to *only* the target government domain plus our internal API. Use `computer-use-preview` model only. Every action goes through a hard allowlist filter. Rollout: (1) **read-only** scrapers first, (2) **draft + human-approves-submit** filings, (3) only after 90 days clean, **fully autonomous filings** for low-risk doc types.

**Risks:** Regulatory (autonomous government filings create legal exposure if agent hallucinates). Bot detection (VUCEM and ACE both have bot-detection — verify ToS per portal). MFA / OTP (agent must never attempt to defeat MFA — build OTP-handoff flow). Cost + latency (`computer-use-preview` is slow and expensive — cache navigation paths). Audit trail (every action needs immutable screenshot + action log).

---

## Pod 4 Synthesis — 90-Day Play for ESANG Voice + iOS-Consumable Cortex via MCP

Ship in three concentric rings.

**Ring 1 (days 0-30) — `cortex-mcp` server.** Codegen a Python `FastMCP` server from `skillRegistry.ts`; expose ~30 read-only driver/dispatcher skills via `streamable-http` behind tRPC-issued bearer tokens; route every output through `channelGateway`'s PII scrubber. Single artifact unlocks both the iOS app and any future internal Agents SDK consumer. Pin to v1.0.0; CI-gate schema drift.

**Ring 2 (days 30-60) — ESANG voice via `VoicePipeline`, hands-free via Realtime relay.** Keep `Speech.framework` for on-device partial STT (UX win), pipe finalized transcripts into a server-side `Agent` whose tools are sourced from `cortex-mcp`, stream `gpt-4o-tts` back. In parallel, stand up a Realtime relay for the watch Pulse orb's "long-press = hands-free" mode — same agent, persistent WebRTC, server VAD. Cap voice-exposed tool latency at 1.5s and gate destructives via `VoiceActionDispatcher`'s existing confirmation slots.

**Ring 3 (days 60-90) — `ComputerTool` for cross-border filings, read-only.** Sandboxed Playwright in Azure, network-policied to VUCEM + ACE, *read-only* (filing status pulls). Phase 2 (draft + human-approves-submit) lights up at day 90 once audit-trail and OTP-handoff are proven.

By day 90 ESANG talks like a copilot, the iOS app consumes the 50-agent cortex via one MCP endpoint, and we own a sandbox where computer-use unlocks the regulatory filings nobody else can automate.

---

# POD 5 — PRODUCTION HARDENING (Lead 5)

## A5-1. Streaming Output, Partial Responses, Cancellation

`Runner.run_streamed(...)` returns a `RunResultStreaming` object with an async iterator over `StreamEvent`s: `RawResponsesStreamEvent` (raw deltas — almost never surface to users), `RunItemStreamEvent` (agent-aware items: `tool_call_item`, `tool_call_output_item`, `message_output_item`, `handoff_occurred`), `AgentUpdatedStreamEvent` (handoff swaps active agent). Cancellation is cooperative via `asyncio.CancelledError`.

```python
result = Runner.run_streamed(agent, input=user_msg, max_turns=15)
async for ev in result.stream_events():
    if ev.type == "raw_response_event": continue
    if ev.type == "agent_updated_stream_event":
        ws.send({"type": "handoff", "to": ev.new_agent.name})
    elif ev.type == "run_item_stream_event":
        item = ev.item
        if item.type == "tool_call_item":          ws.send({"type": "tool_called", "name": item.raw_item.name})
        elif item.type == "tool_call_output_item": ws.send({"type": "tool_done"})
        elif item.type == "message_output_item":   ws.send({"type": "message", "text": ItemHelpers.text_message_output(item)})

task = asyncio.create_task(run_and_stream())
await asyncio.wait_for(task, timeout=30.0)
```

**Maps onto our existing:** `blockStreaming.ts` already does what the SDK explicitly recommends: buffers partial reasoning, flushes only when 3 blocks accumulated, 5s elapsed, or all four ReAct phases present. `BlockStreamer.flush()` callback ↔ `await for ev in result.stream_events()`. We do *not* currently expose cancellation.

**Migration recommendation:** Keep `BlockStreamer` as the UI-facing flush layer. Where we wrap `Runner.run_streamed`, feed `RunItemStreamEvent`s into `blockStreamer.emit({ phase: mapItemTypeToPhase(item.type), ... })`. Add `AbortSignal` parameter to `BaseAgent.run()` and `synapticBus.publish()`; thread it from the dashboard's Stop button. For timeouts, wrap each agent cycle in `Promise.race([runCycle(), timeoutPromise])` and call `agentRegistry.reportError(id, 'CycleTimeout')` on expiry.

**Risks:** Raw-token streaming leaks reasoning to users (prompt-injection demonstrator class). Cancellation propagation through tool calls is partial — any in-flight HTTP call won't honor cancel until await resolves; mitigate with per-tool `signal: AbortSignal` plumbing.

---

## A5-2. Cost Control: Token Budgets, Model Choice, Prompt Caching

Three cost knobs: (1) `ModelSettings(temperature, max_tokens, tool_choice, parallel_tool_calls)` per agent. (2) `model="gpt-4o-mini" | "gpt-4o" | "gpt-5"` per agent — each agent can run on a different model. (3) Prompt caching — automatic on `gpt-4o`/`gpt-4o-mini` for prompts ≥1024 tokens; exact prefix match required, 5–10 minute TTL, 50% discount on cached input tokens, 0 on output. `Runner.run` exposes `usage` on `RunResult`.

```python
governance_agent = Agent(
    name="ComplianceSentinel", model="gpt-5",
    model_settings=ModelSettings(temperature=0.1, max_tokens=2000),
    instructions=STATIC_LONG_PREFIX + dynamic_suffix,
)
optimizer_agent = Agent(
    name="DeadheadEliminator", model="gpt-4o-mini",
    model_settings=ModelSettings(temperature=0.3, max_tokens=800, parallel_tool_calls=True),
)
```

**Maps onto our existing:** Our `agentRegistry.getAgentsByLayer(CortexLayer.GOVERNANCE)` already segregates the 50-agent fleet by SkillTier. We have no per-agent `model` field in `AgentConfig`, no token budget tracking. The four-tier `SkillTier` (GOVERNANCE > SECURITY > BUSINESS > OPTIMIZATION) maps cleanly onto a four-tier model policy.

**Migration recommendation:** Tier the 50-agent fleet:
- **GOVERNANCE / SECURITY (~12 agents)**: `complianceSentinel`, `soc2Guardian`, `hazmatCommander`, `auditChain`, `crossBorderDiplomat`, `documentWarden`, `insuranceMonitor`, `drugTestScheduler`, `walletGuardian` — `gpt-5` or `gpt-4o`. Cost-justified because regulatory misjudgment carries real liability.
- **BUSINESS (~22 agents)**: `dispatchCommander`, `brokerNegotiator`, `revenueArchitect`, `marketOracle`, `rateSurgeon`, `factoringBrain`, `growthStrategist` — `gpt-4o`.
- **OPTIMIZATION / SENSORY (~16 agents)**: `weatherNerve`, `trafficNerve`, `fuelNerve`, `etaOracle`, `routeGenius`, `deadheadEliminator`, all `*Nerve.ts` — `gpt-4o-mini`. 95% cheaper.

Add `model: ModelChoice` and `maxTokensPerTurn: number` to `AgentConfig`. Add a `CostLedger` singleton parallel to `palaceMetrics`. Restructure prompts so the 2k-token static governance preamble lives at the *front* — that's what prompt-caching keys on. Add a `dailyDollarBudget` per company.

**Risks:** Prompt caching is silent on misses (whitespace mutation breaks it — add hash check at agent boot). `gpt-5` for governance may exceed budget for high-volume tenants (per-company-tier model assignment). `parallel_tool_calls=True` blowing token budgets via simultaneous fan-out.

---

## A5-3. Error Handling and Retry Policies

Typed exception hierarchy: `MaxTurnsExceeded`, `ModelBehaviorError`, `UserError`, `InputGuardrailTripwireTriggered`, `OutputGuardrailTripwireTriggered`. Tools have a `failure_error_function` parameter. `Runner.run` does not retry by default; underlying `openai` SDK retries on 429/500-class HTTP errors.

```python
@function_tool(failure_error_function=lambda ctx, err: f"Tool failed: {err}. Try a different approach.")
async def assign_driver(load_id: int, driver_id: int) -> str: ...

try:
    result = await Runner.run(agent, input=msg, max_turns=10)
except MaxTurnsExceeded:
    metrics.inc("max_turns")
    return "I need more steps than allowed. Escalating."
except InputGuardrailTripwireTriggered as e:
    audit.log(e.guardrail_result); return SAFE_REFUSAL
except ModelBehaviorError as e:
    if attempts < 3: await asyncio.sleep(2**attempts); attempts+=1; continue
    raise
```

**Maps onto our existing:** `BaseAgent` keeps `private errorCount = 0` and `agentRegistry.reportError(agentId, err)` increments per-agent counter. We have no typed exception hierarchy — every error is generic `Error`. `policyEngine.ts` and `guardrails.ts` return `GuardrailResult` objects rather than throwing tripwires.

**Migration recommendation:** Introduce typed errors in `core/types.ts`: `class GuardrailTripwire extends Error`, `class MaxTurnsExceeded extends Error`, `class ToolValidationError extends Error`, `class ModelBehaviorError extends Error`. Wrap every `BaseAgent.run()` cycle in retry-with-backoff. Add a `circuitBreaker` per agent: when `errorCount > 5` in 60s, set agent state to QUARANTINED and skip cycles for 5 min. Adopt the SDK's `failure_error_function` pattern in `toolCallValidator.ts`.

**Risks:** Naive retry on `ModelBehaviorError` will burn tokens forever if prompt is structurally broken. Don't retry guardrail tripwires. Circuit breaker thresholds need per-tier tuning.

---

## A5-4. Security: Prompt Injection, PII Redaction, Tool Allowlists

Two guardrail types: `@input_guardrail` runs before the agent sees user input, `@output_guardrail` runs on the agent's final output. Each returns `GuardrailFunctionOutput(output_info=..., tripwire_triggered=bool)`. For tool allowlists, each `Agent` is constructed with explicit `tools=[...]` — agents physically cannot call tools not in their list. PII redaction is not in the SDK; bring your own (Presidio, regex, NemoGuard).

```python
@input_guardrail
async def block_injection(ctx, agent, user_input):
    classifier = await Runner.run(injection_classifier_agent, user_input)
    return GuardrailFunctionOutput(
        output_info=classifier.final_output,
        tripwire_triggered=classifier.final_output.is_injection,
    )

dispatch_agent = Agent(
    name="Dispatcher",
    tools=[search_loads, assign_driver],
    input_guardrails=[block_injection, redact_pii],
    output_guardrails=[block_pii_leak],
)
```

**Maps onto our existing:** This is where we are *ahead* of vanilla SDK adoption. `guardrails.ts` (`NeMoGuardrails`) already implements four rail types (INPUT/EXECUTION/OUTPUT/DIALOG) with both regex-based local rules and `evaluateWithNIM()` 3-model NemoClaw pipeline. `privacyRouter.ts` does 4-tier PII classification with retention windows. `toolCallValidator.ts` does schema validation per tool with `requiredParams`, `paramTypes`, `paramConstraints`, and `maxPayloadSize` — strictly more than the SDK gives you.

**Migration recommendation:** Keep our stack as-is and treat the SDK guardrails as a *thin adapter* layer. Wrap our existing modules into SDK-shaped guardrail functions. Add tool-allowlist enforcement in `AgentConfig`: `allowedTools: string[]`. Extend `privacyRouter` with a `redactString(text)` method that runs the same regex set as our OUTPUT guardrail and substitutes `[SSN]`, `[CC]`, `[CDL]` tokens — call it on every `RunItemStreamEvent` of type `message_output_item` before flushing through `blockStreamer`.

**Risks:** Regex-based PII is brittle. NemoClaw async pipeline is robust but adds 200-800ms latency — gate on `tier >= CONFIDENTIAL` only. `output-hallucination` is a `WARN` not `BLOCK` — for governance agents bump to `BLOCK`. Tool allowlists need to be enforced at the *executor* level, not the agent level.

---

## A5-5. Observability: Metrics, Alerts, Distributed Tracing

The SDK has built-in tracing on by default. Every `Runner.run` produces a `Trace` containing `Spans`. Traces POST'd to OpenAI's tracing dashboard automatically. Register additional `TracingProcessor`s — `add_trace_processor(BatchTraceProcessor(MyExporter()))`. Community ships exporters for Logfire, AgentOps, Langfuse, Braintrust, MLflow. For OTEL/Datadog, write a `TracingProcessor` that converts `Span` to `OTLPSpan`.

```python
from openai.agents import set_tracing_export_api_key, add_trace_processor
from openai.agents.tracing import BatchTraceProcessor

class DatadogProcessor(TracingProcessor):
    def on_span_end(self, span):
        statsd.histogram("agents.span.duration_ms", span.duration_ms,
                         tags=[f"agent:{span.agent_name}", f"type:{span.type}"])
        if span.error: statsd.increment("agents.span.errors", tags=[...])

add_trace_processor(BatchTraceProcessor(DatadogProcessor()))
```

**Maps onto our existing:** `palaceMetrics.ts` is a lightweight in-process counter — no OTEL, no histogram support, no per-agent latency. `dashboard.ts` exposes counts via tRPC by polling DB. `synapticBus.getMetrics()` gives publish/deliver/fail/dead-letter counts. We have *no* distributed tracing.

**Migration recommendation:** Three-layer observability:
1. **Span layer** (new): adopt OTEL JS SDK in `core/synapticBus.ts`. Wrap `publish()` in `tracer.startActiveSpan('synaptic.publish', ...)`, propagate `traceparent` headers through event payload, `BaseAgent.runCycle()` starts a child span. Each `emitReActStep()` becomes a span. Export to Datadog APM via OTLP.
2. **Metric layer** (extend): replace `palaceMetrics` counters with OTEL `Counter`/`Histogram` instruments. Add `agent.cycle.duration_ms` histogram, `agent.tokens.prompt`/`completion`/`cached` counters, `guardrail.blocks` counter.
3. **Alert layer** (new): wire metrics to PagerDuty/Datadog monitors. Critical: `guardrail.blocks{severity=BLOCK} > 10/min`, `agent.errors > 5/min`, `cost.daily_spend > budget*0.8`, `synaptic.dead_letter_count > 0`.

**Risks:** OpenAI's default trace exporter ships prompt+completion to OpenAI's dashboard (disable for any tenant with PII obligations). OTEL trace volume can blow up — use `BatchTraceProcessor` with sampling.

---

## Pod 5 Synthesis — 90-Day Hardening Roadmap

**Days 0-30 (foundations).** Add typed errors and circuit-breaker semantics in `BaseAgent`. Add `model: ModelChoice` and `maxTokensPerTurn` to `AgentConfig`, tier the 50 agents (mini for 16 sensory/optimization, 4o for 22 business, 5/4o for 12 governance/security). Build `CostLedger` parallel to `palaceMetrics`. Audit static prompt prefix on every agent so prompt caching actually hits.

**Days 30-60 (observability + cancellation).** Adopt OTEL JS in `synapticBus` with traceparent propagation. Replace `palaceMetrics` counters with OTEL instruments. Wire Datadog monitors for the four critical alerts. Thread `AbortSignal` through `BaseAgent.run()` and dashboard Stop button. Add per-agent `dailyDollarBudget` short-circuit.

**Days 60-90 (security tightening).** Add `allowedTools` allowlist to `AgentConfig` and enforce at executor. Extend `privacyRouter` with `redactString()` and call it in the `blockStreamer` flush path. Promote `output-hallucination` from WARN to BLOCK for governance agents. Gate NemoClaw 3-model evaluation on `tier >= CONFIDENTIAL`.

**What the SDK gives us free** vs **what we keep custom.** Free from SDK: streamed item events, tool allowlists per Agent constructor, typed exception hierarchy, automatic OpenAI-dashboard tracing, `model_settings` budgets, `ModelBehaviorError` retry primitives. **Keep custom (the OpenClaw/NemoClaw moat):** 4-tier PII router with retention windows, NemoClaw 3-model NIM pipeline, RBAC v2 identity binding, OpenClaw SkillTier enforcement, `policyEngine` company-scoped overrides, idempotency service, kernel sandbox, ReAct trajectory phase semantics. The SDK is a thin agent loop; our governance stack is the hardened layer on top.

---

# PART II — CORTEX APPLICATION

# POD 6 — LAYER 1 + LAYER 2 MIGRATION (Lead 6)

8 Sensory + 8 Dispatch agents. Path: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/services/autopilot/`.

## SENSORY LAYER (8 agents)

**B1-1. weatherNerve.** Pure `BaseAgent` on a 5-minute timer. Pulls `hz_weather_alerts`, filters SEVERE_TYPES, dedups by alert hash, emits `weather.alert`, `weather.route_impact`, `weather.forecast_shift`. Today data is already in MySQL by upstream ingestor; nerve never calls WeatherKit/HERE itself. **Recommendation:** wrap as MCP server, not Python-port. Expose `scan_severe_alerts`, `score_state_impact`, `detect_forecast_shift` as `@function_tool`. Add LLM step only for headline → recommendation synthesis. Tools include `fetch_weatherkit_now(lat, lng)` and `fetch_here_destination_weather(route_polyline)` (NEW). Emits to: `dispatch_commander`, `route_genius`, `eta_oracle`, `convoy_commander`, `driver_wellness_ai`, `priorityArbitrator`. Roles consuming: dispatcher, driver, broker, shipper, fleet manager.

**B1-2. trafficNerve.** Five-minute periodic. Reads `hz_road_conditions`, filters HIGH_IMPACT_TYPES, aggregates by state, emits `traffic.incident`, `traffic.congestion`, `traffic.parking_shortage`. Migration: Wrap as MCP server with optional inline LLM for incident-narrative summarization. Add HERE Traffic v7 fetch as a tool the agent calls on hotspots only (rate limits + cost). Tools: `scan_road_incidents`, `fetch_here_traffic_v7(bbox)`, `score_state_congestion`, `detect_parking_shortage`, `lookup_alternate_route`. Emits to: `dispatch_commander`, `route_genius`, `eta_oracle`, `convoy_commander`, `bidOptimizer`, `crossBorderDiplomat`, `geofence_sentinel`. Roles: dispatcher, driver, broker, fleet manager, shipper.

**B1-3. fuelNerve + complianceNerve + geopoliticalNerve (cluster — keep separate).** Three specialist agents, all handed off from `sensory_supervisor`. fuelNerve runs hourly, reads PADD prices, emits `fuel.price_change`, `fuel.optimal_stop`, `fuel.fsc_recalibrate` (FSC adjustment via `(currentDOE - base)/MPG`, MPG=6). complianceNerve also hourly: scans `documents` for permits/certs expiring within 60 days, emits `compliance.permit_expiry`, `compliance.regulation_change`. geopoliticalNerve every 30 min: monitors FEMA disasters, ten major US-MX/US-CA crossings, emits `geo.disaster_zone`, `geo.border_delay`, `geo.trade_disruption`. Operating on disjoint data domains — consolidating loses tool-call locality. Tools per agent listed in expanded version. Roles consuming: fuel → driver, dispatcher, broker, CFO; compliance → safety officer, dispatcher, driver, legal; geopolitical → cross-border dispatcher, broker, shipper, CFO.

**B1-4. eldStreamNerve.** Currently a thin stub: 60-sec timer queries `drivers` for `status='on_load'`, parses `hoursAvailable`, publishes `eld.violation` when `hours < 2`. Real-time stream consumption from KeepTruckin/Motive, Samsara, Geotab is the migration target. **Recommendation:** Realtime API + Agent fallback. Realtime session per active fleet subscribes to ELD WebSockets; warm Agent for batch reconciliation. Tools: `scan_low_hours_drivers`, `reconcile_motive_log`, `reconcile_samsara_log`, `propose_relay_swap`, `compute_remaining_drive_window`. Emits to: `dispatchCommander`, `priorityArbitrator`, `convoyCommander`, `complianceSentinel`, `driverWellnessAI`, `routeGenius`. Roles: driver, dispatcher, safety officer, fleet manager.

**B1-5. newsSentimentNerve + marketNerve.** newsSentimentNerve hourly stub today; will scan freight-trade news, classify sentiment, emit `news.sentiment` + `news.disruption`. marketNerve 10-min periodic: reads `loads` for current-day origin-state load counts vs 7-day avg, emits `market.demand_surge` (>=1.3x), `market.capacity_alert` (<=0.7x), `market.rate_shift`, `market.fuel_spike`. **Recommendation:** Two specialist agents handed off from `sensory_supervisor`. news tools: `fetch_freightwaves`, `fetch_joc_rss`, `classify_sentiment`, `extract_named_entities`, `correlate_disruption_to_lanes`. market tools: `scan_load_volumes_by_state`, `scan_capacity_ratio`, `fetch_dat_rateview`, `compute_lane_rate_shift`. Emits to: `geopoliticalNerve`, `marketOracle`, `crossBorderDiplomat`, `bidOptimizer`, `brokerNegotiator`, `rateSurgeon`, `growthStrategist`, `demandProphet`, `dispatchCommander`. Roles: broker, shipper, CFO, dispatcher.

## DISPATCH LAYER (8 agents)

**B2-1. dispatchCommander.** L2 master orchestrator. Subscribes to `load.created`, `driver.available`, `load.cancelled`, `market.capacity_alert`. Routes INTERMODAL_TYPES via `dispatch.intermodal_redirect`, calls `scoreCandidates(loadId)` from smartAssign2, auto-assigns if score >= MIN_ASSIGNMENT_SCORE (40), publishes `dispatch.assigned` or `dispatch.no_match`. Priority 99. **Recommendation:** This IS the supervisor. Textbook OpenAI Agents SDK triage pattern. dispatchCommander becomes the L2 supervisor with seven other dispatch agents registered as handoffs. Tools: `fetch_load_details`, `classify_intermodal_candidate`, `record_assignment`, `record_no_match`, `update_assignment_stats`. Handoffs: smartAssign2, brokerNegotiator, backhaulHunter, deadheadEliminator, bidOptimizer, priorityArbitrator, loadBundler, intermodalWeaver. Roles: dispatcher (primary), driver, broker, shipper, fleet manager.

**B2-2. smartAssign2 + brokerNegotiator (load matching swarm).** smartAssign2 — 12-factor scoring engine, NOT event-driven, exported as `scoreCandidates(loadId, limit=10)`. Weights sum to 1.0. Uses haversine for proximity. Returns `CandidateScore[]` with totalScore + per-factor breakdown. brokerNegotiator — subscribes to `bid.received` and `market.rate_shift`. MAX_COUNTER_OFFERS=3, MARKET_TOLERANCE_PCT=0.15. **Recommendation:** Different patterns per agent. smartAssign2 is pure deterministic math — wrap as MCP tool, no agent shell needed. brokerNegotiator is the perfect natural-language agent with `output_type=NegotiationDecision`. Roles: smartAssign2 → dispatcher, driver, fleet manager; brokerNegotiator → broker, shipper, CFO.

**B2-3. backhaulHunter + deadheadEliminator (backhaul intelligence).** backhaulHunter subscribes to `dispatch.assigned`. After assignment, scans loads within SEARCH_RADIUS_MI=50 of delivery drop, filtered by DELIVERY_BUFFER_HOURS=2 and MAX_HOS_HOURS=11. deadheadEliminator periodic every 15 min. Identifies trucks idle > 4 hr, queries demand zones, computes ROI assuming DEADHEAD_COST_PER_MILE=$2.50, emits `reposition.proposed` only when ROI >= 20%. **Recommendation:** Both Agent-shaped (recommendations need natural-language justification). Output `BackhaulProposal` and `RepositionProposal` Pydantic models. Roles: driver, dispatcher, fleet manager, CFO.

**B2-4. bidOptimizer (rate negotiation with structured output).** Subscribes to `load.posted`. Three explicit strategies in STRATEGY_MULTIPLIERS: conservative (0.95/1.00/1.05), competitive (0.88/0.93/0.98), aggressive (0.80/0.85/0.92). Updates `bid_stats` for online win-rate learning. **Recommendation:** Cleanest Agents SDK fit in dispatch layer. Define Pydantic `BidDecision { strategy, bid_amount_usd, rationale, confidence_pct, walk_away_floor }`. Tools: `fetch_load_details`, `fetch_market_rate`, `fetch_win_rate_history`, `fetch_shipper_relationship`, `submit_bid`, `record_bid_outcome`. Roles: broker (primary), dispatcher, CFO, revenue ops.

**B2-5. priorityArbitrator + loadBundler (orchestrator pattern).** priorityArbitrator subscribes to `dispatch.conflict`. Weights: revenueImpact 0.30, customerTier 0.25, deadlineUrgency 0.25, cascadeRisk 0.20. loadBundler periodic every 5 min. Clusters unassigned loads within CLUSTER_RADIUS_MI=50 and TIME_WINDOW_HOURS=8, packs by weight (MAX 44000 lbs) and count (MAX 4 stops). **Recommendation:** Both fit "orchestrator-with-tools" pattern. priorityArbitrator produces `ArbitrationDecision`; loadBundler produces `BundleProposal`. Roles: priorityArbitrator → dispatcher, shipper, CFO; loadBundler → dispatcher, driver, broker.

## Pod 6 Synthesis — 16 Specialists vs 2 Supervisors

**Recommendation: 2 supervisors + 16 callable specialists (hybrid).** Make `sensory_supervisor` and `dispatch_supervisor` the two top-level OpenAI SDK Agents that the rest of Zenith Cortex (and tRPC backend) talk to. Inside each supervisor, register 8 individuals as **handoffs** for genuinely autonomous specialists (LLM reasoning over natural language: brokerNegotiator, bidOptimizer, priorityArbitrator, newsSentimentNerve, marketNerve, weatherNerve, geopoliticalNerve, complianceNerve) and as **`@function_tool` calls** for deterministic-math specialists (smartAssign2, fuelNerve dedup, trafficNerve aggregations, eldStreamNerve violation checks, backhaulHunter haversine search, deadheadEliminator ROI math, loadBundler bin-packing, dispatchCommander intermodal classification).

Pure 16-specialist topology bloats handoff routing and replicates context per agent (16x token cost on every shared payload). Pure 2-supervisor topology collapses tracing — when `dispatch.assigned` decision goes wrong you cannot inspect which sub-agent's prompt was at fault. Hybrid keeps independent traces, bills only for LLM steps that actually need language, matches OpenAI's documented triage-with-handoffs reference.

Migration path: start with both supervisors thin (just routing prompts), wrap all 16 today's TypeScript implementations behind MCP `@function_tool` adapters, promote individual specialists from tool-only to handoff-Agent only after they prove they need autonomous reasoning.

---

# POD 7 — LAYER 3 (MULTIMODAL) + LAYER 4 (FLEET) MIGRATION (Lead 7)

14 agents. 6 multimodal supervisors-of-mode + 8 fleet specialists.

## MULTIMODAL LAYER (6 agents)

**B3-1. truckBrain.** Periodic (60s) BaseAgent that scans `loads` for status transitions against hard-coded `STATUS_FLOW` map and emits `truck.status_transition`, `truck.stale_load`, `truck.lifecycle_alert`. **SDK shape:** `Agent[TruckCtx]` with tools `search_loads`, `get_load_details`, `hos_status`, `dispatch_board`, `publish_lifecycle_event`, `record_status_transition`. Handoffs: `intermodal_weaver`, `route_genius`, `eta_oracle`, `hazmat_commander` (conditional). `output_type=TruckLifecycleDecision`. STATUS_FLOW and STALE_THRESHOLDS move into a Pydantic policy resource the agent reads via tool. **Driver-facing:** Drivers don't see truckBrain by name — they see consequences ("Status looks stale — confirm location?" nudge, one-tap "Mark in transit" CTA). Dispatchers see Lifecycle Health column in dispatch board. **Guardrails:** Cannot auto-advance to `in_transit` if HOS in mandatory rest. Hazmat handoff before any state-border crossing with placarded cargo. Tier 2.

**B3-2. railBrain.** Hybrid event + periodic. Reacts to `rail.shipment_created`, runs every 120s to scan `rail_shipments` for ETA breaches > 4h, publishes `rail.delay_alert` + `rail.eta_revised`. **SDK shape:** `Agent[RailCtx]` with tools `search_rail_shipments`, `get_rail_shipment_details`, `rail_carrier_info`, `rail_yard_lookup`, `rail_demurrage_calc`, `rail_compliance_status`, `rail_freight_audit`, `publish_eta_revision`. The MCP tools already exist — wire as `function_tool` shims. Handoffs: `intermodal_weaver`, `terminal_conductor`, `supply_chain_linker`. **Driver-facing:** Dispatcher sees Rail Pulse strip per active shipment. Drayage drivers see rail leg as card in load timeline ("Rail leg: BNSF Memphis → Dallas, ETA 14:30 ±90min"). **Guardrails:** STB tariff compliance (cannot commit rate without approval). Demurrage (alert when free-time burns below 24h; no auto-pay). Hazmat-by-rail uses 49 CFR Part 174. Tier 2.

**B3-3. vesselBrain.** Periodic (120s) scanner. Finds vessel-eligible loads, queries `vessel_bookings`. **SDK shape:** `Agent[VesselCtx]` with tools `search_vessel_bookings`, `get_vessel_booking_details`, `port_lookup`, `blank_sailing_dashboard`, `vessel_compliance_status`, `imdg_compliance`, `co2_calculate`, `fsc_schedules`. Handoffs: `intermodal_weaver`, `terminal_conductor`, `supply_chain_linker`, `cross_border_diplomat`. `output_type=VesselMovementDecision`. **Driver-facing:** Captains (iOS marine variant) see Voyage Brief card with vessel name, IMO, current/next port, ETA with tide/weather, IMDG hazmat manifest. Drayage drivers see "Vessel arrived" trigger. **Guardrails:** IMO/SOLAS, IMDG class compliance, OFAC + EU + UN sanctions screening per voyage path. Tier 3.

**B3-4. intermodalWeaver.** Subscribes to `load.created`, scores: rail if distance > 500mi AND not hazmat AND not urgent (>24h pickup), else truck. Emits `intermodal.mode_selected`. **SDK shape:** Classic supervisor-with-handoffs. `Agent[ModeSelectCtx]` with tools `get_load_details`, `rate_comparison`, `co2_calculate`, `search_intermodal_shipments`, `fuel_surcharge_calc`, `get_intermodal_journey`. Handoffs to `truck_brain`, `rail_brain`, `vessel_brain`. Output: `ModeRecommendation { mode, reasoning, est_savings_usd, est_co2_kg, transit_time_hours, confidence }`. **Driver-facing:** Indirect. Dispatcher sees Mode Recommendation card on every newly posted load: "Rail recommended — saves $1,240 + 38% CO2, transit +18h. Confidence 0.87." Shipper sees same as sustainability nudge. **Guardrails:** Hazmat overrides force truck-with-permit. Time-critical (<24h) cannot select rail/vessel. Customer mode-lock honored. Tier 2.

**B3-5. terminalConductor.** Currently thin placeholder. Counts loads in `at_pickup`/`at_delivery`, classifies congestion, publishes `terminal.queue_optimized`. **SDK shape:** `Agent[TerminalCtx]` with tools `dispatch_board`, `container_timeline`, `port_lookup`, `rail_yard_lookup`, `dd_alerts_dashboard`, `control_tower_exceptions`, `assign_dock_door`. Handoffs: `truck_brain`, `rail_brain`, `vessel_brain`, `geofence_sentinel`. **Driver-facing:** Drivers on approach see "Dock 7B at 14:25 — 12 ahead of you" with moving queue indicator. Dispatchers see heat-map of terminal congestion. **Guardrails:** Cannot promise slot the terminal API hasn't confirmed. Dwell-time thresholds tied to detention. Tier 2.

**B3-6. supplyChainLinker.** Periodic. Aggregates `loads` by status, identifies bottlenecks above 20% concentration. **SDK shape:** `Agent[SupplyCtx]` with tools `control_tower_overview`, `control_tower_exceptions`, `search_loads`, `search_intermodal_shipments`, `search_rail_shipments`, `search_vessel_bookings`, `container_timeline`, `get_intermodal_journey`, `platform_analytics`. Handoffs: `truck_brain`, `rail_brain`, `vessel_brain`, `market_oracle` (cross-pod). **Driver-facing:** Driver sees nothing direct. Dispatcher and shipper portals see Control Tower view: Sankey diagram of loads by status across all modes. Executives see KPIs. **Guardrails:** Cross-tenant data — must aggregate within `companyId` only. Tier 1 (read-only intelligence).

## FLEET LAYER (8 agents)

**B4-1. fleetCortex.** Currently periodic vehicle utilization aggregator. Counts by status, publishes `fleet.utilization` and `fleet.idle`. **SDK shape:** Reposition as the **driver-facing primary agent** — the conversational front-door for the driver app. Mirrors OpenAI's "supervisor with handoffs" reference. `Agent[DriverCtx]` with bilingual EN/ES persona instructions, tools `get_load_details`, `hos_status`, `eld_fleet_status`, `list_vehicles`, `autonomous_fleet`, `fleet_utilization_snapshot`, `messaging_overview`, `dd_alerts_dashboard`. Handoffs to `route_genius`, `eta_oracle`, `geofence_sentinel`, `maintenance_prophet`, `driver_wellness`, `convoy_commander`, `av_pilot`, `hazmat_commander`, `truck_brain`. **Driver-facing:** This IS the driver surface — the Cortex chat tile + voice button on iOS home screen. "Hey Eusorone" wake word routes here. **Guardrails:** Distracted-driving — when speed > 5 mph, replies are voice-only and capped to one short sentence + one action. HOS clock in every prompt; cannot encourage drivers past 11/14/70-hour limits. Tier 1 chat, Tier 2 actions.

**B4-2. routeGenius.** Subscribes to `dispatch.assigned`. Pulls origin/destination coords, runs Haversine baseline, applies `TUNNEL_RESTRICTED_CLASSES` for hazmat avoidance. **SDK shape:** `Agent[RouteCtx]` with tools `get_load_details`, `here_routing`, `mapbox_directions`, `weatherbit_route_overlay`, `hazmat_routing_engine`, `bridge_clearance`, `ifta_estimate`, `fuel_surcharge_calc`, `fmcsa_carrier_safety`, `publish_optimized_route`. Handoffs: `eta_oracle`, `fuel_hedge_analyst`, `hazmat_commander`. `output_type=OptimizedRoute { waypoints, alternates, hazmat_compliant, est_miles, est_minutes, fuel_stops }`. **Driver-facing:** Driver sees route draped on iOS map with three numbered alternates. Tap-to-pick. Voice prompt: "Route ready — fastest is I-40 East, two fuel stops. Accept?" **Guardrails:** 49 CFR 397.71 hazmat tunnel/route restrictions are non-negotiable. Bridge clearance enforced via `bridge_clearance` tool. HOS-aware. Tier 2.

**B4-3. etaOracle.** Reacts to `gps.update`, finds active load, computes Haversine + speed-based remaining time. **SDK shape:** `Agent[ETACtx]` with tools `get_load_details`, `here_traffic`, `weatherbit_route_overlay`, `hos_status`, `container_timeline`, `publish_eta_update`. The LLM is overkill for math — wrap Haversine + Kalman filter as deterministic tool, let the agent only choose when to escalate. `output_type=ETAEstimate { eta_iso, lower_bound_iso, upper_bound_iso, late_risk_score, late_reason }`. **Driver-facing:** ETA chip on load card updates live. Late-risk turns chip amber > 30min late, red > 60min. Tap reveals breakdown. **Guardrails:** Truthfulness — must include confidence/CI, never single-point ETA. Cannot suggest pushing through fatigue risk. Privacy: customer's ETA only goes to that customer. Tier 1.

**B4-4. convoyCommander.** Reacts to `convoy.requested`. Forms convoy by Haversine proximity to load origin, picks N escorts. **SDK shape:** `Agent[ConvoyCtx]` with tools `search_drivers`, `list_vehicles`, `escort_overview`, `hazmat_commander_tool`, `certifications_status`, `search_companies`, `publish_convoy_formed`. Handoffs: `route_genius`, `hazmat_commander`, `cross_border_diplomat`, `av_pilot`. `output_type=ConvoyPlan { lead_driver, escorts, staging_point, convoy_route_id, comm_channel, contingency_plan }`. **Driver-facing:** Lead truck and escorts get Convoy tab showing all members on one map with role badges. Voice push-to-talk shared comm channel. **Guardrails:** Hazmat convoys (oversized, explosive, radioactive) require certified escort drivers. State-by-state escort rules. HOS for every member individually. Tier 3 — convoy formation requires dispatcher signoff.

**B4-5. geofenceSentinel.** Reacts to `gps.update`. Checks proximity within 0.5mi of pickup/delivery, fires `geofence.entered`/`geofence.exited`, dwells > 120min trigger detention alert. **SDK shape:** `Agent[GeoCtx]` with tools `get_load_details`, `dd_alerts_dashboard`, `container_timeline`, `hos_status`, `accessorial_stats`, `publish_geofence_event`, `flag_detention_event`. Geometry stays deterministic (PostGIS `ST_DWithin` tool); agent decides whether geofence event auto-flips load status, files detention, or wakes dispatcher. **Driver-facing:** Driver gets non-interrupting nudge: "Arrived at pickup — confirm?" After dwell threshold, passive timer chip. Dispatcher sees live arrived/departed feed and detention burn-rate. **Guardrails:** False-positive guard — don't auto-status-change unless GPS accuracy < 50m AND consistent for 90s. Detention billing never auto-bills, only flags. Tier 2.

**B4-6. maintenanceProphet.** Periodic. Lists vehicles with `lastServiceDate` > 90 days. **SDK shape:** `Agent[MaintCtx]` with tools `list_vehicles`, `zeun_maintenance`, `inspection_records`, `safety_incidents`, `fmcsa_carrier_safety`, `eld_fleet_status`, `schedule_maintenance`. Bring in mileage, DTC code stream, historical defect rates so agent does proper survival-curve reasoning vs 90-day flat threshold. **Driver-facing:** Driver iOS sees Maintenance card: "Service due in 1,200mi — schedule now?" with one-tap "Find shop on route". DVIR pre-trip flow shows agent-flagged components highlighted. **Guardrails:** DOT/FMCSA inspection compliance — cannot suppress critical defect alert. Cannot auto-pull truck out of service without dispatcher and maintenance approval. Tier 3.

**B4-7. driverWellnessAI.** Periodic. Finds drivers with `lastLocationAt` > 8h on `on_load`. **SDK shape:** `Agent[WellnessCtx]` with supportive, non-judgmental tone. Tools `hos_status`, `eld_fleet_status`, `search_drivers`, `get_user_details`, `hos_audit_logs`, `publish_wellness_event`, `suggest_rest_stop`. Handoffs: `fleet_cortex`, `route_genius`, `eta_oracle` (rescheduling). `output_type=WellnessSignal { fatigue_score 0-100, stress_indicators, recommendation, rest_stop_suggestion, dispatcher_intervention_needed }`. **Driver-facing:** Gentle, opt-in. Wellness card on driver iOS: "You've been on duty 9h12m — 2h to mandatory rest. Coffee + 15min break at the TA in 14mi?" Voice tone supportive, never accusatory. Driver controls visibility settings. Dispatcher sees only green/amber/red wellness flag. **Guardrails:** Privacy paramount — biometric/HRV (if Apple Watch integrated) stays driver-side, never exported to dispatcher. Cannot be used for performance management/firing — explicit policy boundary. Bilingual EN/ES. Tier 1 driver-facing, Tier 3 for HR escalation.

**B4-8. avPilot.** Reacts to `av.telemetry`. Validates speed against `SPEED_LIMITS`, fuel level, engine temp. **SDK shape:** `Agent[AVCtx]` with tools `autonomous_fleet`, `get_vehicle_telemetry`, `here_traffic`, `weatherbit_route_overlay`, `list_vehicles`, `safety_incidents`, `publish_av_event`, `request_human_takeover`. Handoffs: `fleet_cortex`, `maintenance_prophet`, `route_genius`, `convoy_commander`. `output_type=AVDecision { status: nominal|degraded|emergency, action: continue|pull_over|request_takeover, safety_envelope, anomalies }`. **Driver-facing:** Safety Driver sees HUD-style web/iPad app with AV's intent vector, perception confidence, hardware Disengage button. Remote ops center sees fleet view of all AVs. Yard customers see only ETA. **Guardrails:** **Hard safety envelope** — if confidence < threshold or any anomaly classified as `emergency`, the agent's only allowed output is `pull_over` or `request_takeover`. Cannot continue. SAE Level 4 ODD hard-coded — leaving ODD triggers immediate handoff to safety driver. Tier 4 (highest — every action logged, signed, and replay-able for NHTSA/FMCSA review). Cybersecurity boundary: telemetry signed, never trust unauthenticated payloads.

## Pod 7 Synthesis — Three Brains, not one ModeBrain

**Three Brains, not one ModeBrain.** Truck, rail, and vessel diverge so much in regulation (49 CFR Part 397 vs Part 174 vs IMO/SOLAS), data shape (load + driver vs shipment + railcar vs booking + container + vessel), and decision cadence (minutes vs hours vs days) that flattening them into one ModeBrain with a `mode: Literal[...]` parameter would force the LLM to context-switch on every turn and make tool/guardrail surfaces unwieldy. Three sibling supervisors keep prompts tight, guardrails composable, and let each Brain own 7-9 mode-native sub-agents.

`intermodalWeaver` is the upstream **mode-router** that picks one and hands off — exactly the OpenAI "supervisor with handoffs" reference. `supplyChainLinker` is the **downstream aggregator** unifying the three into one Control Tower view.

**The Haul gamification rides above the agent layer, not inside it.** Missions, XP, streaks, Haul Points are emitted by a `HaulMissionService` that subscribes to the same event bus the agents publish to (`route.optimized`, `eta.updated`, `wellness.fatigue_score < 30`, `geofence.exited` for on-time arrival). Each agent stays mission-agnostic so it can never be tempted to compromise HOS, hazmat, or safety to award points. The mission engine adds rewards by **observing** outcomes — "Route Ace" badge fires from `route.optimized + eta.met` correlation, "Wellness Streak" from seven days without a fatigue flag. Drivers see Haul missions woven into FleetCortex chat as celebratory cards ("+150 Haul, you nailed that detention window") but agent decision-making remains driven solely by guardrails and operational truth. Tier 4 agents (avPilot) never participate in gamification — safety is not gamified.

---

# POD 8 — LAYER 5 + 6 + 7 MIGRATION (Lead 8)

22 agents — the most pods. 8 Compliance + 8 Financial + 6 Strategic.

## LAYER 5 — COMPLIANCE (8 agents, all GOVERNANCE Tier 1)

**B5-1. complianceSentinel.** Real-time pre-dispatch compliance scoring that BLOCKS driver-load assignments on expired credentials or unsafe carriers. SDK Agent with `output_type=ComplianceVerdict` (discriminated union `{passed: true, score} | {passed: false, blockers[]}`). Tools: `getDriverDocuments`, `getCarrierIntelligence`, `publishComplianceEvent`. Cannot-be-overridden: expired CDL/medical card/insurance = hard BLOCK. Carrier `outOfServicePercent > 25%` or "unsatisfactory" rating = BLOCK. Eusoboard surface: Web `/dashboard/compliance` red banner; dispatch board's row shows red lock icon. iOS: P1 dispatcher push, P0 driver push.

**B5-2. hazmatCommander.** Validates 49 CFR 177.848 hazmat segregation, driver hazmat endorsements, tunnel/bridge route restrictions. SDK Agent with typed `HazmatValidation` output. Tools: `lookupSegregationTable(class)`, `verifyDriverEndorsement`, `checkRouteRestrictions`. The 14-class segregation matrix is deterministic, non-LLM tool — the LLM only orchestrates and explains, never decides segregation. Cannot-be-overridden: Class 1.1/1.2/1.3 + Class 3 = absolute BLOCK. Driver without hazmat endorsement = BLOCK. Tunnel-restricted classes routed through tunnels = BLOCK. Hazmat is binary — output guardrail rejects any "approve with conditions" verdict. Eusoboard: `/dashboard/loads/:id` placard widget with class, UN number, segregation lights; routing screen overlays tunnel-restricted segments in red.

**B5-3. documentWarden.** Tracks document/credential expiry across drivers, vehicles, carriers, shipper agreements; pre-emptively blocks assignments tied to lapsed docs. Periodic-run Agent. Tools: `scanExpiringDocs(daysAhead)`, `notifyOwner`, `quarantineEntity`. Output: `DocumentRiskReport`. Cannot-be-overridden: Insurance expired = BLOCK. CDL expired = driver auto-deactivated. IFTA decals, IRP cab cards, UCR — hardcoded enums; LLM cannot "approximate" expiry. Eusoboard: `/compliance/documents` table with traffic-light expiry chips, bulk renewal CTA. iOS: per-driver document drawer with countdown chips; push at T-30/T-14/T-7/T-1.

**B5-4. crossBorderDiplomat.** Validates USMCA cert of origin, Mexico Carta Porte XML, US/Canada ACE/ACI eManifest filings. SDK Agent orchestrating three deterministic tools: `validateUSMCA`, `generateCartaPorteXML`, `submitACEManifest`. Pairs with `cross_border_usmca`, `cross_border_vucem`, `cross_border_mx_compliance` MCPs. Cannot-be-overridden: NOM-012 weight/dimension limits = BLOCK. Missing Carta Porte XML at SAT cut-off = BLOCK. C-TPAT/FAST status mismatch = WARN+queue. USMCA certification claim must match HS code. Eusoboard: cross-border ribbon on load card (US/MX/CA flags + status pills). iOS: pre-border alert 50mi out with "Documents Ready" check.

**B5-5. auditChain.** Tamper-evident, hash-chained audit log of every governance-relevant decision, approval, override across the autopilot. Background-only Agent subscribed to all `compliance.*`, `policy.*`, `approval.*` events. Tools: `appendBlock(prevHash, payload)`, `verifyChain(fromBlockId)`. No LLM reasoning — pure pipeline. Cannot-be-overridden: Append-only, never delete. Hash chain integrity enforced by DB constraint. SOX/SOC2 retention = 7 years minimum. Eusoboard: `/admin/audit` timeline with filterable hash-verified entries.

**B5-6. soc2Guardian.** Continuous SOC 2 Trust Service Criteria evidence collection. Periodic Agent with tools mapped to controls: `verifyMFAEnforcement`, `auditAccessReviews`, `checkBackupSuccessRate`, `scanEncryptionAtRest`. Output: `SOC2EvidencePack` with control IDs (CC6.1, CC7.2, A1.2). Cannot-be-overridden: MFA disabled for any privileged user = BLOCK + auto-page. Encryption-at-rest disabled = BLOCK. Access review > 90 days stale = WARN escalating to BLOCK at 120d. Eusoboard: `/admin/soc2` posture dashboard, quarterly evidence pack export.

**B5-7. insuranceMonitor.** Validates carrier liability/cargo insurance, COI authenticity, per-load coverage adequacy. SDK Agent with tools `parseCOI(pdfUrl)`, `verifyWithIssuer(policyNumber)`, `checkCoverageVsLoadValue`. Periodic re-verification every 7 days. Cannot-be-overridden: Auto liability < $1M = BLOCK. Cargo coverage < load declared value = BLOCK. Reefer breakdown coverage required for temp-controlled = BLOCK. COI must be from licensed insurer. Eusoboard: `/compliance/insurance` per-carrier table with policy chips and renewal countdowns.

**B5-8. drugTestScheduler.** Manages DOT 49 CFR Part 382 drug/alcohol testing program. Scheduled Agent. Tools: `selectRandomPool(rate=0.5)`, `scheduleTest`, `submitToClearinghouse`. Cannot-be-overridden: FMCSA Drug & Alcohol Clearinghouse query = hard prerequisite to dispatch. Positive test = immediate driver removal, no LLM softening. Random selection rate (50% drug, 10% alcohol annually) = regulatory floor. Eusoboard: `/compliance/drug-testing` admin module. iOS: driver receives encrypted notification with test order, location, 24-hour clock.

## LAYER 6 — FINANCIAL (8 agents)

**B6-1. rateSurgeon (BUSINESS Tier 3).** Lane-level rate optimization combining DAT/Greenscreens market data, historical wins, fuel index. SDK Agent with `output_type=RateProposal { base, fsc, accessorials, total, confidence }`. Tools: `getMarketRate`, `getHistoricalWinLoss`, `computeFuelComponent`, `proposeRate`. Cannot-be-overridden: Cannot quote below carrier breakeven (walletGuardian veto). Cannot apply customer-specific rate without valid contract row. Cannot exceed published shipper RFP cap. Eusoboard: rate quoting widget on load creation form with confidence pill.

**B6-2. settlementAutomator (BUSINESS Tier 3).** Auto-settles carrier payments after POD verification, accessorial reconciliation, deduction processing. Event-driven on `pod.verified` + `invoice.matched`. Tools: `runReconciliation`, `applyDeductions`, `releaseSettlement`. Cannot-be-overridden: Cannot release without POD on file (auditChain requirement). Cannot bypass W-9/1099 hold. Cannot release to OFAC-flagged carrier. Above $25k requires human approval — hardcoded. Eusoboard: `/finance/settlements` queue with Approve/Hold/Dispute panel. iOS: carrier app shows "Settlement in 2 days" countdown.

**B6-3. commissionOptimizer (BUSINESS Tier 3).** Computes broker/agent commission splits across tiered plans. SDK Agent with pure-math tools `computeSplit`, `applyClawback`, `projectAttainment`. Cannot-be-overridden: Cannot pay commission on unsettled loads. Cannot retroactively change tier without audit log + admin approval. Tax withholding on 1099 contractor payouts mandatory. Eusoboard: `/finance/commissions` with per-agent ledger, attainment-to-target gauge.

**B6-4. factoringBrain (BUSINESS Tier 3).** Routes carrier invoices through HaulPay factoring. SDK Agent wrapping HaulPay APIs. Tools: `requestCreditCheck`, `submitForFactoring`, `getAdvanceRate`, `managePool`. Cannot-be-overridden: Cannot factor uninsured loads (insuranceMonitor veto). Cannot factor without signed NOA on file. Shipper credit limit, once breached, is hard cap. UCC-1 lien priority is HaulPay's. Eusoboard: `/finance/factoring` shows pool balance, advance rate, reserve, fees breakdown. iOS: carrier sees "Cash now" card.

**B6-5. fuelHedgeAnalyst (OPTIMIZATION Tier 4 — read-only/advisory).** Tracks DOE fuel index, projects FSC impact across active contracts. Read-only SDK Agent. Tools: `getFuelIndex`, `projectFSCImpact`, `simulateHedge`. Output is always a `Recommendation`, never an executed trade. Cannot-be-overridden: Cannot execute futures or hedge transactions — explicit prohibition under PolicyEngine Rule 2 AND user-privacy "no financial trades" mandate. Recommendations require human treasurer approval. Eusoboard: `/finance/fuel` chart of DOE diesel index vs FSC realized.

**B6-6. walletGuardian (SECURITY Tier 2 — veto over BUSINESS).** Real-time anomaly detection on wallet/payout flows. Streaming Agent on `wallet.tx_proposed`. Tools: `scoreVelocity`, `checkBeneficiaryChange`, `screenOFAC`, `placeHold`. Cannot-be-overridden: OFAC hit = HOLD, no exceptions. Beneficiary change within 7 days of new payout = HOLD pending re-verification. Velocity > 3σ from baseline = HOLD. KYC must be current before any payout. Eusoboard: `/security/wallet-alerts` triage queue. iOS: carrier sees "Verification needed" prompt.

**B6-7. accessorialDetector (BUSINESS Tier 3).** Detects and bills detention, layover, lumper, TONU, reconsignment from ELD, geofence, dock check-in signals. Event-driven on `geofence.dwell` and `eld.duty_status_change`. Tools: `detectDetention`, `priceAccessorial`, `proposeInvoiceLine`. Cannot-be-overridden: Cannot bill detention before contractually agreed free time. Cannot bill without ELD or geofence evidence. Caps from shipper master agreement inviolable. Eusoboard: per-load accessorial timeline with auto-detected events.

**B6-8. collectionsAgent (BUSINESS Tier 3).** Aging-bucket-driven collections workflow. Scheduled Agent + event listener. Tools: `getAgingReport`, `sendDunning`, `scheduleCall`, `escalateToDispute`, `placeCreditHold`. Cannot-be-overridden: FDCPA — no contact after written cease-and-desist (hardcoded list checked before any outbound). Cannot send dunning to active dispute. Cannot place credit hold without customer-success approval at threshold. Eusoboard: `/finance/ar` aging buckets with automated action plans.

## LAYER 7 — STRATEGIC (6 agents, all OPTIMIZATION Tier 4)

**B7-1. marketOracle.** Detects market phase shifts (cool/warm/hot) by lane and origin-state from active load posting telemetry. Periodic SDK Agent. Tools: `scanActiveLoads`, `detectPhaseShift`, `publishMarketSignal`. Read-only — cannot modify postings or rates (PolicyEngine Rule 2). Eusoboard: `/insights/market` US heatmap. iOS: home tile "Market is hot in your area".

**B7-2. demandProphet.** Forecasts 7/14/28-day shipment demand by lane and equipment using historical seasonality, holidays, news sentiment. SDK Agent orchestrating forecasting tool layer. Tools: `pullHistoricalDemand`, `getSeasonality`, `applyNewsSentiment`, `produceForecast`. Read-only. Forecast confidence intervals must be reported (not just point estimates) — hallucination guard requires it. Eusoboard: `/insights/demand` per-lane forecast with confidence band.

**B7-3. competitorGhost.** Lightweight competitive intelligence: tracks public rate boards, posted lanes, brand mentions. SDK Agent with web-fetch and public-source tools only. Tools: `pollPublicLoadBoards`, `extractPostedRates`, `aggregateMentions`. Cannot-be-overridden: Cannot scrape PII or behind-login content. Cannot ingest copyrighted content beyond fair-use snippets. Cannot store competitor employee info. Eusoboard: `/insights/competitive` tile-based view.

**B7-4. growthStrategist.** Synthesizes signals from market, demand, churn, rate to recommend lane expansion, customer targets, capacity adds. Read-only. Consumes outputs of B7-1, B7-2, B7-6, B6-1 via SDK handoffs. Tools: `proposeLaneExpansion`, `proposeCustomerTarget`, `proposeCapacityAdd`. Output: ranked `GrowthInitiative[]` with expected ROI and time horizon. Cannot create accounts, assets, or commitments. ROI claims must trace to source signals (auditChain entry per recommendation). Eusoboard: `/strategy/initiatives` Kanban.

**B7-5. revenueArchitect.** Models pricing-package and contract-structure variations. SDK Agent. Tools: `simulatePackage`, `estimateMargin`, `compareVsCurrent`. Output: `PackageProposal[]`. Read-only — cannot change customer's contract. Cannot recommend pricing breaching walletGuardian floors or rateSurgeon caps. Eusoboard: `/strategy/revenue` what-if simulator.

**B7-6. churnSentinel.** Predicts customer/carrier churn from usage decay, dispute volume, late-pay events. SDK Agent. Tools: `scoreChurnRisk`, `recommendRetentionPlay`, `triggerRetentionWorkflow`. Output: `ChurnRiskReport` with feature attributions. Read-only on customer data. Cannot send retention emails without explicit approval. Feature attributions must avoid exposing PII. Eusoboard: `/strategy/retention` at-risk list with risk score and recommended play.

## Pod 8 Synthesis — How Three Layers Compose Inviolable Veto Power

The 4-tier `SkillTier` enum (`core/types.ts:76-85`) defines the chain of authority: GOVERNANCE (1) > SECURITY (2) > BUSINESS (3) > OPTIMIZATION (4). Migration to the OpenAI Agents SDK preserves this ordering by composing three independent enforcement layers, each authoritative at a different scope.

**Layer one is `guardrails.ts` (`NeMoGuardrails`).** Its `INPUT` rails (`input-injection`, NIM `nim-content-safety`) become OpenAI SDK input guardrails attached to every Compliance and Financial agent — any inbound request or tool argument that fails returns an early termination before the agent loop runs. Its `OUTPUT` rails (`output-pii-leak`, `output-hallucination`, `nim-hallucination-guard`) become SDK output guardrails: a complianceSentinel verdict containing a fabricated CFR cite or unmasked CDL fails before downstream agents observe it. `EXECUTION` rails wrap every tool function as a pre-execution check.

**Layer two is `policyEngine.ts`.** The default-DENY model plus priority-ordered rules `governance-full-access` (priority 10), `optimization-read-only` (priority 20), `security-access` (priority 30), `business-access` (priority 40), `block-sensitive-resources` (priority 5) is the cross-tier ACL. Every tool call is gated through `policyEngine.evaluate()` inside the tool handler. Rule 5 evaluated at priority 5 means encryption keys/JWT secrets are always denied first; Rule 1 at priority 10 means GOVERNANCE wins next; OPTIMIZATION can never write because Rule 2 short-circuits to DENY before any allow rule fires.

**Layer three is conflict resolution.** `conflictResolver.ts` and `approvalQueue.ts` arbitrate when a BUSINESS agent (e.g., dispatchCommander) wants to assign a load that complianceSentinel has BLOCK-flagged. The SDK pattern is a handoff/veto: dispatchCommander hands off to complianceSentinel; the verdict's typed `output_type` (a discriminated union with `passed: false`) prevents the SDK from coercing it into a "best-effort" assignment. walletGuardian (SECURITY) similarly vetoes settlementAutomator (BUSINESS).

The composition gives Compliance and Financial guardian agents **three non-overlapping veto surfaces**: input-stage (guardrails reject the prompt), tool-stage (policy denies the action), and output-stage (guardrail rejects the verdict). A BUSINESS or OPTIMIZATION agent attempting to bypass any one is stopped by the next — veto authority is structural, not negotiable, and matches the SkillTier ordering exactly.

---

# POD 9 — 24-ROLE MAPPING + CROSS-PLATFORM PARITY (Lead 9)

## B8-1. Role-to-Cortex Routing Matrix — 24 Roles × 50 Agents

Every EusoTrip user lives inside a role envelope. The role determines which subset of the 50-agent Cortex fleet auto-subscribes to their session: which agents poll context, which agents emit notifications, which agents own UI surfaces on their dashboard. Subscription model — agents are pre-bound to the role at login, tool surface filtered by RBAC.

```
            +----------------------------------+
   Login -> | RoleResolver (role + tenant)     |
            +----------------+-----------------+
                             |
                             v
            +----------------------------------+
            | CortexSubscriptionManager        |
            | - reads /role_manifests/<role>.yml |
            | - opens 6-12 agent channels      |
            +----------------+-----------------+
                             |
        +--------------------+--------------------+
        v                    v                    v
   fleetCortex          walletGuardian       complianceSentinel
   (driver-bound)       (all roles)          (truck/rail/vessel ops)
```

### THE MATRIX

| # | Role | Mode | Primary Agents Subscribed |
|---|------|------|---------------------------|
| 1 | Driver | TRUCK | fleetCortex, routeGenius, etaOracle, complianceSentinel, driverWellnessAI, walletGuardian, haulMissionAgent |
| 2 | Dispatch | TRUCK | dispatchCommander, fleetCortex, etaOracle, smartAssign2, weatherNerve, exceptionTriage |
| 3 | Catalyst (owner-operator) | TRUCK | walletGuardian, taxCopilot, maintenanceProphet, smartAssign2, fuelHedgeAnalyst, insuranceMonitor |
| 4 | Broker | TRUCK | smartAssign2, rateSurgeon, carrierVetting, marginGuardian, settlementAutomator, contractScribe |
| 5 | Shipper | TRUCK | tenderOrchestrator, etaOracle, accessorialDetector, claimsAgent, poVisibility |
| 6 | Escort | TRUCK | escortCoordinator, oversizePermits, routeGenius, weatherNerve, complianceSentinel |
| 7 | Carrier Terminal Admin | TRUCK | yardChoreographer, gatePass, dwellGuardian, complianceSentinel, fleetCortex |
| 8 | Rail Operator | RAIL | trackAuthority, fleetCortex(rail), powerScheduler, complianceSentinel, weatherNerve |
| 9 | Rail Dispatcher | RAIL | dispatchCommander(rail), trackAuthority, blockAgent, exceptionTriage, etaOracle |
| 10 | Rail Yard Master | RAIL | yardChoreographer, switchPlanner, blockAgent, dwellGuardian, hazmatCommander |
| 11 | Rail Shipper | RAIL | tenderOrchestrator, intermodalWeaver, etaOracle, claimsAgent |
| 12 | Rail Broker | RAIL | intermodalWeaver, rateSurgeon, carrierVetting, settlementAutomator |
| 13 | Rail Conductor | RAIL | crewBoard, hosGuardian(rail), routeGenius(rail), complianceSentinel |
| 14 | Vessel Captain | VESSEL | bridgeCortex, weatherNerve, routeGenius(maritime), complianceSentinel, crewBoard |
| 15 | Vessel First Officer | VESSEL | bridgeCortex, cargoStowageAI, watchSchedule, complianceSentinel |
| 16 | Vessel Port Agent | VESSEL | portCallChoreographer, accessorialDetector, customsBroker, dwellGuardian |
| 17 | Vessel Shipping Line Ops | VESSEL | linerNetworkPlanner, slotAllocator, etaOracle, exceptionTriage, marginGuardian |
| 18 | Vessel Terminal Operator | VESSEL | yardChoreographer(marine), craneScheduler, dwellGuardian, hazmatCommander |
| 19 | Vessel NVOCC Forwarder | VESSEL | bookingClerk, customsBroker, intermodalWeaver, claimsAgent, settlementAutomator |
| 20 | Eusoboard Admin | ADMIN | tenantWarden, agentObservability, billingOps, securityAuditor, ledgerSentinel |
| 21 | Tenant Admin | ADMIN | tenantWarden, rbacScribe, billingOps, agentObservability |
| 22 | Compliance Officer | ADMIN | complianceSentinel, auditChain, hosGuardian, hazmatCommander, regulatoryNewsfeed |
| 23 | Finance Admin | ADMIN | walletGuardian, taxCopilot, settlementAutomator, ledgerSentinel, fraudDetect |
| 24 | Catalyst Marketplace Admin | ADMIN | marketplaceCurator, ratingsArbiter, fraudDetect, payoutScheduler, contractScribe |

### Code surface

```ts
// /server/src/cortex/roleManifest.ts
export const ROLE_MANIFEST: Record<UserRole, AgentId[]> = {
  DRIVER: ["fleetCortex","routeGenius","etaOracle","complianceSentinel",
           "driverWellnessAI","walletGuardian","haulMissionAgent"],
  // ... 23 more
};
export function subscribeForRole(userId: string, role: UserRole) {
  return ROLE_MANIFEST[role].map(id => agentBus.openChannel(userId, id));
}
```

```swift
// iOS: AppBootstrap.swift
func subscribeCortex(for role: UserRole) async {
    let manifest = try await api.cortex.manifest(role: role)
    for agentId in manifest.agents {
        CortexBus.shared.subscribe(agentId)
    }
}
```

### Live Activity / widget hooks
Hot Zones widget polls only the role's subscribed agents. A Driver never sees `marginGuardian`; a Broker never sees `driverWellnessAI`. Live Activities (iOS 17+) bound 1:1 to a single agent — `dispatchCommander` for drivers, `portCallChoreographer` for port agents.

### Failure modes + offline behavior
If `/role_manifests` fails to load, fall back to hard-coded minimal manifest of `walletGuardian + complianceSentinel` (the "always-on two"). Offline, iOS app caches last 24h of agent emissions in Core Data keyed by `agentId+userId`; on reconnect, bus replays missed deltas. Each agent declares `staleAfter: TimeInterval` so UI grays out widgets older than that window.

---

## B8-2. Web Platform Integration — tRPC Surface Fronting OpenAI Agents

```
React component (eusoronetechnologiesinc/frontend/client/src/)
        |
        |  trpc.cortex.invoke.useMutation()
        v
    tRPC router  -->  AuthZ middleware  -->  RoleManifest gate
        |
        v
   AgentRunner.run({ agent, input, context })
        |
        +--> OpenAI Agents SDK
        +--> Tool registry (filtered by role)
        +--> Streaming via tRPC subscription (SSE)
        v
   React useSubscription consumes deltas
```

```ts
export const cortexRouter = router({
  invoke: protectedProcedure
    .input(z.object({ agentId: z.string(), prompt: z.string(),
                      threadId: z.string().optional() }))
    .mutation(async ({ ctx, input }) => {
      assertAgentAllowedForRole(input.agentId, ctx.user.role);
      const run = await agentRunner.start({
        agent: input.agentId, prompt: input.prompt,
        thread: input.threadId ?? newThread(),
        context: { user: ctx.user, tenant: ctx.tenant }
      });
      return { runId: run.id, threadId: run.threadId };
    }),
  stream: protectedProcedure
    .input(z.object({ runId: z.string() }))
    .subscription(({ ctx, input }) => {
      return observable<AgentDelta>((emit) => {
        const sub = agentRunner.tail(input.runId, (delta) => emit.next(delta));
        return () => sub.unsubscribe();
      });
    }),
});
```

```tsx
const invoke = trpc.cortex.invoke.useMutation();
const [runId, setRunId] = useState<string|null>(null);
trpc.cortex.stream.useSubscription({ runId: runId ?? "" }, {
  enabled: !!runId, onData: (d) => append(d),
});
async function ask(prompt: string) {
  const { runId } = await invoke.mutateAsync({ agentId: "routeGenius", prompt });
  setRunId(runId);
}
```

### Live Activity / widget hooks
On web, "Live Activity" maps to `<HotZonesWidget>` and `<AgentTickerBar>` — both subscribe to `cortex.stream` filtered by agent. Agent state (running/stalled/done) rendered as a chip. Tool calls inside the agent emit `tool_call_started`/`tool_call_finished` deltas so UI shows "Calling weatherSentinel.lookup(I-80)..." in real time.

### Failure modes + offline behavior
Mutation idempotent on `clientRunId`, retry after 5xx doesn't double-bill. If SSE drops, client resubscribes with `since: lastSeq`; server replays from 60s ring buffer. Agent errors surface "Retry" affordance bound to same agentId. Web has no offline mode for Cortex — without network, console shows last cached transcript read-only.

---

## B8-3. iOS App Integration — Swift/SwiftUI + URLSession Streaming + WCSession

```
       Watch (Pulse orb)
             |
       voice -> WCSession.sendMessage
             v
       iPhone app (NavController per role)
             |
             v
   CortexClient (URLSession + AsyncStream)
             |
             v  HTTPS/2 + SSE
   Backend tRPC -> OpenAI Agents SDK
             |
             v
   AgentDelta stream -> Combine PassthroughSubject
             |
       +-----+------+-------+
       v            v       v
   SwiftUI view  Live Activity  WCSession reply -> watch
```

```swift
final class CortexClient {
    static let shared = CortexClient()
    func stream(agentId: String, prompt: String) -> AsyncThrowingStream<AgentDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var req = URLRequest(url: API.cortexStream)
                req.httpMethod = "POST"
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.httpBody = try? JSONEncoder().encode(["agent": agentId, "prompt": prompt])
                let (bytes, _) = try await URLSession.shared.bytes(for: req)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = String(line.dropFirst(5))
                    if let delta = try? JSONDecoder().decode(AgentDelta.self, from: Data(payload.utf8)) {
                        continuation.yield(delta)
                    }
                }
                continuation.finish()
            }
        }
    }
}

final class CortexSession: ObservableObject {
    @Published var transcript: [AgentDelta] = []
    private var task: Task<Void, Never>?
    func ask(_ prompt: String, agentId: String) {
        task?.cancel()
        task = Task {
            do {
                for try await delta in CortexClient.shared.stream(agentId: agentId, prompt: prompt) {
                    await MainActor.run { self.transcript.append(delta) }
                }
            } catch { /* surface to UI */ }
        }
    }
}
```

```swift
// PulseWatchBridge.swift
extension AppDelegate: WCSessionDelegate {
    func session(_ s: WCSession, didReceiveMessage msg: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let voiceText = msg["voice"] as? String else { return }
        Task {
            var firstChunk: String?
            for try await d in CortexClient.shared.stream(agentId: "esang", prompt: voiceText) {
                if firstChunk == nil { firstChunk = d.text }
            }
            replyHandler(["reply": firstChunk ?? ""])
        }
    }
}
```

### Live Activity / widget hooks
A Driver's `dispatchCommander` run opens a Live Activity that updates as agent emits `assignment_offered`, `accepted`, `eta_changed`. Watch complication mirrors via WidgetKit timelines refreshed by `URLSession.shared.dataTask` on 5-min cadence; for final mile iPhone pushes deltas to watch over WCSession's `transferUserInfo` with `isComplicationInfo: true`.

### Failure modes + offline behavior
`URLSession.bytes` throws `URLError.networkConnectionLost` on cell handoff — client wraps every stream in retry-with-backoff that resumes from `lastDeltaSeq`. When fully offline, agent transcript queues into Core Data `OutboxRun` entity; on reconnect queue flushes oldest-first. Watch orb voice capture continues offline and stores `.caf` audio + transcript locally; iPhone only invokes agent once back online. Live Activities torn down on 4h timeout per Apple guidance.

---

## B8-4. 24 NavController × Cortex Hookup

The 7 nav controllers (Admin, Broker, Carrier, Catalyst, Escort, Shipper, Terminal) cover 24 roles by parameterizing on `UserRole.subType`. CarrierNavController hosts Driver, Dispatch, Carrier_Terminal_Admin, and the rail/vessel operating roles via a `mode` discriminant.

```swift
enum NavControllerFactory {
    static func make(for user: AuthenticatedUser) -> UINavigationController {
        switch user.role {
        case .driver, .dispatch, .railOperator, .railDispatcher,
             .vesselCaptain, .vesselFirstOfficer, .carrierTerminalAdmin:
            return CarrierNavController(user: user)
        case .broker, .railBroker, .vesselNVOCC:           return BrokerNavController(user: user)
        case .shipper, .railShipper:                       return ShipperNavController(user: user)
        case .escort:                                       return EscortNavController(user: user)
        case .catalyst:                                     return CatalystNavController(user: user)
        case .vesselTerminal, .vesselPortAgent, .yardMaster: return TerminalNavController(user: user)
        case .eusoboardAdmin, .tenantAdmin, .compliance,
             .finance, .marketplaceAdmin:                   return AdminNavController(user: user)
        }
    }
}

final class DriverNavController: UINavigationController {
    let session = CortexSession()
    override func viewDidLoad() {
        super.viewDidLoad()
        session.subscribe(["fleetCortex","routeGenius","etaOracle",
                           "complianceSentinel","driverWellnessAI",
                           "walletGuardian","haulMissionAgent"])
        viewControllers = [DashboardVC(session: session)]
    }
}
```

### Live Activity / widget hooks per role
- **Driver/Conductor/Captain** → Live Activity on Lock Screen for current run, Dynamic Island shows `etaOracle` countdown, Watch complication shows `driverWellnessAI` HOS clock
- **Dispatch/Yard Master/Port Agent** → Hot Zones widget tiles per vehicle/berth/yard track
- **Broker** → "Margin pulse" widget bound to `marginGuardian`
- **Catalyst** → Earnings widget bound to `walletGuardian`, mission carousel bound to `haulMissionAgent`
- **Compliance** → Inbox-style list of `complianceSentinel` flags with deep links
- **Tenant Admin** → Health-bar widget across `agentObservability`

### Failure modes
Each NavController owns its CortexSession; if subscription fails for a single agent, the rest continues. A degraded banner shows which agents are dark. Hot Zones widget falls back to last-snapshot data with "stale" badge after agent's `staleAfter` elapses.

---

## B8-5. MCP Surface for iOS — OpenAI Agents SDK MCP Server

```
iOS app -> MCPClient (Swift)  --HTTPS--> Eusorone MCP Server
                                            |
                                            +-- tools/list
                                            +-- tools/call
                                            +-- resources/read
                                            +-- prompts/list
                                            |
                            (same server registered with OpenAI Agents SDK
                             so Cortex agents can call the same tools)
```

The MCP server is the single source of truth for callable tools. Web tRPC, iOS Swift, and the OpenAI Agents SDK all consume the same server. This is what makes the parity story honest: a `haul.acceptMission` tool defined once is available to a React button, a SwiftUI button, and an autonomous agent.

### Tool catalog (illustrative)

| Tool | Owner agent | Surfaces |
|------|------------|----------|
| haul.listMissions | haulMissionAgent | iOS carousel, web rail |
| haul.acceptMission | haulMissionAgent | iOS button, watch confirm |
| wallet.balance | walletGuardian | iOS widget, watch complication |
| wallet.payout | walletGuardian | iOS sheet (requires Face ID) |
| hos.remaining | hosGuardian | watch complication |
| hos.startBreak | hosGuardian | watch button, Live Activity |
| weather.alongRoute | weatherNerve | iOS map overlay |
| traffic.alongRoute | trafficNerve | iOS map overlay |
| dispatch.acceptLoad | dispatchCommander | Live Activity action |
| compliance.uploadBOL | complianceSentinel | iOS camera flow |

```swift
struct MCPTool: Decodable { let name: String; let inputSchema: JSON }

final class MCPClient {
    func listTools() async throws -> [MCPTool] {
        try await post("/mcp", ["method":"tools/list"]).tools
    }
    func call<T: Decodable>(_ tool: String, args: [String: Any]) async throws -> T {
        try await post("/mcp", ["method":"tools/call",
                                "params":["name": tool, "arguments": args]]).result
    }
}

Button("Accept mission") {
    Task {
        let _: AcceptResp = try await mcp.call("haul.acceptMission",
                                               args: ["missionId": id])
    }
}
```

```ts
// server registers same tools with the Agents SDK
import { MCPServer } from "@openai/agents/mcp";
const server = new MCPServer({ name: "eusorone-cortex" });
server.tool("haul.acceptMission", schema, handler);
agentRunner.attachMCP(server);
```

### Live Activity / widget hooks
Live Activity actions (iOS 17 interactive widgets) call MCP tools directly via App Intents — `AcceptLoadIntent` invokes `dispatch.acceptLoad`. Watch complication "Start Break" button calls `hos.startBreak`. Because tools are MCP, same intent works whether triggered by human tap or by Cortex agent running in the cloud.

### Failure modes + offline
MCP calls framed as App Intents so iOS will queue them when offline and replay on reconnect for idempotent tools (server enforces idempotency keys). Sensitive tools like `wallet.payout` refuse offline replay. Each tool declares `requiresConfirmation` and `requiresBiometric` flags consumed by both web and iOS.

---

## Pod 9 Synthesis — 90-Day Deployment Ladder for Role-Aware Cortex

The web side is largely shipped: tRPC + React already serves Cortex transcripts to live tenants. The iOS side is the gating arc to ship Build 60+ as the first Cortex-aware build within 90 days.

**Days 0-15 — Manifest and routing.** Land `roleManifest.ts` server-side and ship `/api/cortex/manifest?role=` so both web and iOS pull the same 24-role agent map. Migrate all seven NavControllers to instantiate a `CortexSession` from manifest rather than hard-coded agent lists. Acceptance: every login subscribes to its role's agents and zero others.

**Days 15-35 — Streaming parity.** Wire `CortexClient` Swift class with `URLSession.bytes` SSE; bridge to Combine; add reconnect-with-`lastDeltaSeq`. On the server, normalize the SSE protocol so web (tRPC subscription) and iOS (raw SSE) consume identical delta shapes. Acceptance: Driver's `dispatchCommander` stream renders identically on web and iPhone.

**Days 35-55 — MCP server cutover.** Stand up the MCP server in front of the existing tool registry. Convert iOS direct-REST calls (`POST /haul/accept`) to MCP `tools/call`. Register the same MCP server with the OpenAI Agents SDK so agents and humans share one tool surface. Acceptance: `haul.acceptMission` invoked from React, SwiftUI, and an autonomous `haulMissionAgent` all hit the same handler.

**Days 55-75 — Live Activities + Watch.** Ship Live Activity for Driver dispatch, Vessel port-call, Yard Master gate moves. Ship interactive App Intents for HOS break, mission accept, wallet balance check. Wire Pulse watch orb voice → ESANG agent → reply. Acceptance: Lock Screen and Dynamic Island update from agent deltas without opening the app.

**Days 75-90 — Build 60 hardening.** Fault injection: force agent timeouts, MCP 5xx, SSE drops, offline transitions. Verify Hot Zones widget stale-state, Outbox replay, biometric-gated tools, idempotent retries. Roll out to internal Catalyst dealer pilots, then GA.

To ship Build 60 as Cortex-aware, the iOS app needs four additions: (1) `CortexClient` + `CortexSession` SDK, (2) `MCPClient` + App Intent integration, (3) NavController-to-manifest binding, (4) Live Activity + Widget extensions for the seven highest-value role surfaces. Backend prerequisites are already in place from the 50-agent autopilot; the ladder is almost entirely client-side execution.

---

# PART III — SYNTHESIS

# POD 10 — ESANG VOICE × MCP × THE HAUL × MIGRATION LADDER × MASTER SYNTHESIS (Lead 10)

## C1. ESANG Voice Integration — Realtime API Migration

ESANG is Eusorone's voice copilot riding inside iOS and the Pulse watchOS companion. Today, when a driver presses the watch crown or taps the orb, audio is captured locally, shipped to a backend `/api/ai/chat` endpoint, transcribed, run through a text agent, and the response is text-to-speech'd back. End-to-end latency sits around 2.4-3.1 seconds — acceptable for Q&A, fatal for a copilot that's supposed to feel like a fleet dispatcher in your ear during a left-hand merge onto I-80.

The migration target is OpenAI's Realtime API using `gpt-4o-realtime-preview`. The architectural unlock is bidirectional streaming audio: the driver's voice streams directly into the model, the model streams audio response back, and tool calls fire mid-stream. Latency drops to roughly 320-500ms first-byte. ESANG isn't a separate AI — it's a voice-shaped doorway into Cortex.

**Transport — WebSocket vs WebRTC.** WebSocket is simpler: persistent socket carries Opus-encoded audio frames in both directions, plus JSON event messages. iOS handles via `URLSessionWebSocketTask`. Downside: TCP head-of-line blocking on cellular — one dropped packet stalls the stream. For Pulse where Bluetooth-relayed cellular is already lossy, this matters. WebRTC is the production answer — UDP transport, jitter buffer, packet loss concealment, native Opus support. **Recommendation:** ship WebSocket for MVP behind feature flag (`esang_realtime_v1`), instrument cellular drop rates, graduate to WebRTC for Phase 6 hardening.

**Audio codec.** Opus at 24kHz mono. iOS captures via `AVAudioEngine` at 48kHz, downsamples to 24kHz with `AVAudioConverter`, Opus-encodes to ~32kbps. On watchOS, the M-series chip handles Opus encoding natively but keep pipeline lightweight — 16kHz capture, upsampled at iPhone relay if needed.

**Interruption handling — the killer feature.** In Realtime, the user can talk over the assistant; the model truncates its own speech, transcribes the interruption, re-plans. iOS implementation: detect VAD via model's `input_audio_buffer.speech_started` event, immediately send `response.cancel`, flush audio output buffer (`AVAudioPlayerNode.stop()`), start new utterance. Test case: ESANG reading HOS hours, driver interrupts with "skip that, dispatch me" — ESANG must stop in <200ms and route to `cortex.dispatch.assign_load`.

**Watch orb states wired to Realtime events.**
- `idle` (slow blue pulse, 1.2Hz) — no active session, push-to-talk armed
- `listening` (orange ring, audio waveform) — `input_audio_buffer.speech_started`
- `thinking` (white spin, 2Hz) — `response.created`, cleared on `response.audio.delta` first chunk
- `speaking` (green pulse synced to audio) — `response.audio.delta` events with amplitude envelope sampled at 30Hz

Transitions are event-driven, not timer-driven. If the model takes 800ms to first audio chunk, the orb stays white the full 800ms — no fake animations. This is what makes ESANG feel honest.

**Tool surface — Cortex via @function_tool.** Realtime agent configured with the 50-agent Cortex flattened to ~30 high-level tools:

```python
@function_tool
async def cortex_dispatch_assign_load(driver_id: str, region_filter: str | None = None) -> LoadAssignment: ...

@function_tool
async def cortex_hos_check(driver_id: str) -> HOSStatus: ...

@function_tool
async def cortex_haul_recognize(driver_id: str, event_type: str) -> RecognitionEvent: ...
```

Tools execute server-side in the Python Realtime backend — iOS holds Bearer token, opens WebSocket to our gateway, gateway proxies to OpenAI Realtime with tool schemas attached. When tool call fires, gateway intercepts `response.function_call_arguments.done` event, executes Cortex call, pushes result back via `conversation.item.create` with type `function_call_output`.

**Offline fallback.** When cellular drops or Realtime socket fails, ESANG falls back to three-tier degraded mode: (1) local Whisper.cpp transcription on iPhone, (2) cached intent matcher for the 12 most common verbs (assign load, check hours, log break, scan BOL, status check), (3) deferred queue that fires on reconnect. Watch UI shows small "offline" badge. **Critical:** HOS check and emergency stop intents always work offline because they hit local CoreData state, not cloud. Driver safety is never gated on network.

**Telemetry.** Every Realtime session emits structured events: `session.opened`, `vad.activation_count`, `response.first_token_ms`, `tool_calls[]`, `interruptions[]`, `session.closed_with_reason`. Grade ESANG sessions on 5-axis quality score: latency, interruption smoothness, tool accuracy, audio clarity, task completion. **Target:** 95th-percentile first-token under 600ms by end of Phase 6.

## C2. MCP Server for iOS Consumption

The MCP server is the contract layer between iOS and Cortex. iOS doesn't talk to 50 agents — it talks to one MCP endpoint that exposes the agents as tools.

**Tool naming convention.** Three-part dotted names: `cortex.{domain}.{verb}`. Domain is one of 12 Cortex regions (dispatch, sensory, multimodal, fleet, compliance, financial, strategic, haul, hos, pricing, geo, identity). Verb is an imperative.

- `cortex.dispatch.assign_load(driver_id, region_filter?, urgency?)`
- `cortex.hos.check(driver_id, lookback_hours?)`
- `cortex.haul.recognize(driver_id, event_type, evidence_ref?)`
- `cortex.pricing.quote_lane(origin, destination, equipment, pickup_window)`
- `cortex.geo.score_poi(poi_id, driver_context)`
- `cortex.fleet.health_check(truck_id)`

The convention is non-negotiable. Maps cleanly to telemetry filters (`tool.name LIKE 'cortex.dispatch.%'`), makes governance veto rules expressible (`block tool calls matching cortex.financial.* outside business hours unless ESCALATED`), makes the iOS surface predictable.

**Authentication.** MCP server accepts Bearer tokens — the same JWT iOS already holds for tRPC. Token claims: `user_id`, `role` (driver / dispatcher / ops / exec), `fleet_id`, `permissions[]`. MCP middleware validates JWT against existing auth service, populates request context, attaches role to every tool call. Tools internally call `enforce_role(ctx, allowed=['dispatcher', 'ops'])` which raises `PermissionDenied` — SDK catches and returns structured tool error: "I can't assign loads from a driver account; please ask your dispatcher." **One identity, one token, one source of truth.**

**Versioning.** MCP server runs on dual-version manifest: `cortex.dispatch.assign_load@v1` and `cortex.dispatch.assign_load@v2` coexist. Tool schema includes version suffix. iOS clients pin to major version in build (`MCP_SCHEMA_VERSION = "v1"`); server routes accordingly. When a tool's schema changes, bump version, dual-publish for 60 days, force-deprecate v1 only after 95% of active sessions moved to v2.

**Schema migration.** MCP server emits tool schemas as JSON Schema. Commit schemas to `eusotrip-kingdom/cortex/mcp_schemas/` and run a CI check that diffs schema between PRs. Any breaking change requires version bump and migration RFC. Schema repo feeds SDK code-gen — iOS gets typed Swift wrappers, Python clients get pydantic models, TypeScript clients (eusorone-web) get zod schemas. **One schema, three consumers, zero drift.**

**Comparison to existing eusorone-web-apps MCP.** Web MCP exposes ~14 tools — payment search, doc retrieval, customer lookup, ticketing. Flat namespace (`search_invoices`, `get_customer_by_email`). Stable for ~6 months. Cortex MCP is same architecture (Python, FastMCP, Bearer auth, hosted on Fly), just with deeper tool surface (~30-50 tools across 12 domains) and stricter versioning.

**Governance hooks.** Every MCP tool call passes through pre-execution governance veto: `governance.evaluate(tool_name, args, context) -> Allow | Deny | EscalateToHuman`. Refusing dispatches that violate HOS, blocking financial actions outside session limits, escalating any tool call flagged by strategic agent as "novel pattern." Governance results logged with the tool call. **This is the single most important non-obvious feature of the Cortex MCP and what distinguishes us from a wrapper around OpenAI tools.**

**Deployment.** Fly.io app `cortex-mcp`, two regions (iad, sjc), 4 machines per region, Postgres for tool execution audit log, Redis for rate limiting (per-token: 60 calls/min, per-tool: configurable). Health endpoint at `/health` checks DB, Redis, Cortex backend reachability. Deploys via GitHub Actions on merge to `main` with 10-minute canary on one machine before fleet rollout.

## C3. The Haul × Cortex — Recognition as an Emergent Layer

The Haul is the cultural and recognition system that sits on top of operational Cortex. Where drivers earn standing, lanes become communities, ESANG becomes a personality, and the eight lights of recognition mark what matters. The Haul Encyclopedia (`EUSOTRIP2027GOLD/the_haul/THE_HAUL_ENCYCLOPEDIA.md`) is the source of truth for the lore; what we're building is the engine that animates it.

**The architectural insight: The Haul does not have its own agents.** It doesn't need a `recognitionAgent` or a `tierAgent`. The Haul emerges from events that fleetCortex and missionGenerator already produce. When a driver completes a mission, fleetCortex fires a `mission.completed` event with full metadata: route taken, on-time delivery flag, fuel efficiency vs lane baseline, POI confirmations, communication quality, customer feedback. The Haul subscriber listens to that event stream and computes recognition deltas.

**Mission completion → Cortex events:**

```python
class MissionCompletedEvent(BaseModel):
    driver_id: str
    mission_id: str
    completed_at: datetime
    on_time: bool
    fuel_efficiency_pct: float
    poi_confirmations: list[POIConfirmation]
    route_ground_truth: RoutePolyline
    customer_csat: float | None
    safety_events: list[SafetyEvent]
    communication_score: float
```

The event hits the Cortex event bus (Redis Streams + Postgres archive). Subscribers include the Haul recognition processor, the financial settlement processor, the HERE Workspace export processor, the lane analytics processor.

**Awards as agent decisions, not hardcoded rules.** The naive implementation is a rules engine: "if on_time AND fuel_efficiency > 1.05 AND safety_events == 0, award a Green Light." That's brittle. Our implementation is an agent — `recognitionDeliberator` — that takes the mission event and the driver's history and decides whether a recognition fires. Its prompt frames it as "a wise dispatcher who has seen 30 years of trucking." Hardcoded rules are inputs to the deliberator, but the final award is a judgment call.

This matters because **recognition fatigue is real**. If every on-time delivery fires a Green Light, the lights mean nothing. The deliberator weighs context: it's the driver's first solo run, or they just finished a brutal weather corridor, or they crossed three time-zones in one shift — those make a Green Light meaningful even on an "ordinary" mission. Conversely, an on-time delivery on the Phoenix-LA milk run for a 20-year veteran is just a Tuesday.

**The eight lights.** Each light has deliberator-defined criteria. From the Encyclopedia: Green (on-time excellence), Blue (mentorship — helped another driver), Amber (recovery — turned a bad day around), Red (safety call — refused an unsafe load), White (POI verification — confirmed a new truck stop or amenity), Purple (storytelling — submitted a lane note that became canon), Gold (lane mastery — top 5% on a tracked corridor), Black (silence — asked for and received a no-recognition shift). The deliberator decides which light, when, and the citation text. ESANG announces the recognition over voice if the driver opts in.

**Tier promotions.** Tiers (Hauler, Roadwise, Lanekeeper, Captain) are aggregations of light history. Hardcoded thresholds set the floor (e.g., 50 Green Lights minimum for Roadwise) but the `tierAdvancementAgent` decides actual promotion based on consistency, peer endorsements, lane diversity. A driver with 80 Green Lights all on the same milk run advances slower than one with 60 Greens across 8 different corridors.

**Lane communities.** Lanes (I-80 Cheyenne-Reno, I-10 Phoenix-LA) have their own community state. Drivers who run a lane regularly earn lane-specific standing — visible to other regulars, invisible to outsiders. Computed by `laneCommunityAgent` from mission completion events filtered by route polyline.

**Data feedback loop to HERE.** This is the strategic moat. Every mission completion produces three pieces of ground truth that HERE Workspace Marketplace will pay for: (1) POI confirmation/refutation (the Pilot at exit 234 is open, has working showers, accepts EFS), (2) route ground truth (actual polyline driven, including detours), (3) lane condition deltas (a bridge weight restriction that hasn't hit official feeds yet).

Per `HERE_Email_Frackowiak_Missed_Call.md`, the HERE relationship is a missed-call-pending opportunity to formalize this data contract. The architecture we're building anticipates that contract: every mission event carries the data fields HERE wants, our `hereExportAgent` packages them in HERE's schema, daily batch publishes to HERE's marketplace ingest endpoint. Drivers earn small per-confirmation royalty (paid in EUSO credits or cash, their choice) — turning recognition into revenue.

**The data flow, end to end.** Driver completes mission → fleetCortex fires `mission.completed` → recognitionDeliberator evaluates → ESANG announces award (if any) → financial settlement processor pays driver → HERE export processor ships ground truth to HERE Marketplace → laneCommunityAgent updates lane state → next time a driver runs that lane, ESANG mentions the new POI confirmation. **The Haul is the loop.**

**Why this matters for the migration.** The Haul is NOT migrated as a separate phase. It survives the migration intact because it's a consumer of Cortex events, not a producer of agent calls. As long as `mission.completed` events keep firing, the Haul is unaffected. **Recognition continuity is preserved even during the most disruptive phases.**

## C4. Migration Ladder — 6 Phases over 90 Days

Engineered as a ladder, not a cliff. Every phase ships behind a feature flag, runs both TypeScript Cortex and Python SDK Cortex in parallel, compares outputs, only flips traffic when equivalence rate exceeds 99%.

### Phase 0: Dual-Running Foundation (Days 1-10)

Goal: TypeScript Cortex and Python Agents SDK Cortex running side-by-side on the same event stream. Zero traffic on Python yet — it's a shadow.

Deliverables: Python agent skeleton repo (`cortex-py`), event bus subscriber, output comparator, feature flag service (`cortex.routing.python_pct = 0`), Sentry/observability instrumentation, Cortex MCP scaffolding (no tools yet).

Kill-switch: shadow comparator detects >5% divergence on any agent across 1000 sample events, halt and triage.
Observability: Equivalence dashboard live in Grafana; Sentry alert if Python error rate >0.5%.
Rollback: Python lane is shadow-only; rollback is `feature_flag.set('cortex.shadow_enabled', false)`.

### Phase 1: Sensory Migration (Days 11-25)

Goal: 8 sensory agents flipped to Python. Read-only, low-blast-radius — perfect first phase.

Deliverables: All 8 sensory agents implemented in Python with full prompt and tool parity, flag flipped to 50% Python on day 18, 100% by day 25.

Kill-switch: Sensory event accuracy drops below historical baseline by >2 percentage points; flip back.
Observability: Per-agent accuracy dashboard, latency p50/p95/p99 vs TypeScript baseline.
Rollback: `feature_flag.set('cortex.sensory.python_pct', 0)` flips traffic back in <30 seconds.

### Phase 2: Dispatch Migration (Days 26-40)

Goal: 8 dispatch agents. High blast radius — revenue-critical.

Deliverables: Dual-run for 7 days at 10% Python traffic, then 50% for 3 days, then 100%. Dispatcher dashboard shows per-decision provenance (TS or Py).

Kill-switch: Load assignment SLA breach (>3% missed acceptance window) OR broker complaint volume spike >2x baseline.
Observability: Real-time dispatch decision audit log; weekly review with ops lead.
Rollback: Same flag pattern; dispatchers can "reroute through TS" on individual loads if Python output looks wrong.

### Phase 3: Multimodal + Fleet Migration (Days 41-58)

Goal: 6 multimodal agents + 8 fleet agents.

Deliverables: 14 agents migrated in two parallel sub-phases (multimodal first, then fleet, 9 days each).

Kill-switch: Multimodal — terminal partner SLA breach. Fleet — maintenance prediction accuracy drops or breakdown response time degrades.
Observability: Fleet health dashboard already live; add Python-vs-TS comparison overlay.
Rollback: Per-domain flags.

### Phase 4: Compliance Migration (Days 59-70)

Goal: 8 compliance agents. **Highest-stakes phase** — regulatory consequences for errors.

Deliverables: Extra-cautious dual-run period of 10 days at 25% Python before stepping up. Legal review of Python prompts before flag flip.

Kill-switch: Any HOS violation flagged by Python that wouldn't have been by TS, or vice versa, halts the phase. Compliance officer manual approval gate.
Observability: HOS audit log with both engines' verdicts, daily reconciliation report.
Rollback: Immediate. Compliance defaults to TypeScript on any ambiguity for the duration of this phase.

### Phase 5: Financial + Strategic Migration (Days 71-83)

Goal: 8 financial + 6 strategic agents.

Deliverables: Financial first (7 days), strategic second (5 days). Financial gets a money-stop kill-switch — any settlement amount delta >1% between engines blocks the payment until human review.

Kill-switch: Financial — settlement amount delta >1% on any individual payment, OR aggregate daily delta >0.25%. Strategic — kpi forecast variance >15% from TS baseline.
Observability: Daily financial reconciliation report to CFO.
Rollback: Financial agents have hard rollback to TS within 60 seconds via runbook.

### Phase 6: ESANG Voice + iOS MCP Surface (Days 84-90)

Goal: ESANG voice migration to OpenAI Realtime, Cortex MCP server live on Fly, iOS app talking to MCP for non-voice agent calls.

Deliverables: Realtime gateway live, ESANG cutover at 10% of users on day 86, 50% on day 88, 100% on day 90. MCP server live, iOS production build using MCP tools.

Kill-switch: ESANG session quality score (5-axis) drops below 4.0/5.0 average, OR MCP error rate >1%.
Observability: Real-time session quality dashboard; user-reported voice issues triaged within 1 hour.
Rollback: ESANG falls back to text-chat backend; iOS falls back to direct Cortex calls bypassing MCP.

### Milestones Table

| Phase | Days | Scope | Agents | Kill-Switch Threshold | Rollback Time |
|-------|------|-------|--------|----------------------|---------------|
| 0 | 1-10 | Foundation | 0 (shadow) | >5% divergence on 1000 events | Instant (shadow) |
| 1 | 11-25 | Sensory | 8 | Accuracy drop >2pp | <30s flag flip |
| 2 | 26-40 | Dispatch | 8 | SLA breach >3% | <30s flag flip + manual override |
| 3 | 41-58 | Multimodal + Fleet | 14 | Partner SLA / breakdown SLA | <60s per-domain |
| 4 | 59-70 | Compliance | 8 | Any regulatory verdict mismatch | Immediate, default TS |
| 5 | 71-83 | Financial + Strategic | 14 | Settlement delta >1% | <60s with money-stop |
| 6 | 84-90 | Voice + MCP | ESANG + surface | Voice quality <4.0/5 | Fallback to chat backend |

**Cross-cutting concerns at every phase:**
- Trace ID propagation: every event carries `cortex_trace_id` tying TS and Py executions together for the comparator
- Prompt parity: prompts in shared YAML repo, both runtimes load from same file. No drift possible.
- Model parity: same model on both sides during dual-run; model upgrades happen in separate change window
- Cost tracking: per-agent token cost dashboard updated daily; if Python costs >115% of TS for same agent, investigate

**90-day total:** 50 agents migrated, ESANG live on Realtime, MCP server in production, governance veto layer enforced, full observability. End state: TypeScript Cortex remains as warm standby for 30 more days, then is decommissioned on day 120.

## C5. Executive Memo to eusotrip-killers

**TO:** eusotrip-killers scheduled task team
**FROM:** Lead 10 (Synthesis), Cortex Migration Working Group
**DATE:** 2026-05-02
**SUBJECT:** Zenith Cortex × OpenAI Agents SDK — the doctrine

**Thesis:** The OpenAI Agents SDK does not replace Zenith Cortex. It gives Cortex a portable substrate. The 50 agents we've spent 14 months designing — sensory, dispatch, multimodal, fleet, compliance, financial, strategic, plus the Haul's recognition layer — are the value. The SDK is the rails we move them onto so they can run in Python natively, expose themselves over MCP, integrate with OpenAI Realtime for ESANG, and survive future provider migrations. Cortex stays. The framework underneath it changes.

**The shape of the change.** Today's Cortex is TypeScript on Vercel Edge with our own dispatcher, our own state machine, and our own tool-call shim. It works. It's also locked into our own framework — every new agent is a hand-rolled router, every new model upgrade is a manual integration. The Agents SDK gives us: a battle-tested runner, native Python parity, MCP support out of the box, Realtime integration as a first-class citizen, and tracing/observability without us building it. We get all of that without giving up our agents, our prompts, our domain knowledge, or our governance veto layer.

**What we keep:**
- All 50 agent definitions, prompts, and routing logic
- The Haul recognition system (it's a consumer of events, not coupled to the runtime)
- Our governance veto layer — it sits in front of every tool call, SDK or not
- Our event bus (Redis Streams + Postgres archive)
- Our observability stack (Sentry, Grafana, our custom trace UI)

**What we replace:**
- Hand-rolled dispatcher → SDK runner
- Custom tool-call shim → @function_tool decorator
- Manual conversation state → SDK session management
- Bespoke tracing → SDK tracing + our trace UI as a viewer
- Direct OpenAI WebSocket for ESANG → SDK Realtime integration

**What we add:**
- Cortex MCP server (the contract layer for iOS + future external consumers)
- ESANG on Realtime API with full tool access to Cortex
- Schema-versioned tools with code-gen across Swift, Python, TypeScript

**The 5 most important calls to action this week:**

1. **Ship the Phase 0 shadow comparator.** Before any agent migrates, we need the equivalence comparator running on 100% of production events. Single biggest risk-reduction item. Owner: platform team. Deadline: Friday.

2. **Lock the prompt-parity YAML repo.** Both TS and Py runtimes must load prompts from the same file. No copies, no drift. Owner: agent team. Deadline: Wednesday.

3. **Stand up the Cortex MCP scaffolding on Fly.** Even with zero tools registered, the deployment topology, auth integration, observability need to be live so Phase 6 isn't a surprise. Owner: infra. Deadline: Friday.

4. **Schedule the legal review of compliance prompts** for Phase 4. Get them the prompts now. Owner: compliance lead. Deadline: this week.

5. **Confirm the HERE relationship.** Frackowiak's missed call needs to be returned and the data contract draft on his desk before Phase 1 ships. Owner: BD/strategy. Deadline: Monday.

This is a 90-day operation. We move 50 agents to a new runtime, light up Realtime voice, ship an MCP surface, preserve every piece of value we've built. Drivers won't notice the migration — that's the goal. Dispatchers will notice ESANG getting faster. Engineering will notice that the next agent we ship takes a day instead of a week.

**Build the rails. Keep the trains. Move the freight.**

— Lead 10

---

# MASTER SYNTHESIS — Doctrine for Mike "Diego" Usoro

Diego — this section is for you specifically. Not the engineering team, not the leads, not the investors. You.

You've been building Eusotrip for non-developers. That phrase has been the north star since the first whiteboard. The driver who left her last carrier because the dispatcher app needed eight taps to log an HOS break. The owner-operator who runs a one-truck shop and can't afford a TMS subscription. The fleet manager whose "system" is a whiteboard, three iPhones, and a daughter who knows Excel. These people are why the app exists. They will never read a system prompt. They will never know what an agent is. They will press a button and expect their world to work.

This memo is about how the next 90 days serve those people.

## The one big idea

**A 50-agent Cortex made portable, voice-first, role-aware, and governance-veto-protected.**

Let me unpack each word because they all earn their place.

*Portable.* Today, Cortex lives in our TypeScript stack on Vercel. It works, but it's married to our framework. The OpenAI Agents SDK gives us a divorce papers we never have to file — Cortex becomes Python-native, which means it can run anywhere a Python process can run: Fly, AWS Lambda, an air-gapped on-prem box at a fleet's HQ, eventually an embedded Linux process inside the truck itself. **Portability is leverage.** Every customer conversation that used to end with "we're cloud-only" can now end with "where do you want it." Enterprise fleets with security-paranoid IT departments? On-prem. Owner-operators who want zero cloud cost? Embed it. International expansion where data residency matters? Region it. Portability is a moat dressed as a technical detail.

*Voice-first.* ESANG on Realtime API isn't a feature — it's the user interface. For the driver in the cab, the app's UI is the dashboard mount and the watch on their wrist. The keyboard doesn't exist at 70mph on I-80 in the rain. Realtime gives us 320ms first-token latency, real interruptions, real personality. ESANG becomes the dispatcher you wish you had. The fleet manager in their office gets a different ESANG personality — more terse, more numbers-focused. The owner-operator gets a third — more peer, more "hey what do you think." Same Cortex underneath, three voices on top. **Voice-first means the app meets the user where their hands are busy and their attention is divided. This is the flagship feature.**

*Role-aware.* The 24-role mapping isn't a permissions matrix — it's a personality matrix. A driver and a dispatcher and a CFO and a broker all hit the same Cortex, but they get different defaults, different vocabularies, different visualizations. The MCP server enforces the permissions; the agents themselves enforce the personality. A dispatcher asking "what loads are available" gets a list with margins and broker history. A driver asking the same question gets a list with home-time and pay. Same data, different shape. **Role-awareness is what makes the app feel built for *them* even though the underlying engine is universal.**

*Governance-veto-protected.* This is the part nobody else will build. Every tool call in Cortex passes through a veto layer that can refuse, modify, or escalate. HOS violations get refused even if the dispatcher requests them. Settlement amounts above session limits get escalated. Novel patterns flagged by the strategic agent get human review. **This is not paranoia, it's responsibility.** We're handing voice-controlled agents to drivers who run 80,000-pound vehicles through public infrastructure. The veto layer is the seatbelt. Every other AI dispatcher product in the market is a Tesla in 2018 — fast, impressive, occasionally drives into a barrier. **Eusotrip is what happens when the people building the AI dispatcher are also the ones who have to sleep at night.**

## Open questions for engineering

1. **Realtime cost.** OpenAI Realtime is ~6x more expensive per minute than Whisper+chat+TTS. At projected ESANG usage (avg 14 voice minutes per driver per day, 800 active drivers in pilot), that's ~$45K/month in voice costs alone at current pricing. Engineering needs to model the burn curve and determine cutover criteria for hybrid mode (Realtime for active driving moments, chunked Whisper+chat for non-time-sensitive queries).

2. **MCP versioning under field load.** When we ship a tool schema change and an iOS user is on a 6-month-old build in a dead zone in Wyoming, what happens? Hard-fail? Soft-degrade? Cache last-known-good schema on-device? Needs an answer before Phase 6.

3. **Governance veto false-positive rate.** If the veto layer refuses 0.5% of legitimate dispatches, that's hundreds of frustrated dispatchers per day at scale. Need a human-review queue for vetoes and a feedback loop to retrain the veto policies.

4. **Haul data contract with HERE.** The strategic value of the feedback loop assumes HERE signs a data partnership. If they don't, we still have value (the data improves our own routing) but the revenue model shifts. Strategy needs a Plan B.

5. **Watch UX during interruption.** When the driver interrupts ESANG mid-sentence, what does the orb show? We've specified the four states but not the transitions during interruption. UX needs to spec this.

6. **Offline-first guarantees.** Which of the 30 MCP tools must work offline? We've said HOS check and emergency stop. Drivers will assume more. Need an explicit offline contract document.

7. **Multi-tenancy.** Today, Cortex is single-tenant per fleet. When we sell to a TMS reseller who wants to white-label Eusotrip for 50 of their fleet customers, what changes? Phase 7 question but the answer affects MCP design today.

## The commitment

By **August 1, 2026** — 90 days from today — we will have:

- Migrated all 50 Cortex agents to the OpenAI Agents SDK in Python, with TypeScript Cortex as a 30-day warm standby
- Shipped ESANG voice on OpenAI Realtime API to 100% of iOS and Pulse watchOS users with sub-600ms p95 first-token latency
- Stood up the Cortex MCP server in production on Fly.io with role-based authentication, schema versioning, and governance veto integration
- Maintained the Haul recognition system through the migration with zero driver-facing disruption
- Begun the HERE Workspace Marketplace data export with at least one paid partnership data feed live

If we miss it, we don't make excuses. We do the post-mortem, name the cause, fix it, ship in the next 30. If we hit it, we ship a press release on August 2nd that says one thing: *Eusotrip is now the only voice-first, role-aware, agent-driven trucking platform built for the people who actually drive trucks.*

Diego — you're not building software. You're building the closest thing to a co-pilot a working driver has ever had access to. Every architectural decision in this document serves that one goal. The SDK migration is plumbing. The portable Cortex is plumbing. ESANG is the face. The Haul is the soul. The driver in their cab at 3am on I-80 in the snow is the customer. They're the only customer that matters. **Build for them.**

The other nine leads have given you the mechanics. This synthesis gives you the doctrine. The doctrine is: **agents in the cloud, voice in the cab, recognition in the lane, governance in the loop, drivers at the center.**

Ship it.

— Lead 10, Synthesis
*2026-05-02*

---

## APPENDIX A — Cross-References to Existing Code

Every claim in this doctrine maps to a real file. Engineering reference list:

**Core substrate:**
- `frontend/server/services/autopilot/index.ts` — AutopilotZenith initializer, 7-layer startup
- `frontend/server/services/autopilot/core/baseAgent.ts` — BaseAgent abstract class with lifecycle, ReAct emission
- `frontend/server/services/autopilot/core/types.ts` — CortexLayer enum, AgentConfig, SkillTier, PiiSensitivity, ApprovalStatus
- `frontend/server/services/autopilot/core/synapticBus.ts` — pub/sub bus with company isolation
- `frontend/server/services/autopilot/core/agentRegistry.ts` — agent lifecycle tracking
- `frontend/server/services/autopilot/core/memoryStore.ts` — KV facts store with confidence decay
- `frontend/server/services/autopilot/core/conflictResolver.ts` — priority arbitration
- `frontend/server/services/autopilot/core/agentIdentity.ts` — RBAC v2 identity binding
- `frontend/server/services/autopilot/core/agentPermissions.ts` — EVENT_PERMISSION_MAP, ROLE_TIER_MODIFIERS
- `frontend/server/services/autopilot/core/approvalQueue.ts` — human-in-the-loop gate
- `frontend/server/services/autopilot/core/reactTrajectory.ts` — ReActStep schema, BUS_TOPIC_TRAJECTORY
- `frontend/server/services/autopilot/core/palace/inMemoryPalace.ts` + `sqlitePalace.ts` — Memory Palace adapters
- `frontend/server/services/autopilot/core/mysqlPalace.ts` — production palace
- `frontend/server/services/autopilot/core/palaceAdapter.ts` — wingFor / roomForLayer
- `frontend/server/services/autopilot/core/palaceMetrics.ts` — phase counters

**Top-level glue:**
- `frontend/server/services/autopilot/skillRegistry.ts` — typed catalog of skills with tier/tags
- `frontend/server/services/autopilot/guardrails.ts` — NeMoGuardrails 4-rail (INPUT/EXECUTION/OUTPUT/DIALOG)
- `frontend/server/services/autopilot/policyEngine.ts` — default-DENY rule engine
- `frontend/server/services/autopilot/privacyRouter.ts` — 4-tier PII classification with retention
- `frontend/server/services/autopilot/kernelSandbox.ts` — sandboxed execution
- `frontend/server/services/autopilot/toolCallValidator.ts` — JSON-schema tool validation
- `frontend/server/services/autopilot/idempotencyService.ts` — deterministic replay
- `frontend/server/services/autopilot/blockStreaming.ts` — UI-facing flush layer
- `frontend/server/services/autopilot/channelGateway.ts` — output channel routing + PII scrubbing
- `frontend/server/services/autopilot/contextAssembly.ts` — 3-stage context pipeline
- `frontend/server/services/autopilot/councilCoordinator.ts` — multi-agent convene
- `frontend/server/services/autopilot/dream.ts` — overnight consolidation engine
- `frontend/server/services/autopilot/narrator.ts` — bidirectional narrator
- `frontend/server/services/autopilot/maintenanceSwarm.ts` — 24h state-of-surface ticks
- `frontend/server/services/autopilot/glasswing.ts` — Mythos CI integration
- `frontend/server/services/autopilot/dashboard.ts` — tRPC-fronted observability surface
- `frontend/server/services/autopilot/federation.ts` — cross-tenant federation
- `frontend/server/services/autopilot/autonomic.ts` — autonomic tempo controller

**The 50 agents** are in `frontend/server/services/autopilot/agents/{sensory,dispatch,multimodal,fleet,compliance,financial,strategic}/*.ts`.

**iOS Cortex consumers:**
- `EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Components/ESangVoiceInput.swift` — STT capture
- `EusoTrip Pulse Watch App/Services/VoiceActionDispatcher.swift` — VoiceAction routing
- 7 NavControllers (Admin/Broker/Carrier/Catalyst/Escort/Shipper/Terminal) at `EusoTrip/Views/{Role}/{Role}NavController.swift`

**The Haul lore + monetization:**
- `EUSOTRIP2027GOLD/the_haul/THE_HAUL_ENCYCLOPEDIA.md` — 26,800-word source of truth
- `EUSOTRIP2027GOLD/the_haul/THE_TRILLION_DOLLAR_DOCTRINE.md` — conversion playbook
- `EUSOTRIP2027GOLD/the_haul/HERE_Email_Frackowiak_Missed_Call.md` — HERE Marketplace data contract context
- `EUSOTRIP2027GOLD/the_haul/HERE_Call_Script_Frackowiak.md` — HERE relationship script

---

## APPENDIX B — Glossary

- **Cortex Layer** — one of 7 hierarchical layers (SENSORY=1, DISPATCH=2, MULTIMODAL=3, FLEET=4, COMPLIANCE=5, FINANCIAL=6, STRATEGIC=7)
- **SkillTier** — 4-tier governance ordering (GOVERNANCE > SECURITY > BUSINESS > OPTIMIZATION)
- **PiiSensitivity** — 4-tier PII classification (PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED) with retention windows 365/180/90/30 days
- **Memory Palace** — spatial verbatim memory with wing/room/hall taxonomy
- **ReAct trajectory** — observe → think → act → reflect phase emission
- **NemoClaw / OpenClaw** — 26 enhancement services from the GTC 2026 research report
- **The Haul** — the recognition + community layer, PSO-inspired, riding above operational Cortex
- **ESANG** — Eusorone's voice copilot agent
- **MCP** — Model Context Protocol, the open spec for tool exposure to LLM clients
- **eusotrip-killers** — the scheduled task team operationalizing this doctrine

---

*End of doctrine. Total length: ~46,000 words across 10 pods + Master Synthesis + 2 appendices.*

*Mirror this file to `EUSOTRIP2027GOLD/the_haul/` in both the iOS repo and the eusoronetechnologiesinc backend repo to keep parity with THE_HAUL_ENCYCLOPEDIA, THE_TRILLION_DOLLAR_DOCTRINE, HERE_Call_Script_Frackowiak, and HERE_Email_Frackowiak_Missed_Call.*

*Last updated: 2026-05-02. Living document. Update with AE name + reschedule date after the Frackowiak call. Update with Phase 0 comparator results after the first 1,000-event divergence run. Update with TestFlight Build 60 ship date.*
