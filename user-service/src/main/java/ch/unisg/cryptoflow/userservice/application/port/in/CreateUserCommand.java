package ch.unisg.cryptoflow.userservice.application.port.in;

import java.util.Objects;

public record CreateUserCommand(String userId, String userName, String password, String email) {

    public CreateUserCommand {
        Objects.requireNonNull(userId, "userId must not be null");
        Objects.requireNonNull(userName, "userName must not be null");
        Objects.requireNonNull(password, "password must not be null");
        Objects.requireNonNull(email, "email must not be null");
    }
}
