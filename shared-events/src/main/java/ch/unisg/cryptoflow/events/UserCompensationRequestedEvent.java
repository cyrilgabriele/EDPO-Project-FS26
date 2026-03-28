package ch.unisg.cryptoflow.events;

public record UserCompensationRequestedEvent(String userId, String userName, String email, String reason) { }
