= Reflections & Lessons Learned <lessons-learned>

== Technical Lessons

*Camunda BPMN has a steep learning curve, but the payoff is real.* In our experience, learning how to model gateways, timers, compensation, and message correlations in Camunda was initially demanding. Once this hurdle was overcome, however, the modeler supported development very well because it made the flow explicit and reduced implementation effort for concrete tasks. A good example was the confirmation email, where Camunda's mail connector simplified a feature that would otherwise have required additional custom code.

*The concepts are often intuitive in theory, but implementation multiplies the decisions.* Patterns such as orchestration, compensation, and event-driven communication are not extremely complicated conceptually and often feel quite intuitive when discussed in lectures or on paper. The complexity appeared during implementation, where many additional degrees of freedom had to be resolved: event structure, correlation keys, error handling, retries, and service boundaries all influenced each other. We therefore learned that precise decision-making is essential, because otherwise it is easy to get lost in technically plausible but incompatible alternatives.

== Process Lessons

*ADRs were even more important here than in ASSE.* Because implementation decisions were tightly coupled across services, documenting them close to the decision was essential. A choice made in one service often constrained or informed the design of another service, so the rationale had to stay visible and reusable. Kafka communication between services is the simplest example: once we settled on how events should be structured and exchanged, that decision had to be applied consistently across multiple services.

*The lecture concepts transferred well to a self-chosen project.* One of the most valuable aspects of this project was that we could apply the concepts from the lectures to a topic we chose ourselves. We liked this freedom because it made the work more engaging, while also forcing us to implement the patterns under realistic constraints instead of only discussing them abstractly.

== Teamwork Lessons

*Clear service ownership reduces coordination overhead.* Assigning each bounded context to a single team member, with shared responsibility for architecture and integration, worked well for a two-person team. Each person could develop their services independently, meeting only to align on event schemas and BPMN process contracts. The `shared-events` module served as the explicit interface between areas of ownership.

*Integration issues surface late.* Despite clear contracts, the majority of bugs appeared during integration: message deserialization mismatches, incorrect Zeebe correlation keys, compensation events missing required fields. Investing in early integration testing and running the full Docker Compose stack rather than testing services in isolation would have caught these issues sooner.

*Two people, five services.* The scope was ambitious for a two-person team within one semester. The decision to add a dedicated onboarding service (ADR-0010), while architecturally sound, added deployment and monitoring overhead. In retrospect, the trade-off was worthwhile for demonstrating the saga pattern, but we underestimated the time required for BPMN process debugging and compensation testing.
