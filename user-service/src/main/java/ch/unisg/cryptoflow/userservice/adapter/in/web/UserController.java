package ch.unisg.cryptoflow.userservice.adapter.in.web;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/user")
@Slf4j
public class UserController {

    @PostMapping
    public Map<String, Object> userCreation(@RequestBody Map<String, Object> payload) {
        log.info("Request arrived");
        log.info("Creating user {} with password {} and email {}", payload.get("userName"), payload.get("password"), payload.get("e_mail"));
        return Map.of(
                "status", "200",
                "message", "User has been successfully created"
        );
    }
}
