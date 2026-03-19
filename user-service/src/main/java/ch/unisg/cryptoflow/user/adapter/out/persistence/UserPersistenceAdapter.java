package ch.unisg.cryptoflow.user.adapter.out.persistence;

import ch.unisg.cryptoflow.user.application.port.out.SaveUserPort;
import ch.unisg.cryptoflow.user.domain.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class UserPersistenceAdapter implements SaveUserPort {

    private final SpringDataUserRepository userRepository;

    @Override
    public User save(User user) {
        UserEntity entity = UserEntity.fromDomain(user);
        UserEntity persisted = userRepository.save(entity);
        return persisted.toDomain();
    }
}
