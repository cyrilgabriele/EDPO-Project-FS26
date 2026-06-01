#import "@preview/gallus-hsg:1.0.1": *

CryptoFlow is an event-driven crypto portfolio simulation platform built with Apache Kafka, Camunda 8, Kafka Streams, and Spring Boot. Developed for the Event-Driven and Process-Oriented Architectures (EDPO) course at the University of St.~Gallen, the system demonstrates how loosely coupled microservices can collaborate through asynchronous event streams, continuously running stream-processing topologies, and orchestrated business processes. The platform ingests real-time cryptocurrency prices and order-book snapshots from Binance, maintains portfolio valuations through both Event-Carried State Transfer and Kafka Streams state stores, processes simulated trading orders through a BPMN-orchestrated workflow backed by bid/ask stream matching, and handles user onboarding as a parallel saga with compensation logic. This report documents the system architecture, the project's architectural decision records, Kafka reliability experiments, stream-processing extensions, and lessons learned throughout the project.

The Project release for this version of the report can be found on GitHub:

https://github.com/cyrilgabriele/EDPO-Project-FS26/releases/tag/v1.1.0
