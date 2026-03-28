package ch.unisg.cryptoflow.user.adapter.out.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SpringDataUserConfirmationLinkRepository extends JpaRepository<UserConfirmationLinkEntity, String> {
}
