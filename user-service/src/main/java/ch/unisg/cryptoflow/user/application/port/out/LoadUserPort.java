package ch.unisg.cryptoflow.user.application.port.out;

import ch.unisg.cryptoflow.user.domain.User;

import java.util.Optional;

public interface LoadUserPort {
    Optional<User> loadUser(String userId);
}
