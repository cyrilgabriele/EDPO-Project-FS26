package ch.unisg.cryptoflow.user.application.port.in;

import ch.unisg.cryptoflow.user.application.UserCreationResult;

public interface CreateUserUseCase {
    UserCreationResult createUser(CreateUserCommand command);
}
