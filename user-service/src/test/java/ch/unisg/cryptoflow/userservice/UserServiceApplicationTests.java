package ch.unisg.cryptoflow.userservice;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(ZeebeTestConfiguration.class)
class UserServiceApplicationTests {

    @Test
    void contextLoads() {
    }

}
