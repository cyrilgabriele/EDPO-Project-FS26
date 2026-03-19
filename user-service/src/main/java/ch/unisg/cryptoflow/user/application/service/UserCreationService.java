package ch.unisg.cryptoflow.user.application.service;

import ch.unisg.cryptoflow.user.application.port.in.CreateUserCommand;
import ch.unisg.cryptoflow.user.application.port.in.CreateUserUseCase;
import ch.unisg.cryptoflow.user.application.port.out.SaveUserPort;
import ch.unisg.cryptoflow.user.domain.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional
public class UserCreationService implements CreateUserUseCase {

    private final SaveUserPort saveUserPort;

    @Override
    public User createUser(CreateUserCommand command) {
        User user = new User(command.userName(), command.password(), command.userId(), command.email());
        return saveUserPort.save(user);
    }
}
