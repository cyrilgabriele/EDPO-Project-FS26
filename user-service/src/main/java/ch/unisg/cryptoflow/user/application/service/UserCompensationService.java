package ch.unisg.cryptoflow.user.application.service;

import ch.unisg.cryptoflow.user.application.port.in.CompensateUserUseCase;
import ch.unisg.cryptoflow.user.application.port.out.DeleteUserPort;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Objects;

@Service
@RequiredArgsConstructor
@Transactional
public class UserCompensationService implements CompensateUserUseCase {

    private final DeleteUserPort deleteUserPort;

    @Override
    public boolean compensateUser(String userId) {
        Objects.requireNonNull(userId, "userId must not be null");
        return deleteUserPort.deleteUser(userId);
    }
}
