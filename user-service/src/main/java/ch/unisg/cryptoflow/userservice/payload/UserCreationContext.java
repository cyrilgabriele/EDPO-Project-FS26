package ch.unisg.cryptoflow.userservice.payload;

import lombok.Getter;

import java.util.HashMap;
import java.util.Map;

public class UserCreationContext {
    @Getter
    private String userName;
    @Getter
    private String password;
    @Getter
    private String email;

    public static UserCreationContext fromMap(Map<String, Object> values) {
        UserCreationContext context = new UserCreationContext();
        context.userName = (String) values.get("userName");
        context.password = (String) values.get("password");
        context.email = (String) values.get("e_mail");
        return context;
    }

    public Map<String, String> asMap() {
        HashMap<String, String> map = new HashMap<>();
        map.put("userName", userName);
        map.put("password", password);
        map.put("e_mail", email);
        return map;
    }

    @Override
    public String toString() {
        return "UserCreationContext [userName=" + userName + ", password=" + password + ", email=" + email +"]";
    }
}
