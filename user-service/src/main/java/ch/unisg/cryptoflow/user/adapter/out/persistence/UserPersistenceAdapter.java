package ch.unisg.cryptoflow.user.adapter.out.persistence;

import ch.unisg.cryptoflow.user.application.port.out.DeleteUserPort;
import ch.unisg.cryptoflow.user.application.port.out.LoadUserPort;
import ch.unisg.cryptoflow.user.application.port.out.SaveUserPort;
import ch.unisg.cryptoflow.user.domain.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Optional;

@Component
@RequiredArgsConstructor
public class UserPersistenceAdapter implements SaveUserPort, LoadUserPort, DeleteUserPort {

    private final SpringDataUserRepository userRepository;

    @Override
    public User save(User user) {
        UserEntity entity = UserEntity.fromDomain(user);
        UserEntity persisted = userRepository.save(entity);
        return persisted.toDomain();
    }

    @Override
    public Optional<User> loadUser(String userId) {
        return userRepository.findById(userId)
            .map(UserEntity::toDomain);
    }

    @Override
    public boolean deleteUser(String userId) {
        if (!userRepository.existsById(userId)) {
            return false;
        }
        userRepository.deleteById(userId);
        return true;
    }
}
