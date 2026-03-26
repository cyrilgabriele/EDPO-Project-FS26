# Transactional Saga Patterns — Architectural Cheat Sheet

**Source scope:** This report is based **only** on *Chapter 12: “Transactional Sagas”* from *Software Architecture: The Hard Parts* (2021). It summarizes the saga patterns, figures, and ratings presented in that chapter.

## Executive summary

The chapter organizes transactional sagas along three design dimensions:

- **Communication:** synchronous vs. asynchronous
- **Consistency:** atomic vs. eventual
- **Coordination:** orchestrated vs. choreographed

Those three dimensions yield eight generic saga patterns:

| Pattern | Communication | Consistency | Coordination |
|---|---|---|---|
| **Epic Saga (sao)** | Synchronous | Atomic | Orchestrated |
| **Phone Tag Saga (sac)** | Synchronous | Atomic | Choreographed |
| **Fairy Tale Saga (seo)** | Synchronous | Eventual | Orchestrated |
| **Time Travel Saga (sec)** | Synchronous | Eventual | Choreographed |
| **Fantasy Fiction Saga (aao)** | Asynchronous | Atomic | Orchestrated |
| **Horror Story (aac)** | Asynchronous | Atomic | Choreographed |
| **Parallel Saga (aeo)** | Asynchronous | Eventual | Orchestrated |
| **Anthology Saga (aec)** | Asynchronous | Eventual | Choreographed |

## Quick selection guidance

- If stakeholders demand **monolith-like all-or-nothing behavior**, they tend to gravitate toward **Epic Saga**, but the chapter treats that familiarity as dangerous because distributed transactionality introduces major failure modes.
- If the workflow can tolerate **eventual consistency**, the chapter presents **Fairy Tale** and **Parallel Saga** as especially attractive patterns.
- If the workflow is **simple, linear, and throughput-oriented**, the choreographed eventual-consistency styles (**Time Travel** and especially **Anthology**) become compelling.
- The chapter treats **Fantasy Fiction** as an often-misguided attempt to make Epic faster, and **Horror Story** as the worst combination overall.

---

## Epic Saga (sao)

### Description

The Epic Saga is the chapter’s “traditional” saga pattern: **synchronous communication**, **atomic consistency**, and **orchestrated coordination**. It most closely mimics the behavior of monolithic transactional systems and is therefore often the default choice for architects who want distributed systems to behave like a single transactional unit.

### Properties

- **Communication:** Synchronous
- **Consistency:** Atomic
- **Coordination:** Orchestrated
- **Structural intent:** A mediator/orchestrator coordinates the full workflow and ensures that either all participating operations succeed or all are undone.
- **Coupling profile:** The chapter presents this as the **most highly coupled** pattern of the set.

### When to use it

Use Epic Saga only when the business truly requires **holistic atomic behavior across services** and the team is willing to absorb the operational and design cost of distributed transaction management. The chapter warns that architects often choose it because it feels familiar, not because it is a good distributed default.

### Example

A mediator coordinates updates across three services as one transactional unit. If one downstream call fails, the mediator issues **compensating updates** to restore the earlier services to their prior state. The Sysops Squad example later in the chapter uses this logic for updating ticket status and sending a survey in one atomic workflow.

### Diagram

**Book figures:** Figure 12-2, Figure 12-3, Figure 12-4, Figure 12-5

```text
Client -> Orchestrator -> Service A
                      -> Service B
                      -> Service C

If one call fails:
Orchestrator -> compensate Service A / Service B / prior participants
```

The figures show a **single workflow owner** inside a transaction boundary. The orchestrator tracks success/failure and initiates rollback behavior through compensating requests.

### Tradeoffs

**Advantages**
- Familiar transactional model for teams coming from monoliths
- Clear workflow ownership through an orchestrator
- Easy to reason about on the happy path because communication is synchronous

**Disadvantages**
- Significant bottlenecks around the orchestrator
- Poor scale and elasticity because the orchestrator must coordinate success/failure across all participants
- Distributed transaction implementations create complex failure modes
- Compensating updates add complexity and can themselves fail
- Database and implementation choices become constrained
- The chapter explicitly warns that distributed transactions are best avoided when possible

### Ratings

**Book source:** Table 12-2

| Rating dimension | Score |
|---|---|
| Coupling | Very high |
| Complexity | Low |
| Responsiveness / Availability | Low |
| Scale / Elasticity | Very low |

---

## Phone Tag Saga (sac)

### Description

Phone Tag Saga changes only one dimension from Epic Saga: coordination becomes **choreographed** instead of orchestrated. It still uses **synchronous communication** and **atomic consistency**, but there is no formal orchestrator. Instead, the initially called service becomes the coordination point and the workflow is forwarded step by step.

### Properties

- **Communication:** Synchronous
- **Consistency:** Atomic
- **Coordination:** Choreographed
- **Structural intent:** Each participant forwards work to the next service, and each service must understand enough of the workflow to participate in success and rollback behavior.
- **Coupling profile:** Slightly less coupled than Epic Saga, but still tightly coupled because atomicity remains.

### When to use it

Use it for **simple workflows** that still need transactional atomicity but can benefit from removing the orchestrator bottleneck. The chapter stresses that this pattern is best when error handling is straightforward and when services can lean on idempotence and retries.

### Example

The first service in the chain acts like a front controller. It performs its work and then invokes the next service, and so on. If a failure occurs, services must send compensating requests **back along the chain** because there is no mediator to centrally coordinate rollback.

### Diagram

**Book figures:** Figure 12-6, Figure 12-7

```text
Client -> Service A -> Service B -> Service C

If an error occurs:
Service C / B / A coordinate compensating steps backward through the chain
```

The figures emphasize that the lack of orchestration distributes workflow logic into the participating services.

### Tradeoffs

**Advantages**
- Fewer central bottlenecks than Epic Saga
- Better happy-path throughput because the last service can return the result
- Maintains synchronous ordering, which avoids race conditions during the forward flow

**Disadvantages**
- Error handling becomes much slower and more complex without a mediator
- Each service must carry more workflow context, routing logic, and compensation knowledge
- Complexity grows with workflow complexity
- For rich workflows, the front controller can become nearly as complex as a mediator anyway

### Ratings

**Book source:** Table 12-3

| Rating dimension | Score |
|---|---|
| Coupling | High |
| Complexity | High |
| Responsiveness / Availability | Low |
| Scale / Elasticity | Low |

---

## Fairy Tale Saga (seo)

### Description

Fairy Tale Saga combines **synchronous communication**, **eventual consistency**, and **orchestrated coordination**. This pattern removes the hardest part of Epic Saga—the requirement for atomic distributed consistency—while keeping the parts many teams find easiest to manage: a mediator and synchronous calls.

### Properties

- **Communication:** Synchronous
- **Consistency:** Eventual
- **Coordination:** Orchestrated
- **Structural intent:** The orchestrator coordinates requests, responses, and errors, but each domain service owns its own transactionality.
- **Coupling profile:** Still highly coupled because communication is synchronous and coordination is orchestrated, but it removes the worst coupling driver: holistic transactionality.

### When to use it

Use Fairy Tale Saga when the workflow benefits from a **central coordinator** and simpler developer reasoning, but the business can tolerate **temporary inconsistency** between services. The chapter presents it as one of the most attractive and common options in microservices environments.

### Example

The ticketing example later in the chapter illustrates this pattern: if the Survey Service is unavailable, the orchestrator changes saga state to `NO_SURVEY`, returns success to the user, and then retries or escalates the failed survey step asynchronously behind the scenes.

### Diagram

**Book figures:** Figure 12-8, Figure 12-9, Figure 12-20

```text
Client -> Orchestrator -> Service A
                      -> Service B
                      -> Service C

If one step fails:
Orchestrator records saga state (for example, NO_SURVEY),
returns success or partial progress,
then resolves the problem asynchronously later
```

The figures show that the orchestrator still owns workflow control, but not a single atomic transaction spanning all services.

### Tradeoffs

**Advantages**
- Much easier error handling than atomic patterns
- Central mediator simplifies workflow management
- Better responsiveness than atomic orchestrated patterns
- Each service can own local transactions while the overall process converges over time
- High scale relative to synchronous patterns because transactional coupling is removed

**Disadvantages**
- Data can temporarily be out of sync
- The system must manage saga state, retries, and correction logic
- Consistency is delayed rather than immediate

### Ratings

**Book source:** Table 12-4

| Rating dimension | Score |
|---|---|
| Coupling | High |
| Complexity | Very low |
| Responsiveness / Availability | Medium |
| Scale / Elasticity | High |

---

## Time Travel Saga (sec)

### Description

Time Travel Saga uses **synchronous communication**, **eventual consistency**, and **choreographed coordination**. It removes both the orchestrator and holistic transactionality, leaving each service responsible for its own local transaction and its role in the larger workflow.

### Properties

- **Communication:** Synchronous
- **Consistency:** Eventual
- **Coordination:** Choreographed
- **Structural intent:** Each service accepts a request, performs its action, and forwards the workflow to another service.
- **Coupling profile:** Medium coupling; synchronous communication still couples timing, but the lack of an orchestrator and holistic transactions reduces structural coupling.

### When to use it

Use this pattern for **simple, one-way workflows** where throughput matters and the process can tolerate eventual consistency. The chapter explicitly points to use cases such as **electronic data ingestion** and **bulk transactions**, and notes that it works well as an on-ramp to more scalable asynchronous patterns if teams are not yet ready to go fully async.

### Example

A service receives a request, performs work, and forwards it to the next participant in a chain. This aligns with **Chain of Responsibility** or **Pipes and Filters**-like flows. Error handling must be built into the services because there is no mediator.

### Diagram

**Book figures:** Figure 12-10, Figure 12-11

```text
Client -> Service A -> Service B -> Service C

Each service:
1. completes its local transaction
2. forwards the request
3. handles its own eventual-consistency recovery logic
```

The figures highlight simple one-way progression and the absence of orchestration.

### Tradeoffs

**Advantages**
- Easier than atomic choreographed patterns because no holistic transaction must be maintained
- Good fit for fire-and-forget and throughput-oriented workflows
- High scale and elasticity
- Easier for teams to reason about than fully asynchronous alternatives

**Disadvantages**
- Complex workflows become difficult to manage without an orchestrator
- Each service must carry workflow state and error-handling responsibility
- Responsiveness is mixed: good on purpose-built linear flows, weak when error-handling becomes complex

### Ratings

**Book source:** Table 12-5

| Rating dimension | Score |
|---|---|
| Coupling | Medium |
| Complexity | Low |
| Responsiveness / Availability | Medium |
| Scale / Elasticity | High |

---

## Fantasy Fiction Saga (aao)

### Description

Fantasy Fiction Saga combines **asynchronous communication**, **atomic consistency**, and **orchestrated coordination**. It resembles Epic Saga but replaces synchronous calls with asynchronous ones. The chapter treats this as an implausible and difficult combination because asynchronous communication makes transactional coordination dramatically harder.

### Properties

- **Communication:** Asynchronous
- **Consistency:** Atomic
- **Coordination:** Orchestrated
- **Structural intent:** A mediator still owns workflow control, but now it must track the state of multiple in-flight transactions that may overlap and complete out of order.
- **Coupling profile:** High coupling, with concurrency making orchestration harder rather than easier.

### When to use it

Use this pattern only rarely, and only when a workflow still insists on **atomic consistency with an orchestrator** but asynchronous execution cannot be avoided. The chapter strongly suggests that many teams reach for it as a misguided performance optimization over Epic Saga and would usually be better served by **Parallel Saga** instead.

### Example

The chapter uses overlapping workflows Alpha, Beta, and Gamma to show the problem. While Alpha is still pending, Beta begins; then Gamma starts with a dependency on Alpha’s unfinished result. The mediator must keep track of multiple pending transactional states and their dependencies.

### Diagram

**Book figures:** Figure 12-12, Figure 12-13

```text
Orchestrator => async request to Service A
Orchestrator => async request to Service B
Orchestrator => async request to Service C

Meanwhile:
Workflow Alpha pending
Workflow Beta starts
Workflow Gamma depends on Alpha

Mediator must track ordering, dependencies, and rollback across all of them
```

The figure set emphasizes that asynchronous communication injects deadlocks, race conditions, and out-of-order effects into an already difficult atomic workflow.

### Tradeoffs

**Advantages**
- Attempts to improve perceived performance over Epic Saga through parallelism

**Disadvantages**
- Atomic coordination across asynchronous calls is extremely difficult
- The mediator must maintain large amounts of concurrent transactional state
- Race conditions, deadlocks, and ordering problems become central design concerns
- Responsiveness and scale remain poor because transactionality is still the dominant constraint
- Debugging and operations become difficult at scale

### Ratings

**Book source:** Table 12-6

| Rating dimension | Score |
|---|---|
| Coupling | High |
| Complexity | High |
| Responsiveness / Availability | Low |
| Scale / Elasticity | Low |

---

## Horror Story (aac)

### Description

Horror Story uses **asynchronous communication**, **atomic consistency**, and **choreographed coordination**. The chapter labels it the worst overall combination because it combines the strictest requirement—atomicity—with the two loosest coordination styles—asynchronicity and choreography.

### Properties

- **Communication:** Asynchronous
- **Consistency:** Atomic
- **Coordination:** Choreographed
- **Structural intent:** There is no mediator, yet the participating services must somehow preserve all-or-nothing transactional behavior across asynchronous, potentially out-of-order interactions.
- **Coupling profile:** Medium by the chapter’s rating model, but with the **worst complexity profile**.

### When to use it

The chapter effectively treats this as a pattern to **avoid**. It can emerge when architects try to improve Epic Saga performance by adding asynchronicity and choreography without changing the atomic consistency requirement. If holistic transactionality can be relaxed, the chapter recommends moving toward **Anthology Saga** instead.

### Example

Transaction Alpha starts. Before it finishes, transaction Beta starts. One Alpha step fails. Now the choreographed services must reverse prior operations in the correct order, even though messages may have been processed asynchronously and out of order. Each service must retain undo information for multiple pending transactions.

### Diagram

**Book figures:** Figure 12-14, Figure 12-15

```text
Service A => async event => Service B => async event => Service C

No orchestrator exists.

If an error occurs:
Services must discover transaction context,
coordinate among themselves,
and undo steps for multiple overlapping workflows
```

The figures show extensive interservice chatter caused by the absence of a mediator combined with the need to preserve atomicity.

### Tradeoffs

**Advantages**
- Better scale than mediator-based atomic patterns
- Asynchronicity allows more work in parallel

**Disadvantages**
- The most difficult pattern to design, implement, debug, and recover
- Each service must track undo information for multiple concurrent transactions
- Out-of-order compensation becomes a major problem
- Responsiveness remains poor because of heavy coordination chatter
- The chapter explicitly frames this as the worst combination overall

### Ratings

**Book source:** Table 12-7

| Rating dimension | Score |
|---|---|
| Coupling | Medium |
| Complexity | Very high |
| Responsiveness / Availability | Low |
| Scale / Elasticity | Medium |

---

## Parallel Saga (aeo)

### Description

Parallel Saga combines **asynchronous communication**, **eventual consistency**, and **orchestrated coordination**. It relaxes the two hardest constraints of Epic Saga—synchronous communication and atomic consistency—while keeping a mediator, making it suitable for **complex workflows that still need coordination**.

### Properties

- **Communication:** Asynchronous
- **Consistency:** Eventual
- **Coordination:** Orchestrated
- **Structural intent:** A mediator coordinates the workflow, but each domain service owns its own transaction boundary.
- **Coupling profile:** Low coupling relative to the more restrictive patterns.

### When to use it

Use this pattern for **complex workflows that need high scale, good responsiveness, and centralized coordination**. The chapter presents it as one of the most attractive trade-off sets in the entire catalog.

### Example

A mediator issues asynchronous requests to participating services. If an error occurs, it can send asynchronous remediation messages to coordinate retries, compensation, or data synchronization. Local transactionality stays inside each service.

### Diagram

**Book figures:** Figure 12-16, Figure 12-17

```text
Client -> Mediator
Mediator => async request to Service A
Mediator => async request to Service B
Mediator => async request to Service C

If one step fails:
Mediator => async retries / compensation / synchronization messages
```

The figures highlight parallel execution with a mediator still present to manage workflow complexity.

### Tradeoffs

**Advantages**
- Strong responsiveness because communication is asynchronous
- High scale and elasticity due to smaller transaction boundaries
- Suitable for complex workflows because the mediator centralizes coordination
- Services can scale independently around domain needs

**Disadvantages**
- Eventual consistency shifts more burden to workflow recovery and synchronization
- Asynchronous communication introduces race conditions, deadlocks, and queue reliability concerns
- Mediator logic must still handle rich error and timing scenarios

### Ratings

**Book source:** Table 12-8

| Rating dimension | Score |
|---|---|
| Coupling | Low |
| Complexity | Low |
| Responsiveness / Availability | High |
| Scale / Elasticity | High |

---

## Anthology Saga (aec)

### Description

Anthology Saga is the **exact opposite** of Epic Saga: **asynchronous communication**, **eventual consistency**, and **choreographed coordination**. The chapter presents it as the **least coupled** pattern in the set and one of the strongest choices for very high throughput.

### Properties

- **Communication:** Asynchronous
- **Consistency:** Eventual
- **Coordination:** Choreographed
- **Structural intent:** Services communicate through asynchronous messaging without an orchestrator; each service maintains its own transactional integrity.
- **Coupling profile:** The chapter rates this as the **lowest-coupled** pattern.

### When to use it

Use Anthology Saga for **simple, mostly linear workflows** where the primary drivers are **throughput, responsiveness, scale, and elasticity**. The chapter specifically calls out **Pipes and Filters** as a strong fit. It is less suitable for complex or critical workflows where coordination and error recovery are intricate.

### Example

Services publish messages to queues and other services consume them asynchronously. No central mediator manages the workflow. Each service must carry enough context to know how to progress or recover its part of the process.

### Diagram

**Book figures:** Figure 12-18, Figure 12-19

```text
Service A => queue => Service B => queue => Service C

No orchestrator.
Each service owns:
- local transactionality
- workflow context
- error-handling strategy
```

The figures show a highly decoupled message-driven topology with no bottleneck or coupling singularity.

### Tradeoffs

**Advantages**
- Highest scale and elasticity of all patterns
- High responsiveness because there are no synchronous waits and no holistic transactions
- Excellent throughput
- Very low structural coupling

**Disadvantages**
- High complexity for coordination because no orchestrator exists
- Error handling and workflow context must be distributed across services
- Not a good fit for complex workflows with frequent or difficult consistency failures

### Ratings

**Book source:** Table 12-9

| Rating dimension | Score |
|---|---|
| Coupling | Very low |
| Complexity | High |
| Responsiveness / Availability | High |
| Scale / Elasticity | Very high |

---

## Cross-cutting architectural lessons from the chapter

1. **Atomic distributed transactions are expensive and fragile.**  
   The chapter repeatedly shows that compensating updates, side effects, and compensation failures make atomic distributed sagas hard to reason about and hard to recover.

2. **Eventual consistency is often the practical pivot point.**  
   Switching from atomic to eventual consistency removes the hardest coordination burden and generally improves responsiveness, scale, and architectural flexibility.

3. **Orchestration reduces workflow complexity; choreography reduces bottlenecks.**  
   Orchestrators simplify error handling and state management for complex workflows. Choreography improves scale and decoupling, but only works well when workflows stay relatively simple.

4. **Asynchronicity is not a free performance upgrade.**  
   It helps responsiveness and scale, but it also introduces ordering, race, deadlock, and reliability concerns. It becomes especially dangerous when combined with atomicity.

5. **State management is a key mechanism for eventual-consistency sagas.**  
   The chapter’s saga state machine material shows that good eventual-consistency designs still require explicit tracking of saga progress, retries, and terminal states.

## Final architect’s cheat-sheet takeaways

- **Best for monolith-like transactional behavior:** Epic Saga — but choose reluctantly.
- **Best atomic choreographed option:** Phone Tag — only for simple workflows.
- **Best “easy default” if eventual consistency is allowed:** Fairy Tale Saga.
- **Best synchronous throughput-oriented choreographed option:** Time Travel Saga.
- **Most tempting but often misguided optimization of Epic Saga:** Fantasy Fiction Saga.
- **Worst overall combination:** Horror Story.
- **Best choice for complex, scalable, coordinated workflows:** Parallel Saga.
- **Best choice for maximum throughput and scale on simple linear flows:** Anthology Saga.
