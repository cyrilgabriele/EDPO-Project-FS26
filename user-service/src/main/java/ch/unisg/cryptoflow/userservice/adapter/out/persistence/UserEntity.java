package ch.unisg.cryptoflow.userservice.adapter.out.persistence;

import ch.unisg.cryptoflow.userservice.domain.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "users")
public class UserEntity {

    @Id
    @Column(name = "user_id", nullable = false, updatable = false)
    private String userId;

    @Column(name = "username", nullable = false)
    private String username;

    @Column(name = "password", nullable = false)
    private String password;

    @Column(name = "email", nullable = false)
    private String email;

    protected UserEntity() {
        // required by JPA
    }

    private UserEntity(String userId, String username, String password, String email) {
        this.userId = userId;
        this.username = username;
        this.password = password;
        this.email = email;
    }

    public static UserEntity fromDomain(User user) {
        return new UserEntity(user.getUserId(), user.getUsername(), user.getPassword(), user.getEmail());
    }

    public User toDomain() {
        return new User(username, password, userId, email);
    }
}
