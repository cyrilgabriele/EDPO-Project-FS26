package ch.unisg.cryptoflow.user.application.service;

import ch.unisg.cryptoflow.user.adapter.out.persistence.SpringDataUserConfirmationLinkRepository;
import ch.unisg.cryptoflow.user.adapter.out.persistence.UserConfirmationLinkEntity;
import ch.unisg.cryptoflow.user.domain.ConfirmationLinkStatus;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
@RequiredArgsConstructor
@Transactional
public class ConfirmationLinkService {

    private final SpringDataUserConfirmationLinkRepository confirmationLinkRepository;

    public void registerPendingLink(String userId) {
        confirmationLinkRepository.save(UserConfirmationLinkEntity.pending(userId));
    }

    public boolean invalidateLink(String userId) {
        return confirmationLinkRepository.findById(userId)
            .map(entity -> {
                if (!entity.isPending()) {
                    return false;
                }
                entity.markInvalidated();
                return true;
            })
            .orElse(false);
    }

    public boolean confirmLink(String userId) {
        return confirmationLinkRepository.findById(userId)
            .map(entity -> {
                if (!entity.isPending()) {
                    return false;
                }
                entity.markConfirmed();
                return true;
            })
            .orElse(false);
    }

    @Transactional(readOnly = true)
    public Optional<ConfirmationLinkStatus> getStatus(String userId) {
        return confirmationLinkRepository.findById(userId)
            .map(UserConfirmationLinkEntity::getStatus);
    }

    public void revertConfirmation(String userId) {
        confirmationLinkRepository.findById(userId)
            .ifPresent(UserConfirmationLinkEntity::revertConfirmedToPending);
    }
}
