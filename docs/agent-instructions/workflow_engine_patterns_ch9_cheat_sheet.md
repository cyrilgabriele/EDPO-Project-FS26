# Chapter 9 Pattern Cheat Sheet — Workflow Engines and Integration Challenges

Source basis: *Chapter 9, “Workflow Engines and Integration Challenges,”* from *Practical Process Automation* by Bernd Ruecker. This cheat sheet summarizes the architectural patterns and closely related decision patterns explicitly discussed in the chapter, using only that chapter as source material.

---

## 1. Synchronous Request/Response

### Description
A process invokes a remote service and waits until the response arrives before continuing. In BPMN this is typically modeled with a **service task** that blocks process progress until the call returns.

### Key properties
- Caller waits for completion.
- Typical implementation technology: REST.
- Creates **temporal coupling** between caller and callee.
- Makes communication delays and service outages directly visible to the caller.
- Can become long-running when the downstream service is slow or unavailable.

### When to use
- The result is required immediately to continue the business flow.
- The expected latency is low and failure handling is simple.
- The user experience requires an immediate answer.
- The failure can reasonably be propagated to the client.

### Example
A check-in service calls a barcode service synchronously to generate a boarding pass. If the barcode service is unavailable, the check-in flow stalls and the user receives an error or must retry later.

### Diagram
```text
[Process Step]
     |
     v
[Service Task: Call Remote Service]
     |
 (wait/block)
     |
     v
[Continue with Response]
```

### Trade-offs
**Benefits**
- Simple interaction model.
- Easy for clients to understand.
- Fits request/response APIs naturally.

**Costs / risks**
- Caller is blocked.
- Outages propagate quickly across service chains.
- Encourages fragile coupling in distributed systems.
- Often pushes retry burden onto clients or end users.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Simplicity | 5/5 | Straightforward call-and-wait model. |
| Operational robustness | 2/5 | Sensitive to latency and downstream failures. |
| Scalability for long waits | 1/5 | Blocking behavior is a poor fit for slow interactions. |
| UX immediacy | 5/5 | Best when answers are available quickly. |

---

## 2. Stateful Retry in the Responsible Service

### Description
Instead of exposing downstream failures to the client, the service that owns the business responsibility keeps state locally and performs retries itself. A workflow engine can hold state and schedule retries.

### Key properties
- Failure handling stays local to the responsible service.
- Retries become **stateful** rather than delegated to the caller.
- Often shifts the external API from immediate response to accepted-for-processing semantics.
- Workflow engines provide persistence and scheduling support.

### When to use
- The service can realistically resolve transient failures itself.
- The client should not carry retry state.
- Business responsibility for completion belongs to the service, not the caller.
- You need retries across minutes or longer.

### Example
The check-in service accepts a boarding-pass request, retries the barcode generation internally, and later completes the request instead of forcing the traveler to retry manually.

### Diagram
```text
[Client Request]
      |
      v
[Responsible Service]
      |
      v
[Workflow State + Retry Schedule]
      |
   retry call
      v
[Downstream Service]
```

### Trade-offs
**Benefits**
- Cleaner client API.
- Encapsulates failure handling where the responsibility belongs.
- Reduces the number of components exposed to failure details.

**Costs / risks**
- Introduces service-side state.
- Makes the implementation more complex than stateless pass-through calls.
- Often implies asynchronous completion.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Client API cleanliness | 5/5 | Keeps retry logic out of the client. |
| Implementation complexity | 3/5 | Requires state and scheduling. |
| Fault containment | 5/5 | Localizes transient integration failures. |
| Architectural maturity required | 4/5 | Benefits from workflow infrastructure. |

---

## 3. Asynchronous Request/Response

### Description
The sender issues a request without blocking for the result. The reply, if required, arrives later through asynchronous communication, typically messaging. BPMN models this with a send step followed by a receive step and often a timeout.

### Key properties
- Nonblocking communication.
- Removes or reduces temporal coupling.
- Makes long-running communication explicit.
- Requires **correlation** to match responses to the waiting process instance.
- Timeouts are first-class design concerns.

### When to use
- A response is required, but not immediately.
- Network or partner latency is unpredictable.
- Long-running waits must be persisted safely.
- Messaging infrastructure is available.

### Example
A process sends a payment request, stores a generated correlation ID, waits for the response message, and handles a timeout if the answer never arrives.

### Diagram
```text
[Send Request] ---> (message channel) ---> [External Service]
      |
      v
[Wait for Response / Timeout]
      |
      v
[Continue or Escalate]
```

### Trade-offs
**Benefits**
- More robust under slow or unavailable downstream systems.
- Natural fit for long-running interactions.
- Encourages explicit timeout handling.

**Costs / risks**
- Correlation logic is required.
- Harder to reason about than synchronous calls.
- Delayed completion affects user experience and client design.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Resilience to latency | 5/5 | Designed for non-immediate responses. |
| Conceptual simplicity | 3/5 | More moving parts than synchronous calls. |
| Support for long-running work | 5/5 | Strong fit for persisted waits. |
| Operational observability need | 4/5 | Requires strong monitoring and tracing. |

### Correlation guidance from the chapter
- Prefer **artificial IDs** such as UUIDs created specifically for one interaction.
- Do **not** rely on workflow engine internal IDs.
- Be cautious when correlating with business IDs because they may stop being unique in edge cases.

---

## 4. Message Buffering / “Ready to Receive” Protection

### Description
BPMN correlation semantics require a process instance to be in the exact receive state when the message arrives. Message buffering compensates for race conditions where the reply arrives before the process instance is technically ready to receive it.

### Key properties
- Addresses timing gaps between sending and entering the receive state.
- Often implemented as a vendor capability, not as standard BPMN behavior.
- Can rely on message-system buffering and retry as a workaround.
- Prevents lost or rejected correlations caused by millisecond-level races.

### When to use
- Fast asynchronous responses can arrive almost immediately.
- The receive state is reached slightly after the external acknowledgment path completes.
- You want to reduce fragile, timing-dependent correlation failures.

### Example
A system sends a SOAP request, receives a technical acknowledgment, but the actual async reply arrives before the process instance has fully committed and entered the BPMN receive task.

### Diagram
```text
[Send Request]
     |
     v
[Process commit / transition]
     |
     |   response arrives early
     +<---------------------------[Async Response]
     |
     v
[Receive Task becomes active]

With buffering:
response is held until correlation succeeds.
```

### Trade-offs
**Benefits**
- Eliminates a subtle but common timing problem.
- Improves robustness of asynchronous orchestration.
- Reduces need for bespoke retry hacks.

**Costs / risks**
- Often vendor-specific.
- Can hide timing issues that teams still need to understand operationally.
- Without it, compensating solutions may become custom and messy.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Robustness improvement | 4/5 | Solves real correlation race conditions. |
| Portability | 2/5 | Often proprietary rather than standard. |
| Implementation burden without engine support | 4/5 | Workarounds are awkward. |
| Importance in fast async integrations | 5/5 | Critical when replies can arrive immediately. |

---

## 5. Aggregator Pattern

### Description
An aggregator collects multiple related messages, stores them until a complete set has arrived, and then publishes or advances with a single consolidated result. The chapter explicitly ties this to the Enterprise Integration Patterns definition and shows BPMN as a practical implementation vehicle.

### Key properties
- **Stateful** by nature.
- Waits for multiple correlated messages.
- Often needs timeout handling.
- Produces one distilled or combined outcome from many inputs.
- Benefits from workflow-engine persistence and visibility.

### When to use
- Multiple responses must be collected before progress is possible.
- Partial results may arrive at different times.
- You need a durable, observable coordination point.
- You need timeouts for missing inputs.

### Example
A process sends requests to multiple parties or subsystems, waits for all expected messages, then continues once the set is complete or a timeout threshold is reached.

### Diagram
```text
[msg A] --\
[msg B] ----> [Aggregator State] ---> [Combined Result]
[msg C] --/
              \--> [Timeout handling if set incomplete]
```

### Trade-offs
**Benefits**
- Centralizes coordination logic.
- Easy to combine state persistence and timeout handling.
- Clear representation in executable process models.

**Costs / risks**
- Requires careful correlation and completeness criteria.
- Can be fragile if message buffering is absent.
- Adds orchestration state and complexity.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Fit for multi-message coordination | 5/5 | Core purpose of the pattern. |
| Need for persistent state | 5/5 | Essential rather than optional. |
| Modeling clarity with BPMN | 4/5 | Clear once message flow is understood. |
| Implementation complexity | 3/5 | Moderate due to correlation and timeouts. |

---

## 6. Synchronous Facade over Asynchronous Communication

### Description
A facade exposes a synchronous API, usually for clients such as frontends, while internally using asynchronous communication or long-running workflows. The facade blocks only at the boundary and translates timeout behavior into a client-facing response strategy.

### Key properties
- External interface is synchronous.
- Internal architecture remains asynchronous.
- The facade must wait using one of three mechanisms mentioned in the chapter: subscription, callback API, or polling.
- Timeout behavior is mandatory.
- Can fall back from HTTP 200 success to HTTP 202 accepted for later completion.

### When to use
- Clients require a synchronous contract.
- Internal services are asynchronous or long-running.
- You need backward compatibility or frontend simplicity.
- You want to shield clients from integration complexity.

### Example
A check-in API returns the boarding pass immediately when everything succeeds, but if downstream generation is delayed it returns “accepted” and later delivers the result asynchronously.

### Diagram
```text
[Client]
   |
   v
[Synchronous Facade]
   |
   +--> [Send Async Request]
   |
   +--> [Wait for reply / timeout]
   |
   +--> [Return 200 with result]
   |
   +--> [or Return 202 and continue asynchronously]
```

### Trade-offs
**Benefits**
- Preserves simple client interaction.
- Allows gradual adoption of asynchronous internals.
- Supports graceful degradation when timing is uncertain.

**Costs / risks**
- The facade may still block and consume resources.
- Timeout handling can become tricky.
- Risk of hiding distributed-system complexity from clients without truly removing it.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Client compatibility | 5/5 | Strong bridge for sync clients. |
| Internal architectural flexibility | 4/5 | Allows async internals behind a sync edge. |
| Runtime efficiency | 3/5 | Boundary blocking still exists. |
| Design subtlety | 4/5 | Timeout and fallback behavior are crucial. |

---

## 7. Business Strategy Pattern for Inconsistency: Ignore

### Description
The business consciously accepts an inconsistent state and does not actively correct it immediately. The chapter treats this as a legitimate business strategy in some contexts, not as an automatic technical mistake.

### Key properties
- Lowest implementation effort.
- Accepts temporary or even persistent inconsistency.
- May require later reconciliation jobs.
- Must be justified by cost/value trade-offs.

### When to use
- The inconsistency has low business impact.
- The problem occurs rarely.
- Corrective automation would cost more than the damage caused.

### Example
A failed customer onboarding leaves an orphan CRM record that the business decides to tolerate because the side effects are minor and infrequent.

### Diagram
```text
[Inconsistency Detected]
        |
        v
 [Accept / Do Nothing Now]
        |
        v
[Optional later reconciliation]
```

### Trade-offs
**Benefits**
- Cheapest strategy to implement.
- May be perfectly rational for low-value scenarios.

**Costs / risks**
- Reports and campaigns may use incorrect data.
- Inconsistencies can accumulate over time.
- Easy to abuse if not explicitly decided with stakeholders.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Implementation effort | 5/5 | Minimal technical work. |
| Data quality | 1/5 | Consistency is intentionally weak. |
| Business suitability | 2/5 | Only valid in narrow scenarios. |
| Governance requirement | 5/5 | Needs explicit stakeholder approval. |

---

## 8. Business Strategy Pattern for Inconsistency: Apologize

### Description
The system does not fully prevent inconsistency, but the organization compensates when the issue becomes visible to the customer or business. This extends the “ignore” strategy with a business recovery step.

### Key properties
- Reactive rather than preventive.
- Often includes manual remediation.
- Adds customer-care cost instead of engineering cost.
- Suitable only when affected cases are rare.

### When to use
- Failures are infrequent but expensive to automate away.
- Manual intervention is acceptable.
- The business prefers cheaper steady-state operations with occasional remediation.

### Example
If a registration fails in a small number of cases, customer support apologizes, provides a voucher, and completes the missing action manually.

### Diagram
```text
[Inconsistency surfaces]
        |
        v
 [Apologize / Compensate Customer]
        |
        v
 [Manual or delayed correction]
```

### Trade-offs
**Benefits**
- Can be economically rational.
- Avoids heavy consistency machinery for edge cases.

**Costs / risks**
- Customers experience the failure.
- Requires operational/manual recovery paths.
- Weakens automation quality and perceived reliability.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Engineering effort | 4/5 | Lower than full technical compensation. |
| Customer experience quality | 2/5 | Failure is visible to the customer. |
| Economic fit for rare incidents | 4/5 | Good when issues are uncommon. |
| Suitability for high-volume critical flows | 1/5 | Poor fit where consistency matters strongly. |

---

## 9. Business Strategy Pattern for Inconsistency: Resolve

### Description
The system actively restores consistency after a failure, either through instance-level logic or through later reconciliation. In the chapter, Saga and outbox are the main concrete resolution patterns discussed.

### Key properties
- Explicitly targets eventual return to a consistent state.
- Can operate immediately per instance or later in batch.
- Requires understanding of failure scenarios and acceptable end states.
- Typically more complex than ignore/apologize.

### When to use
- Inconsistencies create meaningful business harm.
- Data integrity or downstream effects matter.
- The business is willing to invest in corrective automation.

### Example
If billing creation fails after CRM creation, the system deactivates or undoes the CRM-side effect so the customer no longer appears partially onboarded.

### Diagram
```text
[Failure after partial progress]
          |
          v
 [Resolution Logic Triggered]
          |
          v
 [Compensate / Reconcile / Complete Missing Work]
          |
          v
 [Consistent End State]
```

### Trade-offs
**Benefits**
- Best path to restoring trustworthy system state.
- Reduces harmful downstream effects.

**Costs / risks**
- Highest implementation and modeling effort.
- Requires explicit business semantics for “resolved.”
- Often needs workflow support and operational visibility.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Consistency restoration strength | 5/5 | Main purpose of the strategy. |
| Engineering effort | 2/5 | Usually significant. |
| Suitability for critical flows | 5/5 | Strong fit where errors are costly. |
| Need for business involvement | 5/5 | Resolution semantics are business-driven. |

---

## 10. Saga Pattern (Compensation-Based Long-Running Transaction)

### Description
A saga models a distributed, long-running business transaction as a sequence of tasks with corresponding compensating actions. When a later step fails, already completed earlier steps are undone through compensation rather than database rollback.

### Key properties
- Designed for **distributed systems** where ACID transactions cannot span service boundaries.
- Compensation replaces rollback.
- Undo does not necessarily mean restoration to the exact prior technical state; it means business-level cleanup.
- Works well with workflow engines because they persist progress and coordinate compensations.
- Makes business transaction logic explicit and visible.

### When to use
- A business transaction spans multiple services or resources.
- Technical rollback is impossible or impractical.
- The flow is long-running, asynchronous, or involves humans.
- You need explicit cleanup behavior after partial completion.

### Example
Customer onboarding inserts a customer into CRM, billing, and related systems. If a later step fails, compensating tasks remove or deactivate earlier side effects, such as deactivating a SIM card or notifying the customer.

### Diagram
```text
[Task A] ---> [Task B] ---> [Task C]
   |             |             |
[Comp A]      [Comp B]      [Comp C]

On failure after Task C starts or after Task B succeeds:
execute needed compensations in reverse logical order.
```

### Trade-offs
**Benefits**
- Practical way to manage business consistency across boundaries.
- Makes compensation logic explicit.
- Strong fit for long-running workflows.

**Costs / risks**
- Process models become more complicated.
- Compensation logic can be business-specific and nontrivial.
- Requires careful thinking about what “undo” really means.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Fit for distributed business transactions | 5/5 | Central pattern for this problem. |
| Modeling complexity | 2/5 | Compensation adds substantial detail. |
| Business transparency | 5/5 | Explicitly exposes rollback semantics. |
| Dependence on clear domain semantics | 5/5 | Compensations must reflect business reality. |

---

## 11. Outbox Pattern

### Description
The outbox pattern ensures atomicity between updating domain state in a database and later publishing an event to another resource such as an event bus. The service writes the outbound event into an outbox table within the same database transaction as the domain update, and a scheduler later publishes the event and removes it from the outbox.

### Key properties
- Bridges two resources that cannot share one ACID transaction.
- Elevates consistency to **at-least-once delivery**.
- Event publication is delayed but guaranteed eventually.
- Requires an outbox table, scheduler, and usually monitoring.
- Duplicate event publication is possible in certain failure scenarios.

### When to use
- A service must both change local state and publish an event.
- Those two actions must behave atomically from a business perspective.
- Database transaction guarantees are available locally.
- Consumers can handle duplicate events.

### Example
A service commits business data plus an event record in the same relational database transaction. A background mechanism later publishes the event to the bus and deletes the outbox entry.

### Diagram
```text
[Business Logic]
      |
      v
[DB Transaction]
   |         |
   |         +--> [Write Domain Data]
   |
   +--> [Write Outbox Entry]

Later:
[Scheduler] --> [Publish Event] --> [Delete Outbox Entry]
```

### Trade-offs
**Benefits**
- Strong practical solution for atomic state-change + event publication.
- Avoids distributed ACID transactions.
- Widely applicable in event-driven architectures.

**Costs / risks**
- Requires extra infrastructure and monitoring.
- Produces at-least-once rather than exactly-once behavior.
- Event publication can lag behind state changes.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Practicality in distributed systems | 5/5 | Very applicable and realistic. |
| Infrastructure overhead | 3/5 | Needs table, scheduler, and ops support. |
| Delivery guarantee strength | 4/5 | Strong eventual send guarantee, but duplicates possible. |
| Need for idempotent consumers | 5/5 | Essential because duplicates can occur. |

---

## 12. Workflow-Engine-Based Outbox Elimination

### Description
Instead of implementing a dedicated outbox table and scheduler, a workflow engine can orchestrate the sequence of atomic business tasks. It persists state between tasks and resumes from the correct point after a crash, giving equivalent at-least-once semantics without bespoke outbox infrastructure.

### Key properties
- Replaces custom outbox plumbing with process tasks.
- Workflow state acts as the durable coordination mechanism.
- The engine resumes at the correct step after failure.
- Still yields at-least-once semantics.
- Adds monitoring and operational visibility through workflow tooling.

### When to use
- A workflow engine is already part of the architecture.
- You want to avoid custom outbox infrastructure.
- Several tasks must eventually all be completed in sequence.
- Operational observability is important.

### Example
A process first executes business logic and commits it. The next process step publishes the event. If a crash occurs after the business logic but before successful event publication, the engine restarts at the publish step.

### Diagram
```text
[Process Task 1: Persist Business Result]
                 |
                 v
[Workflow State Persisted]
                 |
                 v
[Process Task 2: Publish Event]
                 |
                 v
[Done]

If crash occurs after Task 1:
engine resumes at Task 2.
```

### Trade-offs
**Benefits**
- Removes dedicated outbox table/scheduler implementation.
- Reuses workflow monitoring and recovery features.
- Generalizes beyond only two chained tasks.

**Costs / risks**
- Requires adoption of workflow technology.
- Still does not create exactly-once semantics.
- Best fit when workflow engines are already accepted architecturally.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Reduction of custom plumbing | 5/5 | Main advantage over classic outbox. |
| Operational visibility | 5/5 | Workflow tools help significantly. |
| Architectural dependency on workflow engine | 2/5 | Requires engine adoption. |
| Semantics strength | 4/5 | Same practical at-least-once guarantee. |

---

## 13. Idempotent Remote Operation Pattern

### Description
Because distributed systems inevitably retry calls and redeliver messages, remote operations should be designed to be idempotent: repeated execution must not create unintended additional business effects.

### Key properties
- Essential for retries and at-least-once delivery.
- Some operations are naturally idempotent, such as reads and many deletes.
- Non-idempotent commands require dedicated duplicate-detection strategy.
- Duplicate detection should use explicit identifiers rather than guessing from business payload.
- A service API must support idempotency; clients cannot reliably fix missing support afterward.

### When to use
- Always, for remotely exposed operations.
- Especially when using messaging, retries, recovery, or workflow restarts.
- Whenever at-least-once semantics are present.

### Example
A credit-card charge request includes a client-generated unique ID so the charging service can detect duplicates if the same request is retried.

### Diagram
```text
[Client creates unique operation ID]
              |
              v
 [Send Command with ID]
              |
              v
 [Service checks prior ID]
      |                     |
      | duplicate           | new
      v                     v
[Return prior effect]   [Execute once and store ID]
```

### Trade-offs
**Benefits**
- Makes retries safe.
- Fundamental enabler for robust distributed communication.
- Reduces ambiguity after network failures and crashes.

**Costs / risks**
- Can require additional service-side state.
- Harder for commands with irreversible side effects.
- Poor API design here causes systemic downstream problems.

### Ratings
| Dimension | Rating | Rationale |
|---|---:|---|
| Importance in distributed systems | 5/5 | Foundational requirement. |
| Difficulty for naturally non-idempotent actions | 3/5 | Often manageable with IDs and state. |
| Impact on reliability | 5/5 | Critical for safe retries and recovery. |
| API design priority | 5/5 | Must be designed in from the start. |

---

# Cross-Pattern Comparison

| Pattern | Primary problem addressed | Typical consistency level | Main enabling capability |
|---|---|---|---|
| Synchronous Request/Response | Immediate remote invocation | Immediate but fragile | Blocking call |
| Stateful Retry in Responsible Service | Localizing transient failure handling | Eventually successful or explicitly failed | Persisted state + retry scheduling |
| Asynchronous Request/Response | Long-running or delayed replies | Eventual progression | Messaging + correlation + timeout |
| Message Buffering / Ready-to-Receive Protection | Correlation race conditions | Eventual correlation | Buffered message delivery |
| Aggregator | Collecting multiple related messages | Eventual combined result | Stateful waiting + timeout |
| Synchronous Facade | Sync client over async internals | Immediate or deferred via fallback | Blocking edge + async core |
| Ignore | Low-value inconsistency | Inconsistency accepted | Business decision |
| Apologize | Customer-visible inconsistency with manual remediation | Inconsistency tolerated until surfaced | Business compensation process |
| Resolve | Active restoration of consistency | Eventual consistency restored | Compensation or reconciliation logic |
| Saga | Rollback across service boundaries | Eventual consistency via compensation | Long-running orchestration |
| Outbox | Atomic local state change + event publication | At-least-once eventual publication | Shared DB transaction + scheduler |
| Workflow-Engine-Based Outbox Elimination | Same as outbox with less custom plumbing | At-least-once eventual completion | Durable process state |
| Idempotent Remote Operation | Safe retries and duplicate deliveries | Stable business effect under retries | Duplicate detection / idempotent API |

# Architect’s Recall Notes

- The chapter’s central architectural message is that **the first remote call already introduces distributed-systems failure semantics**.
- Once work crosses boundaries, **ACID guarantees stop at the boundary**, while business transactions continue across it.
- Therefore, the architect must decide **how inconsistencies are tolerated, repaired, or compensated**.
- Workflow engines are presented not only as BPM tools, but as practical infrastructure for **durable waiting, retries, compensation, aggregation, observability, and at-least-once orchestration**.
- **Idempotency is not optional** in the presence of retries, redelivery, or recovery.
