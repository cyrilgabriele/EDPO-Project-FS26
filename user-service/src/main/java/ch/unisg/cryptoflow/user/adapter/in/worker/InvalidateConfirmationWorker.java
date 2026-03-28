package ch.unisg.cryptoflow.user.adapter.in.worker;

import ch.unisg.cryptoflow.user.application.service.ConfirmationLinkService;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.client.api.worker.JobClient;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class InvalidateConfirmationWorker {

    private final ConfirmationLinkService confirmationLinkService;

    @JobWorker(type = "invalidateConfirmationWorker")
    public void invalidateConfirmationLink(JobClient client, ActivatedJob job) {
        Object userIdValue = job.getVariablesAsMap().get("userId");
        if (userIdValue == null) {
            throw new IllegalStateException("userId variable missing for invalidate confirmation job " + job.getKey());
        }

        String userId = userIdValue.toString();
        boolean invalidated = confirmationLinkService.invalidateLink(userId);
        if (invalidated) {
            log.info("Invalidated confirmation link for user {} after timer event", userId);
        } else {
            log.warn("Confirmation link for user {} was not pending when invalidation worker ran", userId);
        }

        client.newCompleteCommand(job.getKey()).send().join();
    }
}
