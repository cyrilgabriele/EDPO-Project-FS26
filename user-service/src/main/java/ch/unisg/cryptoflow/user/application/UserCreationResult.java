package ch.unisg.cryptoflow.user.application;

import ch.unisg.cryptoflow.user.domain.User;

public record UserCreationResult(User user, boolean created) { }
