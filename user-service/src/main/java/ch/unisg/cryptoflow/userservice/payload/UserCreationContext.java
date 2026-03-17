package ch.unisg.cryptoflow.userservice.payload;

import java.util.Map;

public record UserCreationContext(String userName, String password, String email) {

    public static UserCreationContext fromMap(Map<String, Object> values) {
        return new UserCreationContext(
                (String) values.get("userName"),
                (String) values.get("password"),
                (String) values.get("e_mail")
        );
    }

    public Map<String, String> asMap() {
        return Map.of(
                "userName", userName,
                "password", password,
                "e_mail", email
        );
    }
}