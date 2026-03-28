package ch.unisg.cryptoflow.user.adapter.out.persistence;

import ch.unisg.cryptoflow.user.domain.ConfirmationLinkStatus;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Entity
@Table(name = "user_confirmation_links")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class UserConfirmationLinkEntity {

    @Id
    @Column(name = "user_id", nullable = false, updatable = false)
    private String userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private ConfirmationLinkStatus status;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "confirmed_at")
    private Instant confirmedAt;

    @Column(name = "invalidated_at")
    private Instant invalidatedAt;

    private UserConfirmationLinkEntity(String userId,
                                       ConfirmationLinkStatus status,
                                       Instant createdAt,
                                       Instant updatedAt,
                                       Instant confirmedAt,
                                       Instant invalidatedAt) {
        this.userId = userId;
        this.status = status;
        this.createdAt = createdAt;
        this.updatedAt = updatedAt;
        this.confirmedAt = confirmedAt;
        this.invalidatedAt = invalidatedAt;
    }

    public static UserConfirmationLinkEntity pending(String userId) {
        Instant now = Instant.now();
        return new UserConfirmationLinkEntity(userId, ConfirmationLinkStatus.PENDING, now, now, null, null);
    }

    public boolean isPending() {
        return status == ConfirmationLinkStatus.PENDING;
    }

    public void markConfirmed() {
        Instant now = Instant.now();
        status = ConfirmationLinkStatus.CONFIRMED;
        confirmedAt = now;
        updatedAt = now;
    }

    public void markInvalidated() {
        Instant now = Instant.now();
        status = ConfirmationLinkStatus.INVALIDATED;
        invalidatedAt = now;
        updatedAt = now;
    }

    public void revertConfirmedToPending() {
        if (status != ConfirmationLinkStatus.CONFIRMED) {
            return;
        }

        status = ConfirmationLinkStatus.PENDING;
        confirmedAt = null;
        updatedAt = Instant.now();
    }
}
