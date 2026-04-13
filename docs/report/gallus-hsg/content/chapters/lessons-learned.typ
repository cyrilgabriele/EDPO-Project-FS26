= Reflections & Lessons Learned <lessons-learned>

== Technical Lessons

*Camunda BPMN has a steep learning curve, but the payoff is real.* Learning how to model gateways, timers, compensation, and message correlations in Camunda was initially demanding. Once this hurdle was overcome, however, the modeler supported development very well because it made the flow explicit and reduced the implementation effort for individual tasks. A good example was the confirmation email, where Camunda's mail connector replaced what would otherwise have required a custom SMTP client in application code.

*The concepts are intuitive in theory, but implementation multiplies the decisions.* Patterns such as orchestration, compensation, and event-driven communication feel straightforward when discussed in lectures or on paper. The complexity appeared during implementation, where many additional degrees of freedom had to be resolved: event structure, correlation keys, error handling, retries, and service boundaries all influenced each other. Precise decision-making turned out to be essential, because without it, it is easy to get lost in technically plausible but incompatible alternatives.

*Dual-write problems are easy to overlook.* The need for the transactional outbox (ADR-0014) only became obvious once we considered what happens when the application crashes between a database commit and a Kafka publish. Before that, the inline publish felt natural and correct. The lesson is that dual-write hazards hide behind code that looks straightforward — they only surface under failure conditions that are rare but not impossible.

*Idempotency must be designed in, not patched on.* The duplicate portfolio update we observed during integration (documented in @results) confirmed that at-least-once delivery is not a theoretical edge case. It happens during normal restarts and rebalancing. Retrofitting idempotency after the fact required rethinking the transaction boundary around `upsertHolding()`. Designing consumers as idempotent from the start would have been simpler than fixing the bug after discovery.

*Single-broker Kafka obscures real durability semantics.* Running the experiments on multi-broker clusters and then developing against a single-broker Docker Compose stack created a subtle gap: `acks=all` behaved identically to `acks=1` in development, so producer reliability issues were invisible locally. We only recognized this fully when documenting the configuration for the report. For future projects, even a two-broker local cluster would surface replication behavior earlier.

== Process Lessons

*ADRs were even more important here than in ASSE.* Because implementation decisions were tightly coupled across services, documenting them close to the point of decision was essential. A choice made in one service often constrained or informed the design of another, so the rationale had to stay visible and reusable. Kafka event contracts are the simplest example: once we settled on how events should be structured and exchanged, that decision had to be applied consistently across multiple services.

*The lecture concepts transferred well to a self-chosen project.* One of the most valuable aspects of this project was applying the lecture concepts to a topic we chose ourselves. This freedom made the work more engaging, while also forcing us to implement the patterns under realistic constraints instead of only discussing them abstractly.

*Choosing the right saga pattern requires understanding the wait semantics.* The distinction between the Parallel Saga for onboarding and the Fairy Tale Saga for order placement was not immediately obvious. It only became clear once we analyzed the nature of the wait: onboarding waits for a deterministic human action (clicking a link), while order placement waits for a non-deterministic market event (a price match). The wait semantics dictated the coupling model, which in turn dictated the saga style. This selection process was one of the most instructive parts of the project.

== Teamwork Lessons

*Clear service ownership reduces coordination overhead.* Assigning each bounded context to a single team member, with shared responsibility for architecture and integration, worked well for a two-person team. Each person could develop their services independently, meeting only to align on event schemas and BPMN process contracts. The `shared-events` module served as the explicit interface between areas of ownership.

*Integration issues surface late.* Despite clear contracts, the majority of bugs appeared during integration: message deserialization mismatches, incorrect Zeebe correlation keys, and compensation events missing required fields. Running the full Docker Compose stack earlier and more frequently, rather than testing services in isolation, would have caught these issues sooner.

*Two people, five services.* The scope was ambitious for a two-person team within one semester. The decision to add a dedicated onboarding service (ADR-0010), while architecturally sound, added deployment and monitoring overhead. In retrospect, the trade-off was worthwhile for demonstrating the saga pattern cleanly, but we underestimated the time required for BPMN process debugging and compensation testing.
