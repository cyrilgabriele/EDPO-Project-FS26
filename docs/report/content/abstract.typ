#import "@preview/gallus-hsg:1.0.1": *

CryptoFlow is an event-driven crypto portfolio simulation platform built with Apache Kafka, Camunda 8, and Spring Boot. Developed for the Event-Driven and Process-Oriented Architectures (EDPO) course at the University of St.~Gallen, the system demonstrates how five loosely coupled microservices can collaborate through asynchronous event streams and orchestrated business processes. The platform ingests real-time cryptocurrency prices from Binance WebSocket feeds, maintains portfolio valuations via Event-Carried State Transfer, processes simulated trading orders through a BPMN-orchestrated workflow, and handles user onboarding as a parallel saga with full compensation logic. This report documents the system architecture, 20 architectural decision records, Kafka reliability experiments, and lessons learned throughout the project.

The Project release for this version of the report can be found on GitHub:

https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.0.0