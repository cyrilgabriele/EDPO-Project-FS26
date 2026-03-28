package ch.unisg.cryptoflow.events;

public record PortfolioCompensationRequestedEvent(String userId, String userName, Long portfolioId, String reason) { }
