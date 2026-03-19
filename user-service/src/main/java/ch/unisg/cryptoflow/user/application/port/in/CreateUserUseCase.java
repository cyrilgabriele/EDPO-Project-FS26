package ch.unisg.cryptoflow.user.application.port.in;

import ch.unisg.cryptoflow.user.domain.User;

public interface CreateUserUseCase {
    User createUser(CreateUserCommand command);
}
