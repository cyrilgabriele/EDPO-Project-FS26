package ch.unisg.cryptoflow.userservice;

import io.camunda.zeebe.client.ZeebeClient;
import io.camunda.zeebe.client.api.ZeebeFuture;
import io.camunda.zeebe.client.api.command.PublishMessageCommandStep1;
import io.camunda.zeebe.client.api.response.PublishMessageResponse;
import org.mockito.Mockito;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

import java.io.InputStream;
import java.time.Duration;
import java.util.Map;

@TestConfiguration
public class ZeebeTestConfiguration {

    @Bean
    public ZeebeClient zeebeClient() {
        ZeebeClient client = Mockito.mock(ZeebeClient.class);
        PublishMessageCommandStep1 step1 = Mockito.mock(PublishMessageCommandStep1.class);
        PublishMessageCommandStep1.PublishMessageCommandStep2 step2 = Mockito.mock(PublishMessageCommandStep1.PublishMessageCommandStep2.class);
        PublishMessageCommandStep1.PublishMessageCommandStep3 step3 = Mockito.mock(PublishMessageCommandStep1.PublishMessageCommandStep3.class);
        ZeebeFuture<PublishMessageResponse> future = Mockito.mock(ZeebeFuture.class);

        Mockito.when(client.newPublishMessageCommand()).thenReturn(step1);
        Mockito.when(step1.messageName(Mockito.anyString())).thenReturn(step2);
        Mockito.when(step2.correlationKey(Mockito.anyString())).thenReturn(step3);
        Mockito.when(step2.withoutCorrelationKey()).thenReturn(step3);

        Mockito.when(step3.variables(Mockito.any(Map.class))).thenReturn(step3);
        Mockito.when(step3.variables(Mockito.anyString())).thenReturn(step3);
        Mockito.when(step3.variables(Mockito.any(InputStream.class))).thenReturn(step3);
        Mockito.when(step3.variables(Mockito.any(Object.class))).thenReturn(step3);
        Mockito.when(step3.variable(Mockito.anyString(), Mockito.any())).thenReturn(step3);
        Mockito.when(step3.messageId(Mockito.anyString())).thenReturn(step3);
        Mockito.when(step3.timeToLive(Mockito.any(Duration.class))).thenReturn(step3);
        Mockito.when(step3.tenantId(Mockito.anyString())).thenReturn(step3);
        Mockito.when(step3.requestTimeout(Mockito.any(Duration.class))).thenReturn(step3);

        Mockito.when(step3.send()).thenReturn(future);
        Mockito.when(future.join()).thenReturn(Mockito.mock(PublishMessageResponse.class));

        return client;
    }
}
