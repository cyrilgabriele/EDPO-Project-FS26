package ch.unisg.cryptoflow.user;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class UserServiceApplication {
    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(UserServiceApplication.class);
        app.setBanner((environment, sourceClass, out) -> out.println(Banner.TEXT));
        app.run(args);
    }
}
