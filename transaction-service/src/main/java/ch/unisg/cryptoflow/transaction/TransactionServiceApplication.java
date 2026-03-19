package ch.unisg.cryptoflow.transaction;

import io.camunda.zeebe.spring.client.annotation.Deployment;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@Deployment(resources = "classpath:placeOrder.bpmn")
public class TransactionServiceApplication {

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(TransactionServiceApplication.class);
        app.setBanner((environment, sourceClass, out) -> out.println(Banner.TEXT));
        app.run(args);
    }

}
