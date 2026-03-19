package ch.unisg.cryptoflow.user.application.port.out;

import ch.unisg.cryptoflow.user.domain.User;

public interface SaveUserPort {
    User save(User user);
}
